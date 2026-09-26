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
export LC_ALL=C

FORCE=0
DRY_RUN=0
UNINSTALL=0
PREFIX="${HOME}/.claude"

while [ $# -gt 0 ]; do
  case "$1" in
    --force)         FORCE=1 ;;
    --dry-run)       DRY_RUN=1 ;;
    --uninstall)     UNINSTALL=1 ;;
    --prefix)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --prefix" >&2
        exit 2
      fi
      shift; PREFIX="$1"
      ;;
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
PUBLISHED_HASHES="${SCRIPT_DIR}/published.sha256"

DEST_AGENTS="${PREFIX}/agents"
DEST_SKILLS_DIR="${PREFIX}/skills"
MANIFEST="${PREFIX}/feature-crew.sha256"
MANIFEST_PRESENT=0
MANIFEST_VALID=1
MANIFEST_PATHS=()
MANIFEST_HASHES=()
NEXT_ENTRIES=()
REMOVED_ROOTS=()

# Map agent filename -> description. The subagent NAME is the filename without
# .md, so source and installed names cannot drift. Role frontmatter carries no
# model key: hard-gate dispatchers select an explicit override from artifact
# author provenance. Keep in sync with $AgentMeta in install.ps1.
agent_meta() {
  case "$1" in
    fc-pm.md)         echo "Feature-Crew Product Manager: selects Just Do It/Standard/Complex and orchestrates the pipeline." ;;
    fc-architect.md)  echo "Feature-Crew Architect: turns approved spec into a bounded implementation plan (<=500 lines)." ;;
    fc-developer.md)  echo "Feature-Crew Developer: implements one task TDD-style against an approved plan." ;;
    fc-qa-spec.md)    echo "Feature-Crew QA spec reviewer: verifies implementation matches approved spec (one-clue mode)." ;;
    fc-qa-code.md)    echo "Feature-Crew QA code reviewer: code-quality pass on a diff (one-clue mode)." ;;
    fc-tech-lead.md)  echo "Feature-Crew Tech Lead: final cross-family review before merging Complex work." ;;
    *)                echo "Feature-Crew agent." ;;
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

# Dry runs do not create directories, so remember those already announced.
DRY_DIRS=()
ensure_dir() {
  local dir="$1" known
  [ -d "$dir" ] && return 0
  if [ "$DRY_RUN" -eq 1 ]; then
    # Bash 3.2 treats an empty array as unset under nounset.
    if [ "${#DRY_DIRS[@]}" -gt 0 ]; then
      for known in "${DRY_DIRS[@]}"; do
        [ "$known" = "$dir" ] && return 0
      done
    fi
    say "DRY-RUN: mkdir -p $dir"
    DRY_DIRS+=("$dir")
  else
    mkdir -p "$dir"
  fi
}

# Install one agent file: prepend YAML frontmatter (name, description) if the
# source doesn't already have one, then write to dest.
install_agent() {
  local src="$1" dest="$2" name="$3" desc="$4" hash
  local rel="agents/$3.md"
  if [ -e "$dest" ] && [ "$FORCE" -ne 1 ]; then
    say "skip (exists): $dest  [use --force to overwrite]"
    if [ "$DRY_RUN" -eq 0 ] && [ "$MANIFEST_VALID" -eq 1 ]; then
      if hash=$(manifest_hash "$rel"); then
        NEXT_ENTRIES+=("$hash  $rel")
      elif installed_is_ours "$src" "$dest" "$name" "$desc"; then
        record_written "$dest" "$rel"
      fi
    fi
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    say "DRY-RUN: install $src -> $dest  (name: $name)"
    return 0
  fi
  {
    # Only add frontmatter if the source file doesn't start with '---'
    if ! head -n 1 "$src" | grep -q '^---$'; then
      # Quote the description: role descriptions contain ": " (e.g. "Feature-Crew
      # Architect: turns an approved spec into..."), and a plain YAML scalar may
      # not. Claude Code 2.1.220 tolerates the unquoted form, but that tolerance
      # is undocumented. Keep in sync with install.ps1.
      printf -- '---\nname: %s\ndescription: "%s"\n---\n\n' "$name" "$desc"
    fi
    cat "$src"
  } > "$dest"
  record_written "$dest" "$rel"
  say "installed: $dest"
}

install_skill() {
  local src_dir="$1" dest_dir="$2" skill manifest_rel hash
  src_dir=${src_dir%/}
  skill=$(basename "$src_dir")
  ensure_dir "$dest_dir"
  # Copy SKILL.md and any other files within the skill directory.
  if [ ! -d "$src_dir" ]; then
    say "ERROR: skill source not found: $src_dir" >&2
    exit 1
  fi
  # Keep this loop in the current shell so dry-run mkdir tracking persists.
  while IFS= read -r rel; do
    local s="$src_dir/$rel" d="$dest_dir/$rel"
    manifest_rel="skills/$skill/$rel"
    if [ -e "$d" ] && [ "$FORCE" -ne 1 ]; then
      say "skip (exists): $d  [use --force to overwrite]"
      if [ "$DRY_RUN" -eq 0 ] && [ "$MANIFEST_VALID" -eq 1 ]; then
        if hash=$(manifest_hash "$manifest_rel"); then
          NEXT_ENTRIES+=("$hash  $manifest_rel")
        elif skill_file_is_ours "$s" "$d" "$manifest_rel"; then
          record_written "$d" "$manifest_rel"
        fi
      fi
      continue
    fi
    ensure_dir "$(dirname "$d")"
    do_or_echo cp "$s" "$d"
    record_written "$d" "$manifest_rel"
    [ "$DRY_RUN" -eq 1 ] || say "installed: $d"
  done < <(cd "$src_dir" && find . -type f -print | sed 's|^\./||' | sort)
}

# Exact content identity, not a description prefix. Three prior attempts at
# this check each destroyed user data a different way: no ownership check at
# all, then a whole-file grep for "feature-crew" (killed a skill that merely
# mentioned us), then a description prefix (killed one that merely started the
# same way). Prefix matching cannot answer "did we write this file"; a hash
# can, but only for that file -- never its neighbours.
#
# published.sha256 records (LF-normalized hash, prefix-relative path) from the
# v3.1-v5.1.0 installers. T43 regenerates it from those tags. A missing table
# recognizes nothing; edited or unknown files are always kept.

# Hash a file with CRLF normalized to LF, so a Windows checkout of a genuine
# legacy skill still matches. Portable across sha256sum and shasum.
sha256_lf() {
  if command -v sha256sum >/dev/null 2>&1; then
    tr -d '\r' < "$1" | sha256sum | cut -d' ' -f1
  else
    tr -d '\r' < "$1" | shasum -a 256 | cut -d' ' -f1
  fi
}

published_file() {
  local file="$1" rel="$2" hash
  [ -f "$PUBLISHED_HASHES" ] && [ -f "$file" ] || return 1
  hash="$(sha256_lf "$file")"
  grep -qxF "$hash  $rel" "$PUBLISHED_HASHES"
}

sha256_raw() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum < "$1" | cut -d' ' -f1
  else
    shasum -a 256 < "$1" | cut -d' ' -f1
  fi
}

load_manifest() {
  local line rel i pattern='^[0-9a-f]{64}  (agents|skills)/.+$'
  [ -e "$MANIFEST" ] || [ -L "$MANIFEST" ] || return 0
  MANIFEST_PRESENT=1
  if [ ! -f "$MANIFEST" ]; then MANIFEST_VALID=0; return 0; fi
  while IFS= read -r line || [ -n "$line" ]; do
    rel=${line:66}
    if [[ ! $line =~ $pattern ]]; then MANIFEST_VALID=0; fi
    case "/$rel/" in *'/../'*|*$'\r'*|*\\*) MANIFEST_VALID=0 ;; esac
    if [ "$MANIFEST_VALID" -eq 0 ]; then
      MANIFEST_PATHS=(); MANIFEST_HASHES=()
      return 0
    fi
    for ((i=0; i<${#MANIFEST_PATHS[@]}; i++)); do
      [ "${MANIFEST_PATHS[$i]}" = "$rel" ] && break
    done
    MANIFEST_PATHS[$i]="$rel"
    MANIFEST_HASHES[$i]="${line:0:64}"
  done < "$MANIFEST"
}

manifest_hash() {
  local i
  for ((i=0; i<${#MANIFEST_PATHS[@]}; i++)); do
    if [ "${MANIFEST_PATHS[$i]}" = "$1" ]; then
      printf '%s\n' "${MANIFEST_HASHES[$i]}"
      return 0
    fi
  done
  return 1
}

# A recorded mismatch is an edit, even if its bytes match an older release.
historical_file_is_ours() {
  local file="$1" rel="$2" hash
  if hash=$(manifest_hash "$rel"); then
    [ "$(sha256_raw "$file")" = "$hash" ]
  else
    published_file "$file" "$rel"
  fi
}

skill_file_is_ours() {
  local src="$1" dest="$2" rel="$3"
  [ -f "$src" ] && [ -f "$dest" ] || return 1
  cmp -s "$src" "$dest" || historical_file_is_ours "$dest" "$rel"
}

record_written() {
  [ "$DRY_RUN" -eq 0 ] && [ "$MANIFEST_VALID" -eq 1 ] || return 0
  NEXT_ENTRIES+=("$(sha256_raw "$1")  $2")
}

write_manifest_entries() {
  if [ "${#NEXT_ENTRIES[@]}" -gt 0 ]; then
    printf '%s\n' "${NEXT_ENTRIES[@]}" | sort -k2 > "$MANIFEST"
  else
    : > "$MANIFEST"
  fi
}

install_manifest() {
  if [ "$MANIFEST_VALID" -eq 0 ]; then
    say "kept (not a Feature-Crew manifest): $MANIFEST"
  elif [ "$DRY_RUN" -eq 1 ]; then
    say "DRY-RUN: write $MANIFEST"
  else
    write_manifest_entries
    say "installed: $MANIFEST"
  fi
}

uninstall_manifest() {
  [ "$MANIFEST_PRESENT" -eq 1 ] || return 0
  if [ "$MANIFEST_VALID" -eq 0 ]; then
    say "kept (not a Feature-Crew manifest): $MANIFEST"
    return 0
  fi
  local i rel root removed
  NEXT_ENTRIES=()
  for ((i=0; i<${#MANIFEST_PATHS[@]}; i++)); do
    rel=${MANIFEST_PATHS[$i]}
    [ -f "$PREFIX/$rel" ] || continue
    removed=0
    if [ "${#REMOVED_ROOTS[@]}" -gt 0 ]; then
      for root in "${REMOVED_ROOTS[@]}"; do
        case "$rel" in "$root"|"$root"/*) removed=1; break ;; esac
      done
    fi
    [ "$removed" -eq 0 ] || continue
    NEXT_ENTRIES+=("${MANIFEST_HASHES[$i]}  $rel")
  done
  if [ "${#NEXT_ENTRIES[@]}" -eq 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      say "DRY-RUN: would remove $MANIFEST"
    else
      rm -f "$MANIFEST"
      say "removed: $MANIFEST"
    fi
  else
    [ "$DRY_RUN" -eq 1 ] || write_manifest_entries
    say "kept (records the files kept above): $MANIFEST"
  fi
}

keep_legacy() {
  say "kept (not ours — content does not match any published version): $1"
  say "  if this was an older Feature-Crew you edited, remove it by hand: $1"
}

remove_legacy() {
  local location dir rel file
  for location in agents/feature-crew skills/build-or-fix skills/research; do
    dir="$PREFIX/$location"
    [ -d "$dir" ] || continue
    if [ "$location" != agents/feature-crew ]; then
      if [ ! -f "$dir/SKILL.md" ]; then
        say "kept (not ours — no SKILL.md): $dir"
        continue
      fi
      if ! published_file "$dir/SKILL.md" "$location/SKILL.md"; then
        keep_legacy "$dir"
        continue
      fi
    fi
    while IFS= read -r rel; do
      file="$dir/$rel"
      if published_file "$file" "$location/$rel"; then
        if [ "$DRY_RUN" -eq 1 ]; then
          say "DRY-RUN: would remove (legacy): $file"
        else
          rm -f "$file"
          say "removed (legacy): $file"
        fi
      else
        keep_legacy "$file"
      fi
    done < <(cd "$dir" && find . -type f -print | sed 's|^\./||' | sort)
    if [ "$DRY_RUN" -ne 1 ]; then
      # Never recursively delete a legacy directory: prune only empty ones,
      # after their children, so user files (including hidden files) survive.
      find "$dir" -depth -type d -empty -exec rmdir {} \;
    fi
  done
}

# Current generated bytes win; otherwise consult the recorded baseline first.
installed_is_ours() {
  local src="$1" dest="$2" name="$3" desc="$4" tmp rc
  [ -f "$dest" ] || return 1
  tmp="$(mktemp)"
  {
    if ! head -n 1 "$src" | grep -q '^---$'; then
      printf -- '---\nname: %s\ndescription: "%s"\n---\n\n' "$name" "$desc"
    fi
    cat "$src"
  } > "$tmp"
  rc=0
  cmp -s "$tmp" "$dest" || rc=$?
  rm -f "$tmp"
  [ "$rc" -eq 0 ] || historical_file_is_ours "$dest" "agents/$name.md"
}

uninstall_paths() {
  for src in "$SRC_AGENTS"/*.md; do
    [ -e "$src" ] || continue
    local base name desc dest
    base="$(basename "$src")"
    name="${base%.md}"
    desc="$(agent_meta "$base")"
    dest="$DEST_AGENTS/${name}.md"
    if [ ! -e "$dest" ]; then
      say "not present: $dest"
    elif installed_is_ours "$src" "$dest" "$name" "$desc"; then
      if [ "$DRY_RUN" -eq 1 ]; then
        say "DRY-RUN: would remove $dest"
      else
        rm -f "$dest"
        say "removed: $dest"
      fi
      REMOVED_ROOTS+=("agents/$name.md")
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
      # Only files actually present matter; any unknown file protects the dir.
      differs=0
      while IFS= read -r rel; do
        if ! skill_file_is_ours "$src/$rel" "$dest/$rel" "skills/$skill_name/$rel"; then
          differs=1
          break
        fi
      done < <(cd "$dest" && find . -type f -print | sed 's|^\./||' | sort)
      if [ "$differs" -eq 0 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          say "DRY-RUN: would remove $dest"
        else
          rm -rf "$dest"
          say "removed: $dest"
        fi
        REMOVED_ROOTS+=("skills/$skill_name")
      else
        say "kept (yours — differs from what we install): $dest"
      fi
    done
  fi
  uninstall_manifest
  remove_legacy
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
    local base name desc dest
    base="$(basename "$src")"
    name="${base%.md}"
    desc="$(agent_meta "$base")"
    # Flat under ~/.claude/agents/ so they don't collide with personal agents.
    dest="$DEST_AGENTS/${name}.md"
    install_agent "$src" "$dest" "$name" "$desc"
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
  install_manifest
  remove_legacy

  say ""
  say "Done. Installed $count agent file(s) and $skill_count skill(s)."
  say "Agents:  $DEST_AGENTS"
  say "Skills:  $DEST_SKILLS_DIR"
  say ""
  say "Describe your need naturally in any project; slash commands are optional."
  say "Available: /fc-build-or-fix, /fc-brainstorm, /fc-debug, /fc-grill-me, /fc-research,"
  say "/fc-review, /fc-second-opinion, /fc-update - or delegate to an fc-* subagent."
}


load_manifest
if [ "$UNINSTALL" -eq 1 ]; then
  say "feature-crew: uninstalling from $PREFIX"
  uninstall_paths
  exit 0
fi

main_install
