# Feature-Crew

An agent team framework for AI-assisted development with **Claude Code**. Defines specialized agent roles that work as a pipeline to turn ideas into production-ready code.

> **Scope note (2026-05):** Feature-Crew now targets **Claude Code only**. The previous GitHub Copilot integration is **deprecated and removed**. If you need the Copilot wiring, pin to a tag ≤ `v3.1`.

## Quick Start

### Install globally

Install the role agents and skills into your user-level Claude Code config (`~/.claude`):

```bash
# macOS / Linux / Git Bash / WSL
./install.sh

# Native Windows PowerShell
.\install.ps1
```

Options: `--force` (overwrite), `--dry-run`, `--uninstall`, `--prefix DIR`.

After install:

- Agents land flat at `~/.claude/agents/fc-*.md` (`fc-pm`, `fc-architect`, `fc-developer`, `fc-qa-spec`, `fc-qa-code`, `fc-tech-lead`).
- Skills land at `~/.claude/skills/<name>/` (`build-or-fix`, `research`).

Use them in any project: invoke `/build-or-fix`, `/research`, or ask Claude Code to delegate to one of the `fc-*` subagents. The `build-or-fix` skill also auto-triggers on build/fix/change requests.

## How It Works

Every request starts with the PM picking a **track**:

```
Trivial   →  PM does it directly + verifies + commits           (1 file, no design)
Standard  →  bullet-spec + light build + one QA pass            (1–5 files, small feature)
Complex   →  brainstorm → spec → architect → devs → QA → tech lead   (multi-module, new arch)
```

Wrong track = wasted work or missed risk. The PM proposes a track on every request; the user can override. See `.claude/skills/build-or-fix/SKILL.md` for full flows + worked examples.

### The Team

| Role | Used in | What It Does |
|------|---------|--------------|
| **PM** | All tracks | Picks track, brainstorms, orchestrates. Implements directly on Trivial / light Standard. (`agents/pm.md`) |
| **Developer** | Standard, Complex | Implements one task with TDD. Fresh agent per task. |
| **QA Reviewer** | Standard, Complex | One-clue feedback: single most important finding, or PASS. |
| **Architect** | Complex only | Spec → design + task-by-task plan (≤500 lines). |
| **Tech Lead** | Complex only | Final integration review before merge. |

### Skills

| Skill | Slash command | Purpose |
|---|---|---|
| `build-or-fix` | `/build-or-fix` | Track-based build/fix pipeline (Trivial / Standard / Complex). |
| `research` | `/research` | Multi-agent search → synthesize → validate pipeline with cross-family validation. |

### Speed

A Trivial change ships in seconds. A Standard change ships with one dev pass + one QA pass. Within Complex:
- Independent tasks (≥3) run in parallel
- QA starts the moment each developer finishes
- Fix loops on one task don't block the rest

Right-sizing the process is the speed lever — not just parallelism.

## Project Structure

```
feature-crew/
├── .claude/
│   └── skills/
│       ├── build-or-fix/SKILL.md   ← Track-based pipeline
│       └── research/SKILL.md       ← Multi-agent research pipeline
├── agents/
│   ├── architect.md                ← Design + planning prompt
│   ├── developer.md                ← TDD implementation prompt
│   ├── pm.md                       ← PM behavior + orchestration
│   ├── qa-spec-reviewer.md         ← "Does code match spec?" prompt
│   ├── qa-code-reviewer.md         ← "Is code well-built?" prompt
│   └── tech-lead.md                ← Final review prompt
├── docs/
│   ├── specs/                      ← Design specs go here
│   ├── plans/                      ← Implementation plans go here
│   └── reviews/                    ← Review records (optional)
├── install.sh / install.ps1        ← Cross-platform installer
├── AGENTS.md                       ← Canonical agent instructions
├── CLAUDE.md                       ← Claude Code loader → points at AGENTS.md
└── README.md
```

## Non-Negotiable Rules

These apply to all agents in the team:

- **TDD** — No production code without a failing test first
- **No guessing** — Ask when stuck. Bad work is worse than no work.
- **Verify before claiming** — Run the command, read the output, then claim the result
- **Root cause first** — No fixes without investigation. 3+ failed fixes → rethink the approach
- **YAGNI** — Don't build what isn't requested
- **Cross-platform parity** — Any installer/script in this repo must work identically on bash and PowerShell; both files updated in the same commit.

## Updating

Pull the latest and re-run the installer:

```bash
cd feature-crew
git pull origin main
./install.sh --force
```

## License

MIT
