# Why the pipeline is shaped this way

One entry per principle. A real run measured each principle before it became a rule. The
runs, their costs and what they exposed are in [`retrospective.md`](retrospective.md). No
skill loads that file. Read this file before you drop a rule that looks like ceremony.

- **One barrier, one message.** Triage needs the findings of every pass before it verifies
  anything. Passes launched in separate messages serialize the barrier for no gain.
- **Named agents lose their reports.** A named agent ends its turn idle and alive. Its final
  text never returns. Hence no `name`, and the delivery clause as a second channel.
- **A lost report looks exactly like a clean pass.** Hence the roll call before triage.
  Hence an escalation ladder that changes the mechanism instead of a retry of the broken
  channel. Hence the `self-run` marker for findings that the orchestrator had to produce
  itself.
- **Deep review is a budget, not a fan-out.** Lens agents on the same change converged on
  the same findings. One change pass with a block budget keeps the disagreement and drops
  the duplicate spend.
- **A settled-fact ledger must not invite challenge.** "Do challenge" licenses
  re-derivation. Re-derivation costs as much as it cost to establish the fact.
- **One lead, one owner, one verdict.** Every pass verifies an unowned lead. An owned lead
  with no reported verdict vanishes. Every lead names its pass and ends as a finding or a
  `lead cleared:` line.
- **Cluster before ranking.** A multi-file feature in one module is usually one decision, so
  one block. A wrong cluster should cost a block, not an agent run.
- **An agent handed a list writes a survey.** The block format, the small budget and the
  checklist-before-blocks ordering are the hedge.
- **The dominant cost is agents × diff, not agents.** Hence the prepared patches and one
  owner per lane. Only the tests pass reads both.
- **One question, one owner, also across passes that share material.** Questions that
  overlap are worth a debate. Reads that overlap are the measurable cost.
- **Restating a shared fact is cheaper than N agents finding it.** The skeleton quotes the
  Settled facts, the conventions excerpt, CI and the existing comments once.
- **Re-reading what the skeleton already quotes is the largest waste.** Hence the read
  discipline block and the inline diff below ~300 lines.
- **Size is a proxy for risk, not risk itself.** The scale tier has risk overrides. The tier
  sizes budgets, never the pass list.
- **Three questions, three passes.** What the change does and promises. How the code is
  written. Whether the tests pin it. The split follows the seam where the searches differ,
  not the questions. The change type is a prompt add, not a pass.
- **CI is authoritative on a PR.** A green check retires that class of finding. A red check
  is an A by itself. No pass re-runs locally what CI already proved.
- **C findings are the point of a local review, and noise on a PR.** Hence the mode-variant
  C rule.
- **The tier is not the comment.** A/B/C is the plugin's scale. A PR reader gets a
  Conventional Comment. Its label and decoration say the same thing in words that the
  reader knows. An unverified claim posts as a question. The label freezes together with
  the tier, so two renderings cannot disagree.
- **The model is a column, not a rule.** No agent definition pins a model. The tier picks
  the model per pass, and the plan prints it.
- **The plan is the launch.** Literal prompts, literal SHAs, literal paths. No run re-derives
  anything about a launch from prose, so every run has the same prompts.
- **Never Edit the skeleton.** Edit needs a Read. The Read pulls the diff through the
  orchestrator's context. That is the one cost that the skeleton exists to remove.
  Notes go in their own file, written once before fan-out.
- **Existing comments are a filter and a recall source.** The review does not post a
  finding that is already on the PR. Triage verifies an open thread that no pass
  reproduced. The bot's claim is not authoritative. Only the claim's existence is.
- **Loaded docs carry rules. The retrospective carries the measurements.** Every run pays
  for every token in each document that it reads.
