# Feature-Crew — Agent Instructions

> Single source of truth for AI coding assistants (Claude Code, GitHub Copilot, Cursor, etc.) working in this repository.

This project uses the **Feature-Crew** framework: every build/fix/change request goes through a track-based pipeline (Trivial / Standard / Complex) with mandatory hard gates and cross-family model audits.

## On every build/fix/change request

1. **Propose a track** (Trivial / Standard / Complex) and confirm with the user before doing anything else.
2. **Read `.claude/skills/build-or-fix/SKILL.md`** for the chosen track.
3. **Execute the matching flow**, honoring all hard gates.
4. **Dispatch role agents** from `agents/` (PM, architect, developer, qa-spec-reviewer, qa-code-reviewer, tech-lead) instead of inlining their work.

## Cross-family model audit (hard rule)

Every model-authored hard-gate artifact (spec, plan, tests-as-spec, implementation diff, Tech Lead final) must be audited by a model from a **different family**. Preferred pair: `claude-opus-4.7-xhigh` ⇆ `gpt-5.5`, both max reasoning. Fallback when the cross-vendor pair is unavailable: same-vendor cross-family (e.g. Opus ⇆ Sonnet), flagged `audit-pair: degraded (same-vendor)` in cost telemetry. Same-model self-audit is theater and does not satisfy the gate. Trivial track is exempt.

## Non-negotiables

- **TDD** — no production code without a failing test first
- **Verify before claiming** — run the command, read the output, then claim the result
- **Root cause first** — 3 failed fixes → stop and rethink
- **No guessing** — ask when stuck; bad work is worse than no work
- **YAGNI** — don't build what wasn't requested

## Tool-specific entry points

- **Claude Code**: the `build-or-fix` skill at `.claude/skills/build-or-fix/SKILL.md` auto-triggers on build/fix/change requests; you can also invoke it explicitly with `/skill build-or-fix`.
- **GitHub Copilot**: see `.github/copilot-instructions.md` (mirrors this file).
- **Other tools**: read this file plus `.claude/skills/build-or-fix/SKILL.md`.

## Canonical sources

| What | Where |
|------|-------|
| Track flows, gates, dispatch rules | `.claude/skills/build-or-fix/SKILL.md` |
| Role prompts | `agents/{pm,architect,developer,qa-spec-reviewer,qa-code-reviewer,tech-lead}.md` |
| Project overview | `README.md` |

## Using Feature-Crew in another project

Add as a git submodule, then point your tool at this directory:

```bash
git submodule add <feature-crew-repo-url> feature-crew
```

Then in the consumer project:
- **Claude Code**: symlink `feature-crew/.claude/skills/build-or-fix` → `.claude/skills/build-or-fix` so the skill is auto-discovered in the consumer project. Optionally symlink `feature-crew/.claude/agents/*` once those exist.
- **Copilot**: create `.github/copilot-instructions.md` that reads `feature-crew/.github/copilot-instructions.md`.
- Both tools end up reading the same `.claude/skills/build-or-fix/SKILL.md` and `agents/*.md`.
