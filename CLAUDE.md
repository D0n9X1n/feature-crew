# Feature-Crew — Agent Instructions

> Single source of truth for **Claude Code** working in this repository. This repo targets Claude Code only; there is no `AGENTS.md` — everything lives here.

Every request routes to one of six skills. Each maps to something the user is missing.

| The user lacks | Skill | Produces |
|---|---|---|
| facts | `/fc-research` | evidence + open questions |
| pinned-down decisions | `/fc-grill-me` | shared understanding |
| an approach | `/fc-brainstorm` | approved spec |
| the code | `/fc-build-or-fix` | tested implementation |
| confidence in an artifact | `/fc-review` | ranked findings |
| confidence in a decision | `/fc-second-opinion` | survives / refuted |

Offer the next skill; never chain automatically.

## On every build/fix/change request

1. **Propose a track** — Trivial / Standard / Complex — and confirm before doing anything else.
2. **Read `.claude/skills/fc-build-or-fix/SKILL.md`** and run the matching flow.
3. **Honor every hard gate.**
4. **Dispatch role agents** from `agents/fc-*.md` rather than inlining their work.

## Models

- **Operate** (PM, `fc-architect`, `fc-developer`): session default.
- **Review** (`fc-qa-spec`, `fc-qa-code`, `fc-tech-lead`, `/fc-review`, `/fc-second-opinion`): `model: sonnet`, written into frontmatter by the installer so it can't be forgotten at dispatch time.

The cross-family audit rule is canonical in `.claude/skills/fc-build-or-fix/SKILL.md`. Point at it; don't restate it.

## Non-negotiables

- **TDD** — no production code without a failing test first
- **Verify before claiming** — run the command, read the output, paste it in the same message as the claim
- **Root cause first** — 3 failed fixes means stop and rethink
- **No guessing** — look facts up, ask about decisions
- **YAGNI** — don't build what wasn't requested
- **Cross-platform parity** — `install.sh` and `install.ps1` ship together, always mirrored: same flags, same behavior, same output. This covers shipped artifacts; `tests/` is dev-only tooling and is bash-only by design.

## Release process

Releases are cut by CI on tag push. Follow this order — the tag is last, because pushing it publishes.

1. **Milestone.** Every release has a GitHub milestone named for its version (`v5.0.0`).
2. **Issues.** Each distinct work item gets an issue assigned to that milestone. An issue is the unit of "what shipped," so the release notes can be read without opening a diff.
3. **PR.** The PR is assigned to the same milestone and closes its issues with `Closes #N` lines, so merging resolves them.
4. **Merge to `main`.** The suite must be green; `.github/workflows/test.yml` gates this.
5. **Tag `main`** with `vMAJOR.MINOR.PATCH` — three numbers, always. Never tag an unmerged branch.
6. **CI releases.** `.github/workflows/release.yml` fires on `v*`, re-runs the suite, and publishes a GitHub Release whose notes list every commit between the previous tag and this one.

Versioning is semver: breaking changes to skill names, agent names, gate semantics, or installer behavior are MAJOR.

## Framework caps

Feature-Crew changes are **Standard track maximum**. Orchestration (`agents/fc-pm.md` + every `SKILL.md`) stays ≤600 lines; the framework total stays ≤1500. Both are asserted by `tests/framework_test.sh` — run it before committing framework changes.

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

Agents land at `~/.claude/agents/fc-*.md`, skills at `~/.claude/skills/fc-*/`. Both are then available in every project.
