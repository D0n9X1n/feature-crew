# Feature-Crew Development Pipeline

This document defines the full orchestration flow for the agent team. The **main Copilot session** acts as the **Product Manager (PM)** and orchestrates all other agents.

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          PM (Main Session)                       │
│  Discusses requirements with user, produces spec, orchestrates   │
└──────────────────────────────┬───────────────────────────────────┘
                               │ approved spec
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Architect (Subagent)                          │
│  Produces technical design + implementation plan                 │
└──────────────────────────────┬───────────────────────────────────┘
                               │ plan (user approves)
                               ▼
                    ┌──── Per Task Loop ────┐
                    │                       │
                    ▼                       │
┌──────────────────────────────┐           │
│   Developer (Subagent)       │           │
│   Implements task with TDD   │           │
└──────────────┬───────────────┘           │
               ▼                           │
┌──────────────────────────────┐           │
│   QA: Spec Reviewer          │           │
│   Code matches spec?         │──── NO ──→ Developer fixes
└──────────────┬───────────────┘           │
               │ YES                       │
               ▼                           │
┌──────────────────────────────┐           │
│   QA: Code Reviewer          │           │
│   Code well-built?           │──── NO ──→ Developer fixes
└──────────────┬───────────────┘           │
               │ YES                       │
               ▼                           │
         Mark task done ───────────────────┘
                    │
                    ▼ (all tasks done)
┌─────────────────────────────────────────────────────────────────┐
│                   Tech Lead (Subagent)                            │
│  Final integration review of all changes                         │
└──────────────────────────────┬───────────────────────────────────┘
                               │ approved
                               ▼
                         Merge / PR / Keep
```

## Phase 1: Brainstorming & Requirements (PM — follow `agents/pm.md`)

The main session acts as Product Manager. **Read `agents/pm.md` for the full process.**

1. **Understand context** — Check project state, recent commits, existing docs
2. **Assess scope** — Flag if request needs decomposition into sub-projects
3. **Ask clarifying questions** — One at a time, prefer multiple choice
4. **Explore approaches** — Propose 2–3 with trade-offs. Testability is the tiebreaker.
5. **Present design** — In sections scaled to complexity, get user approval per section
6. **Define test strategy** — For every feature. Untestable features get redesigned.
7. **Write spec** — Save to `docs/specs/YYYY-MM-DD-<topic>-design.md`, commit
8. **Self-review spec** — Placeholders, contradictions, ambiguity, testability
9. **User reviews spec** — Wait for explicit approval before proceeding

**Gate:** User approves the written spec.

## Phase 2: Architecture (Architect Subagent)

Dispatch a `general-purpose` subagent with:
- Prompt template: `agents/architect.md`
- Input: full spec text + project structure + tech constraints

The architect produces:
- Technical design (file structure, component boundaries, data flow)
- Implementation plan with bite-sized tasks

**Gate:** User approves the plan.

```
Dispatch:
  agent_type: general-purpose
  name: architect
  prompt: |
    [Contents of agents/architect.md]

    ## Spec

    [Full spec text]

    ## Current Project Structure

    [Output of tree/ls]

    ## Tech Constraints

    [Any constraints from user]
```

## Phase 3: Implementation (Developer Subagents, PARALLEL)

**Speed is a priority. Maximize parallelism.**

### Step 1: Dependency Analysis

Before dispatching, analyze the plan and group tasks:

```
For each task, identify:
  - Files it creates or modifies
  - Files it reads/depends on
  - Tasks that must complete before it can start

Group into parallel batches:
  Batch 1: [tasks with no dependencies — dispatch ALL simultaneously]
  Batch 2: [tasks that depend only on Batch 1 — dispatch ALL when Batch 1 completes]
  ...
```

Tasks that touch **different files** are independent — run them in parallel. Tasks that share files or have data dependencies must be sequenced.

### Step 2: Parallel Dispatch

Dispatch ALL independent tasks in the same batch simultaneously:

```
# Dispatch all Batch 1 tasks at once
Dispatch (background):
  agent_type: general-purpose
  name: dev-task-1
  prompt: [agents/developer.md + task 1 text + context]

Dispatch (background):
  agent_type: general-purpose
  name: dev-task-2
  prompt: [agents/developer.md + task 2 text + context]

Dispatch (background):
  agent_type: general-purpose
  name: dev-task-3
  prompt: [agents/developer.md + task 3 text + context]

# All three run concurrently — wait for completion notifications
```

**Model selection:**
- Simple/mechanical tasks (1–2 files, clear spec) → `claude-haiku-4.5`
- Multi-file integration or judgment calls → default model
- Complex architecture decisions → `claude-sonnet-4`

### Step 3: Handle Results

As each developer reports back:
- **DONE** → immediately dispatch QA (don't wait for other devs)
- **DONE_WITH_CONCERNS** → assess concerns, then QA
- **NEEDS_CONTEXT** → provide context, re-dispatch (don't block other tasks)
- **BLOCKED** → escalate, continue with other tasks

## Phase 4: QA (Two-Stage Review, PARALLEL per task)

QA reviews run **as soon as each developer completes** — don't wait for all developers to finish.

### Parallel QA Strategy

```
Developer Task 1 completes → immediately dispatch QA-Spec-1
Developer Task 3 completes → immediately dispatch QA-Spec-3
  (Task 2 still running — that's fine, don't wait)
QA-Spec-1 passes → immediately dispatch QA-Code-1
Developer Task 2 completes → immediately dispatch QA-Spec-2
QA-Spec-3 passes → immediately dispatch QA-Code-3
...
```

**Rule:** QA reviews for different tasks run in parallel. Only the two stages within ONE task are sequential (spec before code quality).

### Stage 1: Spec Compliance

Dispatch `general-purpose` subagent (background):

```
Dispatch (background):
  agent_type: general-purpose
  name: qa-spec-N
  prompt: |
    [Contents of agents/qa-spec-reviewer.md]

    ## What Was Requested
    [Full task text from plan]

    ## What Developer Claims They Built
    [Developer's report]
```

If ❌ FAIL → Developer fixes → re-review
If ✅ PASS → immediately dispatch Stage 2

### Stage 2: Code Quality

Dispatch `code-review` subagent (background):

```
Dispatch (background):
  agent_type: code-review
  name: qa-code-N
  prompt: |
    [Contents of agents/qa-code-reviewer.md]

    Review the changes for Task N.
    What was implemented: [summary]
    Requirements: [task text]
```

If NEEDS_CHANGES → Developer fixes → re-review
If APPROVED → task complete

## Phase 5: Final Review (Tech Lead Subagent)

After ALL tasks complete, dispatch a `general-purpose` subagent:

```
Dispatch:
  agent_type: general-purpose
  name: tech-lead
  prompt: |
    [Contents of agents/tech-lead.md]

    ## Original Spec

    [Full spec text]

    ## Implementation Plan

    [Full plan text]

    ## Changes

    The full diff is between [base-branch] and [feature-branch].
    Run: git diff [base]...[head]

    ## Task Review Summaries

    [Summary of each task's spec + code review results]
```

If ❌ NEEDS CHANGES → Fix and re-review
If ✅ APPROVED → Proceed to finish

## Phase 6: Finish

Present options to user:
1. Merge back to base branch locally
2. Push and create a Pull Request
3. Keep the branch as-is
4. Discard the work

Execute chosen option. Clean up worktree if applicable.

## Parallelism Rules

1. **Independent tasks run simultaneously** — If tasks don't share files, dispatch them all at once
2. **QA starts immediately** — Don't wait for all devs to finish; review each as it completes
3. **Fix loops don't block others** — If Task 2 needs fixes, Tasks 1 and 3 keep moving
4. **Only Tech Lead is sequential** — It needs all tasks done before it can review the whole
5. **Background mode always** — Dispatch all subagents in background mode, handle results as notifications arrive
6. **Batch next wave early** — While reviewing Batch 1 results, prepare Batch 2 prompts

## Error Handling

**Developer blocked:** Provide more context → re-dispatch → don't block other tasks → if still blocked, escalate to user
**QA finds issues:** Developer fixes → re-review → repeat until pass (max 3 cycles, then escalate) → other tasks continue
**Tech Lead rejects:** Assess severity → fix specific issues → re-review → if architectural, escalate to user
**3+ fix attempts failed on same issue:** Stop. Question the approach with the user. Don't keep trying.
