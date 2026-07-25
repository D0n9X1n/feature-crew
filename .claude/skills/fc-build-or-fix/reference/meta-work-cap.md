# The meta-work cap

Loaded on demand by `/fc-build-or-fix`. Any change to Feature-Crew itself is **Standard track maximum**.

## Numeric caps

- **Orchestration layer** — `agents/fc-pm.md` + every `.claude/skills/*/SKILL.md` — stays **≤ 600 lines combined**.
- **Framework total** — orchestration layer + all `agents/*.md` + all skill supporting files + `README.md` + `AGENTS.md` + `CLAUDE.md` — stays **≤ 1500 lines combined**.

Both are asserted by `tests/framework_test.sh`. If a change would push either total over, **decompose**. Never "make an exception this one time."

The orchestration cap counts *every* `SKILL.md`, not a named list. An earlier version named only two files, which meant new skills could add unbounded orchestration text while the cap still reported green.

## What counts as framework-internal

Anything that modifies:

- **Orchestration rules** — when phases run, what gates trigger, how the PM dispatches
- **Gate semantics** — what gates exist, what promotes advisory to blocking
- **Agent roster** — adding, removing, or renaming agents
- **Skill roster** — adding, removing, or renaming skills
- **Prompt contracts** — what subagents are told to do, or how they report
- **Framework-owned docs** — `agents/*.md`, `.claude/skills/**`, `README.md`, `AGENTS.md`, `CLAUDE.md`, top-level `docs/*.md` (excluding user-authored `docs/specs/`, `docs/plans/`, `docs/reviews/`)

## Refusal example

> User: "redesign feature-crew with multi-auditor voting and North-Star injection."
>
> PM: "Framework-internal — Standard max. That proposal adds ~400 lines to the orchestration layer and breaks the 600-line cap. Options: (1) one optional second-opinion auditor for spec only, ship and evaluate; (2) North-Star injection as a separate follow-up; (3) drop it. Which?"

## Override

Not silently overridable. A casual "just use Complex for this" is not enough. The user must say explicitly that they are bypassing the meta-work cap; record it in the commit message as `framework-cap-override: <reason>`.
