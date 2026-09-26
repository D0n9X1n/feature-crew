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

Show what arrived, then check the installed state even if the pull was a no-op or the user already pulled:

```bash
prefix="$HOME/.claude"
scratch=$(mktemp -d) || exit 1
if ! ./install.sh --prefix "$scratch" --force; then
  rm -rf "$scratch"
  exit 1
fi
up_to_date=0
if cmp -s "$scratch/feature-crew.sha256" "$prefix/feature-crew.sha256" &&
   (cd "$prefix" &&
    if command -v sha256sum >/dev/null 2>&1; then sha256sum -c feature-crew.sha256; else shasum -a 256 -c feature-crew.sha256; fi
   ); then up_to_date=1; fi
rm -rf "$scratch"
printf 'up_to_date=%s\n' "$up_to_date"
```

Only if `up_to_date=1`, say the install is up to date and stop: its manifest matches this clone and every recorded file is present and unchanged. Otherwise continue.

## 3 — Find what you would overwrite, before overwriting it

`--force` overwrites. Run the ownership-aware check first:

```bash
./install.sh --uninstall --dry-run
```

`kept (yours — differs from what we install)` marks files or skill directories whose ownership is uncertain. The check uses current bytes, the recorded install baseline, then published hashes only when no baseline exists. An untagged pre-manifest install cannot be distinguished from an edit; do not label every kept file a user change.

- **No uncertain files** → proceed.
- **Any uncertain files** → list them (including files within kept skill directories) and ask before continuing. Offer a backup for every listed file (`cp <file> <file>.bak`). Preserve a malformed manifest and report it; do not overwrite it to make the check pass. Do not decide backups or overwrites for the user.

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

Legacy cleanup removes files under the old build-or-fix/, research/ and agents/feature-crew/ locations only when their content matches something this project published; anything else is kept and reported.

## 6 — Verify, don't assume

Counts come from the source, so this does not rot when a skill is added:

```bash
ls ~/.claude/agents/fc-*.md | wc -l      # must equal: ls agents/*.md | wc -l
ls -d ~/.claude/skills/fc-*/ | wc -l     # must equal: ls -d .claude/skills/*/ | wc -l
if grep -H '^model:' ~/.claude/agents/fc-{pm,architect,developer,qa-spec,qa-code,tech-lead}.md; then exit 1; fi
(cd ~/.claude &&
 if command -v sha256sum >/dev/null 2>&1; then sha256sum -c feature-crew.sha256; else shasum -a 256 -c feature-crew.sha256; fi
)
```

Paste the output. All six role agents must carry no `model:` key; hard-gate reviewers receive the selected override at dispatch time per `/fc-build-or-fix`.

## What this never does

- Delete a file it cannot prove it installed.
- Overwrite an edited file without asking.
- Stash or discard uncommitted work in the clone.
- Re-clone the repo, or install from anywhere but the clone in front of it.

## Related skills

- Changing Feature-Crew itself → `/fc-build-or-fix`
- First-time install → `./install.sh`, no skill needed
