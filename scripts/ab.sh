#!/usr/bin/env bash
# ab.sh — run one command against the current tree and against another ref of some paths,
# then diff the two outputs. Restores the paths on every exit, including a failure. Only a
# SIGKILL skips the restore. The `swapped:` line prints the command for that case.
#
# Usage:
#   ab.sh --ref <ref> --path <p> [--path <p>]... [--port N] [--ignore <regex>] [--out-dir <dir>]
#         -- <command> [args...]
#
# B is the current working tree, with the uncommitted changes to tracked files, staged or not.
# A is the tree with <paths> exactly as in <ref>
#   (`git restore --source=<ref> --worktree -- <paths>`): files that only B has are removed and
#   files that only <ref> has are created. The restore brings back B from the snapshot and
#   deletes the files that only <ref> has. Untracked files under <paths> stay in place for both
#   runs. The index never changes. Compare an uncommitted change with HEAD: --ref HEAD.
# The command runs through `bash -c`, so quote it as one argument or pass it after `--`.
# --port checks the dev server on that port before the first run and restarts it after each
#   swap, because a long-running web-dev-server can keep serving the old module (see
#   dev-server.sh --check).
# --ignore drops lines that match the regex from both outputs before the diff. Progress bars
#   and durations are the usual noise. Blank lines are always dropped.
# --out-dir keeps A.log and B.log. Default ${TMPDIR:-/tmp}/ab-<time>.
#
# Snapshot: before the swap, the tracked files under <paths> go into a git tree, kept as
#   refs/worktree/ab-snapshot until the restore matches that tree. A SIGKILL leaves the ref, and
#   its message holds the recovery command.
# Guards: refuses while refs/worktree/ab-snapshot exists, because an earlier run did not restore.
# Refuses when an untracked file has the path of a file that only <ref> has, because the swap
# would overwrite it and the restore would delete it.
# Warns when <ref> and the working tree are identical for <paths>. Never uses `git stash`.
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
    --help|-h) sed -n '2,32p' "$0"; exit 0 ;;
    --) shift; CMD=("$@"); break ;;
    *) echo "unknown argument: $1 (put the command after --)" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$REF" ] && [ ${#PATHS[@]} -gt 0 ] && [ ${#CMD[@]} -gt 0 ] || { sed -n '2,32p' "$0"; exit 2; }

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "refuse: not a git repository" >&2; exit 2; }
cd "$ROOT"
git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || { echo "refuse: unknown ref $REF" >&2; exit 2; }
SNAP_REF=refs/worktree/ab-snapshot
if git rev-parse --verify --quiet "$SNAP_REF" >/dev/null; then
  echo "refuse: an earlier run stopped before its restore. Recover with:" >&2
  git log -1 --format=%s "$SNAP_REF" | sed 's/^/  /' >&2
  exit 2
fi
snapshot() {
  # Prints the tree of the working tree for the tracked files under <paths>, staged or not.
  # Works on a copy of the index, so the real index never changes.
  local idx rc=0 tree
  idx=$(git rev-parse --git-path ab-snapshot.index)
  cp "$(git rev-parse --git-path index)" "$idx" || return 1
  GIT_INDEX_FILE="$idx" git add -u -- "${PATHS[@]}" && tree=$(GIT_INDEX_FILE="$idx" git write-tree) || rc=1
  rm -f "$idx"
  [ "$rc" = 0 ] && echo "$tree"
}
SNAP=$(snapshot) || { echo "refuse: cannot snapshot the A/B paths, check for unmerged files" >&2; exit 2; }
for p in "${PATHS[@]}"; do
  git cat-file -e "$REF:$p" 2>/dev/null || { echo "refuse: $p does not exist in $REF" >&2; exit 2; }
done
# Files that only <ref> has. The swap creates them and the restore deletes them.
A_ONLY=()
while IFS= read -r f; do
  [ -n "$f" ] && A_ONLY+=("$f")
done < <(git diff --name-only --no-renames --diff-filter=A "$SNAP" "$REF" -- "${PATHS[@]}")
for f in ${A_ONLY[@]+"${A_ONLY[@]}"}; do
  if [ -e "$f" ]; then
    echo "refuse: untracked $f exists only in $REF, the swap would overwrite it" >&2
    exit 2
  fi
done
if git diff --quiet "$SNAP" "$REF" -- "${PATHS[@]}"; then
  echo "warn: the working tree and $REF are identical for the A/B paths, both runs see the same code" >&2
fi

[ -n "$OUT_DIR" ] || OUT_DIR="${TMPDIR:-/tmp}/ab-$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR//\/\//\/}"
mkdir -p "$OUT_DIR"
DEV="$(cd "$(dirname "$0")" && pwd)/dev-server.sh"
HEAD_SHORT=$(git rev-parse --short HEAD)
REF_SHORT=$(git rev-parse --short "$REF")
CMD_STR="${CMD[*]}"

server() {
  # $1 is a dev-server.sh command: ensure or restart. Runs as a child, like run_side, so that
  # a signal reaches the trap while the server restarts instead of after it.
  [ -n "$PORT" ] || return 0
  local check=()
  for p in "${PATHS[@]}"; do [ -f "$p" ] && check=(--check "$p") && break; done
  { "$DEV" "$1" --port "$PORT" ${check[@]+"${check[@]}"} | sed 's/^/  server: /'; } &
  CHILD=$!
  wait "$CHILD"
  CHILD=""
}

restore() {
  # Brings back the snapshot. Deletes the ref only when the working tree matches it again.
  git restore --source="$SNAP" --worktree -- "${PATHS[@]}" 2>/dev/null
  local f ok=true
  for f in ${A_ONLY[@]+"${A_ONLY[@]}"}; do
    rm -f -- "$f"
    rmdir -p -- "$(dirname "$f")" 2>/dev/null
  done
  for f in ${A_ONLY[@]+"${A_ONLY[@]}"}; do
    [ -e "$f" ] && echo "ERROR: restore left $f from $REF, delete it" >&2 && ok=false
  done
  if [ "$(snapshot)" != "$SNAP" ]; then
    echo "ERROR: the A/B paths do not match the snapshot. $SNAP_REF stays. Recover with: $HINT" >&2
    ok=false
  fi
  [ "$ok" = true ] && git update-ref -d "$SNAP_REF"
  [ "$ok" = true ]
}
SWAPPED=false
CHILD=""
cleanup() {
  [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null
  if [ "$SWAPPED" = true ]; then
    restore && echo "interrupted: paths restored" >&2
    SWAPPED=false
    server restart >/dev/null
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

HINT="git restore --source=$SNAP_REF --worktree -- ${PATHS[*]}"
[ ${#A_ONLY[@]} -gt 0 ] && HINT="$HINT && rm -f -- ${A_ONLY[*]}"
HINT="$HINT && git update-ref -d $SNAP_REF"
SNAP_COMMIT=$(git commit-tree "$SNAP" -p HEAD -m "$HINT") &&
  git update-ref "$SNAP_REF" "$SNAP_COMMIT" "" ||
  { echo "refuse: cannot write $SNAP_REF" >&2; exit 2; }
SWAPPED=true
git restore --source="$REF" --worktree -- "${PATHS[@]}" || { echo "refuse: restore from $REF failed" >&2; exit 2; }
echo "swapped: after a hard kill, restore with: $HINT"
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
