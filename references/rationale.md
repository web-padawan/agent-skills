# Why the pipeline is shaped this way

Measured on real runs, not guessed. Read this when a rule looks like ceremony and you are
tempted to drop it — each one is here because its absence cost something.

**One barrier, one message.** Triage needs every pass's findings before it verifies
anything. Passes launched in separate messages serialize the barrier for no gain.

**Named agents lose their reports.** A named agent becomes an addressable teammate: it ends
its turn idle and still alive, and its final text never comes back. That is why
`delivery.md` forbids `name` and why the delivery clause exists as a second channel.

**A lost report looks exactly like a clean pass.** Hence the roll call before triage, the
escalation ladder that changes the *mechanism* rather than retrying the broken channel, and
the `self-run` marker — reviewing with the same context that produced the diff makes you the
reader least likely to notice what it takes for granted.

**Deep review does not belong in a branch-level pass.** A fix branch reviewed with the old
full profile ran 16 agents and reported the same two A findings from two and three lenses
each, in a 1000-line report whose findings were 60% about code the accepted fix did not
contain. The lens machinery now lives only in `arch-review`; a breadth review is two agents.

**A settled-fact ledger must not invite challenge.** A ledger headed "do not re-derive, *do
challenge*" was re-derived from source by three of four agents. The invitation is what
licenses the spend: a sceptical reading of a settled fact costs as much as establishing it.

**Unowned leads multiply.** Three leads handed to four agents without an owner produced four
independent verifications of one non-issue — the single largest waste in that run. One lead,
one owner pass.

**Clustering before ranking is the cheapest win in arch-review.** A four-file feature in one
module is usually one decision, so one trio. Getting it wrong costs full agent runs, and
dedup at triage happens *after* the spend, not instead of it.

**An agent handed a list writes a survey.** One change per lens agent, always. The same
failure appears at message level: cap a batch at about six agents.

**The dominant cost is agents x diff, not agents.** Eight passes each running their own
`git diff` paid for every line of the branch eight times — and the test hunks, usually most
of the branch, were paid for by seven passes that do not review tests. Hence the two
prepared patches and the `reads` lane in `profiles.md`: one owner per lane, and only the
tests pass — whose coverage question spans both — reads both.

**One question, one owner — including across passes that share material.** Four passes were
reading the test diff to ask four overlapping versions of "does this assertion pin the right
thing". The tests pass now owns every assertion question, added and pre-existing alike, and
it is the only pass that opens the test patch. Overlapping *questions* are worth debating;
overlapping *reads* were the measurable cost, and the lanes are what removed them.

**Restating a shared fact is cheaper than N agents finding it.** Naming the conventions doc
still left the code pass reading all of it, most of which governs untouched code. The
orchestrator now quotes the governing chapters into the context file, the way Settled facts
already worked.

**Size is a proxy for risk, not risk itself.** A three-line change to a public API or a
release workflow is not trivial, which is why the scale tier has risk overrides — and why
scale only sizes the mutant budget instead of dropping a pass.

**Seven breadth agents were one checklist read seven times.** The type-specific passes
(requirements, fix, behavior) and the split of the general questions across general, fit and
slop all judged the same production patch against the same reference material, so triage
spent its verification budget deduping findings the batch had already paid to produce twice.
The whole checklist fits in one agent under the 80-line body target, each section reporting
under its own category, and the type now reaches it as a prompt add — which is what makes a
question type-specific without making it a pass.

**C findings are the point of a local review.** The CI review bot on the PR deliberately
drops low-value findings. Nits, taste and cleanup surface here, judged by the author at zero
round-trip cost — that is also why the cleanup questions moved into this pipeline.
