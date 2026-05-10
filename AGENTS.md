# Feature-Crew — Agent Instructions

> Single source of truth for **Claude Code** working in this repository.
>
> **Scope (2026-05):** Feature-Crew now targets Claude Code only. The previous GitHub Copilot integration is **deprecated and removed** — pin to `v3.1` if you still need it.

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
- **Cross-platform parity** — any installer / CLI / script that ships in this repo MUST work identically on macOS, Linux, and Windows. When a feature lands in `install.sh` it lands in `install.ps1` the same commit; flags, behavior, and output stay mirrored. Do not let one platform drift ahead of the other.

## Entry points

- **`build-or-fix` skill** at `.claude/skills/build-or-fix/SKILL.md` — auto-triggers on build/fix/change requests; also invokable as `/build-or-fix`.
- **`research` skill** at `.claude/skills/research/SKILL.md` — invokable as `/research <topic>` for multi-agent investigations.
- **fc-* subagents** — `fc-pm`, `fc-architect`, `fc-developer`, `fc-qa-spec`, `fc-qa-code`, `fc-tech-lead`. After running `./install.sh`, these are usable in any project.

## Canonical sources

| What | Where |
|------|-------|
| Track flows, gates, dispatch rules | `.claude/skills/build-or-fix/SKILL.md` |
| Multi-agent research pipeline | `.claude/skills/research/SKILL.md` |
| Role prompts | `agents/{pm,architect,developer,qa-spec-reviewer,qa-code-reviewer,tech-lead}.md` |
| Project overview | `README.md` |

## Using Feature-Crew in another project

Run the installer once on your machine — agents and skills land globally in `~/.claude/`:

```bash
./install.sh         # macOS / Linux / Git Bash / WSL
.\install.ps1        # native Windows PowerShell
```

After install, every Claude Code session in any project can invoke `/build-or-fix`, `/research`, and the `fc-*` subagents.
