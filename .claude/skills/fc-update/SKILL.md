---
name: fc-update
description: Updates an installed Feature-Crew to the latest version, replacing the agents and skills in ~/.claude and reporting anything it deliberately left alone. Use when the user asks to update, upgrade, or reinstall Feature-Crew, or after pulling a new version of this repo. Do NOT use for updating unrelated tools, for a first-time install (run ./install.sh directly), or for changing Feature-Crew itself (use /fc-build-or-fix).
---

# fc-update

Replaces installed agents and skills with the current version. Never deletes work it did not install. Run it from a clone of the feature-crew repo, not from `~/.claude`; if the current directory is not one, ask where it is. The installer owns the up-to-date check; do not recompute it here.

## Flow

1. Run `git status --short`; if the clone is dirty, stop and ask, never stash or discard its work.
2. Run `git pull --ff-only` and summarize what arrived.
3. Always run `./install.sh --check` next, even when the pull was a no-op. It is read-only and exits 0 when current, 1 when an update is needed, and 2 on any error.
4. If it reports `check: current`, report its `stale:` lines with the manual `rm` for each, then stop.
5. Otherwise list every `uncertain:` file, including files inside skill directories. Offer a backup of each (`cp <file> <file>.bak`). Get explicit consent before running `--force`. Never decide backups or overwrites for the user.
6. Run `./install.sh --force` and report its `kept` lines. Then run `./install.sh --verify` once and paste its output, with the manual `rm` for each `stale:` line.

Any error stops the flow. Report a malformed manifest and leave it untouched; never rewrite it to pass the check. On native Windows without Git Bash, use `.\install.ps1` with `-Check`, `-Force`, and `-Verify`.

Accepted limit: a file edited between `--check` and `--force` is not asked about again (single-user local window).

## What this never does

- Delete a file it cannot prove it installed.
- Overwrite an edited file without asking.
- Stash or discard uncommitted work in the clone.
- Re-clone the repo, or install from anywhere but the clone in front of it.

## Related skills

- Changing Feature-Crew itself → `/fc-build-or-fix`
- First-time install → `./install.sh`, no skill needed
