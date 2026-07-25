# Complex track

Loaded on demand by `/fc-build-or-fix`. Multi-module work, new subsystems, security or data-integrity central, public API changes.

## Flow

1. **User approves track.**
2. **Spec.** From `/fc-brainstorm`, or write one inline. Path: `docs/specs/YYYY-MM-DD-<topic>-design.md`. Hard cap **1000 words** — over the cap, decompose into sub-projects, each with its own spec → plan cycle.
3. **Cross-audit the spec.** Dispatch a review-family model in one-clue mode. Focus on must-pass criteria and test strategy. Address CRITICAL findings before asking for approval.
4. **User approves the spec.** Hard gate. Verify this happened — a spec file on disk is not approval.
5. **Architect.** Dispatch `fc-architect` with the full spec text inline, plus project structure and tech constraints. Plan cap **500 lines**. Over the cap, the architect decomposes; if irreducible, escalate to the user for re-scoping.
6. **User approves the plan.** Hard gate.
7. **Implementation.** Group tasks by file independence. Dispatch `fc-developer` in parallel only at ≥3 genuinely independent tasks; 1–2 run sequentially. Paste each task's full text inline.
8. **Per-task QA, one-clue mode.** `fc-qa-spec` first, then `fc-qa-code`. In Complex, `fc-qa-code` skips spec compliance because `fc-qa-spec` already covered it.
9. **Tech Lead final.** Dispatch `fc-tech-lead` with spec, plan, full diff, and task summaries. Hard gate before merge.
10. **Cost telemetry.** One line appended to the PR description.

## Worked example

> "Build OAuth + SAML auth."
>
> PM proposes Complex. Grills via `/fc-brainstorm`: which providers, session vs JWT, RBAC scope. Spec written, 850 words. Cross-audit flags a missing logout flow in must-pass criteria → addressed → user approves.
>
> `fc-architect` returns a 380-line plan, 12 tasks. User approves.
>
> 4 tasks are independent (DB schema, OAuth config, SAML config, login shell) → parallel. 8 sequenced behind them.
>
> Per-task QA catches a CRITICAL: session token not invalidated on logout. Fixed in one dev cycle.
>
> `fc-tech-lead` approves. PR opened.
>
> `Cost: 17 dispatches, ~3h wall-clock, models: default (architect, devs) + sonnet (spec audit, QA, tech lead)`

## Failure modes

- **Plan over 500 lines** → decompose. Never ship an oversized plan "because the feature is big."
- **Parallel devs on shared files** → merge conflicts and duplicated work. Group by file independence, not by task count.
- **Spec approval assumed** → the most common gate leak. A spec doc existing is not a user approving it.
- **QA findings batched to the end** → fix loops stack. QA each task as its developer finishes.
