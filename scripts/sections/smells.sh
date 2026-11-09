# smells.sh: a section of the context file, sourced by lib/context.sh. The smell vocabulary
# of references/smells.md, for a repository without a conventions doc and without owner rules.
#
# Reads: CONVENTIONS, OWNER_RULES, PLUGIN_ROOT
# Sets: none

if [ -z "$CONVENTIONS" ] && [ -z "$OWNER_RULES" ]; then
  echo
  echo "## Smell vocabulary"
  echo
  block "$PLUGIN_ROOT/references/smells.md" smells
fi
