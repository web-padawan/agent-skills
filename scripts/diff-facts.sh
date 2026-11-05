#!/usr/bin/env bash
# diff-facts.sh — the facts of a diff that git alone can answer, for the passes: the
# packages that import each changed module, the snapshots of other packages, the Flow
# counterpart, the moved or reindented share of the diff, CSS that unit tests assert, new
# test files, and reads of the shadow DOM of another element.
#
# Usage:
#   diff-facts.sh --base <sha> --head <sha> [--flow-dir <path>]
#
# Run it from inside the target repository. review-plan.sh calls it in both modes and
# quotes the lines under Settled facts. pr-screen.sh takes `reach_max` for its verdict.
# --flow-dir names the flow-components checkout. The default is ../flow-components.
#
# Exit codes: 0 ok · 1 git could not answer · 2 usage error.
set -euo pipefail

BASE=""; HEAD=""; FLOW_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:?--base requires a value}"; shift 2 ;;
    --head) HEAD="${2:?--head requires a value}"; shift 2 ;;
    --flow-dir) FLOW_DIR="${2:?--flow-dir requires a value}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -euo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ "$BASE" =~ ^[0-9a-f]{7,40}$ ]] || { echo "error: --base takes a commit SHA" >&2; exit 2; }
[[ "$HEAD" =~ ^[0-9a-f]{7,40}$ ]] || { echo "error: --head takes a commit SHA" >&2; exit 2; }

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "error: not a git repository" >&2; exit 1; }
cd "$REPO_ROOT"
[ -n "$FLOW_DIR" ] || FLOW_DIR="$REPO_ROOT/../flow-components"

# ── Lanes ─────────────────────────────────────────────────────────────
# Same test-path rule as review-plan.sh, so both scripts split the lanes alike.
TEST_RE='(^|/)(test|tests|__tests__|it)/|\.(test|spec)\.[cm]?[jt]sx?$|Test\.java$|IT\.java$|Tests?\.kt$'
CHANGED=$(git diff --name-only --no-renames "$BASE..$HEAD" 2>/dev/null) || { echo "error: git cannot diff $BASE..$HEAD" >&2; exit 1; }
BINARY=$(git diff --numstat "$BASE..$HEAD" | awk -F'\t' '$1 == "-" { print $3 }')
TEXT=$(printf '%s\n' "$CHANGED" | grep -vxF -f <(printf '%s\n' "$BINARY" | sed '/^$/d'; echo '//none//') || true)
PROD=$(printf '%s\n' "$TEXT" | grep -vE "$TEST_RE" | sed '/^$/d' || true)
TESTS=$(printf '%s\n' "$TEXT" | grep -E "$TEST_RE" | sed '/^$/d' || true)

# Reach: the other packages whose sources import a changed source module, on the base.
# The match is the file name with its import extension, because the path prefix varies
# (`@vaadin/dialog/src/styles/...`, `./...`). A TypeScript module is imported as `.js`.
REACH_LINES=""; REACH_MAX=0
for f in $PROD; do
  case "$f" in packages/*/src/*) ;; *) continue ;; esac
  case "$f" in *.d.ts) continue ;; *.js|*.ts|*.css) ;; *) continue ;; esac
  pkg=$(printf '%s' "$f" | cut -d/ -f2)
  name=${f##*/}
  case "$name" in *.ts) pat="${name%.ts}.js" ;; *) pat="$name" ;; esac
  users=$(git grep -l -F -e "/$pat" -e "'./$pat'" "$BASE" -- 'packages/*/src/**' 2>/dev/null \
    | sed -E "s#^$BASE:packages/([^/]+)/.*#\\1#" | sort -u | grep -vxF "$pkg" | tr '\n' ' ' || true)
  n=$(printf '%s\n' $users | grep -c . || true)
  [ "$n" -gt "$REACH_MAX" ] && REACH_MAX=$n
  REACH_LINES="${REACH_LINES}reach: $f -> $n other packages${users:+ [${users% }]}
"
done

# Snapshots of other packages: the change shows in their DOM.
SNAP_PKGS=$(printf '%s\n' "$CHANGED" | sed -nE 's#^packages/([^/]+)/test/dom/__snapshots__/.*#\1#p' | sort -u | tr '\n' ' ')
SNAP_N=$(printf '%s\n' $SNAP_PKGS | grep -c . || true)

# Flow counterpart of each package whose sources changed.
FLOW_LINE=""
if [ -d "$FLOW_DIR" ]; then
  for pkg in $(printf '%s\n' $PROD | sed -nE 's#^packages/([^/]+)/.*#\1#p' | sort -u); do
    [ -d "$FLOW_DIR/vaadin-$pkg-flow-parent" ] && FLOW_LINE="${FLOW_LINE:+$FLOW_LINE, }vaadin-$pkg-flow-parent"
  done
  FLOW_LINE=${FLOW_LINE:-none}
else
  FLOW_LINE="unknown (no checkout at $FLOW_DIR)"
fi

# Diff noise: changed production lines whose trimmed text appears on both sides. A moved
# block or a reindent inflates the diff without a change in behavior.
NOISE="0 0"
if [ -n "$PROD" ]; then
  NOISE=$(git diff -U0 --no-color "$BASE..$HEAD" -- $PROD | awk '
    /^(\+\+\+|---) / { next }
    /^[-+]/ {
      t = substr($0, 2); gsub(/^[ \t]+|[ \t]+$/, "", t)
      total++
      if (length(t) < 4) next
      if (substr($0, 1, 1) == "-") rem[t]++; else add[t]++
    }
    END { for (t in add) if (t in rem) same += (add[t] < rem[t] ? add[t] : rem[t]) * 2
          printf "%d %d\n", same, total }')
fi
read -r NOISE_N NOISE_TOTAL <<< "$NOISE"

# CSS that a unit test asserts: a style change, and getComputedStyle added in a test that
# is not a visual test. guidelines/testing.md of web-components asks for a visual test.
CSS_HITS=""
if printf '%s\n' "$PROD" | grep -qE '\.css$|-styles\.[cm]?[jt]s$|/styles/'; then
  UNIT_TESTS=$(printf '%s\n' "$TESTS" | grep -v '/visual/' | grep -vE '__snapshots__' || true)
  if [ -n "$UNIT_TESTS" ]; then
    CSS_HITS=$(git diff -U0 --no-color "$BASE..$HEAD" -- $UNIT_TESTS | awk '
      /^\+\+\+ b\// { f = substr($0, 7); next }
      /^@@/ { split($3, a, ","); n = substr(a[1], 2) + 0; next }
      /^\+/ { if ($0 ~ /getComputedStyle/) printf "%s:%d ", f, n; n++ }' | cut -c1-400 | sed 's/ *$//')
  fi
fi

# The rule behind the CSS hits, as a file:line on the base, so the tests pass can quote it.
# In web-components it lives in guidelines/testing.md, which the context file does not quote.
CSS_RULE=""
if [ -n "$CSS_HITS" ]; then
  CSS_RULE=$(git grep -n -i -E 'visual tests? (over|instead of|rather than) unit tests?' "$BASE" -- \
    CONVENTIONS.md 'guidelines/*.md' CLAUDE.md AGENTS.md CONTRIBUTING.md 2>/dev/null \
    | head -1 | sed "s#^$BASE:##" | cut -d: -f1,2 || true)
fi

# New test files, with their size next to the production size. A new suite for a small fix
# breaks the "no new test file unless necessary" rule of the tests pass (#12974: 52 lines of
# a new suite for a 5-line fix).
NEW_TESTS=""
PROD_LINES=$(git diff --numstat "$BASE..$HEAD" -- $PROD 2>/dev/null | awk '$1 != "-" { n += $1 + $2 } END { print n + 0 }')
for f in $(git diff --name-only --diff-filter=A "$BASE..$HEAD" -- $TESTS 2>/dev/null | grep -v '__snapshots__' | grep -v '/screenshots/' || true); do
  n=$(git show "$HEAD:$f" 2>/dev/null | wc -l | tr -d ' ')
  NEW_TESTS="${NEW_TESTS:+$NEW_TESTS, }$f ($n lines)"
done

# Added production code that reads the shadow DOM of another element (`other.$.id`). It
# couples a parent to the internals of a child. The family usually has a declarative
# path instead, for example a delegated property (#13327: `focusElement.$.button`).
SHADOW_REACH=""
SRC_JS=$(printf '%s\n' $PROD | grep -E '\.[cm]?[jt]s$' | grep -v '\.d\.ts$' || true)
if [ -n "$SRC_JS" ]; then
  SHADOW_REACH=$(git diff -U0 --no-color "$BASE..$HEAD" -- $SRC_JS | awk '
    /^\+\+\+ b\// { f = substr($0, 7); next }
    /^@@/ { split($3, a, ","); n = substr(a[1], 2) + 0; next }
    /^\+/ {
      line = substr($0, 2)
      while (match(line, /[A-Za-z_][A-Za-z0-9_]*\.\$\.[A-Za-z_][A-Za-z0-9_]*/)) {
        expr = substr(line, RSTART, RLENGTH)
        if (expr !~ /^this\./) printf "%s:%d %s ", f, n, expr
        line = substr(line, RSTART + RLENGTH)
      }
      n++
    }' | cut -c1-400 | sed 's/ *$//')
fi

# ── Print ─────────────────────────────────────────────────────────────
echo "=== DIFF_FACTS ==="
if [ -n "$REACH_LINES" ]; then printf '%s' "$REACH_LINES"; else echo "reach: no package source changed"; fi
echo "reach_max: $REACH_MAX"
if [ "$SNAP_N" -ge 2 ]; then echo "snapshot_packages: $SNAP_N [${SNAP_PKGS% }]"; else echo "snapshot_packages: $SNAP_N"; fi
echo "flow_counterpart: $FLOW_LINE"
echo "diff_noise: $NOISE_N of $NOISE_TOTAL changed production lines are moved or reindented (the same text on both sides)"
echo "css_unit_assertions: ${CSS_HITS:-none}"
[ -n "$CSS_RULE" ] && echo "css_rule: $CSS_RULE"
echo "shadow_reach: ${SHADOW_REACH:-none}"
echo "new_test_files: ${NEW_TESTS:-none}${NEW_TESTS:+ for $PROD_LINES changed production lines}"
