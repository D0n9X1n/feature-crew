# Usage

[简体中文](Usage-zh-CN)

How to install, run, and update Feature-Crew. Back to [Home](Home).

## Install

Feature-Crew is one plugin for Claude Code and GitHub Copilot CLI. Install it in either or both:

```bash
claude plugin marketplace add D0n9X1n/feature-crew
claude plugin install feature-crew@feature-crew
copilot plugin marketplace add D0n9X1n/feature-crew
copilot plugin install feature-crew@feature-crew
```

Or run `./install.sh` (macOS / Linux / Git Bash / WSL) or `.\install.ps1` (native Windows PowerShell) from a clone: it installs or updates the plugin in each CLI on PATH, then removes an old script install from `~/.claude`. Old `fc-*` agents and skills are removed even when edited, because they would run instead of the plugin's; older files are removed only when their hash proves Feature-Crew wrote them. Nothing is removed through a link, whether the prefix, `agents`, or `skills` is linked; old `fc-*` entries there are reported. An old file or folder it cannot read or remove stops the run with exit 2 before anything changes. If the system still refuses a removal or a read later (an immutable file, a lock, a change during the run), the run lists what is left and exits 1; fix those and run it again. In Claude Code it manages only the user-scope install, so a project's own Feature-Crew settings stay. Flags: `--dry-run`, `--check`, `--uninstall`, `--prefix DIR`, `--source SRC`; `install.ps1` also accepts `-DryRun`, `-Check`, `-Uninstall`, `-Prefix DIR`, `-Source SRC`.

Skills keep their names, such as `/fc-build-or-fix`. Agents register as `feature-crew:fc-*`, such as `feature-crew:fc-qa-code`.

**Known limits.**
- An old `fc-*` skill folder is removed whole; a file inside it that becomes unreadable during the run goes with it.
- Native Windows cannot check permissions upfront, so a file it cannot remove is found only during the run (exit 1).
- Claude Code keeps one source per marketplace name: if a project declares `feature-crew` from another source, switching your install's source moves the project's too, and `--uninstall` drops the project's install while its settings stay.
- A Copilot marketplace added from a Git URL is matched by the `URL:` label Copilot prints; that path is tested only with stub CLIs.

## Describe the need

Slash-command knowledge is optional. Feature-Crew distinguishes a directly discoverable fact, multi-source evidence, a user-owned decision, an unresolved approach, adversarial confidence in a chosen consequential decision, and an unexplained failure. It looks up the first and routes the others to the appropriate skill. A subskill resolves one category, returns to the originating flow, and that flow resumes without recursive invocation or repetition of an unchanged gap.

The exact classifier is stated once in `skills/fc-build-or-fix/SKILL.md`; this page does not duplicate it. Direct commands remain available for `/fc-research`, `/fc-grill-me`, `/fc-brainstorm`, `/fc-debug`, `/fc-explain`, `/fc-build-or-fix`, `/fc-ship`, `/fc-clean`, `/fc-review`, `/fc-second-opinion`, and `/fc-update`.

## Think first

Before building a Standard or Complex change, Feature-Crew researches the problem with `/fc-research`, compares three approaches with `/fc-brainstorm`, and asks you with `/fc-grill-me`: at least one round, the open decisions or one question confirming the plan. Just Do It changes (obvious, low-risk, reversible) skip this. To skip it for one change, say so explicitly, for example "skip the research" or "no questions, just build it"; the agent names what it skipped. "Go for it" approves a plan but skips nothing. Tests, the cross-family review, and the spec check always run.

In a Claude Code `/goal` or Copilot CLI autopilot session, or after you say "you handle all", the agent asks you nothing until that goal's cleanup and final report are done. Research and brainstorm still run. It answers its own questions and waives your approvals with its recommendation, records each as its own call, and reports them at the end. It cannot waive the cross-family review, Tech Lead approval, verification, spec compliance, or host permissions. On anything it cannot undo it takes the safe option: it keeps your stated requirements, stays under the size caps, keeps leftovers it cannot prove it created, and merges or releases only when the goal covers delivery. Claude Code's auto mode alone does not count: Feature-Crew still asks.

## Session routing

Skills run only when the model chooses them, so a code change can skip `/fc-build-or-fix`, especially when a small first request grows into a new repository, a refactor, or a release. The plugin's SessionStart hook puts a short routing contract into the session: in Claude Code at startup, resume, `/clear`, and compaction; in GitHub Copilot CLI at session start and resume. It prints [routing.json](https://github.com/D0n9X1n/feature-crew/blob/main/hooks/routing.json), which points code changes at `/fc-build-or-fix`, re-routes scope that grows mid-task, and names `/fc-ship` for pushing, merging, releasing, and cleanup and `/fc-review` for work that skipped the pipeline. A question that needs evidence goes to `/fc-research`, a choice between approaches to `/fc-brainstorm`, an unexplained failure to `/fc-debug`, and a simple question gets a direct answer; autonomous sessions follow *Think first* above. The text is a pointer, not enforcement: it makes routing far more likely, not certain. To turn it off, disable the plugin with `claude plugin disable feature-crew@feature-crew` or `copilot plugin disable feature-crew@feature-crew`.

**Known limits.**
- Copilot CLI has no hook source after compaction, so a compacted Copilot session relies on the skill descriptions alone ([copilot-cli#5225](https://github.com/github/copilot-cli/issues/5225)). Whether Copilot's interactive `/clear` re-injects the text is untested; only session start and resume are verified.
- Claude Code on native Windows needs Git for Windows for this hook. Without Git Bash, Claude Code runs hooks in PowerShell, where the hook cannot read its install path; it fails without blocking the session.

## Cleaning up

Once a goal is achieved, Feature-Crew finishes with `/fc-clean`. It never runs while a `/goal` or Copilot autopilot objective is still unmet. It archives the outcome first: committed, pushed, merged as authorized, and reported. Then it removes only what the task can prove it created: temp roots, worktrees, merged branches, stashes, background processes, and stale remote-tracking refs, with no backups. Anything dirty, unmerged, in use, or of unknown origin is kept and listed in one question. Run `/fc-clean` or say "clean up" to start it yourself.

## Updating

Run `/fc-update`. It updates the plugin through each CLI's own commands, reports the installed version, and reports any old script install left in `~/.claude`; remove that with `./install.sh --dry-run`, then `./install.sh`. Start a new session afterwards, or run `/reload-plugins` in Claude Code.
