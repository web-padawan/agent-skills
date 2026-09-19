---
name: comment-cleanup
description: Delete, rewrite and shorten comments against a DROP / REWRITE / RETAIN policy - drops restated behavior, history, closed tickets and decision records, border conditions the code already shows, and invariants the types already state. Converts prose docblocks on private and protected members to `@param` and `@return` tags, moves an inline override note into the docblock leading line, expands a `#NNNN` shorthand to a full link, and rewrites each kept comment to its shortest form. Scopes to a branch diff, one commit, the index, the working tree, one file, or one package. Use when asked to clean up comments, de-slop comments, strip AI slop or AI-written comments, remove comment noise, drop redundant or obsolete comments, convert JSDoc prose to tags, or trim the comments a branch added. Edits comment lines only and never changes code. Not for code slop such as duplication, dead code or wrappers, which is ai-slop-cleaner. Not for a review that reports and does not edit, which is self-review or pr-review. Not for a structural refactor, which is refactor-component. Not for a general cleanup of an uncommitted diff, which is simplify.
argument-hint: "[--diff|--commit <sha>|--staged|--working|--all <path>|--package <name>] [path]"
allowed-tools: Read, Edit, Glob, Grep, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(cp:*), Bash(diff:*), Bash(*/scripts/list-comments.sh:*)
---

# Comment Cleanup

This skill deletes the comments that say nothing, and it rewrites the comments that say too
much or say it badly. It processes the comments that a change added, or every comment in a
file or a package. It edits comment lines. It never edits code, and it never commits.

The policy is [`../../references/comments.md`](../../references/comments.md). Read it once at
the start. If that read fails, use `${CLAUDE_PLUGIN_ROOT}/references/comments.md`. The code
pass of the review skills judges against the same policy, so a cleanup run and a later review
agree. The smell table, the rewrite recipes and the manifest check are in
[`references/comment-slop.md`](references/comment-slop.md). A smell is a wording pattern
that marks a comment for a DROP or a REWRITE.

## When to use

- A branch added comments that restate what the code already shows.
- A diff carries history: a closed ticket, a decision record, a changelog note.
- A generated or an assisted change left a comment on every second line.
- A private docblock describes a parameter shape in prose instead of tags.
- One file or one package collected comment noise over the years.

## When NOT to use

- You want a report and no edit. Use `self-review`.
- You want to remove code slop: duplication, dead code, wrappers. Use `ai-slop-cleaner`.
- You want to move code. Use `refactor-component`.
- You want a general cleanup of an uncommitted diff. Use `simplify`.

## Gotchas

**The conventions document of the repository outranks the policy.** Read its JSDoc chapter
before the first verdict. In web-components it mandates the leading line "Override method
from `<BaseMixin>` to ...". The policy table alone gives that line a DROP.

**A docblock on a public member is published.** Its text reaches the type declarations, the
web types and the documentation site. A delete there changes generated output. The policy
keeps it. A REWRITE there edits the sibling `.d.ts` in the same pass.

**No compiler checks a docblock type in a `.js` file.** `tsc` reads only `.ts` files.
Verify a rewritten type from the callers, from `?.` in the body, and from the sibling `.d.ts`.
If the value can be `undefined`, write `{X | undefined}`, not `!X`.

**A style precedent is a count, not a memory.** Before you say that a wording is wrong, count
both forms across `packages/*/src`. The form that one file uses six times can be the minority
in the repository.

**A directive looks like a comment and is not one.** `eslint-disable`, `prettier-ignore`,
`@ts-expect-error`, `c8 ignore` and `istanbul ignore` change the build. A license header is
also not a comment under this policy. The extraction script omits all of them.

**An HTML comment inside a template is real DOM.** A delete can change what the component
renders. Treat a comment in a template literal as code until a test proves otherwise.

**A diff mode reaches only the comments that the change ADDED.** A comment that the diff left
stale beside a changed line belongs to the review skills. Pass `--all` or `--package` when
you mean the whole source.

**A whole-source mode carries more risk.** It reaches comments that nobody on this branch
wrote, so a wrong verdict costs more there. It also returns far more blocks than a diff. Both
whole-source modes refuse on a dirty tree, so that one `git checkout` reverts a bad edit.

**A delete of one line can leave a stray blank line or an empty docblock.** Remove the whole
block, and the blank line that the block owned.

**Docblock edits and inline edits belong in different commits.** One is `docs:`, the other
is `refactor:`. The gate offers them as separate options.

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
   a test directory and a `.d.ts` file. If the request names neither a diff nor a path, ask
   the user which mode to use. Then read the JSDoc chapter of the conventions document.
   Note each rule that names a docblock form.
2. **Extract.** Run the script in one call:

   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/comment-cleanup/scripts/list-comments.sh <flag> [path]
   ```

   It prints one line per comment block, as `<file>:<line> | <kind> | <text>`. The kind is
   `docblock`, `inline` or `html`. It omits a docblock that holds only tags. It prints nothing
   when nothing matches. If it prints nothing, stop. Work only from what the script prints. A
   `refuse:` line ends the run. Say the reason in one line and stop.

   A whole-source run over a package returns many blocks. If the script prints more than about
   40 blocks, print the count per file and ask which files to run. Each verdict needs a read of
   the code around the block, and a long list lowers the quality of each verdict.
3. **Classify.** Give each block one verdict from the policy, and name the row or the
   carve-out that decided it. Read the code around the block first. The table asks what the
   code already shows, and only the code answers that. For a REWRITE, name the smell from the
   smell table and write the new text. A block that you cannot place is a DROP.
4. **Gate.** Print one table with `file:line`, the kind, the verdict, the row or the smell,
   and the new wording of each REWRITE. List every verdict on its own row. Then ask one
   `AskUserQuestion` before any edit. Offer these options:
   - apply all
   - apply the DROP verdicts only
   - apply the docblock edits only
   - apply the inline edits only
   - stop
5. **Apply.** Run one pass per verdict and kind: the DROP pass, the docblock REWRITE pass,
   then the inline REWRITE pass. Edit one file at a time. Delete a whole block together with
   the blank line that it owned. Run the diff check of step 6 after each pass.
6. **Prove.** Run these checks in order, and stop at the first failure:
   - `git diff -U0` over the run. Every added and removed line must be a comment line. If a
     code line appears, revert the file.
   - For a REWRITE of a public docblock, `git diff --stat` must list the sibling `.d.ts`.
   - The type check of the repository.
   - The manifest check from the reference, when the repository generates a manifest from
     JSDoc.
   - The test suite of each touched package.
7. **Report.** List each DROP with its row. List each REWRITE with its smell, the old wording
   and the new wording. Give the count of RETAIN blocks. Say which checks ran. State that the
   skill committed nothing.

## Rules

- Edit only the blocks that the script listed, and only their comment lines.
- Leave `HEAD` and the index as you found them. The skill stages nothing and commits nothing.
- Keep every directive, license header, docblock tag, and docblock on a public member. The
  gotchas above say why.
- Never reduce a docblock on a private or a protected member to its visibility tag alone.
- Check the state of a linked issue with `gh issue view` before you keep or expand the link.
- If a check in step 6 fails, restore the file with `git checkout -- <path>`.
- Name each block that you did not edit, and give the reason. The reader takes an unnamed block
  as approved.
