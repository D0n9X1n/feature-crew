---
name: fc-review
description: Reviews an existing artifact — a diff, a PR, a spec, a plan — against correctness, spec compliance, and maintainability, and returns the findings that matter. Use when the user asks to review, audit, or check work, especially work they did not just watch being written. Do NOT use for judging a decision or claim with no artifact (use /fc-second-opinion), and do NOT use on a diff /fc-build-or-fix just produced — that pipeline reviews its own output.
effort: max
disallowed-tools: Write Edit NotebookEdit
---

# fc-review

Reviews something that already exists. Read-only by policy: do not edit files or mutate repository state through any tool, including shell commands or delegated workers. Frontmatter removes `Write`, `Edit`, and `NotebookEdit` only for the turn that loads the skill. Bash and PowerShell remain write-capable when available; this is not enforced isolation. Reapply the policy after user replies and include it in every worker prompt. This skill cannot approve or block a gate. It reports; the human decides.

## 1 — Establish the artifact

Identify exactly what is under review and pin its boundaries.

| Artifact | Boundary |
|---|---|
| Working diff | `git diff` / `git diff --staged` |
| Branch | `git diff <base>...HEAD` |
| PR | `gh pr diff <n>` |
| Spec or plan | the file, plus the requirement it claims to satisfy |
| Shortcut ledger | `git grep -nE '(#|//|/[*]|--|;)[[:space:]]*shortcut:'`; one row per marker with its limit and trigger, tagged `no-trigger` when it names none |

Read the artifact yourself. A description of a change is not the change.

## 2 — Pick lenses

Two or three, matched to the artifact. More lenses produce longer reports, not better ones.

- **Correctness** — does it do what it claims? Off-by-one, null paths, error handling, race conditions.
- **Spec compliance** — every stated requirement implemented and tested? Anything built that nobody asked for?
- **Maintainability** — could a stranger change this safely in six months?
- **Test quality** — do the tests verify behavior or mocks? Would they catch a regression?
- **Security** — only when the artifact touches auth, secrets, input handling, or persistence.
- **Lean** — code that should not exist or should be smaller; name the helper or library to reuse.
- **Scale** — state the load you assumed; races, lists that only grow, a query per item.

Dispatch at least one lens subagent for every review, whatever the diff size; add parallel lenses when the diff is large. One lens per agent; each returns every finding that has a failure scenario, most severe first. Notes the main session writes itself are labeled same-session and never count as the independent review.
Every lens dispatch carries an explicit `model` override chosen by the canonical selector in `/fc-build-or-fix` when the artifact has a known model author. For a human or unknown author, request the first review-pair member and label the review advisory with independence unverified. Read the recorded model of each lens as [gate-provenance.md](../fc-build-or-fix/reference/gate-provenance.md) describes and exclude any result with missing or unknown provenance or a model in the author family. Zero usable lenses makes the review unavailable, never PASS or an inline review.

## 3 — Report

Start with `What this change does:` in two or three plain sentences. Number findings across **Must fix**, **Should fix**, and **Nice to have**, so the user can say "fix 2 and 5". Each finding gives `file:line`, the problem in one sentence, **a concrete failure scenario**, the smallest fix, and what happens if it is skipped.

A finding with no failure scenario is a preference, not a defect; drop it or label it as taste, and leave style to formatters. A `shortcut:` comment that names its limit is a decision, not a finding, unless the assumed load already crosses it. Report every finding that has a failure scenario; keep lower-severity ones to one line each.

End with `Verdict:`, then `Not checked:` naming anything material you could not verify. **PASS** — nothing material found. **CRITICAL** — a Must fix: correctness, security, or data loss; merging causes harm. **IMPORTANT** — a Should fix: a real problem, not a blocker on its own.

## Rules

- Do not manufacture findings. "This is clean" is a valid, useful result.
- Verify claims against the code; a developer's report is a claim, not evidence.
- Say when you could not verify something rather than assuming it works.

## Related skills

- No artifact, just a decision → `/fc-second-opinion`
- Fixing what this finds → `/fc-build-or-fix`
