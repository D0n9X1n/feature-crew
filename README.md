# Feature-Crew

**v5.1.0** · A need-based agent-team framework for **Claude Code**. Describe what you need naturally; Feature-Crew looks up facts, resolves decisions and approaches, then runs code through right-sized TDD and hard gates.

## Install

```bash
./install.sh         # macOS / Linux / Git Bash / WSL
.\install.ps1        # native Windows PowerShell
```

Flags: `--force`, `--dry-run`, `--uninstall`, `--prefix DIR`. Agents install to `~/.claude/agents/fc-*.md`; skills to `~/.claude/skills/fc-*/`.

## Describe the need

Slash-command knowledge is optional. Feature-Crew distinguishes a directly discoverable fact, multi-source evidence, a user-owned decision, an unresolved approach, and adversarial confidence in a chosen consequential decision. It looks up the first and routes the others to the appropriate skill. A subskill resolves one category, returns to the originating flow, and that flow resumes without recursive invocation or repetition of an unchanged gap.

The exact classifier is stated once in `.claude/skills/fc-build-or-fix/SKILL.md`; this README does not duplicate it. Direct commands remain available for `/fc-research`, `/fc-grill-me`, `/fc-brainstorm`, `/fc-build-or-fix`, `/fc-review`, `/fc-second-opinion`, and `/fc-update`.

## Complexity tracks

| Track | Behavior |
|---|---|
| **Just Do It** | Straightforward, bounded, obvious, low-risk, reversible work; PM explores, writes the failing test first, implements, and verifies without approval/spec/role dispatch |
| **Standard** | Coherent feature; approved bullet spec, TDD, one selected QA pass |
| **Complex** | Multi-module or architectural work; approved spec and plan, developers, selected QA, Tech Lead |

File count is only a warning signal. A mirrored low-risk content change across several files can be Just Do It; a one-line runtime/config/API/deploy change cannot. The canonical escalation list and track rules live in `/fc-build-or-fix`.

Just Do It is auto-selected from natural language and does not ask for track approval. If exploration finds ambiguity, coupling, risk, unresolved decisions, or escalation-list scope, the PM stops before production edits and escalates to Standard. Standard and Complex retain user approval gates unless waived; observed verification, spec compliance, and Complex Tech Lead approval remain mandatory.

## Dynamic hard-gate review

All six role agents install without a `model` frontmatter key. Before each model-authored hard-gate review, the dispatcher uses the artifact author's known family/provenance to select an explicit cross-family Agent override and records an audit envelope. Unknown provenance, a family collision, or unavailable selected model leaves the gate unsatisfied; there is no same-family fallback.

The exact selector is canonical in `/fc-build-or-fix`; other docs point there rather than copying it. Standalone `/fc-review` and `/fc-second-opinion` remain useful but do not substitute for pipeline hard gates.

## Hard gates

1. Standard/Complex track approval unless waived
2. Standard/Complex spec approval unless waived
3. Complex plan approval unless waived
4. Observed verification evidence for every done claim
5. Implementation matches the approved spec
6. Tech Lead approval before merging Complex work

## Non-negotiables

- **TDD** — no production code without an observed failing test first; docs use objective acceptance checks first
- **Verify before claiming** — paste output, do not describe it
- **Root cause first** — three failed fixes means rethink
- **No guessing** — look up facts, ask about decisions
- **YAGNI** — build only what was requested
- **Cross-platform parity** — `install.sh` and `install.ps1` ship together

## Framework caps

Feature-Crew changes are Standard-track maximum. Orchestration (`agents/fc-pm.md` plus every `SKILL.md`) stays ≤600 lines; the total stays ≤1500 and under the ratcheted baseline. Run:

```bash
FC_STRICT=1 bash tests/framework_test.sh
```

## Layout

```text
feature-crew/
├── .claude/skills/fc-*/       # seven skills
├── agents/fc-*.md             # six unpinned role prompts
├── .github/workflows/         # test and release pipelines
├── tests/framework_test.sh
├── CLAUDE.md                  # repository instructions
└── install.sh / install.ps1
```

## Releasing

Milestone → issues → PR → merge → tag. CI publishes on tag push; see [CLAUDE.md](CLAUDE.md). The GitHub release body is the changelog; there is no changelog file.

```bash
git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
```

## Updating

Run `/fc-update`, or `git pull origin main && ./install.sh --force`. Before overwriting, the update flow reports installed files you edited. Legacy cleanup and uninstall remove only files whose exact content proves Feature-Crew installed them.

## Credits

`/fc-grill-me` adapts the grilling mechanic from [mattpocock/skills](https://github.com/mattpocock/skills). The evidence-in-message rule is from [obra/superpowers](https://github.com/obra/superpowers). The description contract follows [tech-leads-club/agent-skills](https://github.com/tech-leads-club/agent-skills).

## License

MIT
