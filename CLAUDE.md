# agent-skills

This repository is a private Claude Code plugin and its single-plugin marketplace.
It is installed from this local path. Nothing is published. `README.md` describes each skill
and how to install and use the plugin. Do not repeat that content here.

## Layout

- `skills/<name>/SKILL.md`: one skill per folder, with optional `references/`, `scripts/` and `assets/`.
- `agents/`: the reviewer subagents that the review skills launch. Their contract is static.
- `references/`: the pipeline documents that the review skills share. They are tuned prompts.
- `docs/`: the design history of the pipeline. No skill loads it.
- `scripts/`: shell helpers that the skills call through `${CLAUDE_PLUGIN_ROOT}`, plus a few
  manual git helpers. `scripts/smoke.sh` checks the ones that rewrite a tree, and the guards
  of the review scripts.
- `.claude-plugin/`: the plugin and marketplace manifests.

## Conventions

- Write every markdown file in Simplified Technical English. The rule in
  `.claude/rules/writing-style.md` loads in every session and lists the criteria and the exempt text.
- Create or change a skill with the `authoring-skills` skill. It holds the description,
  body and frontmatter conventions. Agent conventions are in `skills/authoring-skills/references/agents.md`.
- Keep `SKILL.md` under 150 lines. Move depth into `references/`.
- Files in `agents/` and `references/` change review behavior. Change one file per commit and keep the meaning.
- Encode a recurring fix in a script, a check or a contract field before you add text.
  The rule in `.claude/rules/encode-lessons-in-structure.md` loads in every session and gives the order.

## Test loop

1. Save the change. To run a changed script before a commit, call it from this checkout by
   its full path.
2. Commit the change.
3. Run `claude plugin update agent-skills@local`.
4. Start a new session, then run the skill once on a real branch or PR.

The plugin runs from a copy of one commit in `~/.claude/plugins/cache/local/agent-skills/`.
Until you update the plugin, every session runs the skills, agents and scripts of that commit.

## Do not

- Do not commit `.omc/`, `CLAUDE.local.md` or `.claude/*.local.*`. They are ignored.
- Do not add a `version` field to `plugin.json`. Every commit on `main` is a new version.
