# Significant changes — rules, ranking, inventory contract

The deep review works per change, not per branch, so the changes have to be named first. These rules define what qualifies, how candidates are ranked against a budget, and the output contract for the inventory agent. `arch-review` uses them when given a multi-change scope — including when `self-review --deep` delegates here.

## The five significance rules

A hunk in the diff is a **significant change** when it does any of:

1. **Public surface** — adds or alters an export, public property, attribute, method, event, slot, CSS custom property, CSS part, or `.d.ts` entry.
2. **New module** — adds a mixin, controller, class file, or helper that others will import.
3. **Control flow** — changes a decision in existing logic: a new branch, an altered condition, a changed default, a changed early return, a changed lifecycle timing.
4. **Cross-module contract** — changes a data shape, event detail, callback signature, or a mixin's expectation of its host.
5. **Boundary move** — logic extracted, inlined, or relocated between modules or packages.

Never significant: test-only hunks, docs, build/config, pure renames with no call-site semantics change, formatting, comment-only edits, generated files.

## Ranking and the budget

Rank candidates by public-surface reach first, then cross-module reach, then logic density. Take the invoker's deep-review budget. Every candidate over the budget goes in the report under `## Not deep-reviewed` with its `file:line` and the reason it ranked below the line — silent truncation is forbidden.

A scope with **zero** significant changes (a pure chore, a docs-only edit) skips the deep review and says so. That is a valid outcome, not a failure.

## Cluster before ranking

The unit of review is the **decision a reviewer would judge as one**, not the file. Group candidates first, then rank the groups, then spend the budget on groups.

- New files that exist only to serve one new public surface — a mixin plus its data record plus its controller — are **one** change, reviewed by **one** trio. They share a contract; three trios reading the same three files produce the same findings three times.
- A one-line `implements` / export / registration addition is **part of** the surface it adopts, never its own change. Adding it to a second, third, fourth class is the same decision repeated.
- Two changes stay separate when a reviewer could reach opposite verdicts on them independently — different modules, different contracts, or one could ship without the other.

Never spend a trio on a candidate whose findings could only restate a change already under review. List it under `Not deep-reviewed` with `covered by rank N`.

A four-file feature in one module is usually **one** trio. Getting this wrong is the single most expensive mistake in this skill: the duplicate findings still cost full agent runs, and dedup at triage happens after the spend, not instead of it.

## Inventory contract

One `agent-skills:change-enumerator` agent, read-only. Its definition ([`../../../agents/change-enumerator.md`](../../../agents/change-enumerator.md), fallback `${CLAUDE_PLUGIN_ROOT}/agents/change-enumerator.md`) carries the five rules, the exclusion list, and this contract — the invoker's prompt adds the deep-review budget, the scope context, and the delivery clause. When the plugin's agents are unavailable, fall back to `general-purpose` with the agent file's body pasted into the prompt. The contract, for the stages that consume its output:

```
<rank> | <file>:<line-range>[ + <file>:<line-range> …] | <rule 1-5> | <one sentence: what it changes>
```

- One line per **clustered** change, ranked most significant first, by the ranking above. A cluster lists every file it covers on its one line.
- Exactly the budget's worth of lines, then a `BELOW LINE` header, then every remaining candidate in the same format with the reason it ranked lower — `covered by rank N` when a cluster already accounts for it. An agent that omits the below-line list has not finished.
- `NO SIGNIFICANT CHANGES` when the diff is entirely non-significant — a valid answer; the deep review is then skipped.
- Add the invoker's delivery clause.

The inventory is a *selection*, not a review: no severities, no findings, no recommendations. Keeping it cheap is what makes the extra barrier worth its latency.
