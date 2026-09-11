---
name: comment-cleanup
description: Delete and shorten comments against a DROP / RETAIN policy - restated behavior, history, closed tickets and decision records, border conditions the code already shows, invariants the types already state, and docblock prose on private members. Rewrites each kept comment to its shortest form. Scopes to a branch diff, one commit, the index, the working tree, one file, or one package. Use when asked to clean up comments, remove comment noise, strip AI-written comments, drop redundant or obsolete comments, delete useless comments from a file or a package, or trim the comments a branch added. Edits comment lines only and never changes code. Not for a review that reports and does not edit, which is self-review or pr-review. Not for a structural refactor, which is refactor-component. Not for a general cleanup of an uncommitted diff, which is simplify.
argument-hint: "[--diff|--commit <sha>|--staged|--working|--all <path>|--package <name>] [path]"
allowed-tools: Read, Edit, Glob, Grep, AskUserQuestion, Bash(git:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(*/scripts/list-comments.sh:*)
---

# Comment Cleanup

This skill deletes the comments that say nothing, and it shortens the comments that stay. It
runs over what a change added, or over a whole file or package. It edits comment lines. It
never edits code, and it never commits.

The policy is [`../../references/comments.md`](../../references/comments.md). Read it once at
the start. If that read fails, use `${CLAUDE_PLUGIN_ROOT}/references/comments.md`. The code
pass of the review skills judges against the same policy, so a cleanup run and a later review
agree.

## When to use

- A branch added comments that restate what the code already shows.
- A diff carries history: a closed ticket, a decision record, a changelog note.
- A generated or an assisted change left a comment on every second line.
- One file or one package collected comment noise over the years.

## When NOT to use

- You want a report and no edit. Use `self-review`.
- You want to move code. Use `refactor-component`.
- You want a general cleanup of code that you just wrote. Use `simplify`.

## Gotchas

**A docblock on a public member ships.** Its text reaches the type declarations, the web types
and the documentation site. A delete there changes generated output. The policy keeps it.

**A directive looks like a comment and is not one.** `eslint-disable`, `prettier-ignore`,
`@ts-expect-error`, `c8 ignore` and `istanbul ignore` change the build. A license header is
also not a comment under this policy. The extraction script omits all of them.

**An HTML comment inside a template is real DOM.** A delete can change what the component
renders. Treat a comment in a template literal as code until a test proves otherwise.

**A diff mode reaches only the comments that the change ADDED.** A comment that the diff left
stale beside a changed line belongs to the review skills. Never widen a diff run to a whole
file. Pass `--all` or `--package` when you mean the whole source.

**A whole-source mode is the dangerous one.** It reaches comments that nobody on this branch
wrote, so `uncertain` costs more there. It also returns far more blocks than a diff. Both
whole-source modes refuse on a dirty tree, so that one `git checkout` reverts a bad edit.

**A delete of one line can leave a stray blank line or an empty docblock.** Remove the whole
block, and the blank line that the block owned.

## Steps

1. **Scope.** Resolve the mode from the argument. Four modes read a diff and reach only the
   comments that it added. Two modes read the source and reach every comment in it.

   | Mode | Reaches |
   | --- | --- |
   | `--diff` (default) | the comments that the branch added, since the merge base |
   | `--commit <sha>` | the comments that one commit added |
   | `--staged` | the comments that the index adds |
   | `--working` | the comments that the working tree adds |
   | `--all <path>` | every comment in that file or that directory |
   | `--package <name>` | every comment in `packages/<name>/src` |

   A path narrows any diff mode. A whole-source mode skips `node_modules`, `dist`, `build`,
   a test directory and a `.d.ts` file. Ask the user which mode is meant when the request
   names neither a diff nor a path.
2. **Extract.** Run the script in one call:

   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/comment-cleanup/scripts/list-comments.sh <flag> [path]
   ```

   It prints one line per comment block, as `<file>:<line> | <text>`. It prints nothing when
   nothing matches. Stop there in that case. Never read the diff or walk the tree yourself.
   A `refuse:` line ends the run. Say the reason in one line and stop.

   A whole-source run over a package returns many blocks. Above about 40, print the count per
   file and ask which files to run. Each verdict needs a read of the code around the block,
   and an unbounded list buys a shallow verdict for every entry.
3. **Classify.** Give each block one verdict from the policy, and name the row or the
   carve-out that decided it. Read the surrounding code first. The table asks what the code
   already shows, and only the code answers that. A block that you cannot place is a DROP.
4. **Gate.** Print one table with `file:line`, the verdict, the row, and the new wording of
   each RETAIN. List every verdict. Never fold a group of DROP verdicts into a count. Then
   ask one `AskUserQuestion` before any edit. Offer to apply all, to apply the DROP verdicts
   only, or to stop.
5. **Apply.** Edit the approved lines, one file at a time. Delete a whole block together with
   the blank line that it owned. Rewrite each RETAIN comment per the policy.
6. **Prove.** Run these checks in order, and stop at the first failure:
   - `git diff -U0` over the run. Every added and removed line must be a comment line. Revert
     the file when a code line appears.
   - The type check of the repo, and the build that generates the type declarations.
   - The test suite of each touched package.
7. **Report.** List each DROP with its row. List each RETAIN with the old wording and the new
   wording. Say which checks ran. State that the skill committed nothing.

## Rules

- Never change a line of code. The run diff holds comment lines only.
- Never stage, commit, amend or push. `HEAD` and the index end as you found them.
- Never touch a comment that the script did not list.
- Never delete a directive, a license header or a docblock tag.
- Never delete a docblock on a public member.
- Restore the file with `git checkout -- <path>` when a check in step 6 fails.
- Say which blocks you left alone, and why. Silence reads as approval.
