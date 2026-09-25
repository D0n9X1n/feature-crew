# Gate provenance

Use the canonical selector in [../SKILL.md](../SKILL.md); this reference explains its evidence, not a second selector. A requested alias and a successful dispatch are not proof of which model answered.

## Read the record

Capture the `agentId` from the Agent result and locate `~/.claude/projects/<cwd-slug>/<session-id>/subagents/agent-<agentId>.jsonl`. The main session's own record is `~/.claude/projects/<cwd-slug>/<session-id>.jsonl`; use it for artifacts authored inline. Resolve the actual project slug and session id from this harness, not a guessed directory or another session's record.

Assistant entries carry `.message.model`, the model that answered. Read all assistant entries relevant to the artifact, including resumed turns; retain every distinct model id so a mid-run fallback is not hidden by the final answer. For a subagent dedicated to one artifact, inspect the complete record:

```bash
jq -r 'select(.type=="assistant") | .message.model // "UNKNOWN"' "$record" | sort | uniq -c
```

`agent-<agentId>.meta.json` carries `.model`, the requested alias, not runtime evidence; `.agentType` names the agent type. Do not use either as a substitute for assistant entries. Save the record path and relevant turn boundaries in the audit envelope, alongside requested aliases and all observed ids. An unreadable record means unknown provenance; so does a missing/empty model, no assistant entries, or an incomplete record. This internal, undocumented format may change: fail closed rather than accepting an alias or a reviewer's self-report. `/tasks` and substitution warnings can help locate discrepancies, but do not replace the recorded evidence.

## Map model ids to families

- `claude-sonnet-*` → Sonnet; `claude-opus-*` → Opus; `claude-haiku-*` → Haiku. Version or context suffixes do not create a new family.
- A non-Claude id requires a verified provider or gateway mapping to its family; do not classify it by the alias requested, assume it is Sonnet, or treat every unfamiliar id as a distinct family. Without a reliable mapping, provenance is unknown.
- If several models contributed, retain the complete family set for that artifact. A reviewer cannot satisfy the selector against any author family it shares; every contributing reviewer model must be known and outside that set. Do not cherry-pick the last model after a fallback.
- Keep this session's observed alias-to-family substitutions with the records. Use them for the selector's collision check and alternative override; never generalize an alias mapping across sessions. Record an acceptable substitution even when the review otherwise passes.

## Environment assumptions

- Require Claude Code **≥2.1.251**. Resolution is per-invocation `model` → agent frontmatter `model` → `CLAUDE_CODE_SUBAGENT_MODEL` → main model. Earlier versions let the environment variable override an explicit dispatch. Keep role frontmatter unpinned; pin authoring and review calls instead.
- Require `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` **unset**. When enabled (v2.1.257+), it ignores agent model fields and prevents a per-invocation model override. If these prerequisites cannot be verified, stop the gate; do not change the user's settings to force compliance.
- `availableModels` can substitute an allowed version in the requested family, or an inherited model when that family is unavailable. A successful call does not establish the requested family ran.
- Configured fallback chains may switch models during a run without failing the call. Inspect the full set of recorded assistant models after completion.
- With alias-remapping gateways, `sonnet` or `opus` may resolve to another family or provider. Treat aliases only as requests and apply the selector to the recorded ids; a verified third-family substitution stands and is logged.

Sources: [subagent model resolution and restrictions](https://code.claude.com/docs/en/sub-agents#choose-a-model), [subagent API fallbacks](https://code.claude.com/docs/en/sub-agents#api-errors-in-subagents). Transcript paths and fields above are observed harness internals, not a documented API guarantee.
