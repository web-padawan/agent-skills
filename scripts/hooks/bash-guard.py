#!/usr/bin/env python3
"""bash-guard.py: PreToolUse hook that holds the reviewer passes to read-only Bash.

Registered in hooks/hooks.json. Claude Code sends the hook payload on stdin. The payload
names the calling subagent in `agent_type`. The guard acts only on the three reviewer
agents of this plugin, `<plugin name>:<pass>-reviewer`, and returns no decision for every
other caller. The plugin name comes from .claude-plugin/plugin.json.

Two modes:
  same  the default. Deny commands that write: file writes, redirects to a file, write
        flags of read commands, git subcommands that change state, network tools, gh.
        Interpreters and test runners stay allowed, because a pass on an own branch may
        measure a claim (agents/change-reviewer.md, Running the code).
  fork  while the fork marker of review-plan.sh is younger than MARKER_TTL seconds. Allow
        only the read commands below. A fork head is untrusted code: no interpreter, no
        package manager, no test runner, no command substitution.

Usage (manual check):
  printf '%s' '<payload json>' | python3 -I bash-guard.py [--marker <path>] [--mode same|fork]

Exit code 0 always. A denial is JSON on stdout. A parse failure of the command is a denial.
"""
import json
import os
import re
import shlex
import sys
import time

def plugin_name():
    """The name in .claude-plugin/plugin.json, or None when the file cannot be read."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                        ".claude-plugin", "plugin.json")
    try:
        with open(path) as f:
            return json.load(f).get("name") or None
    except (OSError, ValueError):
        return None


PLUGIN = plugin_name()
# Without a plugin name, the guard acts on a reviewer agent of any plugin. It never fails open.
AGENTS = re.compile("^" + (re.escape(PLUGIN) if PLUGIN else "[^:]+") + ":(change|code|test)-reviewer$")
MARKER = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                      PLUGIN or "review-pipeline", "fork-review")
MARKER_TTL = 3 * 3600

READ = {
    "cat", "head", "tail", "wc", "grep", "egrep", "fgrep", "rg", "ls", "find", "diff", "comm",
    "cut", "tr", "basename", "dirname", "sort", "uniq", "awk", "gawk", "sed", "jq", "echo",
    "printf", "pwd", "test", "[", "true", "false", "file", "stat", "du", "od", "hexdump",
    "xxd", "nl", "column", "paste", "join", "fold", "expand", "realpath", "readlink", "git",
    "cd", "which", "type", "date", "seq", "rev", "tac", "cmp", "strings", "shasum",
    "sha256sum", "md5", "md5sum",
}
ALWAYS_DENY = {
    "rm", "rmdir", "mv", "cp", "touch", "mkdir", "ln", "chmod", "chown", "chgrp", "tee", "dd",
    "truncate", "install", "patch", "shred", "unlink", "curl", "wget", "nc", "ncat", "ssh",
    "scp", "sftp", "rsync", "open", "osascript", "gh", "kill", "pkill", "killall", "sudo", "su",
    "crontab", "launchctl", "defaults", "security", "eval", "exec", "source", ".",
}
SHELLS = {"bash", "sh", "zsh", "dash", "fish", "ksh"}
WRAPPERS = {"env", "command", "nice", "time", "nohup", "builtin"}
GIT_READ = {
    "show", "log", "diff", "grep", "blame", "ls-files", "ls-tree", "merge-base", "rev-parse",
    "cat-file", "status", "rev-list", "name-rev", "describe", "shortlog", "show-ref",
    "for-each-ref", "whatchanged", "range-diff", "diff-tree", "diff-files", "diff-index",
    "cherry", "count-objects", "var", "version", "help", "annotate", "branch", "tag",
}
GIT_BAD_ARG = re.compile(r"^(--output(=.*)?|-O.*|--open-files-in-pager(=.*)?|--ext-diff)$")
BRANCH_WRITE = {"-d", "-D", "-m", "-M", "-c", "-C", "--delete", "--move", "--copy", "-f",
                "--force", "-u", "--set-upstream-to", "--unset-upstream", "--edit-description",
                "--create-reflog"}
BRANCH_LIST = {"--list", "-l", "--contains", "--no-contains", "--merged", "--no-merged",
               "--points-at"}
SEPARATORS = {"|", "||", "&&", ";", "&", "(", ")", "|&", ";;", "\n"}
REDIRECT = re.compile(r"^(\d*)(>>?|>&|&>>?|>\|)$")
SAFE_TARGETS = {"/dev/null", "1", "2", "&1", "&2", "-"}


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "bash-guard: " + reason,
    }}))
    sys.exit(0)


def fork_mode(marker):
    try:
        return time.time() - os.path.getmtime(marker) < MARKER_TTL
    except OSError:
        return False


def tokenize(command):
    lex = shlex.shlex(command, posix=True, punctuation_chars=";&|()<>")
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def segments(tokens):
    """Split on control operators. Return (argv, redirects) per segment."""
    out, argv, redirects, i = [], [], [], 0
    while i < len(tokens):
        tok = tokens[i]
        if tok in SEPARATORS:
            out.append((argv, redirects))
            argv, redirects = [], []
        elif REDIRECT.match(tok) or tok in ("<", "<<", "<<<", "<&", "<>"):
            if argv and argv[-1].isdigit():
                argv.pop()
            target = tokens[i + 1] if i + 1 < len(tokens) else ""
            redirects.append((tok, target))
            i += 1
        else:
            argv.append(tok)
        i += 1
    out.append((argv, redirects))
    return [(a, r) for a, r in out if a or r]


def strip_wrappers(argv):
    while argv and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", argv[0]):
        argv = argv[1:]
    while argv and os.path.basename(argv[0]) in WRAPPERS:
        argv = argv[1:]
        while argv and (argv[0].startswith("-") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", argv[0])):
            argv = argv[1:]
    return argv


def check_git(args):
    i = 0
    while i < len(args):
        a = args[i]
        if a == "-C":
            i += 2
            continue
        if a in ("--no-pager", "-P", "--paginate", "-p", "--no-replace-objects", "--literal-pathspecs"):
            i += 1
            continue
        if a.startswith("--git-dir=") or a.startswith("--work-tree="):
            i += 1
            continue
        if a == "-c" or a.startswith("--exec-path") or a.startswith("--config-env"):
            return "git -c and --exec-path can run configured commands"
        break
    if i >= len(args):
        return None
    sub, rest = args[i], args[i + 1:]
    if sub not in GIT_READ:
        return "git %s changes state or reaches the network; passes are read-only" % sub
    for a in rest:
        if GIT_BAD_ARG.match(a):
            return "git %s %s writes a file or runs a command" % (sub, a)
    if sub in ("branch", "tag"):
        if any(a in BRANCH_WRITE for a in rest):
            return "git %s with a write flag" % sub
        positional = [a for a in rest if not a.startswith("-")]
        if positional and not any(a in BRANCH_LIST for a in rest):
            return "git %s <name> creates a ref" % sub
    return None


def check_sed(args):
    for a in args:
        if a.startswith("-i") or a.startswith("--in-place"):
            return "sed -i edits a file"
    scripts = [a for a in args if not a.startswith("-")]
    for s in scripts:
        if re.search(r"(^|[;{}\n])\s*[0-9$,/!\\^.*]*\s*[wWe](\s|$)", s) or re.search(r"s(.).*\1.*\1[gpiImM0-9]*w\s", s):
            return "a sed w or e command writes a file or runs a command"
    return None


def check_awk(args):
    for a in args:
        if a in ("-i", "--include") or a.startswith("-i"):
            return "awk -i can load inplace editing"
    for s in args:
        if "system(" in s or re.search(r"print[f]?\b[^;}\n]*[^<>=!]>{1,2}\s*[\"$A-Za-z_(]", s) \
                or re.search(r"print[f]?\b[^;}\n]*\|\s*\"", s) or re.search(r"\"\s*\|\s*getline", s) \
                or "|&" in s:
            return "an awk script that writes a file or runs a command"
    return None


def check_program(argv, fork, depth=0):
    argv = strip_wrappers(argv)
    if not argv:
        return None
    prog = os.path.basename(argv[0])
    args = argv[1:]
    if prog in ALWAYS_DENY:
        return "%s writes, deletes, or reaches the network; passes are read-only" % prog
    if prog in SHELLS:
        if fork or "-c" in args:
            return "%s runs a script that the guard cannot read" % prog
    if prog == "git":
        return check_git(args)
    if prog == "sed":
        return check_sed(args)
    if prog in ("awk", "gawk"):
        return check_awk(args)
    if prog == "find":
        bad = {"-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprint0", "-fprintf", "-fls"}
        hit = [a for a in args if a in bad]
        if hit:
            return "find %s runs a command or writes" % hit[0]
    if prog == "sort" and any(a.startswith("-o") or a.startswith("--output") for a in args):
        return "sort -o writes a file"
    if prog == "uniq" and len([a for a in args if not a.startswith("-")]) >= 2:
        return "uniq with two file names writes the second"
    if prog == "rg" and any(a.startswith("--pre") for a in args):
        return "rg --pre runs a command"
    if prog == "date" and any(a in ("-s", "--set") or a.startswith("--set=") for a in args):
        return "date -s sets the clock"
    if prog == "xargs":
        if fork:
            return "xargs runs a command that the guard cannot read in a fork review"
        rest, i = list(args), 0
        while i < len(rest) and rest[i].startswith("-"):
            i += 2 if rest[i] in ("-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a") else 1
        return check_program(rest[i:], fork, depth + 1) if depth < 3 else "nested xargs"
    if fork and prog not in READ:
        return "%s is not a read command; a fork review runs no code of the head" % prog
    return None


def check(command, fork):
    if fork and ("$(" in command or "`" in command):
        return "command substitution in a fork review; use the literal SHAs of the plan"
    if fork and "<<" in command:
        return "a heredoc in a fork review"
    for inner in re.findall(r"\$\(([^()]*)\)|`([^`]*)`", command):
        text = inner[0] or inner[1]
        reason = check(text, fork)
        if reason:
            return reason
    try:
        tokens = tokenize(command)
    except ValueError as e:
        return "the command did not parse (%s)" % e
    for argv, redirects in segments(tokens):
        for op, target in redirects:
            if ">" in op and target not in SAFE_TARGETS:
                return "a redirect to %s writes a file" % (target or "a file")
        reason = check_program(argv, fork)
        if reason:
            return reason
    return None


def main():
    marker, mode = MARKER, None
    argv = sys.argv[1:]
    while argv:
        if argv[0] == "--marker" and len(argv) > 1:
            marker, argv = argv[1], argv[2:]
        elif argv[0] == "--mode" and len(argv) > 1:
            mode, argv = argv[1], argv[2:]
        else:
            argv = argv[1:]
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    if payload.get("tool_name") != "Bash":
        return
    if not AGENTS.match(payload.get("agent_type") or ""):
        return
    command = (payload.get("tool_input") or {}).get("command") or ""
    fork = (mode == "fork") if mode else fork_mode(marker)
    reason = check(command, fork)
    if reason:
        if fork:
            reason += " (fork review mode: %s, younger than %d hours)" % (marker, MARKER_TTL // 3600)
        deny(reason)


if __name__ == "__main__":
    main()
