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
# --scope prose (default) reads markdown. It joins the lines of each paragraph and each list
#   item, so a phrase that wraps still matches. It skips the frontmatter, fenced code,
#   headings, table rows, quote lines, HTML comments and each line that holds
#   <!-- prose-ok -->. It removes code spans, URLs and link targets before the match.
# --scope comment reads the output lines of list-comments.sh, `<file>:<line> | <kind> | <text>`,
#   and checks the text field. It removes the comment markers, code spans and URLs before the
#   match. A multi-line comment is one line, with its lines joined by ` / `.
#
# Output, one line per hit:
#   <file>:<line> | <tier> | <matched text> | <use instead>
#
# Exit codes: 0 no ban hit (flag hits can print), 1 one or more ban hits, 2 a usage error, a
# bad pattern row, a comment line in the wrong format, or an input that cannot be read.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PATTERNS="$ROOT/references/banned-patterns.md"
SCOPE=prose
INPUTS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --scope)
      [ $# -ge 2 ] || { echo "refuse: --scope needs a value" >&2; exit 2; }
      SCOPE="$2"; shift ;;
    --help|-h) sed -n '2,25p' "$0"; exit 0 ;;
    -) INPUTS+=("-") ;;
    --*) echo "refuse: unknown flag $1" >&2; exit 2 ;;
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

class Refuse(Exception):
    pass

def load_rows():
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
            if cells and (cells[0] == "Pattern" or set(cells[0]) <= set("-: ")):
                continue
            if len(cells) != 4:
                raise Refuse("pattern row without 4 cells: " + line)
            pat, tier, instead, row_scope = cells
            if tier not in ("ban", "flag") or row_scope not in ("all", "prose", "comment"):
                raise Refuse("bad tier or scope: " + line)
            if row_scope not in ("all", scope):
                continue
            if len(pat) > 1 and pat[0] == "`" and pat[-1] == "`":
                pat = pat[1:-1]
            try:
                if len(pat) > 2 and pat[0] == "/" and pat[-1] == "/":
                    rx = re.compile(pat[1:-1], re.IGNORECASE)
                else:
                    # A one-word pattern matches the start of a word. A phrase matches whole words.
                    tail = r"\w*" if " " not in pat else r"\b"
                    rx = re.compile(r"(?<![\w-])" + re.escape(pat) + tail, re.IGNORECASE)
            except re.error as e:
                raise Refuse("bad pattern " + pat + ": " + str(e))
            rows.append((rx, tier, instead))
    if not rows:
        raise Refuse("no pattern rows in " + patterns_path)
    return rows

CODE_SPAN = re.compile(r"(`+)(.+?)\1")
URL = re.compile(r"https?://\S+")
LINK_TARGET = re.compile(r"\]\([^)]*\)")
MARKER = re.compile(r"(?:(?<=\s)|^)(?:/\*\*?|\*+/|//+|\*+)(?=\s|$)")
SEPARATOR = re.compile(r"\s/\s")

def clean(text):
    text = CODE_SPAN.sub(" x ", text)
    text = LINK_TARGET.sub("]", text)
    return URL.sub(" ", text)

def run():
    rows = load_rows()
    bans = 0

    def check(locs, parts):
        # parts: the text of each source line, in order. locs: the location of each part.
        nonlocal bans
        starts, text = [], ""
        for p in parts:
            starts.append(len(text))
            text += p + " "
        for rx, tier, instead in rows:
            for m in rx.finditer(text):
                i = max(k for k, s in enumerate(starts) if s <= m.start())
                print(f"{locs[i]} | {tier} | {m.group(0)} | {instead}")
                if tier == "ban":
                    bans += 1

    FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
    HEADING = re.compile(r"^\s{0,3}#{1,6}(\s|$)")
    ITEM = re.compile(r"^\s*([-*+]|\d+[.)])\s")

    def prose(name, lines):
        lines = [l.rstrip("\r\n") for l in lines]
        front = bool(lines) and lines[0] == "---" and "---" in lines[1:]
        fence, in_html = None, False
        locs, parts = [], []

        def flush():
            if parts:
                check(list(locs), list(parts))
            locs.clear()
            parts.clear()

        for i, line in enumerate(lines, 1):
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
                flush()
                fence = m.group(1)
                continue
            if in_html:
                if "-->" in line:
                    in_html = False
                continue
            stripped = line.strip()
            if stripped.startswith("<!--") and "-->" not in stripped:
                flush()
                in_html = True
                continue
            if (not stripped or HEADING.match(line) or stripped.startswith(("|", ">", "<!--"))
                    or "<!-- prose-ok -->" in line):
                flush()
                continue
            if ITEM.match(line):
                flush()
            locs.append(f"{name}:{i}")
            parts.append(clean(line))
        flush()

    def comments(lines):
        for raw in lines:
            line = raw.rstrip("\r\n")
            if not line.strip():
                continue
            fields = line.split(" | ", 2)
            if len(fields) != 3:
                raise Refuse("not a list-comments.sh line: " + line)
            text = clean(fields[2])
            text = MARKER.sub(" ", SEPARATOR.sub(" ", " " + text + " "))
            check([fields[0]], [" ".join(text.split())])

    for path in inputs:
        if path == "-":
            name, lines = "stdin", sys.stdin.readlines()
        else:
            try:
                with open(path, encoding="utf-8") as f:
                    name, lines = path, f.readlines()
            except (OSError, UnicodeDecodeError) as e:
                raise Refuse("cannot read " + path + ": " + str(e))
        if scope == "comment":
            comments(lines)
        else:
            prose(name, lines)
    return 1 if bans else 0

try:
    sys.exit(run())
except Refuse as e:
    print("refuse: " + str(e), file=sys.stderr)
    sys.exit(2)
except Exception as e:
    print("refuse: internal error: " + repr(e), file=sys.stderr)
    sys.exit(2)
EOF
)

exec python3 -I -c "$PY" "$PATTERNS" "$SCOPE" "${INPUTS[@]}"
