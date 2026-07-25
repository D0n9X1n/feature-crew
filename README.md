# Feature-Crew

**v5.0.1** · An agent-team framework for **Claude Code**. Seven skills, each for a different thing you're missing, plus role agents that do the work under hard gates and cross-family review.

## Install

```bash
./install.sh         # macOS / Linux / Git Bash / WSL
.\install.ps1        # native Windows PowerShell
```

Flags: `--force`, `--dry-run`, `--uninstall`, `--prefix DIR`.

Agents install to `~/.claude/agents/fc-*.md`, skills to `~/.claude/skills/fc-*/`. Both work in every project afterwards.

## The seven skills

| Skill | Use when you lack | What it does |
|---|---|---|
| `/fc-research` | **facts** | Parallel search across distinct angles → synthesize → validate against sources |
| `/fc-grill-me` | **decisions** | Interviews you one question at a time, each with a recommended answer |
| `/fc-brainstorm` | **an approach** | Three subagents with opposing stances → diversity check → one opinionated recommendation |
| `/fc-build-or-fix` | **the code** | Right-sized track (Trivial / Standard / Complex) with gates and TDD |
| `/fc-review` | **confidence in an artifact** | Reviews a diff, PR, spec, or plan. Read-only by construction |
| `/fc-second-opinion` | **confidence in a decision** | Adversarial refuters, majority verdict |
| `/fc-update` | **the current version** | Pulls, warns about files you edited, reinstalls |

Each skill's description says what it does, when to use it, and when to use a sibling instead — so seven skills don't fight over the same request. Skills offer each other; they never chain automatically.

## Tracks

```
Trivial   →  do it + verify + commit                          (1 file, no design choice)
Standard  →  bullet spec + TDD + one QA pass                  (1–5 files, small feature)
Complex   →  spec → architect → devs → QA → tech lead         (multi-module, new architecture)
```

The PM proposes a track on every request; you can override. Right-sizing is the speed lever — a typo fix does not pay for the Complex track's ceremony, because that track lives in a reference file loaded only when it's used.

## The team

| Role | Used in | Model |
|---|---|---|
| **PM** | all tracks | session default |
| **Architect** | Complex | session default |
| **Developer** | Standard, Complex | session default |
| **QA spec / QA code** | Standard, Complex | `sonnet` |
| **Tech Lead** | Complex | `sonnet` |

Operate roles and review roles run on different model families. The installer writes `model:` into review agents' frontmatter, so cross-family review is structural rather than something the PM has to remember. If a second family isn't reachable, run fewer reviewers rather than two from the same family.

## Hard gates

1. User approves the track
2. User approves the spec (Standard, Complex)
3. User approves the plan (Complex)
4. Verification evidence for every "done" claim — command output in the message making the claim
5. Implementation matches the approved spec
6. Tech Lead approval before merging Complex work

Everything else is advisory: reported, then judged.

## Non-negotiables

- **TDD** — no production code without a failing test first
- **Verify before claiming** — paste the output, don't describe it
- **Root cause first** — 3 failed fixes means rethink
- **No guessing** — look facts up, ask about decisions
- **YAGNI** — don't build what wasn't requested
- **Cross-platform parity** — `install.sh` and `install.ps1` change in the same commit

## Framework caps

Changes to Feature-Crew itself are Standard-track maximum. Orchestration (`agents/fc-pm.md` + every `SKILL.md`) stays ≤600 lines; the total stays ≤1500. Enforced by:

```bash
bash tests/framework_test.sh
```

The framework must not become heavier than the work it serves.

## Layout

```
feature-crew/
├── .claude/skills/
│   ├── fc-research/        fc-grill-me/       fc-brainstorm/
│   ├── fc-review/          fc-second-opinion/
│   └── fc-build-or-fix/
│       ├── SKILL.md        ← hot path, loaded every build request
│       └── reference/      ← Complex track + meta-work cap, loaded on demand
├── agents/fc-*.md          ← six role prompts
├── .github/workflows/      ← test on PR, release on tag
├── docs/specs|plans|reviews/
├── tests/framework_test.sh
├── CLAUDE.md               ← agent instructions (no AGENTS.md; Claude Code only)
└── install.sh / install.ps1
```

## Releasing

Milestone → issues → PR → merge → tag. CI publishes on tag push; see the release process in [CLAUDE.md](CLAUDE.md).

```bash
git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
```

**The GitHub release body is the changelog.** There is no changelog file — one record, generated per tag from the commits that actually shipped, so it cannot drift from the tag it describes. See [releases](https://github.com/D0n9X1n/feature-crew/releases).

## Updating

```bash
/fc-update
```

Pulls, tells you which installed files you have edited **before** overwriting them, reports skills that are installed but no longer shipped, and reinstalls. Or by hand:

```bash
git pull origin main && ./install.sh --force
```

The installer removes the legacy unprefixed skill directories so `/build-or-fix` doesn't linger beside `/fc-build-or-fix` — but only ones whose content hash matches something this project actually published. Uninstall is the same: it removes only files byte-identical to what it installed, so anything you edited or added alongside is left alone.

## Credits

`/fc-grill-me` adapts the grilling mechanic from [mattpocock/skills](https://github.com/mattpocock/skills). The evidence-in-message rule is from [obra/superpowers](https://github.com/obra/superpowers). The description contract — what it does, when to use it, when not to — follows [tech-leads-club/agent-skills](https://github.com/tech-leads-club/agent-skills).

## License

MIT
