# store.sh: sourced by review-plan.sh. The report paths, and the findings file that the
# last self-review of the branch wrote.
#
# Reads: MODE, BRANCH, HEAD, FRESH, REPORT_DIR
# Sets: SLUG, REPORT_DIR, FINDINGS_FILE, EARLIER_MODE, EARLIER_HEAD, EARLIER_COUNT,
#       EARLIER_OPEN, EARLIER_LIST, CHANGED_SINCE

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
  # (skills/self-review/references/finalize.md, "Findings file"). One review does not find
  # everything, so the next one starts from it:
  #   same      the head is unchanged: a further round. The earlier findings must not repeat.
  #   delta     the head descends from the reviewed one: the author changed the branch. Each
  #             pass reconciles the earlier findings of its categories, and C findings stay
  #             on the lines changed since (the markers below).
  #   rewritten the reviewed head is gone (rebase, force-push): reconcile, no line markers.
  FINDINGS_FILE=""; EARLIER_MODE="none"; EARLIER_HEAD=""; EARLIER_COUNT=0; EARLIER_OPEN=0
  EARLIER_LIST=""; CHANGED_SINCE=""
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
      EARLIER_COUNT=$(jq '.findings | length' "$FINDINGS_FILE")
      EARLIER_OPEN=$(jq '[.findings[] | select(.status as $s | ["open", "not_fixed", "partially_fixed", "fixed_wrongly"] | index($s))] | length' "$FINDINGS_FILE")
      if [ "$EARLIER_HEAD" = "$HEAD" ]; then
        EARLIER_MODE="same"
      elif [ -n "$EARLIER_HEAD" ] && git merge-base --is-ancestor "$EARLIER_HEAD" "$HEAD" 2>/dev/null; then
        EARLIER_MODE="delta"
        # One line per file: the new-side line ranges that changed since the reviewed head.
        CHANGED_SINCE=$(git diff --unified=0 --no-renames "$EARLIER_HEAD..$HEAD" 2>/dev/null | awk '
          /^\+\+\+ b\// { f = substr($0, 7); next }
          /^\+\+\+ / { f = ""; next }
          /^@@/ && f != "" {
            split($3, a, ","); s = substr(a[1], 2) + 0; n = (a[2] == "" ? 1 : a[2] + 0)
            if (n > 0) r[f] = r[f] (r[f] == "" ? "" : ", ") (n > 1 ? s "-" (s + n - 1) : s)
          }
          END { for (f in r) print f ": " r[f] }' | sort)
      else
        EARLIER_MODE="rewritten"
      fi
      # A finding that triage merged into another one rides on the kept line, so a
      # further round sees it and does not report it again.
      EARLIER_LIST=$(jq -r '.findings[] | "\(.id) | \(.status) | \(.category) | \(.file // "-"):\(.line // "-") | \(.tier) | \(.claim)" + ([.merged[]? | " Merged: \(.file // "-"):\(.line // "-") \(.claim)"] | join(""))' "$FINDINGS_FILE")
    fi
  fi
  return 0
}
