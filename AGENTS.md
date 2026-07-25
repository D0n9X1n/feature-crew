# Feature-Crew — Agent Instructions

> Single source of truth for **Claude Code** working in this repository.

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
4. **Dispatch role agents** from `agents/` rather than inlining their work.

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

## Framework caps

Feature-Crew changes are **Standard track maximum**. Orchestration (`agents/pm.md` + every `SKILL.md`) stays ≤600 lines; the framework total stays ≤1500. Both are asserted by `tests/framework_test.sh` — run it before committing framework changes.

## Layout

| What | Where |
|---|---|
| Skills | `.claude/skills/fc-*/SKILL.md` |
| Complex track, meta-work cap | `.claude/skills/fc-build-or-fix/reference/` |
| Role prompts | `agents/*.md` |
| Self-test | `tests/framework_test.sh` |

## Install

```bash
./install.sh         # macOS / Linux / Git Bash / WSL
.\install.ps1        # native Windows PowerShell
```

Agents land at `~/.claude/agents/fc-*.md`, skills at `~/.claude/skills/fc-*/`. Both are then available in every project.
