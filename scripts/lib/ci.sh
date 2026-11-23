# ci.sh: sourced by get-pr-context.sh. The failing checks of the CI_STATUS section.
#
# Reads: none
# Sets: none
#
# An owner lists advisory checks in the `advisory_checks` key of its screening.json, for
# example a quality gate that measures duplication. A failing advisory check is shown, but it
# is not a finding. Every other failing check is an A-tier finding on its own.

advisory_pattern() {  # advisory_pattern <screening.json or nothing> — the patterns joined by |
  local config="$1"
  [ -n "$config" ] && [ -f "$config" ] || return 0
  jq -r '.advisory_checks // [] | join("|")' "$config" 2>/dev/null || true
}

ci_failing() {  # ci_failing <checks, TAB-separated: name, state, elapsed, link> <pattern>
  # Prints the hint and the failing lines. A pattern is an extended regular expression that
  # must match a whole check name, without regard to case.
  local checks="$1" pattern="$2" failing blocking advisory
  failing=$(printf '%s\n' "$checks" | awk -F'\t' '$2=="fail"')
  [ -n "$failing" ] || return 0
  if [ -n "$pattern" ]; then
    advisory=$(printf '%s\n' "$failing" | awk -F'\t' -v p="$pattern" 'tolower($1) ~ ("^(" tolower(p) ")$")')
    blocking=$(printf '%s\n' "$failing" | awk -F'\t' -v p="$pattern" 'tolower($1) !~ ("^(" tolower(p) ")$")')
  else
    advisory=""
    blocking="$failing"
  fi
  if [ -n "$blocking" ]; then
    echo "hint: a failing check is an A-tier finding on its own — name the check in the claim"
    printf '%s\n' "$blocking" | awk -F'\t' '{printf "  failing: %s — %s\n", $1, $4}'
  fi
  if [ -n "$advisory" ]; then
    echo "hint: an advisory check of the owner config is not a finding, also when it fails"
    printf '%s\n' "$advisory" | awk -F'\t' '{printf "  failing (advisory): %s — %s\n", $1, $4}'
  fi
  return 0
}
