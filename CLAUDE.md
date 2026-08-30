# Feature-Crew — Agent Instructions

> Single source of truth for **Claude Code** in this repository. There is no `AGENTS.md`.

Users describe needs naturally; slash-command knowledge is not required. The canonical missing-ingredient classifier and bounded return-to-origin composition rule live in `.claude/skills/fc-build-or-fix/SKILL.md`. Use compact pointers elsewhere; do not duplicate that classifier.

## On every build/fix/change request

1. Read `.claude/skills/fc-build-or-fix/SKILL.md` and classify the need.
2. Select **Just Do It / Standard / Complex** by complexity and risk.
3. Auto-run eligible Just Do It work; Standard/Complex retain approval flow unless waived.
4. Honor every hard gate. Dispatch role agents from `agents/fc-*.md` only where the flow calls for them.

## Models

All six installed role agents carry no `model` key. For every model-authored hard-gate review, apply the artifact-author-provenance selector, exact Agent override, audit envelope, and fail-closed behavior canonical in `.claude/skills/fc-build-or-fix/SKILL.md`. Do not restate it here.

Standalone `/fc-review` and `/fc-second-opinion` are not hard-gate substitutes.

## Non-negotiables

- **TDD** — no production code without an observed failing test first; docs use objective acceptance checks first
- **Verify before claiming** — run the command, read output, paste it in the same message
- **Root cause first** — three failed fixes means stop and rethink
- **No guessing** — look up facts, ask about decisions
- **YAGNI** — do not build what was not requested
- **Cross-platform parity** — `install.sh` and `install.ps1` ship together with the same flags, behavior, and output. `tests/` is dev-only and bash-only by design.

## Release process

Releases are cut by CI on tag push. The tag is last because pushing it publishes.

1. Create a milestone named for the exact version.
2. Give each distinct work item an issue assigned to that milestone.
3. Assign the PR to the milestone and close its issues with `Closes #N` lines.
4. Merge to `main` only with `.github/workflows/test.yml` green.
5. Tag `main` as `vMAJOR.MINOR.PATCH`; never tag an unmerged branch.
6. `.github/workflows/release.yml` reruns the suite and publishes the release body.

**No changelog file.** The GitHub release body is generated from commits between tags and is the sole changelog. Write commit subjects worth publishing. Body structure: `## <project> <tag>`, then `### Commits`, `### Contents`, `### Validation`, `### Install`.

Versioning defaults to semver; an explicit approved version decision overrides that default.

## Framework caps

Feature-Crew changes are **Standard track maximum**. Orchestration (`agents/fc-pm.md` plus every `SKILL.md`) stays ≤600 lines; framework total stays ≤1500 and under its ratcheted baseline. `tests/framework_test.sh` enforces the binding limits.

## Layout

| What | Where |
|---|---|
| Skills | `.claude/skills/fc-*/SKILL.md` |
| Complex track, meta-work cap | `.claude/skills/fc-build-or-fix/reference/` |
| Role prompts | `agents/fc-*.md` |
| Self-test | `tests/framework_test.sh` |
| CI | `.github/workflows/` |

## Install

```bash
./install.sh         # macOS / Linux / Git Bash / WSL
.\install.ps1        # native Windows PowerShell
```

Agents land at `~/.claude/agents/fc-*.md`; skills at `~/.claude/skills/fc-*/`.
