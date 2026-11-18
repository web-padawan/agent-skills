---
name: codebase-onboarding
description: Analyze an unfamiliar Node.js codebase (JavaScript or TypeScript with a root package.json) and produce a structured onboarding guide with the tech stack, architecture map, key entry points, commands, conventions and gotchas, plus a starter CLAUDE.md. Use when the user says "onboard me", "help me understand this codebase", "walk me through this repo", "generate a CLAUDE.md" or "I just joined this project", or asks to set up Claude Code in a Node.js repo for the first time. Not for a repository without a package.json, such as a Java, Python or Go project. Not for an update of an existing CLAUDE.md. Not for one pull request (pr-review).
---

# Codebase Onboarding

This skill analyzes an unfamiliar Node.js codebase. It produces a short onboarding guide and a
starter `CLAUDE.md`. The guide serves a developer who joins the project. The `CLAUDE.md` serves
the first Claude Code session in the repository.

## Scope

Select the scope from the request:

- **Full onboarding**: "Onboard me", "Help me understand this codebase", "I just joined this
  project". Run phases 1 to 4. Print the guide. Then write `CLAUDE.md` to the project root.
- **CLAUDE.md only**: "Generate a CLAUDE.md for this project". Run phases 1 to 3. Then run
  phase 4 for `CLAUDE.md` only.

The skill never writes over a `CLAUDE.md`. If `CLAUDE.md` or `.claude/CLAUDE.md` exists, read it
as a source of facts. Do not write `CLAUDE.md`. Print the filled `CLAUDE.md` template to the
conversation instead. Tell the user that the file exists.

## Workflow

1. Check that the project root has a `package.json`. If it does not, stop. Tell the user
   that the skill covers Node.js projects only.
2. Select the scope. If the request fits neither scope, select full onboarding.
3. Run phase 1.
4. Run phase 2 on the signals of phase 1.
5. Run phase 3. Identify the patterns that the project already uses.
6. If phase 1 found monorepo signals, apply [references/monorepo.md](references/monorepo.md).
7. Produce the outputs of the scope with phase 4.
8. Report each conflict and each unknown. Do not guess.

## Phase 1: Reconnaissance

Collect the raw signals of the project with file listings and searches. Run the checks in
parallel. Read the root `package.json` in full. Its `scripts`, dependencies, `engines`,
`workspaces`, `type` and `packageManager` fields give most of the signals.

| Check | Signals |
| --- | --- |
| Package manager | `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lock`, `bun.lockb`, the `packageManager` field |
| Node.js version | `.nvmrc`, `.node-version`, `engines.node` |
| Framework | `next.config.*`, `nuxt.config.*`, `angular.json`, `vite.config.*`, `svelte.config.*`, `astro.config.*`, `nest-cli.json`, Express, Fastify or Koa in the dependencies |
| Entry points | `main`, `exports` and `bin` in `package.json`, `index.*`, `main.*`, `app.*`, `server.*` |
| Directory structure | The top 2 levels of the tree, without `node_modules`, `.git`, `dist`, `build`, `.next`, `.turbo`, `.cache` |
| Config and tooling | `tsconfig.json`, `eslint.config.*`, `.eslintrc*`, `.prettierrc*`, `Makefile`, `Dockerfile`, `docker-compose*`, `.github/workflows/`, `.env.example` |
| Tests | `test/`, `tests/`, `__tests__/`, `*.test.*`, `*.spec.*`, `jest.config.*`, `vitest.config.*`, `playwright.config.*`, `web-test-runner.config.*` |
| Monorepo | `workspaces` in `package.json`, `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `lerna.json`, `packages/` or `apps/` at the root |

**Conflicting signals**: two signals can disagree. For example, `package.json` lists React, but
`vite.config.*` loads the Vue plugin. Another example is two test runners with a config each.
Read the related files to resolve the conflict. If the conflict stays, report both signals and
name the dominant one.

## Phase 2: Architecture mapping

**Tech stack**:
- JavaScript or TypeScript, and the Node.js version
- The frameworks and the major libraries
- The databases and the ORMs, for example Prisma, Drizzle or TypeORM
- The build tools and the bundlers, for example Vite, webpack, Rollup or `tsc`
- The CI/CD platform

**Architecture pattern**:
- A monolith, a monorepo, microservices, serverless functions, or a library of npm packages
- A split frontend and backend, or one full-stack app
- The API style: REST, GraphQL, gRPC or tRPC

**Key directories**: map each top-level directory to its purpose. Skip a name that explains
itself, such as `src/`.

```
src/components/  → React UI components
src/api/         → API route handlers
src/lib/         → Shared utilities
src/db/          → Database models and migrations
tests/           → Test suites
scripts/         → Build and deployment scripts
```

**Data flow**: trace one typical request from the entry to the response.

- Entry: the router, handler or controller that receives the request
- Validation: the middleware, schemas or guards
- Business logic: the services, models or use cases
- Database access: the ORM, raw queries or repositories

For a library, trace one public export to its implementation. Start from `exports` in
`package.json`, or from `main` if `exports` is absent.

## Phase 3: Convention detection

**Naming**:
- File names: kebab-case, camelCase, PascalCase or snake_case
- The naming patterns of components and classes
- Test file names, for example `*.test.ts` or `*.spec.ts`

**Code patterns**:
- Error handling: `try`/`catch`, result types or error codes
- Dependency injection or direct imports
- The state management approach
- Async code: callbacks, promises or `async`/`await`
- Modules: ES modules or CommonJS. The `type` field of `package.json` sets the default.

**Git conventions**:
- Branch names, from the recent branches
- The commit message style, from the recent commits
- The PR workflow: squash, merge or rebase
- If the history is not available or is shallow, skip this check. An example is a clone with
  `--depth 1`. Write "Git history too shallow to detect conventions".

**Gotchas**: search for the project traps that a new developer often meets.

- A required package manager, for example "use pnpm, not npm"
- A required Node.js version
- Manual environment steps, for example a `.env` file to create, or local secrets
- A command that looks safe but is not, for example a `clean` script that also drops the database
- A service that must run first, for example "Redis must run before the dev server starts"
- Flaky tests, or a test setup that needs special flags

## Phase 4: Outputs

- **Onboarding guide**: print it to the conversation. Fill [assets/GUIDE.template.md](assets/GUIDE.template.md).
  A reader must be able to scan it in under 2 minutes.
- **CLAUDE.md**: write it to the project root. Fill [assets/CLAUDE.template.md](assets/CLAUDE.template.md).
  Keep it under 100 lines. A focused file is better than a complete one.

Write each command with the package manager of the lockfile and a script name from
`package.json`. For example, write `yarn test` in a Yarn project, not `npm test`. If the
lockfile and the `packageManager` field disagree, report the conflict as a gotcha. If no script
exists for a command, write "Could not determine" for it.

## Rules

1. Do not read every file. Read the root `package.json` in full. Read another file only to
   resolve an ambiguous signal.
2. Verify each fact. If a config names one framework and the code uses another, trust the code.
3. Do not write over an existing `CLAUDE.md`.
4. Keep the guide short. It is for a scan, not for an archive.
5. Report each unknown. "Could not determine test runner" is better than a wrong answer.
6. Make the gotchas easy to see in both outputs. A new developer loses the most time on them.
7. List only the dependencies that change how developers write the code.
8. Do not explain a directory name that explains itself.
9. Do not copy the README. The guide adds the structure that the README does not give.
10. Do not guess a convention that the code or the config does not confirm.
