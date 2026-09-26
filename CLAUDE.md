# agent-skills

This repository is a private Claude Code plugin and its single-plugin marketplace.
It is installed from this local path. Nothing is published. `README.md` describes each skill
and how to install and use the plugin. Do not repeat that content here.

## Layout

- `skills/<name>/SKILL.md`: one skill per folder, with optional `references/`, `scripts/` and `assets/`.
- `agents/`: the reviewer subagents that the review skills launch. Their contract is static.
- `references/`: the pipeline documents that the review skills share. They are tuned prompts.
- `scripts/`: shell helpers that the skills call through `${CLAUDE_PLUGIN_ROOT}`, plus a few
  manual git helpers. `scripts/smoke.sh` checks the ones that rewrite a tree.
- `.claude-plugin/`: the plugin and marketplace manifests.

## Conventions

- Write every markdown file in Simplified Technical English. The rule in
  `.claude/rules/writing-style.md` loads in every session and lists the criteria and the exempt text.
- Create or change a skill with the `authoring-skills` skill. It holds the description,
  body and frontmatter conventions. Agent conventions are in `skills/authoring-skills/references/agents.md`.
- Keep `SKILL.md` under 150 lines. Move depth into `references/`.
- Files in `agents/` and `references/` change review behavior. Change one file per commit and keep the meaning.

## Test loop

1. Commit the change.
2. Run `claude plugin update agent-skills@local`.
3. Start a new session, then run the skill once on a real branch or PR.

## Do not

- Do not commit `.omc/`, `CLAUDE.local.md` or `.claude/*.local.*`. They are ignored.
- Do not add a `version` field to `plugin.json`. Every commit on `main` is a new version.
