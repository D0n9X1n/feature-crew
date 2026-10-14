---
name: fc-update
description: Updates the installed Feature-Crew plugin to the latest version in Claude Code and GitHub Copilot CLI, and reports any old script install left behind. Use when the user asks to update, upgrade, or reinstall Feature-Crew. Do NOT use for updating unrelated plugins or tools, for a first-time install (follow the README), or for changing Feature-Crew itself (use /fc-build-or-fix).
---

# fc-update

Updates the plugin through each CLI's own plugin commands. It never copies, edits, or deletes files.

## Flow

1. Run `claude plugin list --json` and `copilot plugin list --json` for each CLI on PATH; update only where `feature-crew` is installed.
2. Claude Code: run `claude plugin marketplace update feature-crew`, then `claude plugin update feature-crew@feature-crew`.
3. Copilot CLI: run `copilot plugin marketplace update feature-crew`, then `copilot plugin update feature-crew@feature-crew`.
4. List the plugins again and report the installed version for each CLI.
5. Run `./install.sh --check` from a Feature-Crew clone; it only reads and reports any old script install, which shadows the plugin.
6. If it reports old files, tell the user to run `./install.sh --dry-run`, then `./install.sh`, themselves; this skill never runs them.
7. Remind the user to start a new session, or run `/reload-plugins` in Claude Code.

Any error stops the flow; report the command and its output.

## What this never does

- Delete, copy, or edit a file, including the plugin cache.
- Change CLI settings or install Feature-Crew where it is not installed.

## Related skills

- Changing Feature-Crew itself → `/fc-build-or-fix`
- First-time install → the README's quick start, no skill needed
