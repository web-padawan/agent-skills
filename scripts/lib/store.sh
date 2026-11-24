# store.sh: sourced by review-plan.sh. The report paths, and the findings file that the
# last self-review of the branch wrote.
#
# Reads: MODE, BRANCH, HEAD, FRESH, REPORT_DIR
# Sets: SLUG, REPORT_DIR, FINDINGS_FILE, EARLIER_MODE, EARLIER_HEAD, EARLIER_COUNT,
#       EARLIER_LIST

plan_store() {
  # ── Report paths
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

  # ── Earlier findings
  # The findings file that the last self-review of this branch wrote
  # (skills/self-review/references/finalize.md, "Findings file"). One round does not find
  # everything, so a further round on the same head starts from it: the earlier findings
  # must not repeat. A file of another head is ignored, and the review starts new.
  FINDINGS_FILE=""; EARLIER_MODE="none"; EARLIER_HEAD=""; EARLIER_COUNT=0
  EARLIER_LIST=""
  if [ "$MODE" = "self" ] && [ "$REPORT_DIR" != "SCRATCHPAD" ] && [ -n "$HEAD" ]; then
    FINDINGS_FILE="$REPORT_DIR/$SLUG-findings.json"
    if [ ! -f "$FINDINGS_FILE" ]; then
      EARLIER_MODE="none"
    elif [ "$FRESH" = true ]; then
      EARLIER_MODE="ignored (--fresh)"
    elif ! command -v jq >/dev/null 2>&1; then
      EARLIER_MODE="unreadable (jq not found)"
    elif ! jq -e '.findings | type == "array"' "$FINDINGS_FILE" >/dev/null 2>&1; then
      EARLIER_MODE="unreadable (no findings array)"
    elif ! jq -e '(.schema // 1) == 1' "$FINDINGS_FILE" >/dev/null 2>&1; then
      # A file without `schema` is schema 1. A higher schema comes from a newer plugin.
      EARLIER_MODE="unreadable (schema $(jq -r '.schema' "$FINDINGS_FILE"))"
    else
      EARLIER_HEAD=$(jq -r '.head // empty' "$FINDINGS_FILE")
      if [ "$EARLIER_HEAD" != "$HEAD" ]; then
        EARLIER_MODE="ignored (the findings file is of ${EARLIER_HEAD:0:10}, not of this head)"
        return 0
      fi
      EARLIER_MODE="same"
      EARLIER_COUNT=$(jq '.findings | length' "$FINDINGS_FILE")
      # A finding that triage merged into another one rides on the kept line, so a
      # further round sees it and does not report it again.
      EARLIER_LIST=$(jq -r '.findings[] | "\(.id) | \(.status) | \(.category) | \(.file // "-"):\(.line // "-") | \(.tier) | \(.claim)" + ([.merged[]? | " Merged: \(.file // "-"):\(.line // "-") \(.claim)"] | join(""))' "$FINDINGS_FILE")
    fi
  fi
  return 0
}
