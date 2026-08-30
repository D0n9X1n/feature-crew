---
name: fc-grill-me
description: A relentless interview that pins down every user-owned requirement or decision before work starts, then returns the result to its originating flow. Use when the user says "grill me" or a flow needs the user's choices surfaced one at a time. Do NOT use for gathering facts (look up one fact or use /fc-research), generating solution approaches (use /fc-brainstorm), or judging existing work (use /fc-review or /fc-second-opinion).
---

# fc-grill-me

Interview the user relentlessly about every aspect of this until you reach a shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one by one.

Four rules:

1. **One question at a time.** Wait for the answer before asking the next. Several questions at once is bewildering.
2. **Every question ships with your recommended answer** and a one-line reason. The user confirms or overrides — they should never have to compose an answer from scratch.
3. **Facts you look up; decisions you ask.** If something is discoverable in the environment — filesystem, git history, dependencies, test commands, existing patterns — go find it. Never ask the user something you could have read. The decisions are theirs.
4. **Do not act until the user confirms shared understanding.** No code, no files, no implementation. This skill only produces agreement.

Order questions by dependency: resolve what constrains other choices first. When a decision is reversible, say so — it deserves less deliberation than a one-way door.

Stop when the user confirms, or when the remaining questions are ones only implementation can answer. Say which it is.

## Output

When grilling ends, restate the shared understanding as a numbered list of settled decisions, each with its rationale in a few words. If another flow invoked this skill, return that result to the originator; do not invoke another skill yourself. If the user invoked it directly, offer the appropriate next flow:

- **Build it** → `/fc-build-or-fix`
- **Explore alternatives first** → `/fc-brainstorm`
- **Pressure-test the conclusion** → `/fc-second-opinion`

Credit: mechanic adapted from `mattpocock/skills` (`grill-me` → `grilling`).
