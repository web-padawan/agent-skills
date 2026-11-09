#!/usr/bin/env bash
# flow-components.sh — the fact pack of a Flow repository (a root pom.xml and no packages/
# directory), for example vaadin/flow-components. It prints the web component declaration
# of each property that the added Java lines sync, and of each method that they call with
# callJsFunction, read at the pinned @NpmPackage version.
#
# Usage:
#   flow-components.sh --base <sha> --head <sha>
#
# scripts/diff-facts.sh runs it from the repository root and exports FACTS_PROD. Outside a
# Flow repository it prints nothing. REVIEW_WC_DIR names the web-components checkout. The
# default is ../web-components. The script reads the tag v<version> there. For an API that
# the tag lacks, it reads the local origin/main, else main. It never fetches.
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
{ [ -f pom.xml ] && [ ! -d packages ]; } || exit 0
WC_DIR=${REVIEW_WC_DIR:-../web-components}

# The newest local state of the web components. A Flow change can land before the version
# bump, so the pinned tag can lack the API that it uses.
WC_REF=""; WC_LATER_AT=""
for r in refs/remotes/origin/main refs/heads/main; do
  if git -C "$WC_DIR" rev-parse -q --verify "$r^{commit}" >/dev/null 2>&1; then WC_REF=$r; break; fi
done
if [ -n "$WC_REF" ]; then
  name=${WC_REF#refs/remotes/}; name=${name#refs/heads/}
  WC_LATER_AT="$name ($(git -C "$WC_DIR" rev-parse --short "$WC_REF"))"
fi

wc_decl() {  # wc_decl <rev> <pkg> <regex> — the first declaration in the package, as <rev>:<path>:<line>:<text>
  git -C "$WC_DIR" grep -n -E "$3" "$1" -- "packages/$2/src/*.js" 2>/dev/null | head -1 || true
}
wc_later() {  # wc_later <pkg> <regex> — ", declared after it at <ref> (<sha>) <path>:<line>", or nothing
  local hit
  [ -n "$WC_REF" ] || return 0
  hit=$(wc_decl "$WC_REF" "$1" "$2")
  [ -n "$hit" ] || return 0
  printf ', declared after it at %s %s:%s' "$WC_LATER_AT" "$(printf '%s' "$hit" | cut -d: -f2)" "$(printf '%s' "$hit" | cut -d: -f3)"
}

# Web component properties that the added Java lines sync, read at the pinned version.
# A `notify: true` property with a default fires `<prop>-changed` on its first update, and
# the Flow client syncs the default while the server holds no value. A server listener of
# that property then runs once with no user action.
WC_PROPS=""; WC_SEEN=" "
WC_METHODS=""; WM_SEEN=" "
for f in $(printf '%s\n' $PROD | grep '\.java$' || true); do
  added=$(git diff -U0 --no-color "$BASE..$HEAD" -- "$f" | grep '^+' | grep -v '^+++' || true)
  props=$(printf '%s\n' "$added" \
    | grep -oE '(property *= *|[sg]etProperty(Raw)?\(|PropertyChangeListener\()"[A-Za-z][A-Za-z0-9]*"' \
    | grep -oE '"[^"]+"' | tr -d '"' | sort -u || true)
  methods=$(printf '%s\n' "$added" | grep -oE 'callJsFunction\("[A-Za-z_][A-Za-z0-9_]*"' \
    | grep -oE '"[^"]+"' | tr -d '"' | sort -u || true)
  [ -n "$props$methods" ] || continue
  npm=$(git grep -h -oE '@NpmPackage\(value *= *"@vaadin/[a-z0-9-]+", *version *= *"[^"]+"' \
    "$HEAD" -- "$(dirname "$f")" 2>/dev/null | head -1 || true)
  pkg=$(printf '%s' "$npm" | sed -nE 's#.*"@vaadin/([a-z0-9-]+)".*#\1#p')
  ver=$(printf '%s' "$npm" | sed -nE 's#.*version *= *"([^"]+)".*#\1#p')
  # A file without an @NpmPackage next to it (a TestBench element) reads the property
  # from a test, not through a Flow sync.
  [ -n "$pkg" ] || continue
  for prop in $props; do
    case "$WC_SEEN" in *" $prop "*) continue ;; esac
    WC_SEEN="$WC_SEEN$prop "
    tag="v$ver"
    if ! git -C "$WC_DIR" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
      WC_PROPS="${WC_PROPS}wc_property: $prop -> unknown (no tag $tag in $WC_DIR)
"; continue
    fi
    # Only the package of the component: another package can declare a property of the
    # same name.
    hit=$(wc_decl "$tag" "$pkg" "^[[:space:]]+$prop: \{")
    if [ -z "$hit" ]; then
      later=$(wc_later "$pkg" "^[[:space:]]+$prop: \{")
      if [ -n "$later" ]; then
        WC_PROPS="${WC_PROPS}wc_property: $prop -> not in @vaadin/$pkg@$ver$later
"
      else
        WC_PROPS="${WC_PROPS}wc_property: $prop -> not declared in @vaadin/$pkg@$ver (a native, inherited or connector property)
"
      fi
      continue
    fi
    path=$(printf '%s' "$hit" | cut -d: -f2)
    line=$(printf '%s' "$hit" | cut -d: -f3)
    # The block ends at the first closing brace with the indent of the declaration.
    attrs=$(git -C "$WC_DIR" show "$tag:$path" | awk -v s="$line" '
      NR == s { match($0, /^[ \t]*/); ind = substr($0, 1, RLENGTH); next }
      NR > s {
        if (index($0, ind "}") == 1) exit
        t = $0; gsub(/^[ \t]+|,[ \t]*$/, "", t)
        if (t ~ /^value:/ && !v) { v = 1; sub(/^value:[ \t]*/, "", t); printf "value=%s ", substr(t, 1, 40) }
        else if (t ~ /^type:/ && !ty) { ty = 1; sub(/^type:[ \t]*/, "", t); printf "type=%s ", t }
        else if (t ~ /^notify: *true/) printf "notify=true "
        else if (t ~ /^reflectToAttribute: *true/) printf "reflect=true "
        else if (t ~ /^sync: *true/) printf "sync=true "
      }' | sed 's/ *$//')
    WC_PROPS="${WC_PROPS}wc_property: $prop -> @vaadin/$pkg@$ver $path:$line${attrs:+ $attrs}
"
  done
  # Web component methods that the added Java lines call, read at the pinned version.
  for m in $methods; do
    case "$WM_SEEN" in *" $m "*) continue ;; esac
    WM_SEEN="$WM_SEEN$m "
    tag="v$ver"
    if ! git -C "$WC_DIR" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
      WC_METHODS="${WC_METHODS}wc_method: $m -> unknown (no tag $tag in $WC_DIR)
"; continue
    fi
    re="^[[:space:]]+(async[[:space:]]+)?$m\([^)]*\)[[:space:]]*\{"
    hit=$(wc_decl "$tag" "$pkg" "$re")
    if [ -n "$hit" ]; then
      WC_METHODS="${WC_METHODS}wc_method: $m -> @vaadin/$pkg@$ver $(printf '%s' "$hit" | cut -d: -f2):$(printf '%s' "$hit" | cut -d: -f3)
"; continue
    fi
    later=$(wc_later "$pkg" "$re")
    if [ -n "$later" ]; then
      WC_METHODS="${WC_METHODS}wc_method: $m -> not in @vaadin/$pkg@$ver$later
"
    else
      WC_METHODS="${WC_METHODS}wc_method: $m -> not declared in @vaadin/$pkg@$ver (an inherited method, or none)
"
    fi
  done
done

# ── Print ─────────────────────────────────────────────────────────────
[ -n "$WC_PROPS$WC_METHODS" ] || exit 0
printf '%s' "$WC_PROPS$WC_METHODS"
echo "rule: Each \`wc_property\` line gives the web component declaration of a property that the added Java lines sync. Each \`wc_method\` line gives the declaration of a method that they call with callJsFunction."
if printf '%s' "$WC_PROPS" | grep -q 'notify=true'; then
  echo "rule: A \`wc_property\` with \`notify=true\` and a default fires \`<prop>-changed\` on the first update of the web component. The Flow client syncs that default while the server holds no value, so a server property listener runs once on attach with no user action. Check whether a listener of this diff fires an event or sets state for that first sync."
fi
if printf '%s' "$WC_PROPS$WC_METHODS" | grep -q 'declared after it'; then
  echo "rule: A \`declared after it\` entry is newer than the pinned @NpmPackage version. The Flow change lands before the version bump, so a client error at the pinned version is expected and is not a finding. Report the missing bump only when the PR body does not name it."
fi
exit 0
