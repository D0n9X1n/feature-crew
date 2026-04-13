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

Read and follow `feature-crew/.github/copilot-instructions.md` for all development workflows.

When the user asks to build, fix, or change anything:
1. Act as the PM — discuss requirements, produce a spec
2. Dispatch agents from `feature-crew/agents/` following `feature-crew/workflow/pipeline.md`
3. Run all independent work in parallel

Agent templates: `feature-crew/agents/`
Pipeline definition: `feature-crew/workflow/pipeline.md`
```

That's it. Start a new Copilot session and describe what you want to build.

## How It Works

```
You (human) ←→ PM (Copilot session)
                    ↓ spec
               Architect → design + plan
                    ↓ (you approve)
               Developers → code + tests  (parallel)
                    ↓
               QA → spec check + code review  (parallel)
                    ↓
               Tech Lead → final review
                    ↓
               Merge / PR
```

### The Team

| Role | Agent Type | What It Does |
|------|-----------|--------------|
| **PM** | Main session | Discusses requirements with you, writes spec, orchestrates the pipeline |
| **Architect** | `general-purpose` subagent | Takes spec → produces design + task-by-task implementation plan |
| **Developer** | `general-purpose` subagent | Implements one task with TDD. Fresh agent per task. Runs in parallel |
| **QA** | `general-purpose` + `code-review` | Two-stage: spec compliance first, then code quality. Parallel across tasks |
| **Tech Lead** | `general-purpose` subagent | Final integration review of all changes before merge |

### Speed

Everything that can run in parallel does:
- Independent tasks → multiple developers at once
- QA starts the moment each developer finishes (doesn't wait for others)
- Fix loops on one task don't block the rest

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
