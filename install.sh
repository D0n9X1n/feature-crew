#!/usr/bin/env bash
# feature-crew installer — installs the Feature-Crew plugin in Claude Code and
# GitHub Copilot CLI, then removes an old script install from ~/.claude.
# Works on macOS, Linux, and Windows via Git Bash / WSL; install.ps1 mirrors it.
#
# Usage:
#   ./install.sh                  # install or update the plugin in each CLI on PATH, then remove the old install
#   ./install.sh --dry-run        # print every command and removal, change nothing
#   ./install.sh --check          # read-only: report plugin state and old files
#   ./install.sh --uninstall      # remove the plugin from each CLI and the old install
#   ./install.sh --prefix DIR     # old install location (default ~/.claude)
#   ./install.sh --source SRC     # plugin marketplace source (default D0n9X1n/feature-crew)
# Old fc-* files are removed even when edited: they would shadow the plugin.
# Older files are removed only when published.sha256 proves them ours.
# --check exits 0 when current, 1 when action is needed, 2 on an error.

set -euo pipefail
export LC_ALL=C

DRY_RUN=0
UNINSTALL=0
CHECK=0
PREFIX="${HOME}/.claude"
SOURCE="D0n9X1n/feature-crew"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --check)     CHECK=1 ;;
    --prefix|--source)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for $1" >&2
        exit 2
      fi
      if [ "$1" = --prefix ]; then PREFIX="$2"; else SOURCE="$2"; fi
      shift
      ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ "$CHECK" -eq 1 ] && [ $((DRY_RUN + UNINSTALL)) -gt 0 ]; then
  echo "--check cannot be combined with --dry-run or --uninstall" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUBLISHED_HASHES="${SCRIPT_DIR}/published.sha256"
PLUGIN_ID="feature-crew@feature-crew"
MARKETPLACE="feature-crew"

# Every path an old script install wrote, from what tagged installers did
# (T77 regenerates these from v3.1-v5.3.1). Keep in sync with install.ps1.
LEGACY_FC_AGENTS=("fc-architect" "fc-developer" "fc-pm" "fc-qa-code" "fc-qa-spec" "fc-tech-lead")
LEGACY_FC_SKILLS=("fc-brainstorm" "fc-build-or-fix" "fc-debug" "fc-explain" "fc-grill-me" "fc-research" "fc-review" "fc-second-opinion" "fc-ship" "fc-update")
LEGACY_OLD_AGENTS=("architect" "developer" "pm" "qa-code-reviewer" "qa-spec-reviewer" "tech-lead")
LEGACY_OLD_SKILLS=("build-or-fix" "research")

say() { printf '%s\n' "$*"; }

CLIS=()
for c in claude copilot; do
  if command -v "$c" >/dev/null 2>&1; then CLIS+=("$c"); fi
done
if [ "${#CLIS[@]}" -eq 0 ]; then
  echo "feature-crew: neither claude nor copilot is on PATH; install Claude Code or GitHub Copilot CLI first." >&2
  exit 2
fi

# The CLIs' own JSON listings are the only plugin state this script reads.
# 0 listed, 1 not listed, 2 the listing failed.
listed() { # cli, marketplace|plugin
  local out
  if [ "$2" = marketplace ]; then
    out="$("$1" plugin marketplace list --json 2>/dev/null)" || return 2
    [[ "$out" =~ \"name\":\ *\"feature-crew\" ]] && return 0
  else
    out="$("$1" plugin list --json 2>/dev/null)" || return 2
    if [ "$1" = claude ]; then
      [[ "$out" =~ \"id\":\ *\"feature-crew@feature-crew\" ]] && return 0
    else
      # Copilot lists a registered marketplace's plugin disabled until it is installed.
      [[ "$out" =~ \"name\":\ *\"feature-crew\"[^}]*\"enabled\":\ *true ]] && return 0
    fi
  fi
  return 1
}

cli_failed() {
  echo "feature-crew: $1 step failed; old files left in place." >&2
  exit 1
}

# Print, then run; under --dry-run only print.
step() {
  if [ "$DRY_RUN" -eq 1 ]; then
    say "would run: $*"
  else
    say "run: $*"
    "$@"
  fi
}

install_cli() {
  local cli="$1" rc
  rc=0; listed "$cli" marketplace || rc=$?
  case "$rc" in
    0) step "$cli" plugin marketplace update "$MARKETPLACE" || cli_failed "$cli" ;;
    1) step "$cli" plugin marketplace add "$SOURCE" || cli_failed "$cli" ;;
    *) cli_failed "$cli" ;;
  esac
  rc=0; listed "$cli" plugin || rc=$?
  case "$rc" in
    0) step "$cli" plugin update "$PLUGIN_ID" || cli_failed "$cli" ;;
    1) step "$cli" plugin install "$PLUGIN_ID" || cli_failed "$cli" ;;
    *) cli_failed "$cli" ;;
  esac
}

uninstall_cli() {
  local cli="$1" rc
  rc=0; listed "$cli" plugin || rc=$?
  case "$rc" in
    0) step "$cli" plugin uninstall "$PLUGIN_ID" || cli_failed "$cli" ;;
    1) ;;
    *) cli_failed "$cli" ;;
  esac
  rc=0; listed "$cli" marketplace || rc=$?
  case "$rc" in
    0) step "$cli" plugin marketplace remove "$MARKETPLACE" || cli_failed "$cli" ;;
    1) ;;
    *) cli_failed "$cli" ;;
  esac
}

# Hash a file with CRLF normalized to LF, so a Windows checkout of a genuine
# legacy file still matches. Portable across sha256sum and shasum.
sha256_lf() {
  if command -v sha256sum >/dev/null 2>&1; then
    tr -d '\r' < "$1" | sha256sum | cut -d' ' -f1
  else
    tr -d '\r' < "$1" | shasum -a 256 | cut -d' ' -f1
  fi
}

published_file() { # file, prefix-relative path
  [ -f "$PUBLISHED_HASHES" ] && [ -f "$1" ] || return 1
  grep -qxF "$(sha256_lf "$1")  $2" "$PUBLISHED_HASHES"
}

LEGACY_FOUND=0
KEPT=()
legacy_remove() { # path; rm -rf removes a link itself, never its target
  LEGACY_FOUND=1
  if [ "$CHECK" -eq 1 ]; then
    say "old file: $1"
  elif [ "$DRY_RUN" -eq 1 ]; then
    say "would remove: $1"
  else
    rm -rf "$1"
    say "removed: $1"
  fi
}

old_skill_files() { # skill dir: its regular files, sorted
  (cd "$1" && find . -type f | sed 's#^\./##' | sort)
}

clean_legacy() {
  local n p rel
  KEPT=()
  for n in "${LEGACY_FC_AGENTS[@]}"; do
    p="$PREFIX/agents/$n.md"
    if [ -e "$p" ] || [ -L "$p" ]; then legacy_remove "$p"; fi
  done
  for n in "${LEGACY_FC_SKILLS[@]}"; do
    p="$PREFIX/skills/$n"
    if [ -e "$p" ] || [ -L "$p" ]; then legacy_remove "$p"; fi
  done
  p="$PREFIX/feature-crew.sha256"
  if [ -e "$p" ] || [ -L "$p" ]; then legacy_remove "$p"; fi
  for n in "${LEGACY_OLD_AGENTS[@]}"; do
    p="$PREFIX/agents/feature-crew/$n.md"
    if [ -f "$p" ] && [ ! -L "$p" ]; then
      if published_file "$p" "agents/feature-crew/$n.md"; then legacy_remove "$p"; else KEPT+=("$p"); fi
    fi
  done
  for n in "${LEGACY_OLD_SKILLS[@]}"; do
    p="$PREFIX/skills/$n"
    if [ -d "$p" ] && [ ! -L "$p" ]; then
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        if published_file "$p/$rel" "skills/$n/$rel"; then legacy_remove "$p/$rel"; else KEPT+=("$p/$rel"); fi
      done < <(old_skill_files "$p")
    fi
  done
  if [ "$CHECK" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then prune_empty; fi
  if [ "${#KEPT[@]}" -gt 0 ]; then
    for p in "${KEPT[@]}"; do say "kept (not ours): $p"; done
  fi
}

# Remove only directories the old install made and this run emptied.
prune_empty() {
  local n p
  for n in "${LEGACY_OLD_SKILLS[@]}"; do
    p="$PREFIX/skills/$n"
    if [ -d "$p" ] && [ ! -L "$p" ]; then find "$p" -depth -type d -empty -exec rmdir {} \; ; fi
  done
  p="$PREFIX/agents/feature-crew"
  if [ -d "$p" ] && [ ! -L "$p" ]; then rmdir "$p" 2>/dev/null || true; fi
}

if [ "$UNINSTALL" -eq 1 ]; then
  say "feature-crew: uninstalling; old install at $PREFIX"
else
  say "feature-crew: plugin source $SOURCE; old install at $PREFIX"
fi

if [ "$CHECK" -eq 1 ]; then
  for c in "${CLIS[@]}"; do
    rc=0; listed "$c" plugin || rc=$?
    case "$rc" in
      0) say "$c: feature-crew installed" ;;
      1) say "$c: feature-crew missing"; LEGACY_FOUND=1 ;;
      *) echo "feature-crew: $c plugin list failed" >&2; exit 2 ;;
    esac
  done
  clean_legacy
  if [ "$LEGACY_FOUND" -eq 1 ]; then say "check: action-needed"; exit 1; fi
  say "check: current"
  exit 0
fi

for c in "${CLIS[@]}"; do
  if [ "$UNINSTALL" -eq 1 ]; then uninstall_cli "$c"; else install_cli "$c"; fi
done
clean_legacy

if [ "$DRY_RUN" -eq 1 ]; then
  say "Dry run: nothing changed."
elif [ "$UNINSTALL" -eq 1 ]; then
  say "Done. Feature-Crew is uninstalled."
else
  say "Done. Start a new Claude Code or Copilot CLI session to load the plugin."
  say "Describe your need naturally in any project; slash commands are optional."
  say "Available: /fc-build-or-fix, /fc-brainstorm, /fc-debug, /fc-explain, /fc-grill-me, /fc-research,"
  say "/fc-review, /fc-second-opinion, /fc-ship, /fc-update - or delegate to an fc-* subagent."
fi
