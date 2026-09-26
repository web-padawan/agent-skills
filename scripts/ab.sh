#!/usr/bin/env bash
# ab.sh — run one command against the current tree and against another ref of some paths,
# then diff the two outputs. Restores the paths on every exit, including a failure.
#
# Usage:
#   ab.sh --ref <ref> --path <p> [--path <p>]... [--port N] [--ignore <regex>] [--out-dir <dir>]
#         -- <command> [args...]
#
# B is the current tree. A is the tree with <paths> taken from <ref> (`git checkout <ref> -- <paths>`).
# The command runs through `bash -c`, so quote it as one argument or pass it after `--`.
# --port checks the dev server on that port before the first run and restarts it after each
#   swap, because a long-running web-dev-server can keep serving the old module (see
#   dev-server.sh --check).
# --ignore drops lines that match the regex from both outputs before the diff. Progress bars
#   and durations are the usual noise. Blank lines are always dropped.
# --out-dir keeps A.log and B.log. Default ${TMPDIR:-/tmp}/ab-<time>.
#
# Guards: refuses when <paths> hold uncommitted changes, because the restore would erase them.
# Warns when <ref> and HEAD are identical for <paths>. Never uses `git stash`.
#
# Exit codes: 0 outputs identical · 1 outputs differ · 2 guard or usage error.
set -uo pipefail

REF=""
PATHS=()
PORT=""
IGNORE=""
OUT_DIR=""
CMD=()

while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="${2:?--ref requires a value}"; shift ;;
    --path) PATHS+=("${2:?--path requires a value}"); shift ;;
    --port) PORT="${2:?--port requires a value}"; shift ;;
    --ignore) IGNORE="${2:?--ignore requires a value}"; shift ;;
    --out-dir) OUT_DIR="${2:?--out-dir requires a value}"; shift ;;
    --help|-h) sed -n '2,21p' "$0"; exit 0 ;;
    --) shift; CMD=("$@"); break ;;
    *) echo "unknown argument: $1 (put the command after --)" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$REF" ] && [ ${#PATHS[@]} -gt 0 ] && [ ${#CMD[@]} -gt 0 ] || { sed -n '2,21p' "$0"; exit 2; }

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "refuse: not a git repository" >&2; exit 2; }
cd "$ROOT"
git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || { echo "refuse: unknown ref $REF" >&2; exit 2; }
DIRTY=$(git status --porcelain --untracked-files=no -- "${PATHS[@]}")
if [ -n "$DIRTY" ]; then
  echo "refuse: uncommitted changes under the A/B paths, commit them first:" >&2
  printf '%s\n' "$DIRTY" >&2
  exit 2
fi
for p in "${PATHS[@]}"; do
  git cat-file -e "$REF:$p" 2>/dev/null || { echo "refuse: $p does not exist in $REF" >&2; exit 2; }
done
if git diff --quiet HEAD "$REF" -- "${PATHS[@]}"; then
  echo "warn: HEAD and $REF are identical for the A/B paths, both runs see the same code" >&2
fi

[ -n "$OUT_DIR" ] || OUT_DIR="${TMPDIR:-/tmp}/ab-$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR//\/\//\/}"
mkdir -p "$OUT_DIR"
DEV="$(cd "$(dirname "$0")" && pwd)/dev-server.sh"
HEAD_SHORT=$(git rev-parse --short HEAD)
REF_SHORT=$(git rev-parse --short "$REF")
CMD_STR="${CMD[*]}"

server() {
  # $1 is a dev-server.sh command: ensure or restart.
  [ -n "$PORT" ] || return 0
  local check=()
  for p in "${PATHS[@]}"; do [ -f "$p" ] && check=(--check "$p") && break; done
  "$DEV" "$1" --port "$PORT" ${check[@]+"${check[@]}"} | sed 's/^/  server: /'
}

restore() {
  git checkout HEAD -- "${PATHS[@]}" 2>/dev/null
  git reset -q HEAD -- "${PATHS[@]}" 2>/dev/null
  if [ -n "$(git status --porcelain --untracked-files=no -- "${PATHS[@]}")" ]; then
    echo "ERROR: restore left changes under the A/B paths, inspect git status" >&2
  fi
}
SWAPPED=false
CHILD=""
cleanup() {
  [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null
  if [ "$SWAPPED" = true ]; then
    restore
    SWAPPED=false
    server restart >/dev/null
    echo "interrupted: paths restored" >&2
  fi
}
trap cleanup EXIT
trap 'cleanup; trap - EXIT; exit 130' INT TERM

run_side() {
  # $1 label, $2 description. The command runs as a child, so that a signal reaches the
  # trap at once instead of after the command ends.
  echo "== $1: $2"
  bash -c "$CMD_STR" > "$OUT_DIR/$1.log" 2>&1 &
  CHILD=$!
  wait "$CHILD"
  local code=$?
  CHILD=""
  echo "$code" > "$OUT_DIR/$1.exit"
  echo "  exit $code, $(wc -l < "$OUT_DIR/$1.log" | tr -d ' ') lines → $OUT_DIR/$1.log"
}

echo "command: $CMD_STR"
echo "paths: ${PATHS[*]}"
server ensure
run_side B "current tree (HEAD $HEAD_SHORT)"

git checkout "$REF" -- "${PATHS[@]}" || { echo "refuse: checkout from $REF failed" >&2; exit 2; }
SWAPPED=true
server restart
run_side A "$REF ($REF_SHORT) for the paths"

restore
SWAPPED=false
server restart
trap - EXIT INT TERM

filter() {
  if [ -n "$IGNORE" ]; then grep -vE "$IGNORE" "$1" | grep -v '^[[:space:]]*$'; else grep -v '^[[:space:]]*$' "$1"; fi
}
filter "$OUT_DIR/A.log" > "$OUT_DIR/A.filtered"
filter "$OUT_DIR/B.log" > "$OUT_DIR/B.filtered"
echo "== diff A ($REF_SHORT) → B ($HEAD_SHORT)"
if diff -q "$OUT_DIR/A.filtered" "$OUT_DIR/B.filtered" >/dev/null; then
  echo "RESULT: identical (exit A $(cat "$OUT_DIR/A.exit"), B $(cat "$OUT_DIR/B.exit"))"
  exit 0
fi
diff -u "$OUT_DIR/A.filtered" "$OUT_DIR/B.filtered" | tail -n +3 | head -80
CHANGED=$(diff "$OUT_DIR/A.filtered" "$OUT_DIR/B.filtered" | grep -cE '^[<>]')
echo "RESULT: differs ($CHANGED lines; exit A $(cat "$OUT_DIR/A.exit"), B $(cat "$OUT_DIR/B.exit"))"
exit 1
