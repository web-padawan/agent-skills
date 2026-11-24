#!/usr/bin/env python3
"""notes-guard.py: PreToolUse hook that holds a reviewer pass until its notes file exists.

Registered in hooks/hooks.json for the Agent tool. Claude Code sends the hook payload on
stdin. The guard reads the prompt of the Agent call. It acts only on a prompt that holds the
context line of scripts/lib/prompts.sh:

  Context file: `<context path>` — read it first. Then read `<notes path>` whole if it exists.

It denies the launch when the context file or the notes file does not exist. A pass that
starts without the notes file reviews without the Settled facts of the orchestrator. The
notes file must exist before the fan-out message, so the Write goes in a message of its own.

It also denies the launch when the notes file has no `## Settled facts` or `## Open leads`
section, or when an entry there has no id. The entries of a section are numbered S1, S2, ...
and L1, L2, ..., in order, or the section reads `- none`. Each pass ends its reply with the
last id that it read, and the roll call compares that line with the file (pipeline.md §4).
Every other Agent call gets no decision.

Usage (manual check):
  printf '%s' '<payload json>' | python3 -I notes-guard.py

Exit code 0 always. A denial is JSON on stdout.
"""
import json
import os
import re
import sys

SECTIONS = (("Settled facts", "S"), ("Open leads", "L"))
HEADING = re.compile(r"^#{2,}\s+(.*?)\s*$")
ENTRY = re.compile(r"^- ")


def id_problem(text):
    """The first problem with the ids of the notes file, or None."""
    sections, current = {}, None
    for line in text.splitlines():
        heading = HEADING.match(line)
        if heading:
            current = heading.group(1).lower()
            sections.setdefault(current, [])
            continue
        if current is not None and ENTRY.match(line):
            sections[current].append(line[2:].strip())
    for name, prefix in SECTIONS:
        entries = sections.get(name.lower())
        if entries is None:
            return "it has no `## %s` section" % name
        if not entries:
            return "`## %s` is empty, write `- none`" % name
        if entries == ["none"]:
            continue
        for n, entry in enumerate(entries, 1):
            if not re.match(r"%s%d\b" % (prefix, n), entry):
                return ("entry %d of `## %s` does not start with `%s%d`: %s"
                        % (n, name, prefix, n, entry[:60]))
    return None


CONTEXT_LINE = re.compile(
    r"Context file: `([^`]+)` — read it first\. Then read `([^`]+)` whole if it exists\.")


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "notes-guard: " + reason,
    }}))
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    if not isinstance(payload, dict) or payload.get("tool_name") not in ("Agent", "Task"):
        return
    prompt = (payload.get("tool_input") or {}).get("prompt") or ""
    if not isinstance(prompt, str):
        return
    match = CONTEXT_LINE.search(prompt)
    if not match:
        return
    context, notes = match.group(1), match.group(2)
    if not os.path.isfile(context):
        deny("the context file %s does not exist. Run the plan again, then launch the passes." % context)
    if not os.path.isfile(notes):
        deny("the notes file %s does not exist. Write it in a message of its own, then launch "
             "every pass again in one message (references/pipeline.md §2)." % notes)
    try:
        with open(notes) as f:
            problem = id_problem(f.read())
    except OSError as err:
        problem = "it cannot be read (%s)" % err
    if problem:
        deny("the notes file %s is not ready: %s. Number the entries S1, S2, ... and L1, L2, ..., "
             "or write `- none` under an empty section (references/pipeline.md §2)." % (notes, problem))


if __name__ == "__main__":
    main()
