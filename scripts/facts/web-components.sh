#!/usr/bin/env bash
# web-components.sh — the fact pack of a web component monorepo (packages/*/src), for
# example vaadin/web-components. It prints the packages that import each changed module,
# the snapshots of other packages, the Flow counterpart, CSS that unit tests assert, and
# reads of the shadow DOM of another element. Each fact that has entries gets a `rule:` line.
#
# Usage:
#   web-components.sh --base <sha> --head <sha>
#
# scripts/diff-facts.sh runs it from the repository root and exports FACTS_PROD and
# FACTS_TESTS. Outside a packages/*/src layout it prints nothing.
# REVIEW_FLOW_DIR names the flow-components checkout. The default is ../flow-components.
#
# Exit codes: 0 ok · 2 usage error.
set -euo pipefail

BASE=""; HEAD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:?--base requires a value}"; shift 2 ;;
    --head) HEAD="${2:?--head requires a value}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -euo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ "$BASE" =~ ^[0-9a-f]{7,40}$ ]] || { echo "error: --base takes a commit SHA" >&2; exit 2; }
[[ "$HEAD" =~ ^[0-9a-f]{7,40}$ ]] || { echo "error: --head takes a commit SHA" >&2; exit 2; }
PROD=${FACTS_PROD:-}
TESTS=${FACTS_TESTS:-}
ls -d packages/*/src >/dev/null 2>&1 || exit 0
FLOW_DIR=${REVIEW_FLOW_DIR:-../flow-components}

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
CHANGED=$(git diff --name-only --no-renames "$BASE..$HEAD")
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
if [ -n "$REACH_LINES" ]; then printf '%s' "$REACH_LINES"; else echo "reach: no package source changed"; fi
echo "reach_max: $REACH_MAX"
[ "$REACH_MAX" -gt 0 ] && echo "rule: Each \`reach\` line names the other packages that import the changed module on the base. They are consumers of that module. Start a consumer search there."
if [ "$SNAP_N" -ge 2 ]; then echo "snapshot_packages: $SNAP_N [${SNAP_PKGS% }]"; else echo "snapshot_packages: $SNAP_N"; fi
echo "flow_counterpart: $FLOW_LINE"
case "$FLOW_LINE" in none|unknown*) ;; *) echo "rule: A \`flow_counterpart\` module wraps the changed package. It is a consumer of every changed default, event and data path." ;; esac
echo "css_unit_assertions: ${CSS_HITS:-none}"
[ -n "$CSS_RULE" ] && echo "css_rule: $CSS_RULE"
[ -n "$CSS_HITS" ] && echo "rule: A style change that only a \`getComputedStyle\` assertion in a unit test pins is a \`tests\` finding at B when \`css_rule\` names a visual-test rule. Cite \`css_rule\` as \`src:\`."
echo "shadow_reach: ${SHADOW_REACH:-none}"
[ -n "$SHADOW_REACH" ] && echo "rule: Each \`shadow_reach\` entry is added code that reads the shadow DOM of another element. Judge it as \`reuse\`: could the child receive the value through a delegated property and bind it in its template?"
exit 0
