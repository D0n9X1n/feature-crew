---
name: fc-brainstorm
description: Generates genuinely different approaches to a problem using a panel of subagents with opposing stances, then converges on one recommendation and writes an approved spec. Use when the user knows the problem but not the solution — "how should I", "what's the best way to", "I'm torn between". Do NOT use for gathering facts (use /fc-research), for pinning down decisions on an approach already chosen (use /fc-grill-me), or for implementing (use /fc-build-or-fix).
---

# fc-brainstorm

Produces an approved spec by exploring the solution space before committing to it.

## 1 — Frame

Restate the problem in one sentence and name the constraint that matters most. Look up anything discoverable yourself: existing patterns, dependencies, prior art in the repo.

If a user-owned requirement is missing, use the canonical need classifier in `/fc-build-or-fix`: its leaf exception lets this flow call `/fc-grill-me`, which resolves that category and returns here before the panel runs.

## 2 — Panel

Dispatch **3 subagents in parallel**, each pinned to exactly one stance. Never send the same prompt three times — identical prompts return three shades of one idea.

Default stances:

| Stance | Brief |
|---|---|
| **Simplest** | Smallest change that solves the stated problem. No new dependencies, no new abstractions. |
| **Risk-first** | Assume this must not break. Optimize for reversibility, blast radius, and failure modes. |
| **User-first** | Optimize for the person using the result. Accept internal complexity to buy external simplicity. |

Substitute a different axis when it fits better — 1 day / 1 week / 1 month of effort, or build / buy / defer.

Each agent's prompt, including re-dispatches, ends with:

> Propose one concrete approach from this stance. Include: the approach in 3–5 sentences, the strongest objection to it, and what would have to be true for it to be the wrong call. Do not hedge and do not propose alternatives — argue your stance. Keep it short enough to compare side by side. Do not call `Agent`, `Skill`, `Workflow`, or delegate any part of the task.

## 3 — Diversity check

Before showing anything, compare the three. If two approaches differ only in wording, or all three converge on the same shape, **re-dispatch once** as a single round of up to three replacement workers with sharper stances and at least one deliberately unconventional angle. Report that you did.

Convergence is a real result when it happens after a genuine re-spawn — say so plainly instead of manufacturing a third option.

## 4 — Converge

Present the approaches in a comparison table, then **recommend one**. The recommendation must be opinionated and carry a concrete hedge condition: "X, unless <specific observable>, in which case Y."

"It depends" is not an answer. If it genuinely depends, name the observable it depends on and which way each value points.

## 5 — Spec

Once the user picks a direction, invoke `/fc-grill-me` only for remaining user-owned decisions; it returns the settled result here. Then write the spec to `docs/specs/YYYY-MM-DD-<topic>-design.md`. **Hard cap 1000 words** — over it, decompose into sub-projects.

Cross-audit the spec with the dynamic hard-gate selector in `/fc-build-or-fix` before asking for approval. Address CRITICAL findings first.

The user approving the spec is a hard gate. If another flow invoked this skill, return the approved spec and approval evidence to the originator; do not invoke `/fc-build-or-fix`. Only if the user invoked this skill directly, offer `/fc-build-or-fix` after approval.

## Caps

- **Max 7 panel/review dispatches** — 3 panel + up to 3 re-dispatch + 1 cross-audit, including descendants at any depth. Reserve the audit slot; re-spawns and descendants count. Pause for user approval before exceeding the cap or starting a second diversity round.
- The only nested skill call is the `/fc-grill-me` leaf; it returns here without invoking skills. For any other missing category, return to the invoking flow to reclassify a distinct gap; do not self-invoke or recurse, per `/fc-build-or-fix`.

## Anti-patterns

- Same prompt to 3 agents (no diversity).
- Personas with biographies instead of stances — the stance is the whole mechanic.
- Presenting 3 options with no recommendation.
- Writing a spec before the user picked a direction.
