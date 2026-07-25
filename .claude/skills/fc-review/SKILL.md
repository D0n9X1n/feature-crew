---
name: fc-review
description: Reviews an existing artifact — a diff, a PR, a spec, a plan — against correctness, spec compliance, and maintainability, and returns the findings that matter. Use when the user asks to review, audit, or check work, especially work they did not just watch being written. Do NOT use for judging a decision or claim with no artifact (use /fc-second-opinion), and do NOT use on a diff /fc-build-or-fix just produced — that pipeline reviews its own output.
model: sonnet
effort: max
disallowed-tools: Write Edit NotebookEdit
---

# fc-review

Reviews something that already exists. Read-only by construction: this skill has no write tools, so it cannot "helpfully fix" what it finds, and it cannot approve or block a gate. It reports; the human decides.

## 1 — Establish the artifact

Identify exactly what is under review and pin its boundaries.

| Artifact | Boundary |
|---|---|
| Working diff | `git diff` / `git diff --staged` |
| Branch | `git diff <base>...HEAD` |
| PR | `gh pr diff <n>` |
| Spec or plan | the file, plus the requirement it claims to satisfy |

Read the artifact yourself. A description of a change is not the change.

## 2 — Pick lenses

Two or three, matched to the artifact. More lenses produce longer reports, not better ones.

- **Correctness** — does it do what it claims? Off-by-one, null paths, error handling, race conditions.
- **Spec compliance** — every stated requirement implemented and tested? Anything built that nobody asked for?
- **Maintainability** — could a stranger change this safely in six months?
- **Test quality** — do the tests verify behavior or mocks? Would they catch a regression?
- **Security** — only when the artifact touches auth, secrets, input handling, or persistence.

Run lenses as parallel subagents when the diff is large. One lens per agent, each in one-clue mode.

## 3 — Report

Findings first, ranked by severity. For each:

- `file:line`
- what is wrong, in one sentence
- **a concrete failure scenario** — inputs or state that produce the wrong result

A finding with no failure scenario is a preference, not a defect. Drop it or label it as taste.

End with a verdict:

- **PASS** — nothing material found.
- **CRITICAL** — correctness, security, or data-loss defect. Merging causes harm.
- **IMPORTANT** — real problem, not a blocker on its own.

Cap the report at the top **5** findings. Say how many you dropped.

## Rules

- Do not manufacture findings. "This is clean" is a valid, useful result.
- No style nitpicking — formatters own that.
- Verify claims against the code; a developer's report is a claim, not evidence.
- Say when you could not verify something rather than assuming it works.

## Related skills

- No artifact, just a decision → `/fc-second-opinion`
- Fixing what this finds → `/fc-build-or-fix`
