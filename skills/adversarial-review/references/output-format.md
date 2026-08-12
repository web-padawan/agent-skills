# Output Format — Worked Example

Canonical example of a well-formed adversarial review comment. Match this shape exactly.

The example below is a real-shaped adversarial review on a small CI-setup PR (a GitHub Actions release workflow for a Ruby gem).

---

## Adversarial Review: Add release workflow with gem-publish action

Overall this is a clean, well-scoped PR. The intent is clear and the workflow already runs green. Below are the issues I found, ordered by severity.

---

### 🔴 High

**Ruby version is hard-coded and will silently go stale**

`ruby-version: "3.2"` in `.github/workflows/release.yml:18` is pinned to a minor version but will diverge from whatever the gemspec declares as the minimum supported Ruby. When Ruby 3.2 reaches EOL, `ruby/setup-ruby` will keep installing it, so CI will keep passing against an unsupported runtime without anyone noticing. Consider:
- Deriving the version from the gemspec (`ruby-version: .ruby-version` file, or reading `required_ruby_version`), or
- At minimum adding a comment that this must be kept in sync with the gemspec's `required_ruby_version`.

---

### 🟠 Medium

**No `timeout-minutes` on the job**

A hung `bundle install` (network blip, registry outage) will run until the 6-hour GitHub Actions default, burning runner minutes and blocking the release until someone cancels it. `timeout-minutes: 15` on the job costs nothing.

**`bundle install --jobs 4` is hard-coded**

The job count `4` may not match the runner's CPU count. Prefer `--jobs "$(nproc)"` or omit `--jobs` to let Bundler use its own default.

---

### 🟡 Low / Nitpicks

**Cache key covers only the gemspec, not `Gemfile`**

An earlier automated review flagged the missing `Gemfile.lock`; the author confirmed this gem intentionally omits the lockfile. However, `Gemfile` itself is also not in the cache key — adding a new group or source to `Gemfile` without touching the gemspec won't invalidate the cache. Adding it costs nothing:

```yaml
key: gems-${{ hashFiles('my-gem.gemspec', 'Gemfile') }}
```

---

### ✅ What is done well

- Actions are pinned to full commit SHAs, not floating tags (previous `@v4` concern was addressed).
- `permissions:` is scoped to the minimum the publish step needs (`contents: read`, `id-token: write`).
- The `concurrency` group prevents two release runs from racing on the same tag.
- The PR is narrowly scoped: one workflow file + rubocop directive cleanup only.

---

**Summary:** Mergeable as-is, but the hard-coded Ruby version is worth addressing before merge to avoid silent drift.
