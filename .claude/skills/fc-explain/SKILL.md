---
name: fc-explain
description: Explains an existing project, subsystem, or flow with readable Mermaid diagrams tied to code evidence — maps the components, draws an overview plus one key flow, and cites the files behind every node. Use when someone asks how a project, subsystem, or flow works, wants orientation in an unfamiliar codebase, or asks for an architecture or flow diagram of existing code. Do NOT use for changing code (use /fc-build-or-fix), diagnosing a failure (use /fc-debug), or answering questions that need evidence beyond the code (use /fc-research).
---

# fc-explain

## Scope and map

- Run in the main conversation. Infer the scope (the whole project, a subsystem, or one flow) and ask only when it is genuinely ambiguous.
- Build the component map with the bottom-up mapping contract in [design-check.md](../fc-build-or-fix/reference/design-check.md): read small scopes directly; for large ones use at most three read-only `Explore` helpers, each helper prompt ending with the Worker boundary suffix below. Keep the map for follow-ups and refresh its evidence before answering them.

> Perform the assigned work yourself. Do not call `Agent`, `Skill`, `Workflow`, or delegate any part of the task.

## Diagrams

- Default to one overview (containers or building blocks) plus one evidenced key flow; add a context, component drill-down, or deployment view only when useful or requested.
- Use fenced Mermaid only: `flowchart` for structure and `sequenceDiagram` for interactions. No experimental C4 or `architecture-beta`, and never ASCII art.
- Keep each diagram professional and readable: a title, scope, and legend; one abstraction level; 5–12 nodes, split above 15; short responsibility labels; labeled directional arrows; consistent shapes; minimal styling and never color-only meaning; citations beside nodes, not inside them.

## Verify

- Trace every node and edge to evidence. Parse or render only with an already-installed renderer (never install one or upload source), with at most two fix attempts; otherwise state "not render-checked".

## Answer

- After each diagram give the takeaway, a short walkthrough, and a component table with file links. Separate verified facts, inferences, and unknowns, and end with where to start reading.
- Answer in chat; write a repository file or publish a page only on request.
