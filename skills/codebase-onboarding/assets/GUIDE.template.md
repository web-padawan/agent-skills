<!--
Output template for the onboarding guide of codebase-onboarding. Copy the structure, replace
the placeholders and delete every comment. Print the result to the conversation.
-->
# Onboarding guide: [Project name]

## Overview

[2 to 3 sentences: what the project does, who it serves, and its current state]

## Tech stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Language | [JavaScript or TypeScript] | [version] |
| Runtime | Node.js | [version from `.nvmrc` or `engines`] |
| Package manager | [npm, Yarn, pnpm or Bun] | [version] |
| Framework | [detected] | [version] |
| Database | [detected] | [version] |
| Testing | [detected] | - |

## Architecture

[A diagram or prose: how the parts connect]
[For a monorepo: the map of the workspace layout]

## Key entry points

- **[Entry point]**: [path]. [What it does]
- **[Config source of truth]**: [path]. [What it controls]

## Directory map

[Each top-level directory and its purpose. Omit the names that explain themselves.]

## Request lifecycle

[Trace one API request from the entry to the response in 4 to 6 steps. For a library, trace one public export.]

## Common commands

- **Install**: [command]
- **Dev server**: [command]
- **Tests**: [command]
- **Lint**: [command]
- **Build**: [command]

## Conventions

- [File naming pattern]
- [Error handling approach]
- [Test file naming]
- [Git commit style, if detectable]

## Where to look

| I want to... | Look at... |
|--------------|-----------|
| [common task] | [path] |
| [common task] | [path] |

## Gotchas and known issues

- [A setup requirement or a trap that is not obvious]
- [Each conflicting signal that you could not resolve]
- [Write "Could not determine [X]" for each fact that stays unclear. Never guess.]
