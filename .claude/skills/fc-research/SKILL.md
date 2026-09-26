---
name: fc-research
description: Multi-agent research pipeline that fans out across distinct search angles, synthesizes the findings, and validates them against the sources. Use when answering needs evidence from several places — codebase plus web, multiple files, comparing options, surveying prior art. Do NOT use for a single grep or one known file (read it directly), for choosing between approaches (use /fc-brainstorm), for judging existing work (use /fc-review), or for explaining a project's structure with diagrams (use /fc-explain).
---

# fc-research

You orchestrate; you do not do the searching yourself.

**Focused path.** For one bounded question or angle, dispatch one author with an explicit `model` override from the authoring rule in `/fc-build-or-fix` to search and synthesize in the Phase 2 format; record its actual author model for the selector. The author returns raw evidence beside the synthesis: each claim with a concrete source (`file:line`, URL, or command output). One validator chosen by the canonical selector then checks both as in Phase 3: two dispatches. The Worker boundary suffix, the five-dispatch cap, and one revise cycle still apply. Broader questions keep the full pipeline below.

## Worker boundary

Append this suffix to every worker prompt in Phases 1, 2 and 3, including any re-dispatch:

> Perform the assigned work yourself. Do not call `Agent`, `Skill`, `Workflow`, or delegate any part of the task. Return only the requested output. The entire invocation has a five-dispatch budget, including descendants at any depth; return an unresolved gap to the orchestrator rather than expanding it.

## Phase 1 — search, parallel

Decompose the topic into **distinct angles** first. Three agents on one query is three copies of one answer. Prefer `Explore` for direct search; it has no `Agent` tool. Where a search needs other tools, use a profile excluding `Agent` when available; the no-delegation suffix remains mandatory for every worker.

Typical angles:

- **Codebase** — `Explore` agent, specific search terms and file globs.
- **Web/docs** — prefer `Explore` when it exposes WebSearch/WebFetch; otherwise a search-capable profile as above.
- **Adjacent context** — related systems, prior art, history via git log, changelogs, ADRs.

Reserve one dispatch each for synthesis and validation before search; the default budget leaves at most three search workers. Dispatch them in one message, parallel tool calls. Give each this prompt, followed by the mandatory Worker boundary suffix:

> Return raw findings only. Each finding: a 1–2 sentence claim and a concrete source — `file:line`, URL, or command output. Do not synthesize, do not recommend. If a search returns nothing relevant, say so explicitly rather than padding. Say when you could not verify something instead of guessing.

## Phase 2 — synthesize

One `general-purpose` agent with an explicit `model` override from the authoring rule in `/fc-build-or-fix`; record its actual author model for the selector. Paste **all** Phase-1 output inline; never tell it to go read the results. Append the Worker boundary suffix to this prompt:

> Synthesize these findings into a structured answer:
>
> 1. **TL;DR** — 2–3 sentences.
> 2. **Key claims** — numbered, each citing `[S1]`, `[S2]`… from the source list.
> 3. **Open questions** — what the searches did not answer.
> 4. **Sources** — numbered, with `file:line` or URL.
>
> Do not invent claims. Surface disagreements between inputs rather than averaging them. Keep it concise.

## Phase 3 — validate

Dispatch one validator with the dynamic selector in `/fc-build-or-fix`, using the synthesis author's recorded model/family. Verify the recorded validator model before accepting the result. Paste the synthesis **and** the original Phase-1 material; append the Worker boundary suffix to this prompt:

> Audit this report against its sources. Mark each numbered claim:
>
> - **SUPPORTED** — the source substantiates it.
> - **PARTIAL** — partly supported; name the gap.
> - **UNSUPPORTED** — not in the sources, or contradicted.
>
> Then one verdict: **PASS** (all supported, trustworthy) or **REVISE** (name the worst claim). Audit only — do not add research of your own.

On REVISE: drop or qualify the flagged claim, or dispatch one targeted search only within the remaining budget (otherwise pause for approval). All re-dispatches use the Worker boundary suffix. **One revise cycle maximum**, then surface the remaining uncertainty.

## Output

Present the synthesis with each claim annotated `[SUPPORTED]` / `[PARTIAL]` / `[UNSUPPORTED]`, then:

```
Cost: <N> dispatches, ~<M> min wall-clock, models: <list>
```

Report any angle that returned nothing — a silent gap reads as coverage.

## Caps

- **Max 5 dispatches** per invocation, counting descendants at any depth, not just top-level calls. Track the total across searches, synthesis, validation and re-dispatches; pause for user approval before any expansion beyond five. If delegation occurs despite the worker rule, count it too and stop further expansion.
- **Max 1 revise cycle.**
- Phase 3 uses the canonical selector; if its gate is unsatisfied, say so instead of validating within one family.

## Anti-patterns

- Three search agents on the same query string.
- Skipping Phase 3 because the synthesis looked convincing.
- Synthesizing claims that appear in no source.
- Recursive research-the-research past the cap.
