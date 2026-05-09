# Integrating Feature-Crew Into a Project

Feature-Crew is an agent framework added as a git submodule. This guide gets you set up.

## Step 1: Add the submodule

```bash
cd your-project
git submodule add <feature-crew-repo-url> feature-crew
git commit -m "chore: add feature-crew agent framework"
```

## Step 2: Create your project's Copilot instructions

Create `.github/copilot-instructions.md` in your project root. Replace bracketed sections with your project's specifics.

```markdown
# [Your Project Name]

This project uses the **feature-crew** agent framework.

## Agent Framework

Read at session start:
- `feature-crew/.github/copilot-instructions.md`
- `feature-crew/agents/pm.md`
- `feature-crew/.claude/skills/build-or-fix/SKILL.md`

When asked to build, fix, or change anything:
1. Act as the PM — propose a track (Trivial / Standard / Complex) and confirm with the user
2. Follow the matching flow in `feature-crew/.claude/skills/build-or-fix/SKILL.md`
3. Right-size the process to the change — don't apply Complex ceremony to Trivial work

## Project-Specific

### Tech Stack
[e.g., TypeScript, Node.js, React, PostgreSQL]

### Build & Test
[e.g.,
- Build: `npm run build`
- Test all: `npm test`
- Test single file: `npm test -- path/to/test.ts`
- Lint: `npm run lint`
]

### Architecture
[Brief: what lives where, how components connect]

### Conventions
[Project-specific patterns agents need to know]
```

## Step 3: (Claude Code only) Wire up the skill

Claude Code only auto-discovers skills under the consumer project's own `.claude/skills/` directory. Symlink the build-or-fix skill so it loads in the consumer:

```bash
mkdir -p .claude/skills
ln -s ../../feature-crew/.claude/skills/build-or-fix .claude/skills/build-or-fix
```

Verify with `/skill build-or-fix` in a fresh Claude Code session — it should resolve. Skip this step for Copilot-only projects.

## Step 4: Verify it works

Start a new Copilot session and ask the PM to do something. It should:

1. **Propose a track** (Trivial / Standard / Complex) and ask you to confirm.
2. For non-Trivial: write a spec (bullet list for Standard, full doc for Complex), ask for approval.
3. Implement and verify with concrete test output.
4. For Complex: dispatch architect → developers → QA → tech lead. For Standard: implement + one QA pass. For Trivial: just do it + verify.

If your PM session jumps straight to implementing without proposing a track, or writes a spec for a Trivial change "for completeness," the framework integration didn't take. Re-check the file pointers in your `.github/copilot-instructions.md`.

## Customizing for Your Project

### Override agent behavior

If your project needs different agent behavior, create a `feature-crew-overrides/` directory in your project root with modified prompt templates and reference them in your project instructions:

```markdown
Use agent templates from `feature-crew-overrides/` when they exist, falling back to `feature-crew/agents/` otherwise.
```

### Adjust parallelism

If you have shared resources (test DB, limited CI runners), document the constraint:

```markdown
## Constraints
- Max 2 parallel developer agents (shared test database)
- Run `npm run db:reset` between task batches
```
