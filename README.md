# Feature-Crew

An agent team framework for AI-assisted development. Defines 5 specialized agent roles that work as a pipeline to turn ideas into production-ready code.

## Quick Start

### Add to your project

```bash
cd your-project
git submodule add <feature-crew-repo-url> feature-crew
```

### Wire it up

Create `.github/copilot-instructions.md` in your project root:

```markdown
This project uses the feature-crew agent framework.

Read `feature-crew/.github/copilot-instructions.md`, `feature-crew/agents/pm.md`, and `feature-crew/workflow/pipeline.md` at session start.

When the user asks to build, fix, or change anything:
1. Act as the PM — propose a track (Trivial / Standard / Complex) and confirm with the user
2. Follow the matching flow in `feature-crew/workflow/pipeline.md`
3. Right-size the process to the change — don't apply Complex ceremony to Trivial work
```

That's it. Start a new Copilot session and describe what you want to build.

## How It Works

Every request starts with the PM picking a **track**:

```
Trivial   →  PM does it directly + verifies + commits           (1 file, no design)
Standard  →  bullet-spec + light build + one QA pass            (1–5 files, small feature)
Complex   →  brainstorm → spec → architect → devs → QA → tech lead   (multi-module, new arch)
```

Wrong track = wasted work or missed risk. The PM proposes a track on every request; the user can override. See `workflow/pipeline.md` for full flows + worked examples.

### The Team

| Role | Used in | What It Does |
|------|---------|--------------|
| **PM** | All tracks | Picks track, brainstorms, orchestrates. Implements directly on Trivial / light Standard. (`agents/pm.md`) |
| **Developer** | Standard, Complex | Implements one task with TDD. Fresh agent per task. |
| **QA Reviewer** | Standard, Complex | One-clue feedback: single most important finding, or PASS. |
| **Architect** | Complex only | Spec → design + task-by-task plan (≤500 lines). |
| **Tech Lead** | Complex only | Final integration review before merge. |

### Speed

A Trivial change ships in seconds. A Standard change ships with one dev pass + one QA pass. Within Complex:
- Independent tasks (≥3) run in parallel
- QA starts the moment each developer finishes
- Fix loops on one task don't block the rest

Right-sizing the process is the speed lever — not just parallelism.

## Project Structure

```
feature-crew/
├── .github/
│   └── copilot-instructions.md   ← PM behavior + orchestration rules
├── agents/
│   ├── architect.md              ← Design + planning prompt
│   ├── developer.md              ← TDD implementation prompt
│   ├── qa-spec-reviewer.md       ← "Does code match spec?" prompt
│   ├── qa-code-reviewer.md       ← "Is code well-built?" prompt
│   └── tech-lead.md              ← Final review prompt
├── workflow/
│   └── pipeline.md               ← Full pipeline with dispatch examples
├── docs/
│   ├── specs/                    ← Design specs go here
│   ├── plans/                    ← Implementation plans go here
│   └── reviews/                  ← Review records (optional)
└── README.md
```

## Non-Negotiable Rules

These apply to all agents in the team:

- **TDD** — No production code without a failing test first
- **No guessing** — Ask when stuck. Bad work is worse than no work.
- **Verify before claiming** — Run the command, read the output, then claim the result
- **Root cause first** — No fixes without investigation. 3+ failed fixes → rethink the approach
- **YAGNI** — Don't build what isn't requested

## Updating

```bash
cd your-project/feature-crew
git pull origin main
cd ..
git add feature-crew
git commit -m "chore: update feature-crew"
```

## License

MIT
