# Integrating M-Team Into a Project

## Step 1: Add the submodule

```bash
cd your-project
git submodule add <m-team-repo-url> m-team
git commit -m "chore: add m-team agent framework"
```

## Step 2: Create your project's Copilot instructions

Create `.github/copilot-instructions.md` in your project root with the content below. Replace the placeholder sections with your project's specifics.

```markdown
# [Your Project Name]

This project uses the **m-team** agent framework for all development.

## Agent Framework

Read and follow `m-team/.github/copilot-instructions.md` for all development workflows.

When asked to build, fix, or change anything:
1. Act as the PM — discuss requirements, produce a spec
2. Dispatch agents from `m-team/agents/` following `m-team/workflow/pipeline.md`
3. Run all independent work in parallel using background mode

Agent templates: `m-team/agents/`
Pipeline: `m-team/workflow/pipeline.md`

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
[Brief description of your project's structure — what lives where, how components connect]

### Conventions
[Any project-specific patterns that agents need to know]
```

## Step 3: Verify it works

Start a new Copilot session in your project and ask it to build something. It should:
1. Ask you clarifying questions (PM role)
2. Produce a spec and ask for approval
3. Dispatch an architect to create a plan
4. Execute tasks in parallel with developer + QA subagents
5. Run a final Tech Lead review

## Customizing for Your Project

### Override agent behavior

If your project needs different agent behavior, create a `m-team-overrides/` directory in your project root with modified prompt templates. Reference them in your `.github/copilot-instructions.md`:

```markdown
Use agent templates from `m-team-overrides/` when they exist, falling back to `m-team/agents/` otherwise.
```

### Skip phases for small changes

For trivial changes (typo fixes, config tweaks), tell the PM:
> "Skip the full pipeline, just make this change directly."

The PM should comply — user instructions always take precedence.

### Adjust parallelism

If your project has constraints (shared test database, limited CI runners), note it in your project instructions:

```markdown
## Constraints
- Max 2 parallel developer agents (shared test database)
- Run `npm run db:reset` between task batches
```
