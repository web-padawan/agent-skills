---
name: adversarial-review
description: Use when running a critical, skeptical pass over a GitHub pull request — either as the author before requesting human review, or as a reviewer wanting a structured first cut — produces a findings report grouped by severity (High / Medium / Low / Done well) and, after confirmation, posts it as a single comment on the PR. Not for inline line-by-line comments (pr-review), an interactive walkthrough (guided-review), or your own branch before it has a PR (self-review).
argument-hint: "[PR number or URL, or blank to auto-detect from current branch]"
disable-model-invocation: true
---

# Adversarial Review

Skeptical, reviewer-mode pass over a GitHub pull request. The skill posts a single comment
with the findings in severity groups. The format is standard, so that authors, reviewers, and
downstream tooling can scan reviews consistently.

## Inputs

PR URL or number. If the argument is empty, resolve the PR from the current branch with
`gh pr view`.

## Workflow

1. Resolve the PR: `gh pr view <number-or-url>`.
2. Read the diff: `gh pr diff <number-or-url>`. For a large PR, read the files around the
   diff for the context that the diff lacks.
3. Read the prior discussion: `gh pr view <number-or-url> --json comments,reviews`. Do not
   repeat points that others already made or that the author addressed.
4. Run the review (see [stance](#stance) and [coverage](#coverage)).
5. Format the output per [Output format](#output-format). The format is not negotiable. The
   format is the product.
6. Show the full report in chat. Then ask with a single `AskUserQuestion` (header `Post`):
   "Post this as a comment on the PR?" The options are `Yes — post it` / `No — chat only`.
   If the answer is yes:
   - Write the body to a file in the session scratchpad. Put `:robot: AI-generated` as the
     first line, above the `## Adversarial Review:` heading.
   - Run `gh pr comment <number-or-url> --body-file <that literal path>`. Write the path out
     literally. Shell variables do not persist between tool calls.
   - Always use `--body-file`, never `--body`. An inline body mangles backticks, `$`, and
     code fences.

Do not fix, approve, request changes, or resolve threads. One pass per invocation.

## Stance

- Skeptical, not theatrical. Flag real issues, no filler.
- Evidence over speculation. Name the line and the failure mode. If you are uncertain, say so.
- Do not repeat existing review comments.
- Acknowledge what is done well. This tells the author which decisions you considered and
  endorsed.
- Do not moralize ("be careful", "make sure to"). State the issue.

## Coverage

Check each area below explicitly. If an area has no real finding, say nothing. Do not invent
a finding to fill a group.

- **Correctness**: off-by-one, null/empty cases, races, wrong defaults.
- **Security**: input validation, auth/authz, injection, secrets, sensitive data in responses.
- **Performance**: unnecessary allocations, unbounded loops, repeated layout or measurement
  work on hot paths.
- **API design**: backwards compatibility, naming consistency, error shapes, public surface.
- **Error handling**: swallowed exceptions, leaky messages, non-idempotent retries.
- **Testing**: coverage, edge cases, tautological tests, flaky patterns.
- **Maintainability**: lying comments, dead code, premature abstraction, misleading names.
- **CI / build**: pinned versions that drift, cache keys, missing retry/timeout.
- **Docs**: required docs / changelog / migration updates.

## Output format

See [references/output-format.md](references/output-format.md) for the canonical worked example.

```markdown
## Adversarial Review: <PR title>

<One short framing paragraph: mergeable as-is? main takeaway? 2–3 sentences.>

---

### 🔴 High

**<Short noun-phrase heading>**

<Body: what, why, where (file:line), suggestion.>

---

### 🟠 Medium

...

---

### 🟡 Low / Nitpicks

...

---

### ✅ What is done well

- <Specific decision worth endorsing, not generic praise>
- ...

---

**Summary:** <One sentence. Mergeable? One thing worth doing before merge, if anything?>
```

### Rules

- The severity groups are fixed: 🔴 High → 🟠 Medium → 🟡 Low / Nitpicks → ✅ What is done
  well. Always use this order, these labels, and these emoji.
- **Omit empty groups.** Absence is the signal. Never write
  "No high-severity issues found."
- Always include `✅ What is done well` unless the PR is a real wreck. Use 3 to 5 bullets.
- Always end with `**Summary:**`. Use one sentence of plain prose.
- Each finding has a bold heading and a body paragraph. Headings are short noun phrases, not
  questions or imperatives.
- Put `---` separators between groups and before the Summary. Do not put a separator between
  findings within a group.

### Severity

- **🔴 High**: incorrect behavior in production, security, data loss, broken contract. Do not
  merge before the author addresses it.
- **🟠 Medium**: friction (performance, maintainability, fragile patterns) but not strictly
  wrong. Fix it here or in a follow-up.
- **🟡 Low / Nitpicks**: style, docs, minor improvements. The author may ignore it.

When in doubt between two levels, pick the lower one. Inflated severity makes this skill
useless.

The groups are the A / B / C scale of the plugin under other names. Each finding heading
carries the matching Conventional Comments label from
[`../../references/severity.md`](../../references/severity.md) (*Rendering*). 🔴 High
headings read `**issue (blocking):** <noun phrase>`. 🟠 Medium headings read
`**issue (non-blocking):**` or `**suggestion (non-blocking):**`. 🟡 Low headings read
`**nitpick:**`. The ✅ bullets are the `praise` of the review.

A concern that you could not confirm is a `**question:**` heading. Put it in the group that
its impact would earn if the concern is true. Word the heading as a question.
