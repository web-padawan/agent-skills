#!/usr/bin/env bash
# prose-check.sh — find banned words, phrases and punctuation in prose or in code comments.
#
# Usage:
#   prose-check.sh [--scope prose|comment] <file ...>
#   prose-check.sh [--scope prose|comment] -          # read stdin
#
# Reads the pattern table of references/banned-patterns.md. Each row has a tier and a scope.
#   ban    the text must change. The row gives the replacement.
#   flag   a smell. Judge it in context, and change the text only when it adds no fact.
# A row of scope `all` applies to both scopes.
#
# --scope prose (default) reads markdown. It skips the frontmatter, fenced code, headings,
#   table rows, quote lines, HTML comment lines and each line that holds <!-- prose-ok -->.
#   It removes code spans, URLs and link targets before the match.
# --scope comment reads the output lines of list-comments.sh, `<file>:<line> | <kind> | <text>`,
#   and checks the text field. It removes code spans and URLs before the match.
#
# Output, one line per hit:
#   <file>:<line> | <tier> | <matched text> | <use instead>
#
# Exit codes: 0 no ban hit (flag hits can print), 1 one or more ban hits, 2 a usage error.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PATTERNS="$ROOT/references/banned-patterns.md"
SCOPE=prose
INPUTS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --scope) SCOPE="${2:-}"; shift ;;
    --help|-h) sed -n '2,22p' "$0"; exit 0 ;;
    -) INPUTS+=("-") ;;
    --*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) INPUTS+=("$1") ;;
  esac
  shift
done

case "$SCOPE" in prose|comment) ;; *) echo "refuse: --scope must be prose or comment" >&2; exit 2 ;; esac
[ ${#INPUTS[@]} -gt 0 ] || { echo "refuse: no input, pass a file or -" >&2; exit 2; }
[ -r "$PATTERNS" ] || { echo "refuse: cannot read $PATTERNS" >&2; exit 2; }

PY=$(cat <<'EOF'
import re
import sys

patterns_path, scope, *inputs = sys.argv[1:]

def fail(msg):
    print("refuse: " + msg, file=sys.stderr)
    sys.exit(2)

rows = []
in_block = False
with open(patterns_path, encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if line == "<!-- block:patterns -->":
            in_block = True
            continue
        if line == "<!-- /block -->":
            in_block = False
            continue
        if not in_block or not line.startswith("|"):
            continue
        cells = [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", line)[1:-1]]
        if len(cells) != 4 or cells[0] == "Pattern" or set(cells[0]) <= set("-: "):
            continue
        pat, tier, instead, row_scope = cells
        if tier not in ("ban", "flag") or row_scope not in ("all", "prose", "comment"):
            fail("bad row in banned-patterns.md: " + line)
        if row_scope not in ("all", scope):
            continue
        if len(pat) > 1 and pat[0] == "`" and pat[-1] == "`":
            pat = pat[1:-1]
        try:
            if len(pat) > 2 and pat[0] == "/" and pat[-1] == "/":
                rx = re.compile(pat[1:-1], re.IGNORECASE)
            else:
                rx = re.compile(r"(?<![\w-])" + re.escape(pat) + r"\w*", re.IGNORECASE)
        except re.error as e:
            fail("bad pattern " + pat + ": " + str(e))
        rows.append((rx, tier, instead))
if not rows:
    fail("no pattern rows in " + patterns_path)

CODE_SPAN = re.compile(r"(`+)(.+?)\1")
URL = re.compile(r"https?://\S+")
LINK_TARGET = re.compile(r"\]\([^)]*\)")

def clean(text):
    text = CODE_SPAN.sub(" x ", text)
    text = LINK_TARGET.sub("]", text)
    return URL.sub(" ", text)

bans = 0

def check(loc, text):
    global bans
    text = clean(text)
    for rx, tier, instead in rows:
        for m in rx.finditer(text):
            print(f"{loc} | {tier} | {m.group(0)} | {instead}")
            if tier == "ban":
                bans += 1

FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
HEADING = re.compile(r"^\s{0,3}#{1,6}(\s|$)")
HTML_COMMENT = re.compile(r"^\s*<!--.*-->\s*$")

def prose(name, lines):
    fence = None
    front = bool(lines) and lines[0].rstrip("\n") == "---"
    for i, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")
        if front:
            if i > 1 and line == "---":
                front = False
            continue
        m = FENCE.match(line)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):
                fence = None
            continue
        if m:
            fence = m.group(1)
            continue
        if (HEADING.match(line) or line.lstrip().startswith(("|", ">"))
                or HTML_COMMENT.match(line) or "<!-- prose-ok -->" in line):
            continue
        check(f"{name}:{i}", line)

def comments(lines):
    for raw in lines:
        parts = raw.rstrip("\n").split(" | ", 2)
        if len(parts) == 3:
            check(parts[0], parts[2])

for path in inputs:
    if path == "-":
        name, lines = "stdin", sys.stdin.readlines()
    else:
        try:
            with open(path, encoding="utf-8") as f:
                name, lines = path, f.readlines()
        except OSError as e:
            fail("cannot read " + path + ": " + e.strerror)
    if scope == "comment":
        comments(lines)
    else:
        prose(name, lines)

sys.exit(1 if bans else 0)
EOF
)

exec python3 -I -c "$PY" "$PATTERNS" "$SCOPE" "${INPUTS[@]}"
