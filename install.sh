#!/usr/bin/env bash
# feature-crew installer — wires the framework into Claude Code globally.
#
# Works on macOS, Linux, and Windows via Git Bash / WSL.
# For native Windows PowerShell, see install.ps1 (mirrored).
#
# Usage:
#   ./install.sh                       # install for Claude Code globally (~/.claude)
#   ./install.sh --force               # overwrite existing files
#   ./install.sh --dry-run             # print what would happen, change nothing
#   ./install.sh --uninstall           # remove files this script installs
#   ./install.sh --prefix DIR          # use DIR instead of ~/.claude

set -euo pipefail

FORCE=0
DRY_RUN=0
UNINSTALL=0
PREFIX="${HOME}/.claude"

while [ $# -gt 0 ]; do
  case "$1" in
    --force)         FORCE=1 ;;
    --dry-run)       DRY_RUN=1 ;;
    --uninstall)     UNINSTALL=1 ;;
    --prefix)        shift; PREFIX="$1" ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# Resolve the directory this script lives in (portable; no realpath dependency).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_AGENTS="${SCRIPT_DIR}/agents"
SRC_SKILLS_DIR="${SCRIPT_DIR}/.claude/skills"

DEST_AGENTS="${PREFIX}/agents"
DEST_SKILLS_DIR="${PREFIX}/skills"

# Map agent filename -> (description, model). The subagent NAME is the filename
# without .md -- source files are fc-prefixed, so there is no mapping to keep in
# sync and no way for source and installed names to drift apart.
#
# The model field is what makes cross-family review structural rather than a
# rule the PM has to remember at dispatch time:
#   operate roles (pm, architect, developer) -> empty, inherit the session model
#   review roles  (qa-spec, qa-code, tech-lead) -> sonnet, a different family
# Keep in sync with $AgentMeta in install.ps1.
agent_meta() {
  case "$1" in
    fc-pm.md)         echo "Feature-Crew Product Manager: picks track (Trivial/Standard/Complex) and orchestrates the pipeline.|" ;;
    fc-architect.md)  echo "Feature-Crew Architect: turns approved spec into a bounded implementation plan (<=500 lines).|" ;;
    fc-developer.md)  echo "Feature-Crew Developer: implements one task TDD-style against an approved plan.|" ;;
    fc-qa-spec.md)    echo "Feature-Crew QA spec reviewer: verifies implementation matches approved spec (one-clue mode).|sonnet" ;;
    fc-qa-code.md)    echo "Feature-Crew QA code reviewer: code-quality pass on a diff (one-clue mode).|sonnet" ;;
    fc-tech-lead.md)  echo "Feature-Crew Tech Lead: final cross-family review before merging Complex work.|sonnet" ;;
    *)                echo "Feature-Crew agent.|" ;;
  esac
}

say() { printf '%s\n' "$*"; }
# Run argv as a command, or just print it under --dry-run. Arguments are
# passed as a real argv array (no eval), so paths with spaces or shell
# metacharacters are treated as data, not code.
do_or_echo() {
  if [ "$DRY_RUN" -eq 1 ]; then
    say "DRY-RUN: $*"
  else
    "$@"
  fi
}

ensure_dir() {
  if [ ! -d "$1" ]; then
    do_or_echo mkdir -p "$1"
  fi
}

# Install one agent file: prepend YAML frontmatter (name, description) if the
# source doesn't already have one, then write to dest.
install_agent() {
  local src="$1" dest="$2" name="$3" desc="$4" model="${5:-}"
  if [ -e "$dest" ] && [ "$FORCE" -ne 1 ]; then
    say "skip (exists): $dest  [use --force to overwrite]"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    say "DRY-RUN: install $src -> $dest  (name: $name${model:+, model: $model})"
    return 0
  fi
  {
    # Only add frontmatter if the source file doesn't start with '---'
    if ! head -n 1 "$src" | grep -q '^---$'; then
      # Quote the description: role descriptions contain ": " (e.g. "Feature-Crew
      # Architect: turns an approved spec into..."), and a plain YAML scalar may
      # not. Claude Code 2.1.220 tolerates the unquoted form, but that tolerance
      # is undocumented. Keep in sync with install.ps1.
      printf -- '---\nname: %s\ndescription: "%s"\n' "$name" "$desc"
      [ -n "$model" ] && printf -- 'model: %s\n' "$model"
      printf -- '---\n\n'
    fi
    cat "$src"
  } > "$dest"
  say "installed: $dest${model:+  (model: $model)}"
}

install_skill() {
  local src_dir="$1" dest_dir="$2"
  ensure_dir "$dest_dir"
  # Copy SKILL.md and any other files within the skill directory.
  if [ ! -d "$src_dir" ]; then
    say "ERROR: skill source not found: $src_dir" >&2
    exit 1
  fi
  # Use find to portably handle subdirectories.
  ( cd "$src_dir" && find . -type f -print | sed 's|^\./||' ) | while IFS= read -r rel; do
    local s="$src_dir/$rel" d="$dest_dir/$rel"
    if [ -e "$d" ] && [ "$FORCE" -ne 1 ]; then
      say "skip (exists): $d  [use --force to overwrite]"
      continue
    fi
    do_or_echo mkdir -p "$(dirname "$d")"
    do_or_echo cp "$s" "$d"
    [ "$DRY_RUN" -eq 1 ] || say "installed: $d"
  done
}

# Skills gained the fc- prefix in v5.0.0. Remove the unprefixed directories so
# an upgrade doesn't leave both installed and /build-or-fix still resolving.
#
# ONLY remove a directory we can prove we shipped. `research` and `build-or-fix`
# are plausible names for a user's own skill, and deleting one would destroy
# work with no prompt and no backup. Each candidate must carry both the exact
# legacy `name:` field and a Feature-Crew provenance marker; anything else is
# left alone and reported so the user can decide.
# Mirrors Remove-LegacySkills in install.ps1.
# SHA-256 of every SKILL.md this project has ever published under the legacy
# unprefixed names, hashed after normalizing CRLF to LF.
#
# Exact content identity, not a description prefix. Three prior attempts at
# this check each destroyed user data a different way: no ownership check at
# all, then a whole-file grep for "feature-crew" (killed a skill that merely
# mentioned us), then a description prefix (killed one that merely started the
# same way). Prefix matching cannot answer "did we write this file"; a hash
# can.
#
# A user who hand-edited a genuine legacy skill will not match, so it is kept
# and reported. That is the safe direction -- once they have edited it, it is
# partly their work.
#
# Regenerate with:
#   for t in v3.0 v3.1 v4.0; do for s in build-or-fix research; do
#     git show "$t:.claude/skills/$s/SKILL.md" 2>/dev/null | tr -d '\r' | shasum -a 256
#   done; done
# Note: research/SKILL.md did not exist at v3.0, so that lookup yields the
# empty-string hash (e3b0c442...). It is deliberately NOT listed -- including
# it would treat any zero-byte SKILL.md as ours.
legacy_hashes() {
  case "$1" in
    build-or-fix)
      echo "f11a81aff11703559827198e66f2d237d2bdab263ad43199e82972ec52d9cf72"  # v3.0, v3.1
      echo "13cd94d534d0ed87d2b8d4edbf9bc904761a92ef826780ed9d7138f7258cd808"  # v4.0
      ;;
    research)
      echo "e119bc4fe7ab4d528fd1fc2394a33e1aff6a7821be2182ae2903e1ecb925b94a"  # v3.1, v4.0
      ;;
  esac
}

# Hash a file with CRLF normalized to LF, so a Windows checkout of a genuine
# legacy skill still matches. Portable across sha256sum and shasum.
sha256_lf() {
  if command -v sha256sum >/dev/null 2>&1; then
    tr -d '\r' < "$1" | sha256sum | cut -d' ' -f1
  else
    tr -d '\r' < "$1" | shasum -a 256 | cut -d' ' -f1
  fi
}

remove_legacy_skills() {
  local old d f got
  for old in build-or-fix research; do
    d="$DEST_SKILLS_DIR/$old"
    f="$d/SKILL.md"
    [ -d "$d" ] || continue
    if [ ! -f "$f" ]; then
      say "kept (not ours — no SKILL.md): $d"
      continue
    fi
    got="$(sha256_lf "$f")"
    if ! legacy_hashes "$old" | grep -qx "$got"; then
      say "kept (not ours — content does not match any published version): $d"
      say "  if this was an older Feature-Crew you edited, remove it by hand: rm -rf $d"
      continue
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      say "DRY-RUN: would remove (legacy skill): $d"
    else
      rm -rf "$d"
      say "removed (legacy skill): $d"
    fi
  done
}

# Is the installed file byte-identical to what we would install right now?
# Compares against a freshly generated copy, frontmatter included, so an agent
# the user edited is not ours to delete.
installed_is_ours() {
  local src="$1" dest="$2" name="$3" desc="$4" model="${5:-}" tmp rc
  [ -f "$dest" ] || return 1
  tmp="$(mktemp)"
  {
    if ! head -n 1 "$src" | grep -q '^---$'; then
      printf -- '---\nname: %s\ndescription: "%s"\n' "$name" "$desc"
      [ -n "$model" ] && printf -- 'model: %s\n' "$model"
      printf -- '---\n\n'
    fi
    cat "$src"
  } > "$tmp"
  cmp -s "$tmp" "$dest"; rc=$?
  rm -f "$tmp"
  return $rc
}

uninstall_paths() {
  local removed_any=0
  # Remove only files byte-identical to what we install. The fc- prefix makes
  # a collision unlikely, not impossible -- and install deliberately SKIPS a
  # pre-existing file ("skip (exists)"), so deleting it here would destroy work
  # the install path just went out of its way to protect. A user who edited one
  # of ours keeps it too; once edited it is partly their work.
  for src in "$SRC_AGENTS"/*.md; do
    [ -e "$src" ] || continue
    local base meta name desc model dest
    base="$(basename "$src")"
    name="${base%.md}"
    meta="$(agent_meta "$base")"
    desc="${meta%%|*}"
    model="${meta#*|}"
    dest="$DEST_AGENTS/${name}.md"
    if [ ! -e "$dest" ]; then
      say "not present: $dest"
    elif installed_is_ours "$src" "$dest" "$name" "$desc" "$model"; then
      if [ "$DRY_RUN" -eq 1 ]; then
        say "DRY-RUN: would remove $dest"
      else
        rm -f "$dest"
        say "removed: $dest"
      fi
      removed_any=1
    else
      say "kept (yours — differs from what we install): $dest"
    fi
  done
  if [ -d "$SRC_SKILLS_DIR" ]; then
    for src in "$SRC_SKILLS_DIR"/*/; do
      [ -d "$src" ] || continue
      # Only consider what we would have installed.
      [ -f "${src}SKILL.md" ] || continue
      local skill_name dest differs
      skill_name="$(basename "$src")"
      dest="$DEST_SKILLS_DIR/$skill_name"
      if [ ! -d "$dest" ]; then
        say "not present: $dest"
        continue
      fi
      # Every file we ship must be present and identical, and the directory
      # must hold nothing else -- an extra file means the user put it there.
      differs=0
      ( cd "$src" && find . -type f -print | sed 's|^\./||' ) | while IFS= read -r rel; do
        cmp -s "$src/$rel" "$dest/$rel" || exit 1
      done || differs=1
      if [ "$differs" -eq 0 ]; then
        local ours theirs
        ours=$( ( cd "$src"  && find . -type f | wc -l ) )
        theirs=$( ( cd "$dest" && find . -type f | wc -l ) )
        [ "$ours" -eq "$theirs" ] || differs=1
      fi
      if [ "$differs" -eq 0 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          say "DRY-RUN: would remove $dest"
        else
          rm -rf "$dest"
          say "removed: $dest"
        fi
        removed_any=1
      else
        say "kept (yours — differs from what we install): $dest"
      fi
    done
  fi
  # Best-effort cleanup of any legacy ~/.claude/agents/feature-crew/ from
  # older installer versions.
  if [ -d "$DEST_AGENTS/feature-crew" ]; then
    do_or_echo rm -rf "$DEST_AGENTS/feature-crew"
    say "removed (legacy): $DEST_AGENTS/feature-crew"
  fi
  remove_legacy_skills
}

main_install() {
  if [ ! -d "$SRC_AGENTS" ]; then
    say "ERROR: cannot find agents/ directory next to install.sh ($SRC_AGENTS)" >&2
    exit 1
  fi

  say "feature-crew: installing into $PREFIX"
  ensure_dir "$DEST_AGENTS"

  local count=0
  for src in "$SRC_AGENTS"/*.md; do
    [ -e "$src" ] || continue
    local base meta name desc model dest
    base="$(basename "$src")"
    name="${base%.md}"
    meta="$(agent_meta "$base")"
    desc="${meta%%|*}"
    model="${meta#*|}"
    # Flat under ~/.claude/agents/ so they don't collide with personal agents.
    dest="$DEST_AGENTS/${name}.md"
    install_agent "$src" "$dest" "$name" "$desc" "$model"
    count=$((count + 1))
  done

  # Install every skill directory under .claude/skills/.
  local skill_count=0
  if [ -d "$SRC_SKILLS_DIR" ]; then
    for src in "$SRC_SKILLS_DIR"/*/; do
      [ -d "$src" ] || continue
      # A directory without SKILL.md is not a skill -- skip scratch dirs
      # rather than shipping them. Mirrored in install.ps1.
      [ -f "${src}SKILL.md" ] || continue
      local name="$(basename "$src")"
      install_skill "$src" "$DEST_SKILLS_DIR/$name"
      skill_count=$((skill_count + 1))
    done
  fi
  remove_legacy_skills

  say ""
  say "Done. Installed $count agent file(s) and $skill_count skill(s)."
  say "Agents:  $DEST_AGENTS"
  say "Skills:  $DEST_SKILLS_DIR"
  say ""
  say "Use in any project: /fc-build-or-fix, /fc-brainstorm, /fc-grill-me, /fc-research,"
  say "/fc-review, /fc-second-opinion, /fc-update — or delegate to an fc-* subagent."
}


if [ "$UNINSTALL" -eq 1 ]; then
  say "feature-crew: uninstalling from $PREFIX"
  uninstall_paths
  exit 0
fi

main_install
