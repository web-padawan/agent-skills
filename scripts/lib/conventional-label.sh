# conventional-label.sh — sourced by post-comment.sh and post-review.sh.
#
# check_conventional_label <message>
#   Returns 0 when the first line of <message> is `**<label>:** <subject>` or
#   `**<label> (<deco>[, <deco>]):** <subject>`, with every token from the closed
#   vocabulary in references/severity.md (Rendering). Otherwise prints why to
#   stderr and returns 1. A comment that fails here never reaches GitHub — a
#   refused post beats an unparseable one.

CC_LABELS='nitpick|suggestion|issue|todo|question|thought|chore|note'
CC_CATEGORIES='scope|behavior|fix|boundary|api|impact|logic|conventions|reuse|maintainability|comments|tests'
CC_ROUTES='a11y|design|semver|flow'
CC_MODIFIERS='blocking|non-blocking|if-minor'

check_conventional_label() {
  local deco first
  deco="($CC_CATEGORIES|$CC_ROUTES|$CC_MODIFIERS)"
  first="${1%%$'\n'*}"
  if printf '%s' "$first" | grep -Eq "^\*\*($CC_LABELS)( \($deco(, $deco)?\))?:\*\* .+"; then
    return 0
  fi
  echo "error: the message must open with a bold Conventional Comments label, e.g. '**issue (behavior, blocking):** <claim>'" >&2
  echo "hint: labels: ${CC_LABELS//|/ } · decorations: a pipeline category, a11y/design/semver/flow, blocking/non-blocking/if-minor (at most two) · pass --no-label for a reply or the summary comment" >&2
  echo "got: $first" >&2
  return 1
}
