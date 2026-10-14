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

The exact classifier is stated once in `skills/fc-build-or-fix/SKILL.md`; this page does not duplicate it. Direct commands remain available for `/fc-research`, `/fc-grill-me`, `/fc-brainstorm`, `/fc-debug`, `/fc-explain`, `/fc-build-or-fix`, `/fc-ship`, `/fc-review`, `/fc-second-opinion`, and `/fc-update`.

## Updating

Run `/fc-update`. It updates the plugin through each CLI's own commands, reports the installed version, and reports any old script install left in `~/.claude`; remove that with `./install.sh --dry-run`, then `./install.sh`. Start a new session afterwards, or run `/reload-plugins` in Claude Code.
