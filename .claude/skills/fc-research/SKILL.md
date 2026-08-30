---
name: fc-research
description: Multi-agent research pipeline that fans out across distinct search angles, synthesizes the findings, and validates them against the sources. Use when answering needs evidence from several places — codebase plus web, multiple files, comparing options, surveying prior art. Do NOT use for a single grep or one known file (read it directly), for choosing between approaches (use /fc-brainstorm), or for judging existing work (use /fc-review).
---

# fc-research

You orchestrate; you do not do the searching yourself.

## Phase 1 — search, parallel

Decompose the topic into **distinct angles** first. Three agents on one query is three copies of one answer.

Typical angles:

- **Codebase** — `Explore` agent, specific search terms and file globs.
- **Web/docs** — `general-purpose` agent with WebSearch/WebFetch.
- **Adjacent context** — related systems, prior art, history via git log, changelogs, ADRs.

Dispatch all of them in one message, parallel tool calls. Every prompt ends with:

> Return raw findings only. Each finding: a 1–2 sentence claim and a concrete source — `file:line`, URL, or command output. Do not synthesize, do not recommend. Cap 400 words. If a search returns nothing relevant, say so explicitly rather than padding. Say when you could not verify something instead of guessing.

## Phase 2 — synthesize

One `general-purpose` agent. Paste **all** Phase-1 output inline; never tell it to go read the results.

> Synthesize these findings into a structured answer:
>
> 1. **TL;DR** — 2–3 sentences.
> 2. **Key claims** — numbered, each citing `[S1]`, `[S2]`… from the source list.
> 3. **Open questions** — what the searches did not answer.
> 4. **Sources** — numbered, with `file:line` or URL.
>
> Do not invent claims. Surface disagreements between inputs rather than averaging them. ≤600 words.

## Phase 3 — validate

Dispatch one validator with the dynamic selector in `/fc-build-or-fix`, using the synthesis author's known family/provenance. Paste the synthesis **and** the original Phase-1 material.

> Audit this report against its sources. Mark each numbered claim:
>
> - **SUPPORTED** — the source substantiates it.
> - **PARTIAL** — partly supported; name the gap.
> - **UNSUPPORTED** — not in the sources, or contradicted.
>
> Then one verdict: **PASS** (all supported, trustworthy) or **REVISE** (name the worst claim). Audit only — do not add research of your own.

On REVISE: drop or qualify the flagged claim, or run one targeted search to close the gap. **One revise cycle maximum**, then surface the remaining uncertainty.

## Output

Present the synthesis with each claim annotated `[SUPPORTED]` / `[PARTIAL]` / `[UNSUPPORTED]`, then:

```
Cost: <N> dispatches, ~<M> min wall-clock, models: <list>
```

Report any angle that returned nothing — a silent gap reads as coverage.

## Caps

- **Max 5 dispatches** per invocation. More than that needs the user's OK first.
- **Max 1 revise cycle.**
- Phase 3 uses the canonical selector; if its gate is unsatisfied, say so instead of validating within one family.

## Anti-patterns

- Three search agents on the same query string.
- Skipping Phase 3 because the synthesis looked convincing.
- Synthesizing claims that appear in no source.
- Recursive research-the-research past the cap.
