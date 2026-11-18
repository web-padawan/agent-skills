# Monorepo handling

Apply these steps when phase 1 finds monorepo signals.

- **Workspace layout**: map `apps/`, `packages/` or the equivalent directories. State what each
  one contains.
- **Root and package config**: shared config sits at the root, for example `turbo.json`,
  `tsconfig.base.json` or `eslint.config.*`. A package config extends or overrides it. Check
  the `extends` field of each package config.
- **Workspace tool**: identify the workspace manager (npm, Yarn or pnpm workspaces). Then
  identify the task runner on top of it (Turborepo, Nx or Lerna), if one exists. Each tool
  has different run conventions.
- **Dev command**: state whether the command runs from the root or from a package directory.
  Prefer a script of the root `package.json` to a direct tool call.
- **Internal packages**: if packages import each other, list the internal package names. A new
  developer must not try to install them from the npm registry.

In the commands below, `web` is the `name` field of the package, or the Nx project name. A
scoped package has a name such as `@acme/web`.

```bash
# npm workspaces
npm run dev --workspace=web

# Yarn workspaces
yarn workspace web dev

# pnpm workspaces
pnpm --filter web dev

# Turborepo
turbo dev                      # all apps
turbo dev --filter=web         # specific app

# Nx
nx serve web

# Lerna
lerna run dev --scope=web
```
