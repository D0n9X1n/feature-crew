#!/usr/bin/env bash
# feature-crew installer — wires the framework into Claude Code (global)
# and/or GitHub Copilot (per-project).
#
# Works on macOS, Linux, and Windows via Git Bash / WSL.
# For native Windows PowerShell, see install.ps1 (a thin wrapper).
#
# Usage:
#   ./install.sh                       # install for Claude Code globally (~/.claude)
#   ./install.sh --project DIR         # ALSO install into project DIR for Copilot
#   ./install.sh --project DIR --copilot-only   # skip global Claude install
#   ./install.sh --force               # overwrite existing files
#   ./install.sh --dry-run             # print what would happen, change nothing
#   ./install.sh --uninstall           # remove files this script installs
#   ./install.sh --prefix DIR          # use DIR instead of ~/.claude

set -euo pipefail

FORCE=0
DRY_RUN=0
UNINSTALL=0
PREFIX="${HOME}/.claude"
PROJECT=""
COPILOT_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --force)         FORCE=1 ;;
    --dry-run)       DRY_RUN=1 ;;
    --uninstall)     UNINSTALL=1 ;;
    --prefix)        shift; PREFIX="$1" ;;
    --project)       shift; PROJECT="$1" ;;
    --copilot-only)  COPILOT_ONLY=1 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
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

DEST_AGENTS="${PREFIX}/agents/feature-crew"
DEST_SKILLS_DIR="${PREFIX}/skills"

# Map agent filename -> Claude Code subagent (name, one-line description).
# These are written as YAML frontmatter so Claude Code recognizes them.
agent_meta() {
  case "$1" in
    pm.md)               echo "fc-pm|Feature-Crew Product Manager: picks track (Trivial/Standard/Complex) and orchestrates the pipeline." ;;
    architect.md)        echo "fc-architect|Feature-Crew Architect: turns approved spec into a bounded implementation plan (<=500 lines)." ;;
    developer.md)        echo "fc-developer|Feature-Crew Developer: implements one task TDD-style against an approved plan." ;;
    qa-spec-reviewer.md) echo "fc-qa-spec|Feature-Crew QA spec reviewer: verifies implementation matches approved spec (one-clue mode)." ;;
    qa-code-reviewer.md) echo "fc-qa-code|Feature-Crew QA code reviewer: code-quality pass on a diff (one-clue mode)." ;;
    tech-lead.md)        echo "fc-tech-lead|Feature-Crew Tech Lead: final cross-family review before merging Complex work." ;;
    *)                   echo "fc-$(basename "$1" .md)|Feature-Crew agent." ;;
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
  local src="$1" dest="$2" name="$3" desc="$4"
  if [ -e "$dest" ] && [ "$FORCE" -ne 1 ]; then
    say "skip (exists): $dest  [use --force to overwrite]"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    say "DRY-RUN: install $src -> $dest  (name: $name)"
    return 0
  fi
  {
    # Only add frontmatter if the source file doesn't start with '---'
    if ! head -n 1 "$src" | grep -q '^---$'; then
      printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$name" "$desc"
    fi
    cat "$src"
  } > "$dest"
  say "installed: $dest"
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
  ( cd "$src_dir" && find . -type f -print ) | while IFS= read -r rel; do
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

uninstall_paths() {
  local removed_any=0
  if [ -d "$DEST_AGENTS" ]; then
    do_or_echo rm -rf "$DEST_AGENTS"
    say "removed: $DEST_AGENTS"
    removed_any=1
  else
    say "not present: $DEST_AGENTS"
  fi
  if [ -d "$SRC_SKILLS_DIR" ]; then
    for src in "$SRC_SKILLS_DIR"/*/; do
      [ -d "$src" ] || continue
      local name dest
      name="$(basename "$src")"
      dest="$DEST_SKILLS_DIR/$name"
      if [ -d "$dest" ]; then
        do_or_echo rm -rf "$dest"
        say "removed: $dest"
        removed_any=1
      else
        say "not present: $dest"
      fi
    done
  fi
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
    local base meta name desc
    base="$(basename "$src")"
    meta="$(agent_meta "$base")"
    name="${meta%%|*}"
    desc="${meta#*|}"
    install_agent "$src" "$DEST_AGENTS/$base" "$name" "$desc"
    count=$((count + 1))
  done

  # Install every skill directory under .claude/skills/.
  local skill_count=0
  if [ -d "$SRC_SKILLS_DIR" ]; then
    for src in "$SRC_SKILLS_DIR"/*/; do
      [ -d "$src" ] || continue
      local name="$(basename "$src")"
      install_skill "$src" "$DEST_SKILLS_DIR/$name"
      skill_count=$((skill_count + 1))
    done
  fi

  say ""
  say "Done. Installed $count agent file(s) and $skill_count skill(s)."
  say "Agents:  $DEST_AGENTS"
  say "Skills:  $DEST_SKILLS_DIR"
  say ""
  say "Use in any project by invoking '/skill build-or-fix' or by asking"
  say "Claude Code to delegate to one of the fc-* subagents."
}

# Per-project install for GitHub Copilot. Copilot has no global config — it
# only reads files inside the repo (.github/copilot-instructions.md and
# anything that file links to). So for Copilot we copy the framework into the
# target project and write a copilot-instructions.md that points at it.
project_install() {
  local proj="$1"
  if [ ! -d "$proj" ]; then
    say "ERROR: --project path does not exist: $proj" >&2
    exit 1
  fi
  proj="$(cd "$proj" && pwd)"
  say ""
  say "feature-crew: installing into project $proj (for Copilot)"

  local proj_root="$proj/.feature-crew"
  ensure_dir "$proj_root/agents"
  ensure_dir "$proj_root/.claude/skills"
  ensure_dir "$proj/.github"

  # Copy raw agent files (no Claude frontmatter — Copilot reads them as docs).
  for src in "$SRC_AGENTS"/*.md; do
    [ -e "$src" ] || continue
    local d="$proj_root/agents/$(basename "$src")"
    if [ -e "$d" ] && [ "$FORCE" -ne 1 ]; then
      say "skip (exists): $d  [use --force to overwrite]"; continue
    fi
    do_or_echo cp "$src" "$d"
    [ "$DRY_RUN" -eq 1 ] || say "installed: $d"
  done

  # Copy skills.
  if [ -d "$SRC_SKILLS_DIR" ]; then
    for src in "$SRC_SKILLS_DIR"/*/; do
      [ -d "$src" ] || continue
      install_skill "$src" "$proj_root/.claude/skills/$(basename "$src")"
    done
  fi

  # Copy AGENTS.md (canonical doc) if present.
  if [ -f "$SCRIPT_DIR/AGENTS.md" ]; then
    local d="$proj_root/AGENTS.md"
    if [ ! -e "$d" ] || [ "$FORCE" -eq 1 ]; then
      do_or_echo cp "$SCRIPT_DIR/AGENTS.md" "$d"
      [ "$DRY_RUN" -eq 1 ] || say "installed: $d"
    else
      say "skip (exists): $d"
    fi
  fi

  # Wire Copilot: write .github/copilot-instructions.md pointing at the bundle.
  local copilot_md="$proj/.github/copilot-instructions.md"
  if [ -e "$copilot_md" ] && [ "$FORCE" -ne 1 ]; then
    say "skip (exists): $copilot_md  [use --force to overwrite]"
  elif [ "$DRY_RUN" -eq 1 ]; then
    say "DRY-RUN: write $copilot_md"
  else
    cat > "$copilot_md" <<'EOF'
# Copilot Instructions

This project uses the **feature-crew** agent framework, vendored under `.feature-crew/`.

At session start, read:
- `.feature-crew/AGENTS.md` — full framework rules
- `.feature-crew/agents/pm.md` — PM behavior and track selection
- `.feature-crew/.claude/skills/build-or-fix/SKILL.md` — three pipelines, gates, dispatch rules

On every build/fix/change request:
1. Act as the **PM** — propose a track (Trivial / Standard / Complex) and confirm with the user.
2. Follow the matching flow in `.feature-crew/.claude/skills/build-or-fix/SKILL.md`.
3. Honor every hard gate (track approval, spec approval, plan approval, verification evidence, all tests pass, Tech Lead approval for Complex, cross-family audit on hard gates).
4. Dispatch role agents from `.feature-crew/agents/`.

For research / investigation requests, use the `/research` flow defined in
`.feature-crew/.claude/skills/research/SKILL.md` (search → synthesize → validate).
EOF
    say "installed: $copilot_md"
  fi

  say ""
  say "Done. Project-installed at $proj_root and $copilot_md"
}

project_uninstall() {
  local proj="$1"
  proj="$(cd "$proj" && pwd)"
  say "feature-crew: uninstalling from project $proj"
  for p in "$proj/.feature-crew" "$proj/.github/copilot-instructions.md"; do
    if [ -e "$p" ]; then
      do_or_echo rm -rf "$p"
      say "removed: $p"
    else
      say "not present: $p"
    fi
  done
}

if [ "$UNINSTALL" -eq 1 ]; then
  if [ "$COPILOT_ONLY" -ne 1 ]; then
    say "feature-crew: uninstalling from $PREFIX"
    uninstall_paths
  fi
  if [ -n "$PROJECT" ]; then
    project_uninstall "$PROJECT"
  fi
  exit 0
fi

if [ "$COPILOT_ONLY" -ne 1 ]; then
  main_install
fi
if [ -n "$PROJECT" ]; then
  project_install "$PROJECT"
fi
