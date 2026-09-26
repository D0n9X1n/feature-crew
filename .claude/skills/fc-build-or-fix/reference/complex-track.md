# Complex track

Loaded on demand by `/fc-build-or-fix`. Multi-module work, new subsystems, security or data-integrity central, public API changes.

## Flow

Every model-authored review below uses the canonical artifact-author selector in `/fc-build-or-fix`: read the recorded author model, record the audit envelope, call Agent with its exact selected `model` override, then verify the recorded reviewer model before accepting the audit. Pin authoring calls too; see [gate-provenance.md](gate-provenance.md). Missing evidence or a family collision leaves the gate unsatisfied.

1. **User approves track.**
2. **Spec.** From `/fc-brainstorm`, or write one inline. Path: `docs/specs/YYYY-MM-DD-<topic>-design.md`. Hard cap **1000 words** — over the cap, decompose into sub-projects, each with its own spec → plan cycle.
3. **Cross-audit the spec.** Dispatch with the selected override in one-clue mode. Focus on must-pass criteria and test strategy. Address CRITICAL findings before asking for approval.
4. **User approves the spec.** Hard gate. Verify this happened — a spec file on disk is not approval.
5. **Architect.** Dispatch `fc-architect` with an explicit `model` override from the authoring rule in `/fc-build-or-fix`, the full spec text inline, plus project structure and tech constraints. Record its actual author model before plan QA. Plan cap **500 lines**. Over the cap, the architect decomposes; if irreducible, escalate to the user for re-scoping. In parallel, dispatch the blind second designer per [design-check.md](design-check.md), then resume the architect with its sketch to compare and reconcile in the plan.
6. **Cross-audit the plan.** Dispatch with the selected override in one-clue mode. Focus on tasks that trace to no requirement, requirements with no task, components that duplicate existing code or fail the fitness check, placeholders, and naming drift. Address CRITICAL findings before approval.
7. **User approves the plan.** Hard gate.
8. **Implementation.** Group tasks by file independence. Dispatch `fc-developer` with an explicit `model` override from the authoring rule in `/fc-build-or-fix`, in parallel only at ≥3 genuinely independent tasks; 1–2 run sequentially. Paste each task's full text inline and record the actual author models for tests-as-spec and implementation before QA.
9. **Per-task QA.** Select and record an explicit override for the tests-as-spec author before `fc-qa-spec`, and for the implementation author before `fc-qa-code`. In Complex, `fc-qa-code` skips spec compliance.
10. **Tech Lead final.** Select and record the override, then dispatch `fc-tech-lead` with spec, plan, full diff, and task summaries. Hard gate before merge.
11. **Cost telemetry.** Record dispatch count, wall-clock estimate, and exact selected aliases in the PR description.

## Worked example

> "Build OAuth + SAML auth." (Illustrative. In an Opus-family session the same rules request `model: opus` for authoring and select `model: sonnet` for review.)
>
> PM proposes Complex in a Sonnet-family session. `/fc-brainstorm` returns a chosen approach; `/fc-grill-me` returns settled provider/session/RBAC decisions. Spec written, 850 words. The harness records a Sonnet-family author, selecting `model: opus`; the recorded reviewer is Opus. The audit flags a missing logout criterion → addressed → user approves.
>
> `fc-architect`, requested with `model: sonnet` under the authoring rule, returns a 380-line plan, 12 tasks. Its recorded model is Sonnet, so the selector requests `model: opus`; the recorded reviewer is Opus. The audit passes → user approves. These families are observed, not inferred from aliases; a substituted same-family reviewer would leave the gate unsatisfied.
>
> 4 tasks are independent (DB schema, OAuth config, SAML config, login shell) → parallel. 8 are sequenced. Developers requested with `model: sonnet` under the authoring rule record as Sonnet; each QA and final dispatch records artifact identity, recorded author model, author family, and selected override first, then checks the recorded reviewer model.
>
> Per-task QA catches a CRITICAL: session token not invalidated on logout. Fixed in one dev cycle. `fc-tech-lead` approves. PR opened.
>
> `Cost: 17 dispatches, ~3h wall-clock, models: opus + sonnet (explicit gate overrides)`

## Failure modes

- **Plan over 500 lines** → decompose. Never ship an oversized plan "because the feature is big."
- **Parallel devs on shared files** → merge conflicts and duplicated work. Group by file independence, not by task count.
- **Spec approval assumed** → the most common gate leak. A spec doc existing is not a user approving it.
- **Plan shipped unaudited** → the rule names `plan` as a must-audit artifact, and it is the easiest one to skip because the architect's output reads as authoritative.
- **QA findings batched to the end** → fix loops stack. QA each task as its developer finishes.
