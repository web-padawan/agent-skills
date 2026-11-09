# owner.sh: sourced by review-plan.sh, diff-facts.sh and pr-screen.sh. The owner of a
# repository, and the owner directory that holds its fact packs (facts/*.sh), its
# screening config (screening.json) and its rules (rules.md).
#
# Reads: REVIEW_SKILLS_CONFIG_DIR, XDG_CONFIG_HOME, HOME
# Sets: none
#
# The owner directory is <config dir>/<owner>/, else <plugin root>/owners/<owner>/. The
# config dir is REVIEW_SKILLS_CONFIG_DIR, else ${XDG_CONFIG_HOME:-~/.config}/<plugin name>.
# The owner gate is here: a repository of another owner never runs the packs of an owner.

owner_of_url() {  # owner_of_url <remote URL or owner/name> — the owner in lowercase, or nothing
  printf '%s\n' "$1" \
    | sed -E -n 's#^(https?://[^/]+/|ssh://([^@/]+@)?[^/]+/|([^@:/]+@)?[^:/]+:)?([A-Za-z0-9_.-]+)/[A-Za-z0-9_.-]+/?$#\4#p' \
    | tr '[:upper:]' '[:lower:]'
}

owner_of_repo() {  # owner_of_repo — the owner of the upstream remote, else of origin
  owner_of_url "$(git remote get-url upstream 2>/dev/null || git remote get-url origin 2>/dev/null || true)"
}

owner_dir() {  # owner_dir <plugin root> <owner> — the owner directory, or nothing
  local root="$1" owner="$2" name cfg
  [ -n "$owner" ] || return 0
  name=$(jq -r '.name // empty' "$root/.claude-plugin/plugin.json" 2>/dev/null || true)
  cfg="${REVIEW_SKILLS_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/$name}"
  if [ -d "$cfg/$owner" ]; then echo "$cfg/$owner"
  elif [ -d "$root/owners/$owner" ]; then echo "$root/owners/$owner"
  fi
  return 0
}
