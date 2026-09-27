# Usage

[简体中文](Usage-zh-CN)

How to install, run, and update Feature-Crew. Back to [Home](Home).

## Install

```bash
./install.sh         # macOS / Linux / Git Bash / WSL
.\install.ps1        # native Windows PowerShell
```

Flags: `--force`, `--dry-run`, `--uninstall`, `--check`, `--verify`, `--prefix DIR`; `install.ps1` also accepts `-Force`, `-DryRun`, `-Uninstall`, `-Check`, `-Verify`, `-Prefix DIR`. Agents install to `~/.claude/agents/fc-*.md`; skills to `~/.claude/skills/fc-*/`.

## Describe the need

Slash-command knowledge is optional. Feature-Crew distinguishes a directly discoverable fact, multi-source evidence, a user-owned decision, an unresolved approach, adversarial confidence in a chosen consequential decision, and an unexplained failure. It looks up the first and routes the others to the appropriate skill. A subskill resolves one category, returns to the originating flow, and that flow resumes without recursive invocation or repetition of an unchanged gap.

The exact classifier is stated once in `.claude/skills/fc-build-or-fix/SKILL.md`; this page does not duplicate it. Direct commands remain available for `/fc-research`, `/fc-grill-me`, `/fc-brainstorm`, `/fc-debug`, `/fc-explain`, `/fc-build-or-fix`, `/fc-ship`, `/fc-review`, `/fc-second-opinion`, and `/fc-update`.

## Updating

Run `/fc-update`, or `git pull origin main && ./install.sh --force`. Before overwriting, the update flow reports installed files you edited. Legacy cleanup and uninstall remove only files whose exact content proves Feature-Crew installed them. Each install records what it wrote in `~/.claude/feature-crew.sha256`, so the update flow can tell your edits from upstream changes.
