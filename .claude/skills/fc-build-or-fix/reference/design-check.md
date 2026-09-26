# Design check

Loaded by `/fc-build-or-fix` for every Standard or Complex design; paste it into the architect's task. Keep it fast: one second opinion, one comparison, no loops.

## Both directions

1. **Top-down:** requirements → responsibilities → components → interfaces. Every requirement has a home; every component traces to a requirement.
2. **Bottom-up:** map the existing code near the change before creating anything, one row per component: `component | job | key files | depends on | evidence (file:line)`. Mark inferences and unknowns. Reuse or extend before creating.
3. **Reconcile:** fit the design to existing seams, walk one normal and one failure path through it, and raise real conflicts as decisions, never guesses.

## Fitness check

Every new or changed component passes all five, or is redesigned, merged, or deleted:
- One job, stated in one sentence.
- The right home, with dependencies pointing one way.
- An interface smaller than what it hides.
- The most likely future change touches only this component.
- Testable through its interface.

The spec or plan carries a **component map** — `component | job | interface | reuses or extends | likely change | test seam` — and plan audits, `fc-qa-code`, and `fc-tech-lead` check the work against it.

## Second opinion

Mandatory unless the design is super straightforward. When the first design starts, dispatch a blind second designer in parallel, choosing its model with the canonical selector from the first author's recorded model. Only the dispatching session sends it; the architect never does. Give it the same brief but not the first design. It leads with the bottom-up view and returns at most 300 words — a component map and key decisions, never artifact text. One round only. The first author compares both in a table — `agree | differ | chosen and why` — recorded in the spec or plan.

The second designer is an input, not an author: record its recorded model in the gate record. It never replaces the cross-family audit, which reviews the reconciled artifact. Unknown provenance, a family collision, or an unavailable dispatch stops the step, as the selector does.

**Super straightforward** means all of: reversible; one unambiguous design that extends an existing pattern; objectively verifiable; no new component, interface, or dependency; no unresolved decision. Record the reason in the spec. Complex work is never exempt, and approval waivers do not waive this step.
