# store.sh: sourced by review-plan.sh. The report paths of a run.
#
# Reads: MODE, BRANCH, REPORT_DIR
# Sets: SLUG, REPORT_DIR

plan_store() {
  SLUG=$(printf '%s' "${BRANCH:-detached}" | tr '/' '-')
  if [ -z "$REPORT_DIR" ]; then
    case "$MODE" in
      # The git directory is never tracked and belongs to one worktree, so the report of
      # each branch survives between runs without a .gitignore entry.
      self) REPORT_DIR=$(git rev-parse --path-format=absolute --git-path self-review 2>/dev/null) \
              || { echo "error: the self-review report dir needs git 2.31 or later" >&2; exit 1; } ;;
      # pr mode never writes into the repo: the review record is the reviewer's own,
      # never committed or posted (the Present step of pr-review).
      pr) REPORT_DIR="SCRATCHPAD" ;;
    esac
  fi
  return 0
}
