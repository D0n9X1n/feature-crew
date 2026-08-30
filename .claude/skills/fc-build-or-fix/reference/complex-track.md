# Complex track

Loaded on demand by `/fc-build-or-fix`. Multi-module work, new subsystems, security or data-integrity central, public API changes.

## Flow

Every model-authored review below uses the canonical artifact-author selector in `/fc-build-or-fix`: record the audit envelope, then call Agent with its exact selected `model` override. A missing/failed selection leaves the gate unsatisfied.

1. **User approves track.**
2. **Spec.** From `/fc-brainstorm`, or write one inline. Path: `docs/specs/YYYY-MM-DD-<topic>-design.md`. Hard cap **1000 words** — over the cap, decompose into sub-projects, each with its own spec → plan cycle.
3. **Cross-audit the spec.** Dispatch with the selected override in one-clue mode. Focus on must-pass criteria and test strategy. Address CRITICAL findings before asking for approval.
4. **User approves the spec.** Hard gate. Verify this happened — a spec file on disk is not approval.
5. **Architect.** Dispatch `fc-architect` with the full spec text inline, plus project structure and tech constraints. Plan cap **500 lines**. Over the cap, the architect decomposes; if irreducible, escalate to the user for re-scoping.
6. **Cross-audit the plan.** Dispatch with the selected override in one-clue mode. Focus on tasks that trace to no requirement, requirements with no task, placeholders, and naming drift. Address CRITICAL findings before approval.
7. **User approves the plan.** Hard gate.
8. **Implementation.** Group tasks by file independence. Dispatch `fc-developer` in parallel only at ≥3 genuinely independent tasks; 1–2 run sequentially. Paste each task's full text inline.
9. **Per-task QA.** Select and record an explicit override for the tests-as-spec author before `fc-qa-spec`, and for the implementation author before `fc-qa-code`. In Complex, `fc-qa-code` skips spec compliance.
10. **Tech Lead final.** Select and record the override, then dispatch `fc-tech-lead` with spec, plan, full diff, and task summaries. Hard gate before merge.
11. **Cost telemetry.** Record dispatch count, wall-clock estimate, and exact selected aliases in the PR description.

## Worked example

> "Build OAuth + SAML auth."
>
> PM proposes Complex. `/fc-brainstorm` returns a chosen approach; `/fc-grill-me` returns settled provider/session/RBAC decisions. Spec written, 850 words. Its Sonnet-family author provenance selects `model: opus`; the audit flags a missing logout criterion → addressed → user approves.
>
> `fc-architect` returns a 380-line plan, 12 tasks. Its known non-Sonnet author provenance selects `model: sonnet`; the audit passes → user approves.
>
> 4 tasks are independent (DB schema, OAuth config, SAML config, login shell) → parallel. 8 are sequenced. Each QA and final dispatch records artifact identity, author family, and selected override first.
>
> Per-task QA catches a CRITICAL: session token not invalidated on logout. Fixed in one dev cycle. `fc-tech-lead` approves. PR opened.
>
> `Cost: 17 dispatches, ~3h wall-clock, models: opus + sonnet (explicit gate overrides)`

## Failure modes

- **Plan over 500 lines** → decompose. Never ship an oversized plan "because the feature is big."
- **Parallel devs on shared files** → merge conflicts and duplicated work. Group by file independence, not by task count.
- **Spec approval assumed** → the most common gate leak. A spec doc existing is not a user approving it.
- **Plan shipped unaudited** → the rule names `plan` as a must-audit artifact, and it is the easiest one to skip because the architect's output reads as authoritative. Step 6 exists because this flow omitted it for two versions and five reviewers caught it.
- **QA findings batched to the end** → fix loops stack. QA each task as its developer finishes.
