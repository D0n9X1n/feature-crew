---
name: research
description: Multi-agent research pipeline (search → synthesize → validate). TRIGGER when the user asks to "research", "investigate", "compare", "find out", "look into", or any open-ended question that needs evidence from multiple sources. SKIP for single-fact lookups, simple file reads, or status checks — those use Read/Grep/Explore directly.
---

# research — Multi-Agent Search / Synthesize / Validate

Invoke as `/research <topic>` (or it triggers automatically on research-style asks). The main session is the **PM**: you do not do the research yourself, you orchestrate three phases of subagents and present a validated report.

## When to use

Use this skill when the answer requires **synthesis across multiple sources** — codebase + web, several files, several docs, comparing options, surveying state-of-the-art. The cost (3–5 subagent dispatches) is only worth it when single-shot exploration would miss something.

**Skip** for: a single grep, reading one known file, checking one fact, status questions, or anything where you already know exactly where to look.

## Hard rule — cross-family validation

The **Validate** phase MUST be a different model family from the Synthesize phase. Same-family validation is theater. Preferred pair: `claude-opus-4.7-xhigh` ⇆ `gpt-5.5`. Same-vendor cross-family (e.g. `claude-opus` ⇆ `claude-sonnet`) is a **degraded fallback** — note `audit-pair: degraded` in the final report. This mirrors the `build-or-fix` cross-audit rule.

## Pipeline

### Phase 1 — Search (parallel fan-out, 2–3 agents)

Decompose the topic into **distinct angles** before dispatching. Don't fan out 3 agents on the same query — that wastes budget. Typical angles:

- **Codebase angle** — `Explore` agent with specific search terms / file globs.
- **Web/docs angle** — `general-purpose` agent with WebSearch/WebFetch authority.
- **Adjacent-context angle** — related systems, prior art, history (git log, changelogs, ADRs).

Dispatch all search agents in **one message, parallel tool calls**. Each agent's prompt MUST include:

> Return raw findings only. For each finding: a 1–2 sentence claim and a concrete source (`file:line`, URL, or command output). Do not synthesize, do not recommend. Cap your report at 400 words. If a search returns nothing relevant, say so explicitly — do not pad.

### Phase 2 — Synthesize (1 agent)

Dispatch one `general-purpose` agent. Inline-paste **all** Phase-1 outputs (do not tell it to "read the search results"). Prompt:

> You are synthesizing prior search findings into a structured answer. Output format:
>
> 1. **TL;DR** — 2–3 sentences.
> 2. **Key claims** — numbered list. Each claim cites at least one source from the inputs by `[S1]`, `[S2]`, etc., where the source list is at the bottom.
> 3. **Open questions** — what the searches did NOT answer.
> 4. **Sources** — numbered, each with the original `file:line` or URL.
>
> Do not invent claims. If inputs disagree, surface the disagreement. ≤ 600 words.

### Phase 3 — Validate (1 agent, cross-family)

Dispatch one validator from a **different model family** than the synthesizer. Inline-paste the synthesis report AND the original Phase-1 source material. Prompt:

> You are auditing a research report against its source material. For each numbered claim, mark one of:
>
> - **SUPPORTED** — source clearly substantiates it.
> - **PARTIAL** — partially supported; note the gap.
> - **UNSUPPORTED** — claim not present in sources, or contradicted.
>
> Then give a single one-clue verdict:
>
> - **PASS** — all claims SUPPORTED, report is trustworthy.
> - **REVISE** — at least one PARTIAL/UNSUPPORTED claim; name the worst one.
>
> Do not write your own research; only audit.

If verdict is REVISE: either drop/qualify the flagged claim, or run one targeted Phase-1 search to fill the gap (max **one** revise cycle — then surface the uncertainty to the user).

## Output to user

Present the synthesis report to the user with:

- Each claim annotated `[SUPPORTED]` / `[PARTIAL]` / `[UNSUPPORTED]` from the validator.
- A one-line cost telemetry footer:
  ```
  Cost: <N> subagent dispatches, ~<M> minutes wall-clock, models: <list>, audit-pair: <preferred|degraded>
  ```

## Caps

- **Max 5 subagent dispatches** per `/research` invocation by default. If the topic genuinely needs more (e.g., 4 distinct search angles), confirm with the user first.
- **Max 1 revise cycle.** Past that, return what you have plus the open questions — don't loop.
- **No same-model audit.** Hard rule.

## Anti-patterns

- Fanning out 3 search agents on the same query string (no diversity).
- Skipping Validate because "the synthesis looked good."
- Same-family validation without flagging it as degraded.
- Letting the synthesizer pull in claims that weren't in any source ("hallucinated synthesis").
- Recursive research-the-research loops past the cap.
