# Why the pipeline is shaped this way

One line per principle. Each was measured on a real run before it became a rule; the runs,
their costs and what they exposed are in [`retrospective.md`](retrospective.md), which no
skill loads. Read this when a rule looks like ceremony and you are tempted to drop it.

- **One barrier, one message.** Triage needs every pass's findings before it verifies
  anything; passes launched in separate messages serialize the barrier for no gain.
- **Named agents lose their reports.** A named agent ends its turn idle and alive, and its
  final text never comes back — hence no `name`, and the delivery clause as a second channel.
- **A lost report looks exactly like a clean pass.** Hence the roll call before triage, an
  escalation ladder that changes the mechanism instead of retrying the broken channel, and the
  `self-run` marker for findings the orchestrator had to produce itself.
- **Deep review is a budget, not a fan-out.** Lens agents on the same change converged on the
  same findings; one change pass with a block budget keeps the disagreement and drops the
  duplicate spend.
- **A settled-fact ledger must not invite challenge.** "Do challenge" licenses re-derivation,
  which costs as much as establishing the fact did.
- **One lead, one owner, one verdict.** Unowned leads are verified by every pass; an owned
  lead with no reported verdict vanishes. Every lead names its pass and ends as a finding or a
  `lead cleared:` line.
- **Cluster before ranking.** A multi-file feature in one module is usually one decision, so
  one block; getting that wrong should cost a block, not an agent run.
- **An agent handed a list writes a survey.** The block format, the small budget and
  checklist-before-blocks ordering are the hedge.
- **The dominant cost is agents × diff, not agents.** Hence the prepared patches and one
  owner per lane; only the tests pass reads both.
- **One question, one owner — including across passes that share material.** Overlapping
  questions are worth debating; overlapping reads are the measurable cost.
- **Restating a shared fact is cheaper than N agents finding it.** Settled facts, the
  conventions excerpt, CI and the existing comments are quoted once into the skeleton.
- **Re-reading what the skeleton already quotes is the largest waste.** Hence the read
  discipline block and the inline diff below ~300 lines.
- **Size is a proxy for risk, not risk itself.** The scale tier has risk overrides, and it
  sizes budgets, never the pass list.
- **Three questions, three passes.** What the change does and promises, how the code is
  written, whether the tests pin it — split along the seam where the searches differ, not the
  questions. The change type is a prompt add, not a pass.
- **CI is authoritative on a PR.** A green check retires that class of finding; a red one is
  an A by itself. No pass re-runs locally what CI already proved.
- **C findings are the point of a local review, and noise on a PR.** Hence the mode-variant
  C rule.
- **The tier is not the comment.** A/B/C is the plugin's scale; a PR reader gets a
  Conventional Comment whose label and decoration say the same thing in words they know, and an
  unverified claim posts as a question. The label is frozen with the tier so two renderings
  cannot disagree.
- **The model is a column, not a rule.** No agent definition pins a model; the tier picks it
  per pass and the plan prints it.
- **The plan is the launch.** Literal prompts, literal SHAs, literal paths — nothing about a
  launch is re-derived from prose, so every run's prompts are the same.
- **Never Edit the skeleton.** Edit needs a Read, and the Read pulls the diff through the
  orchestrator's context — the one cost the skeleton exists to remove. Notes go in their own
  file, written once before fan-out.
- **Existing comments are a filter and a recall source.** A finding already on the PR is not
  posted again; an open thread no pass reproduced is verified. The bot's claim is not
  authoritative, only its existence is.
- **Loaded docs carry rules; the retrospective carries the measurements.** Every token in a
  document a run reads is paid on every run.
