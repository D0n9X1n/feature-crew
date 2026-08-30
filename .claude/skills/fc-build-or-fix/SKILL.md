---
name: fc-build-or-fix
description: Runs a code change through a right-sized track (Just Do It / Standard / Complex) with hard gates, TDD, and cross-family review. Use when the user asks naturally to build, fix, change, refactor, implement, add, or extend code. Do NOT use for an open question whose primary need is facts, an approach, or review of an artifact this pipeline did not produce; route that need with the classifier below.
---

# fc-build-or-fix

You are the PM. Classify the missing ingredient, pick the track, and run its flow.

## Need classifier

Users describe the need naturally; slash-command knowledge is not required. At entry and whenever blocked, preserve **facts you look up; decisions you ask**:

| Missing ingredient | Route |
|---|---|
| One discoverable fact | Look it up directly. |
| Evidence from several places | Invoke `/fc-research`. |
| User-owned requirement or decision | Invoke `/fc-grill-me`. |
| Unresolved solution approach or options | Invoke `/fc-brainstorm`. |
| A chosen consequential decision needing adversarial confidence | Invoke `/fc-second-opinion`. |

Do not grill for facts, research preferences, brainstorm an already chosen approach, or use second-opinion to make the initial choice. A subskill resolves one category and returns its result to the originating flow; the originator may reclassify a distinct remaining gap, invoke one next appropriate skill, then resume. A subskill must not self-invoke or recursively invoke another skill. Do not repeat the same skill for an unchanged gap: no cycles.

## Step 1 — pick a track

| Track | When | Spec | Dispatches |
|---|---|---|---|
| **Just Do It** | Straightforward and bounded; obvious solution; no unresolved design; low regression risk; reversible | none | 0 |
| **Standard** | One coherent feature, modest coupling, no new architecture | bullet list in chat | 1–2 |
| **Complex** | Multi-module, new subsystem, security or data-integrity central, public API change | doc, ≤1000 words | 5+ |

File count is an optional warning signal, never an eligibility rule: a mirrored low-risk content change across several files can qualify, while a one-line high-risk change cannot. **Just Do It never applies** when the change touches the canonical **escalation list**: runtime behavior, config, auth, secrets, persistence, public API contract, or deploy behavior. This list is stated only here; it controls both the track floor and Standard spec audit.

For Standard or Complex, ask: "Proposing **<track>** because <reason>. OK?" User approval remains required unless waived. The PM auto-selects Just Do It from natural language and proceeds without track approval.

Explore before production edits. If exploration reveals ambiguity, coupling, risk, unresolved decisions, or escalation-list scope, stop before production edits and escalate to Standard. Framework-internal changes are Standard maximum; see [reference/meta-work-cap.md](reference/meta-work-cap.md).

## Step 2 — run the track

### Just Do It

1. Explore enough to confirm eligibility and the existing pattern.
2. Write a failing test first; for docs, write objective acceptance checks first.
3. Make the minimal change.
4. Run observed verification and paste its output.
5. Commit only if the overall user request authorizes a commit.

No track approval, spec, role-agent dispatch, or QA pass.

### Standard

1. User approves track unless waived.
2. Write a bullet spec in chat: purpose · files · 3–8 behavior bullets · must-pass full-suite command · non-goals. Look up facts; ask only user-owned decisions.
3. **Cross-audit the spec** when it touches the escalation list. Otherwise skip as one of the two exemptions in the audit rule.
4. User approves spec unless waived.
5. Implement TDD: failing test → observe failure → minimal code → observe pass → refactor.
6. Run the must-pass full suite and paste output.
7. Dispatch `fc-qa-code` in one-clue mode for combined spec + code review, using the selector below.
8. Judge the finding: CRITICAL → fix; IMPORTANT → fix or follow-up; PASS → done.
9. Commit only when authorized; use a feature branch and offer a PR.

### Complex

Load [reference/complex-track.md](reference/complex-track.md) and follow it. Entry requires an approved spec from `/fc-brainstorm` or one written inline; verify actual approval.

## Hard gates

Blocking; no forward motion until satisfied.

1. **User approves the track** for Standard and Complex unless waived. Just Do It is auto-selected.
2. **User approves the spec** for Standard and Complex unless waived.
3. **User approves the plan** for Complex unless waived.
4. **Verification evidence exists for every done claim**, and the full suite passes before an authorized commit claiming done.
5. **Implementation matches the approved spec.** Unmet requirements or absent required tests block regardless of severity.
6. **Tech Lead approval** before merging Complex work.

Verification, spec compliance, and Complex Tech Lead approval cannot be waived. Other findings are advisory unless they confirm correctness, security, or data-loss defects.

## Cross-family audit at hard gates

**Canonical rule. Every other Feature-Crew doc points here instead of restating it.**

Every model-authored hard-gate artifact — spec, plan, tests-as-spec, implementation diff, Tech Lead final — must be audited by a model from a different family than the one that wrote it. Same-family review and self-critique do not satisfy a gate.

Before every such review, the dispatcher identifies the artifact and its known author family/provenance, computes the reviewer, and records an **audit envelope / gate record** with `artifact identity`, `known author family`, and `selected Agent model override`:

- Sonnet-family author → call Agent with explicit `model: opus` override.
- Any known non-Sonnet-family author → call Agent with explicit `model: sonnet` override.

Use family aliases, not version-specific IDs. Whoever authored tests-as-spec determines their author family. The reviewer must not infer or self-identify its runtime family from prompt or context; provenance and selection belong to the dispatcher.

Unknown author family/provenance, or a computed same-family collision: do not dispatch; record `GATE UNSATISFIED`. If selected-model dispatch fails or is unavailable, record `GATE UNSATISFIED`; no fallback or retry to the author family. Run fewer reviewers rather than a same-family substitute.

**Exemptions:** Just Do It produces no model-authored artifact. A Standard spec outside the escalation list is also exempt because the user approves it inline and combined QA later checks compliance. Every other named artifact is audited.

Standalone `/fc-review` and `/fc-second-opinion` are not hard-gate substitutes.

## Dispatch rules

- Paste task text inline; never tell a subagent to read the plan file.
- For a hard-gate review, pass the audit envelope and exact explicit Agent model override above.
- Parallel only at ≥3 independent tasks; otherwise run sequentially.
- Use background mode for substantive work and handle results as they arrive.
- Max 3 fix cycles per issue, then stop and question the approach.
- Subagent self-review never replaces QA.

## One-clue mode

Every QA dispatch in Standard and Complex reports one result: **PASS**, **CRITICAL** (bug/security/data loss with `file:line` and repro), or **IMPORTANT** (design problem/missing test/unclear behavior with `file:line`). One finding, not a list.

## Cost telemetry

Standard and Complex append `Cost: <N> dispatches, ~<M> min wall-clock, models: <selected overrides>` to the PR description, or authorized final commit body when there is no PR. Just Do It is exempt.

## Anti-patterns

- Complex ceremony for an obvious low-risk change.
- A spec doc for Just Do It.
- File count treated as a hard track rule.
- Production edits before exploration confirms eligibility.
- Parallel developers on overlapping files.
- Same-family audit or fallback.
- Pushing past a size cap.
- Treating advisory findings as automatic blockers.
