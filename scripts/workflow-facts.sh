#!/usr/bin/env bash
# workflow-facts.sh — the facts of a GitHub Actions workflow change that the diff does not
# show. A review of a workflow change depends on the code of each action it calls, on the
# token that each job gets, and on who triggers the runs.
#
# Usage:
#   workflow-facts.sh --base <sha> --head <sha> [--repo <owner/name>] [--no-gh]
#
# Run it from inside the target repository. review-plan.sh calls it when a file under
# .github/workflows/ changed. It prints nothing when no workflow changed.
#
# Lines:
#   uses: <action>@<ref> (<sha|tag|branch|local|docker>) [read: <gh api path>]
#     One line per action that an added line calls. A branch ref can change after the review.
#   jobs_without_permissions: <file>: <job> [(new)], ...
#     Jobs of a changed workflow with no `permissions:` block and no workflow-level block.
#     Such a job gets the repository default token (see default_token).
#   default_token: <read|write>, can_approve_pull_request_reviews: <true|false>
#   bot_authors_30d: <login> (<count>), ...
#     Bots that opened a PR in the last 30 days. Their pushes trigger pull_request runs too.
#   hint: <one line>
#
# --repo names the repository for the gh calls. The default is `gh repo view`.
# --no-gh skips every gh call and prints only the facts that git can answer. The smoke test
#   uses it.
#
# Exit codes: 0 ok · 2 usage error.
set -uo pipefail

BASE=""; HEAD=""; REPO=""; USE_GH=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:?--base requires a value}"; shift 2 ;;
    --head) HEAD="${2:?--head requires a value}"; shift 2 ;;
    --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
    --no-gh) USE_GH=false; shift ;;
    --help|-h) sed -n '2,/^set -uo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$BASE" ] && [ -n "$HEAD" ] || { echo "error: --base and --head are required" >&2; exit 2; }

FILES=$(git diff --name-only --no-renames --diff-filter=AM "$BASE..$HEAD" -- \
  '.github/workflows/*.yml' '.github/workflows/*.yaml' 2>/dev/null)
[ -n "$FILES" ] || exit 0

# ── Actions that added lines call ─────────────────────────────────────
# `owner/repo/path@ref` → the action.yml at that ref, so the reviewer reads the inputs and
# the code that the workflow relies on.
git diff -U0 --no-renames "$BASE..$HEAD" -- $FILES 2>/dev/null \
  | sed -nE 's/^\+[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*["'\'']?([^"'\''[:space:]#]+).*/\2/p' \
  | sort -u \
  | while IFS= read -r spec; do
      case "$spec" in
        ./*) echo "uses: $spec (local)"; continue ;;
        docker://*) echo "uses: $spec (docker)"; continue ;;
      esac
      action="${spec%@*}"; ref="${spec##*@}"
      if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then kind=sha
      elif [[ "$ref" =~ ^v?[0-9]+(\.[0-9]+)*$ ]]; then kind=tag
      else kind=branch; fi
      owner_repo=$(printf '%s' "$action" | cut -d/ -f1-2)
      path=$(printf '%s' "$action" | cut -d/ -f3-)
      echo "uses: $spec ($kind) read: repos/$owner_repo/contents/${path:+$path/}action.yml?ref=$ref"
    done

# ── Jobs without a permissions block ──────────────────────────────────
# Prints one job name per line, then `workflow-level` when the file sets permissions for
# every job. Job keys sit at the first indent under `jobs:`, job properties one level deeper.
jobs_of() {  # jobs_of <rev> <file> → "<job> <has_permissions 0|1>" lines, or "workflow-level"
  git show "$1:$2" 2>/dev/null | awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    /^permissions:/ { print "workflow-level"; next }
    /^jobs:/ { in_jobs = 1; next }
    /^[^[:space:]]/ { in_jobs = 0 }
    !in_jobs { next }
    {
      match($0, /^ */); ind = RLENGTH
      if (job_ind == 0) job_ind = ind
      if (ind == job_ind) {
        if (job != "") print job, perm
        job = $1; sub(/:.*$/, "", job); perm = 0; prop_ind = 0; next
      }
      if (prop_ind == 0) prop_ind = ind
      if (ind == prop_ind && $1 == "permissions:") perm = 1
    }
    END { if (job != "") print job, perm }'
}
NO_PERMS=""
for f in $FILES; do
  head_jobs=$(jobs_of "$HEAD" "$f")
  printf '%s\n' "$head_jobs" | grep -qx 'workflow-level' && continue
  base_jobs=$(jobs_of "$BASE" "$f" | awk '{ print $1 }')
  while read -r job perm; do
    [ -n "$job" ] && [ "$perm" = 0 ] || continue
    new=""
    printf '%s\n' "$base_jobs" | grep -qxF "$job" || new=" (new)"
    NO_PERMS="${NO_PERMS:+$NO_PERMS, }$f: $job$new"
  done <<< "$head_jobs"
done
echo "jobs_without_permissions: ${NO_PERMS:-none}"

[ "$USE_GH" = true ] || exit 0

# ── Repository facts ──────────────────────────────────────────────────
[ -n "$REPO" ] || REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
if [ -z "$REPO" ]; then
  echo "default_token: unknown (no repository)"
  exit 0
fi
TOKEN=$(gh api "repos/$REPO/actions/permissions/workflow" \
  --jq '"\(.default_workflow_permissions), can_approve_pull_request_reviews: \(.can_approve_pull_request_reviews)"' 2>/dev/null || echo "")
echo "default_token: ${TOKEN:-unknown (the API refused, it needs admin access)}"

SINCE=$(date -u -v-30d +%F 2>/dev/null || date -u -d '30 days ago' +%F)
BOTS=$(gh pr list --repo "$REPO" --state all --limit 200 --search "created:>=$SINCE" --json author \
  --jq '[.[] | select(.author.is_bot) | .author.login] | group_by(.) | map("\(.[0]) (\(length))") | join(", ")' 2>/dev/null || echo "")
echo "bot_authors_30d: ${BOTS:-none}"

if [ -n "$NO_PERMS" ] && [[ "$TOKEN" == write* ]]; then
  echo "hint: a job without permissions gets a write token here; check that each such job needs it"
fi
if [[ "$BOTS" == *dependabot* ]] \
  && for f in $FILES; do git show "$HEAD:$f"; done 2>/dev/null | grep -q 'secrets\.'; then
  echo "hint: runs that Dependabot triggers get Dependabot secrets only, so each \`secrets.*\` value is empty there"
fi
