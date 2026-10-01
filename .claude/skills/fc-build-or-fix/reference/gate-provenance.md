# Gate provenance

Use the canonical selector in [../SKILL.md](../SKILL.md); this reference explains its evidence, not a second selector. A requested alias and a successful dispatch are not proof of which model answered.

## Read the record

Capture the `agentId` from the Agent result and locate `~/.claude/projects/<cwd-slug>/<session-id>/subagents/agent-<agentId>.jsonl`. The main session's own record is `~/.claude/projects/<cwd-slug>/<session-id>.jsonl`; use it for artifacts authored inline. Resolve the actual project slug and session id from this harness, not a guessed directory or another session's record. A harness without this record needs its own per-dispatch record of the answering model; without one, provenance is unknown.

Assistant entries carry `.message.model`, the model that answered. Select the authoring or review turns for the artifact, including resumed turns; retain every distinct model id per role so a fallback is not hidden by the final answer. Only `Agent` or `Workflow` calls made to produce or change the artifact contribute to its author set. Gate reviews, validators and refuters, and their children, stay in reviewer sets when they only report findings, even if their calls sit in the main-session record; using their findings in a later fix does not make them authors. A call that changes the artifact is an authoring contributor, whoever made it; if it also reviewed, keep it in both sets. Read each relevant authoring or review child record recursively, including forked `Skill` runs. A child record that cannot be found or read makes provenance unknown and the gate unsatisfied. A `Skill` call without a fork stays in the same record. For a record dedicated to one artifact and role, inspect its complete record and relevant child records; for a mixed main-session record, select the role's relevant turns before applying this query:

```bash
jq -r 'select(.type=="assistant") | .message.model // "UNKNOWN"' "$record" | sort | uniq -c
```

Match `.toolUseId` in child `agent-<agentId>.meta.json` to the spawning `Agent` tool_use `.id` in the parent record, then read the matching `agent-<agentId>.jsonl`. List candidate call ids with `jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and (.name=="Agent" or .name=="Workflow")) | .id' "$record"`; classify their tasks before assigning child models to a set. This child-record link has been observed for depth-1 `Agent` calls only; `Workflow` children and depth 2 or greater have not been observed. If this link cannot locate a contributor record, provenance is unknown and the gate unsatisfied.

`agent-<agentId>.meta.json` carries `.model`, the requested alias, not runtime evidence; `.agentType` names the agent type. Do not use either as a substitute for assistant entries. Save the record path, role, spawning call id and relevant turn boundaries in the audit envelope, alongside requested aliases and all observed ids. An unreadable record means unknown provenance; so does a missing/empty model, no assistant entries, or an incomplete record. This internal, undocumented format may change: fail closed rather than accepting an alias or a reviewer's self-report. `/tasks` and substitution warnings can help locate discrepancies, but do not replace the recorded evidence.

## Read the model picker

The model picker (`/model`) is the only list of selectable models. Read `modelPicker` from the Claude Code settings that apply to the session. If its `options` list at least two models, those are the candidates: pick the review pair at random from them, two entries in different mapped families, and record the draw in order. Otherwise the candidates are the default `opus`, `sonnet` pair. Unreadable settings leave the gate unsatisfied.

An entry's model is its `model` value. An alias value such as `opus[1m]` runs that alias's `ANTHROPIC_DEFAULT_<ALIAS>_MODEL` setting when one is set, otherwise the alias's own family; map the result with the family table below. Request an entry through the alias that reaches it: its own alias, or the alias whose `ANTHROPIC_DEFAULT_<ALIAS>_MODEL` names its full id, trying `opus`, `sonnet`, then `haiku`. Several aliases reaching one entry are still one model. For example, entries `opus[1m]` and `gpt-6-astra[1m]`, with `sonnet` set to `gpt-6-astra[1m]`, give Opus and GPT: an Opus author is reviewed through `sonnet`, a GPT author through `opus`.

Never look behind an entry into a relay or gateway; the picker, these settings, and the session record are the only evidence.

## Map model ids to families

- Opus, Sonnet, Haiku, and GPT are four separate families; any two are cross-family. `claude-sonnet-*` → Sonnet; `claude-opus-*` → Opus; `claude-haiku-*` → Haiku. Version or context suffixes do not create a new family.
- A model whose family is unmapped never qualifies for the review pair; pick only from mapped families.
- A non-Claude id maps by its provider/vendor model-line prefix to a family: `gpt-*` → GPT. Every id in one vendor line is one family, regardless of version or suffix; do not infer a family from the requested alias. For a recorded non-Claude id, provenance is unknown only when its vendor cannot be identified.
- Keep the author family set separate from each reviewer's set. Authoring children join the author family set at every depth, according to their task rather than the parent record. Children doing review join the set for that reviewer at every depth, not the author set unless they changed the artifact. Every model in a reviewer set must be known and outside the author family set. Do not cherry-pick the last model after a fallback or omit a child's model because delegation was forbidden.
- Keep this session's observed alias-to-family substitutions with the records. Use them for the selector's collision check and alternative override; never generalize an alias mapping across sessions. Record an acceptable substitution even when the review otherwise passes.

## Environment assumptions

- Require Claude Code **≥2.1.251**. Resolution is per-invocation `model` → agent frontmatter `model` → `CLAUDE_CODE_SUBAGENT_MODEL` → main model. Earlier versions let the environment variable override an explicit dispatch. Keep role and skill frontmatter unpinned; pin authoring and review calls instead.
- Require `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` **unset**. When enabled (v2.1.257+), it ignores agent model fields and prevents a per-invocation model override. If these prerequisites cannot be verified, stop the gate; do not change the user's settings to force compliance.
- `availableModels` can substitute an allowed version in the requested family, or an inherited model when that family is unavailable. A successful call does not establish the requested family ran.
- Configured fallback chains may switch models during a run without failing the call. Inspect the full set of recorded assistant models after completion.
- With alias-remapping gateways, `sonnet` or `opus` may resolve to another family or provider. Treat aliases only as requests and apply the selector to the recorded ids; a verified third-family substitution stands and is logged.

Sources: [subagent model resolution and restrictions](https://code.claude.com/docs/en/sub-agents#choose-a-model), [subagent API fallbacks](https://code.claude.com/docs/en/sub-agents#api-errors-in-subagents). Transcript paths and fields above are observed harness internals, not a documented API guarantee.
