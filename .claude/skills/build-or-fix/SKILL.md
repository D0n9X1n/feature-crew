---
name: build-or-fix
description: Build, fix, change, refactor, implement, add, or extend code. TRIGGER whenever the user asks for any code change (e.g. "add login", "fix this bug", "refactor the parser", "implement X"). Runs the request through the Feature-Crew pipeline: picks a track (Trivial / Standard / Complex), runs the matching gates with cross-family model audits, and dispatches role agents (PM, Architect, Developer, QA, Tech Lead). SKIP for pure questions, read-only exploration, status checks, or codebase searches.
---

# build-or-fix — Feature-Crew Pipeline (Three Tracks)

This is the canonical orchestration document for any build/fix/change request. The PM picks one of three tracks per request. Each track defines its own flow, gates, and worked example.

> **Canonical home for cross-family audit rule:** `agents/pm.md` §Universal Rules. The copy below mirrors it so this skill is self-sufficient — keep the two in sync when either is edited.

## Why three tracks

A 5-line README typo and a multi-module auth subsystem are not the same problem. Applying the same gates to both produces RFC-grade ceremony for trivial work and rushes complex work. The framework right-sizes by:

- **Trivial** — direct edit + verification
- **Standard** — bullet spec + lightweight build + one review
- **Complex** — full pipeline with size caps and Tech Lead final

The PM proposes a track on every request. The user can override.

## Hard gates vs soft gates

A **hard gate** blocks all forward motion until satisfied. The complete list:

1. **User approves track** — every request, every track.
2. **User approves spec** — Standard (inline bullet spec) and Complex (doc). Never required for Trivial.
3. **User approves plan** — Complex only.
4. **Verification evidence is present** for every "done" claim — every agent, every phase.
5. **All tests pass** before any commit-claiming-done.
6. **Tech Lead approval** before merging Complex work to main.
7. **Implementation matches approved spec.** A QA-spec-reviewer finding of "implementation does not satisfy approved requirement X" or "required test absent" is a hard gate — it blocks "done" for that task regardless of severity rubric below.

A **soft gate** is advisory — the agent reports findings, the PM decides whether to act now or file a follow-up. **Code-quality QA findings (style, structure, maintainability) are soft gates by default.** Promote to hard only when the finding is a confirmed correctness, security, or data-loss bug — but spec-compliance failures (gate #7) are *always* hard regardless of severity.

### Cross-Model Audit at Every Hard Gate

Every model-authored hard-gate artifact (spec, plan, **tests-as-spec**, implementation diff, Tech Lead final review) must be audited by a model from a **different family** before it counts as satisfied. Strongest pair, both at max reasoning effort:

- `claude-opus-4.7-xhigh` ⇆ `gpt-5.5`

**Fallback when the cross-vendor pair is unavailable** (GPT access down, quota exhausted, offline, etc.): a same-vendor cross-family pair such as `claude-opus-4.7-xhigh` ⇆ `claude-sonnet-4.7` is **acceptable but degraded**. It satisfies the hard gate only when the preferred cross-vendor pair cannot be reached; the PM must note `audit-pair: degraded (same-vendor)` in the cost telemetry line so reviewers know a weaker check was used. Never use the fallback by default — always attempt the preferred pair first.

Same-model audit (even self-critique with rotated prompts) is theater and **does not satisfy the gate**. The author of the must-pass tests is the spec author for cross-audit purposes — bad tests poison every downstream gate.

Trivial-track work has only user-approval and mechanical-verification gates (no model-authored artifact), so cross-model audit does not apply there. Speed is preserved.

**This rule applies to every skill in this repo, not just build-or-fix.** Any future skill that produces a model-authored hard-gate artifact must follow it.

---

## Track 1 — Trivial

### Use when

- ≤30 minutes
- 1 file, single concept change
- No design decision required
- Reverting via `git revert` is trivially safe

### Trivial does NOT apply if

If any of the following is touched, the change is **at minimum Standard**, regardless of how few lines it is:

- Runtime behavior (default values, feature flags, config)
- Auth, security, secrets handling
- Persistence (DB schema, data formats, migrations)
- Public API contract (request/response shapes, CLI flags, library exports)
- Deploy behavior (CI/CD scripts, infra-as-code, rollout)
- Anything where a 1-line wrong value reaches production

A 1-line change in any of these areas can have outsized blast radius and needs at least a bullet spec + verification + one QA pass.

### Flow

1. PM proposes "Trivial" with one-line reason.
2. User approves track (hard gate).
3. PM makes the change.
4. PM runs verification command and pastes output (hard gate).
5. PM commits.

### Worked example

> User: "fix typo — 'orchestrats' → 'orchestrates' in README.md"
>
> PM: "Trivial — agreed?" → user "yes" → PM edits → PM runs `grep -n 'orchestr' README.md` → output confirms fix → PM commits with message `docs: fix typo in README`. Total: 0 subagent dispatches, ~30 seconds.

### What you do NOT do

- No spec doc.
- No subagent.
- No QA pass.
- No new branch unless the user prefers one.

---

## Track 2 — Standard

### Use when

- 1–5 files
- Single coherent feature
- No new architecture
- Security/data-integrity not central
- **All framework-internal changes** (per the meta-work cap below)

### Flow

1. PM proposes "Standard" with reason.
2. User approves track (hard gate).
3. PM writes bullet-list spec in chat (≤1 page):
   - Purpose (1 sentence)
   - Files touched (list)
   - Behavior (3–8 bullets)
   - Test approach (must-pass test command)
   - Non-goals
4. **Cross-audit spec.** Before requesting user approval, dispatch a different-family model in one-clue mode to review the spec — especially the must-pass test command — for ambiguity, missing edge cases, or a test that doesn't actually verify the stated behavior. Address CRITICAL findings.
5. User approves spec (hard gate).
6. PM implements directly (≤2 files) **or** dispatches one developer subagent with TDD prompt.
7. PM runs the must-pass tests; output pasted (hard gate).
8. Dispatch one `code-review` subagent in **one-clue mode** (see below).
9. PM judges the finding: CRITICAL → fix; IMPORTANT → fix or follow-up; PASS → done.
10. Commit on feature branch; offer PR to the user.

### Worked example

> User: "add a `--dry-run` flag to deploy.sh"
>
> PM: "Standard — 2 files (`deploy.sh`, `tests/deploy_test.sh`), no architectural change. OK?" → user OK.
>
> PM writes 5-bullet spec inline → dispatches gpt-5.5 in one-clue mode to cross-audit spec → returns PASS → user approves.
>
> PM implements TDD: failing test for `--dry-run` not yet supported → makes it pass → all tests green.
>
> PM runs `bats tests/deploy_test.sh` → output: `8 tests, 0 failures` → pastes.
>
> PM dispatches `code-review` in one-clue mode → returns PASS.
>
> PM commits, offers PR. Total: 2 subagent dispatches (1 spec cross-audit, 1 code-review).

### Cost expectation

≤2 subagent dispatches typical. Anything more = wrong track or scope creep.

---

## Track 3 — Complex

### Use when

- Multi-module change
- New architecture or new subsystem
- Security/data-integrity central
- Public API change
- **Never** for framework-internal changes (those route to Track 2 max — see meta-work cap)

### Flow

1. PM proposes "Complex" with reason.
2. User approves track (hard gate).
3. **Brainstorm.** PM asks clarifying questions, one at a time, multiple-choice preferred. Covers purpose, constraints, success criteria, edge cases, test strategy.
4. PM presents design in sections, gets per-section user approval.
5. **Spec.** Write to `docs/specs/YYYY-MM-DD-<topic>-design.md`. **Hard cap: 1000 words.** If draft exceeds, decompose into sub-projects.
6. **Cross-audit spec.** Different-family one-clue review of spec doc — especially must-pass criteria and test strategy — before requesting user approval. Address CRITICAL findings.
7. User approves spec (hard gate).
8. **Architect.** Dispatch `general-purpose` subagent with full spec text + project structure + tech constraints. Architect produces plan.
9. **Plan cap.** Plan ≤ **500 lines**. Over the cap → architect decomposes; if irreducible, escalate to user for re-scoping.
10. User approves plan (hard gate).
11. **Parallel implementation.** Group tasks by file independence. Dispatch developers in parallel **only when ≥3 truly independent tasks remain**. For 1–2 tasks, sequential is fine.
12. **Per-task QA in one-clue mode.** Spec-compliance pass first, then code-quality pass. Each returns single most important finding or PASS.
13. **Tech Lead final review.** Dispatch with spec, plan, full diff, task summaries. Hard gate before merge.
14. **Cost telemetry.** PM appends one-liner to PR description: total dispatches, approximate wall-clock, model mix.

### Worked example (sketch)

> User: "build OAuth + SAML auth subsystem."
>
> PM proposes Complex. Brainstorms: which providers? session vs JWT? RBAC scope? → spec written, 850 words, committed. **gpt-5.5 cross-audits spec** → flags one IMPORTANT (missing logout flow in must-pass criteria) → addressed → user approves.
>
> Architect (Opus) produces 380-line plan with 12 tasks. User approves.
>
> 4 tasks are independent (DB schema, OAuth provider config, SAML config, login UI shell) — dispatched in parallel. 8 sequenced behind them.
>
> Per-task QA in one-clue mode catches one CRITICAL (session token not invalidated on logout) — fixed in a single dev cycle.
>
> **Tech Lead final on gpt-5.5** (different family from Opus implementers) approves. PR opened. Cost line: `17 dispatches, ~3h wall-clock, models: claude-opus-4.7-xhigh (architect, devs) + gpt-5.5 (spec audit, tech lead) + Haiku (mechanical tasks)`.

---

## The Meta-Work Cap

**Any change to feature-crew itself is Track 2 maximum.**

### Numeric caps

- The **orchestration layer** (`agents/pm.md` + `.claude/skills/build-or-fix/SKILL.md`) stays **≤ 600 lines combined**.
- The **framework total** (orchestration layer + all `agents/*.md` prompt templates + `README.md` + `AGENTS.md` + `CLAUDE.md` + framework-owned `docs/*.md` + every `.claude/skills/*/SKILL.md`) stays **≤ 1500 lines combined**. The cap was raised from 1200 to accommodate the Claude Code skill wiring; the +300 covers the SKILL expansion that absorbed the legacy pipeline doc plus headroom for one or two future skills.

If a proposed change would push either total over its cap, **decompose**, never "make an exception this one time."

### What counts as framework-internal

A request is framework-internal — and therefore Track-2-max + subject to the caps above — if it modifies any of:

- **Orchestration rules** — when phases run, what gates trigger, how the PM dispatches
- **Gate semantics** — what hard/soft gates exist, what promotes a soft to a hard
- **Agent roster** — adding, removing, or renaming agents (e.g., new auditor role, new reviewer role)
- **Prompt contracts** — what subagents are told to do or how they report
- **Framework-owned docs** — anything in this repo authored by feature-crew itself: `agents/*.md`, `.claude/skills/*/SKILL.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, and any top-level `docs/*.md` (excluding the user-authored `docs/specs/`, `docs/plans/`, `docs/reviews/` subdirectories)
- **Framework artifacts** — adding new files in any of the directories above, or new top-level framework-owned docs

The literal "multi-auditor voting" case is one instance of this class. **Any** request that changes orchestration, gates, agents, prompts, or framework docs is in the same class and gets the same treatment, regardless of phrasing.

### Refusal example

> User: "redesign feature-crew with multi-auditor voting and North-Star injection."
>
> PM: "This is framework-internal — capped at Track 2 max. The full proposal would add ~400 lines to this skill alone, breaking the 600-line orchestration cap. Options:
>
> 1. Add a single optional second-opinion auditor for spec only (Track 2, ~50 lines). Ship it, evaluate, then decide whether to add more.
> 2. North-Star injection is a separate question — file as a follow-up.
> 3. Drop the multi-auditor direction.
>
> Which?"

The deleted-branch experience (6,800 lines of meta-work for an unrun feature) is what this cap exists to prevent.

### If the user wants to override

The cap is not silently overridable. If the user explicitly says "I am intentionally bypassing the framework meta-work cap," comply but record the override in the commit message as `framework-cap-override: <reason>`. A casual "use Complex track for this" is not enough — confirm intent first.

---

## Subagent Dispatch Rules

- **Background mode** for any subagent that does substantive work; handle results as notifications arrive.
- **Parallel only when independent.** ≥3 truly independent tasks → parallel. 1–2 tasks or shared files → sequential. "Maximize parallelism" is a trap when each branch needs its own context construction and review.
- **Fresh context per dispatch.** Paste the task/spec text inline. Do not tell subagents to "read the plan file."
- **Model selection:** Haiku for mechanical tasks (well-specified, single-file). Sonnet/default for design or judgment. Don't over-spec models — defaults are fine.
- **Subagent self-review does not replace QA.** Both happen.
- **No same-model self-audit.** See "Cross-Model Audit at Every Hard Gate" above. Even outside hard gates, prefer a different-family model for any second-opinion pass.
- **Max 3 fix cycles per issue.** Then stop and question the approach with the user.

---

## One-Clue Feedback Mode

For every QA dispatch in Standard/Complex tracks, instruct the subagent:

> Report your **single most important finding**. Format:
>
> - **PASS** — nothing material to flag, OR
> - **CRITICAL** — bug / security / data-loss risk; specific `file:line` + minimal repro
> - **IMPORTANT** — design problem / missing test / unclear behavior; specific `file:line`
>
> Do not list multiple issues. Pick one. Save the rest for follow-up.

This trades comprehensive defect lists for actionable signal. Long reports invite nitpicks and inflate fix cycles.

---

## Cost Telemetry

For every Standard or Complex feature, append a single-line telemetry record at the end of the work:

- For PR-bound work: append to the PR description
- For non-PR work (e.g., direct commit on a feature branch): append to the final commit message body

Format:

```
Cost: <N> subagent dispatches, ~<M> minutes wall-clock, models: <list>
```

Trivial work does not require telemetry (it's by definition cheap). If we don't measure, we won't tighten — visible cost is the friction that keeps small changes small.

---

## Anti-Patterns

- Applying full Complex flow to a one-file change.
- Writing a spec doc for a Trivial change "for completeness."
- Dispatching multiple parallel devs on overlapping files.
- Same-model self-audit (theater).
- Pushing past spec/plan size caps "this one time."
- Adding gates without removing them — gate count grows monotonically.
- Treating QA findings as automatic blockers rather than PM-judged signals.
