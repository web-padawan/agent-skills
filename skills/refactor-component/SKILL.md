---
name: refactor-component
description: Plan and run a structural refactor of web component sources without a behavior change. Use when asked to refactor a component, a mixin or a package, to remove duplication between sibling components, to extract a controller or consolidate shared logic, to simplify a mixin that grew too large, or to order several refactors. Not for a review of a branch or a pull request, which is self-review, guided-review or pr-review. Not for finding test gaps, which is mutation-coverage. Not for a cleanup inside an uncommitted diff, which is simplify.
argument-hint: "[package path, or blank to use the current package]"
---

# Refactor Component

This skill moves web component code and keeps the behavior. It assumes a monorepo of packages.
Each component composes its behavior from a chain of mixins. Sibling components apply different
subsets of that chain. A shared child element often calls back into its owner.

Placement is the first hard question. Proof of an unchanged behavior is the second. Start with
the chain, not with the code that you want to move.

The argument names the package to refactor. With no argument, evaluate the options of the
current package and propose an order.

## When to use

- The same logic exists in two or more sibling packages.
- A mixin holds several concerns and grew too large.
- A child element receives a property that it only passes back to its owner.
- Several refactors compete with a feature branch that is already in review.

## When NOT to use

- The change adds or alters behavior. That is a feature or a fix.
- The change covers only code that you just wrote. Use `simplify`.
- You want a report and no edit. Use `self-review`.

## Gotchas

**A shared child element pins the placement.** Every method that the child calls through its
owner must exist on the lowest mixin that all hosts apply. A host that applies fewer mixins
fails at run time, and no type check finds it first.

**Observer order is load-bearing and invisible.** Observers run in declaration order. A merge
of several observers into one shared hook changes that order and can change what renders.

**A private member is not private across repositories.** Server side integrations and test
helpers read members with an underscore prefix. Grep the consumer repository before you move
or rename one.

## Phase 1 — Map

1. List the mixin chain of every component in the family. Record which mixins each host applies.
2. Find every consumer of the mixin that you plan to change. Search the source of all packages.
3. Find the shared child elements and the methods that they call on their owner.
4. Count the duplication with history. Search the log for a distinctive line of the candidate
   code across the packages. A fix that landed three times marks three copies.

## Phase 2 — Place

Decide the target mixin before you move a line.
[references/mixin-placement.md](references/mixin-placement.md) holds the decision procedure,
the split between a neutral default and an override, and the public API consequence.

## Phase 3 — Move

1. Move code in one direction at a time. Do not rename in the same commit as a move.
2. Keep the name and the argument order of a method that has call sites. A changed name turns
   each call site into a rename and hides the real change.
3. Delete a property on a child element that the child only gives back. Let the child ask the
   owner instead.
4. Keep the comments short. Put the long reasoning in the pull request body.

## Phase 4 — Prove

A green suite proves that the old paths still work. It does not prove that a test covers the
code that you moved. Follow [references/verification.md](references/verification.md). The short
form:

1. Confirm a green baseline. Run the suite of every package that applies the changed mixin, not
   only the one you edited.
2. Run the DOM snapshot suites and the type check.
3. Revert each moved piece alone and confirm that a test fails.
4. Report each piece that no test catches. Decide if it is a coverage gap or a change that no
   public path can reach.
5. If the change touches a member that a server side integration reads, run that integration
   suite against the local checkout.

## Phase 5 — Deliver

[references/delivery.md](references/delivery.md) holds the split rule and the order for a
program of several refactors. The short form: put pure motion in one pull request and the
behavior change in a second one. Land a refactor that shrinks an in-flight feature before that
feature. Land the rest after it.

## Rules

- Never mix a move and a behavior change in one pull request.
- Never add a helper that has no caller until a later feature arrives.
- Prove the placement with a run, not with an argument.
- Name the failing test that justifies a behavior change, in the pull request body.
- State every piece that no test covers. Silence about it reads as coverage.
