---
name: fc-update
description: Updates an installed Feature-Crew to the latest version, replacing the agents and skills in ~/.claude and reporting anything it deliberately left alone. Use when the user asks to update, upgrade, or reinstall Feature-Crew, or after pulling a new version of this repo. Do NOT use for updating unrelated tools, for a first-time install (run ./install.sh directly), or for changing Feature-Crew itself (use /fc-build-or-fix).
---

# fc-update

Replaces installed agents and skills with the current version. Never deletes work it did not install.

## 1 — Find the clone

This runs from a clone of the feature-crew repo, not from `~/.claude`. If the current directory is not one, ask where it is. Do not re-clone and do not guess.

## 2 — Pull

```bash
git status --short          # stop and ask if dirty; do not stash silently
git pull --ff-only
git log --oneline HEAD@{1}..HEAD
```

Show what arrived. If the pull was a no-op, say so and stop — an update that changes nothing should not reinstall.

## 3 — Find what you would overwrite, before overwriting it

`--force` overwrites. Locally edited files are found first:

```bash
./install.sh --uninstall --dry-run
```

Every `kept (yours — differs from what we install)` line is a file you changed. That check compares against a freshly generated copy, so it catches real edits, not timestamps.

- **No such lines** → proceed.
- **Any such lines** → list them and ask before continuing. Offer to back them up first (`cp <file> <file>.bak`). Do not decide this for the user; the file is their work.

## 4 — Find stale artifacts

Skills removed in a later version linger, because the installer only writes what currently exists:

```bash
comm -23 <(ls ~/.claude/skills | grep '^fc-' | sort) <(ls .claude/skills | sort)
```

Anything listed is installed but no longer shipped. Report it with the manual `rm`; do not delete it silently. The same reasoning applies as everywhere else in this installer — a directory bearing our prefix is not proof we put it there.

## 5 — Install

```bash
./install.sh --force
```

The installer removes the legacy unprefixed `build-or-fix/` and `research/` directories, but only when their content hashes match something this project actually published.

## 6 — Verify, don't assume

Counts come from the source, so this does not rot when a skill is added:

```bash
ls ~/.claude/agents/fc-*.md | wc -l      # must equal: ls agents/*.md | wc -l
ls -d ~/.claude/skills/fc-*/ | wc -l     # must equal: ls -d .claude/skills/*/ | wc -l
grep -c '^model: sonnet$' ~/.claude/agents/fc-{qa-spec,qa-code,tech-lead}.md
```

Paste the output. Review agents must carry `model: sonnet`; operate agents must carry no `model:` key at all.

## What this never does

- Delete a file it cannot prove it installed.
- Overwrite an edited file without asking.
- Stash or discard uncommitted work in the clone.
- Re-clone the repo, or install from anywhere but the clone in front of it.

## Related skills

- Changing Feature-Crew itself → `/fc-build-or-fix`
- First-time install → `./install.sh`, no skill needed
