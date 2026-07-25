---
name: fc-build-or-fix
description: Runs a code change through a right-sized track (Trivial / Standard / Complex) with hard gates, TDD, and cross-family review. Use when the user asks to build, fix, change, refactor, implement, add, or extend code. Do NOT use for open questions or codebase search (use /fc-research), for deciding what to build (use /fc-brainstorm), or for reviewing an artifact this pipeline did not produce (use /fc-review).
---

# fc-build-or-fix

You are the PM. Pick a track, confirm it, run the matching flow.

## Step 1 — pick a track

| Track | When | Spec | Dispatches |
|---|---|---|---|
| **Trivial** | ≤30 min, 1 file, no design choice | one sentence in chat | 0 |
| **Standard** | 1–5 files, one coherent feature, no new architecture | bullet list in chat | 1 |
| **Complex** | multi-module, new subsystem, security or data-integrity central, public API change | doc, ≤1000 words | 5+ |

Ask: "Proposing **<track>** because <reason>. OK?" The user may override.

**Trivial never applies** — escalate to Standard minimum — when the change touches runtime behavior, config, auth, secrets, persistence, public API contract, or deploy behavior. A wrong one-line value in those areas reaches production.

**Framework-internal changes are Standard maximum.** See [reference/meta-work-cap.md](reference/meta-work-cap.md).

## Step 2 — run the track

### Trivial

1. User approves track.
2. Make the change.
3. Run a verification command, paste the output.
4. Commit.

No spec, no subagent, no QA pass.

### Standard

1. User approves track.
2. Write a bullet spec in chat: purpose (1 sentence) · files touched · behavior (3–8 bullets) · must-pass test command · non-goals.
   Look facts up yourself — paths, existing patterns, test commands. Ask the user only about decisions.
3. **Cross-audit the spec only if** the change touches the escalation list above. Otherwise skip.
4. User approves spec.
5. Implement TDD: failing test → verify it fails → minimal code → verify it passes.
6. Run the must-pass command, paste the output.
7. One QA dispatch, one-clue mode, **combined spec + code review** — `fc-qa-code` prompted to check both, since this is the only review pass.
8. Judge the finding: CRITICAL → fix. IMPORTANT → fix or file follow-up. PASS → done.
9. Commit on a feature branch, offer a PR.

### Complex

Load [reference/complex-track.md](reference/complex-track.md) and follow it.

Entry condition: an approved spec from `/fc-brainstorm`, or write one inline. **Verify the user actually approved it** — a spec file existing on disk is not approval.

## Hard gates

Blocking. No forward motion until satisfied.

1. **User approves the track.** Every request.
2. **User approves the spec.** Standard and Complex. Never Trivial.
3. **User approves the plan.** Complex only.
4. **Verification evidence exists for every "done" claim**, and all tests pass before any commit claiming done. The command output must appear in the message making the claim — an agent asserting it ran the tests is not evidence.
5. **Implementation matches the approved spec.** "Requirement X not satisfied" or "required test absent" blocks that task regardless of severity.
6. **Tech Lead approval** before merging Complex work.

Everything else is advisory: report it, the PM decides fix-now or follow-up. Promote advisory to blocking only for a confirmed correctness, security, or data-loss bug.

## Cross-family audit at hard gates

**Canonical rule. Every other Feature-Crew doc points here instead of restating it.**

Every model-authored hard-gate artifact — spec, plan, tests-as-spec, implementation diff, Tech Lead final — must be audited by a model from a different family than the one that wrote it. Same-model audit is theater and does not satisfy the gate, including self-critique with a rotated prompt.

- **Operate** (PM, `fc-architect`, `fc-developer`): session default model.
- **Review** (`fc-qa-spec`, `fc-qa-code`, `fc-tech-lead`, spec cross-audits, `/fc-review`, `/fc-second-opinion`): `model: sonnet`.

Whoever wrote the must-pass tests counts as the spec author for audit purposes — bad tests poison every gate downstream.

If no second family is reachable, run **fewer reviewers rather than two from the same family**. A smaller panel is honest; a same-family pair only looks like coverage.

Trivial produces no model-authored artifact, so no cross-audit applies.

## Dispatch rules

- **Paste task text inline.** Never tell a subagent to "read the plan file."
- **Parallel only at ≥3 independent tasks.** 1–2 tasks, or shared files, run sequentially.
- **Background mode** for substantive work; handle results as they arrive.
- **Max 3 fix cycles per issue**, then stop and question the approach with the user.
- Subagent self-review does not replace QA. Both happen.

## One-clue mode

Every QA dispatch in Standard and Complex:

> Report your single most important finding.
>
> - **PASS** — nothing material, or
> - **CRITICAL** — bug / security / data-loss. `file:line` + minimal repro.
> - **IMPORTANT** — design problem / missing test / unclear behavior. `file:line`.
>
> One finding, not a list. Save the rest for follow-up.

## Cost telemetry

Standard and Complex append one line to the PR description, or the final commit body when there is no PR:

```
Cost: <N> dispatches, ~<M> min wall-clock, models: <list>
```

Trivial is exempt.

## Anti-patterns

- Full Complex flow on a one-file change.
- A spec doc for a Trivial change "for completeness."
- Parallel developers on overlapping files.
- Same-family audit.
- Pushing past a size cap "this one time."
- Adding a gate without removing one.
- Treating advisory findings as automatic blockers.

## Related skills

- Don't know what to build → `/fc-brainstorm`
- Decisions not pinned down → `/fc-grill-me`
- Don't know the facts → `/fc-research`
- Reviewing an artifact this pipeline didn't produce → `/fc-review`
- Testing a decision rather than an artifact → `/fc-second-opinion`
