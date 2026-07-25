---
name: fc-second-opinion
description: Adversarially stress-tests a claim, decision, or conclusion by trying to refute it from several angles and returning a verdict. Use when the user is about to commit to something and wants it attacked first — "am I right that", "talk me out of", "is this the right call". Do NOT use for reviewing a concrete artifact like a diff or spec (use /fc-review), and do NOT use it to satisfy a Feature-Crew hard gate — gate audits run inside /fc-build-or-fix.
model: sonnet
effort: max
disallowed-tools: Write Edit NotebookEdit
---

# fc-second-opinion

Attacks a position. Inverts the usual review bias: a model asked to "review this" tends to bless a plausible-looking answer, so here the burden of proof runs the other way.

**This is not a substitute for a hard gate.** The cross-family audits inside `/fc-build-or-fix` are mandatory and automatic; this skill is opt-in, for calls the pipeline is not touching. Never substitute a `/fc-second-opinion` verdict for a required gate audit — if it could stand in, the mandatory gate would quietly become optional.

## 1 — State the claim

Write the claim as one falsifiable sentence, and confirm it with the user before spending dispatches. "Postgres over SQLite here" is not yet a claim — "Postgres is the right store because we need concurrent writers within 6 months" is.

## 2 — Steelman

Before any criticism, state the strongest honest case **for** the claim. Not a strawman you can knock down — the version its best advocate would recognize.

An attack on a weakened version of the argument is worthless, and skipping this step is how contrarianism becomes theater.

## 3 — Refute

Dispatch **2–3 subagents**, each with a distinct lens (correctness · cost/complexity · what-breaks-later · security when relevant). Each prompt:

> Try to refute this claim. You are not asked whether it is reasonable — you are asked to break it. Report `refuted: true` if you can construct a concrete scenario where the claim leads to a bad outcome, **and default to `refuted: true` when you are uncertain.** Give the scenario in 3 sentences: the conditions, what goes wrong, and the cost. If you genuinely cannot break it, report `refuted: false` and name the single assumption the claim most depends on.

## 4 — Verdict

- **SURVIVES** — majority could not refute. State the load-bearing assumption they all named. It is the thing to watch.
- **REFUTED** — majority refuted. Give the strongest single scenario, not all of them.
- **SPLIT** — reviewers disagree. Report the disagreement plainly; do not average it into false confidence.

Then one line on what would change the verdict.

## Caps

- **Max 3 refuters.** Fewer when a lens does not apply — a smaller panel is honest, padding it is not.
- **One round.** No re-litigating after the user responds.
- If no second model family is reachable, run fewer reviewers rather than two from the same family, and say so.

## Known limitation

Refute-by-default trades false approval for false rejection. It will sometimes kill a good idea by constructing an unlikely failure scenario. Weigh the verdict as evidence, not as a decision — and read the scenario, not just the label.

## Related skills

- A concrete artifact to review → `/fc-review`
- Alternatives instead of a verdict → `/fc-brainstorm`
