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

HELP='Usage: install.sh / install.ps1 [--dry-run] [--check] [--uninstall] [--prefix DIR] [--source SRC]
Installs or updates the Feature-Crew plugin in each of Claude Code and GitHub Copilot CLI found on
PATH, then removes an old script install from the --prefix folder (default ~/.claude).
  --dry-run     print every command and removal, change nothing
  --check       read-only: report plugin state and old files; exit 0 current, 1 action needed, 2 error
  --uninstall   remove the plugin from each CLI and the old install
  --prefix DIR  old install location
  --source SRC  plugin marketplace source (default D0n9X1n/feature-crew)
install.ps1 also accepts -DryRun, -Check, -Uninstall, -Prefix DIR, -Source SRC, -Help.
Old fc-* agents and skills are removed even when edited: they would run instead of the plugin.
Older files are removed only when published.sha256 proves Feature-Crew wrote them.'

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
    -h|--help) printf '%s\n' "$HELP"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ "$CHECK" -eq 1 ] && [ $((DRY_RUN + UNINSTALL)) -gt 0 ]; then
  echo "--check cannot be combined with --dry-run or --uninstall" >&2
  exit 2
fi

# A local --source is registered as an absolute path, so a rerun from anywhere matches it.
if [ -d "$SOURCE" ]; then SOURCE="$(CDPATH= cd "$SOURCE" && pwd)"; fi
# Resolve the prefix too, so a trailing / or /. on a linked prefix cannot hide
# the link from linked_dir.
if [ -d "$PREFIX" ]; then
  resolved="$(CDPATH= cd "$PREFIX" 2>/dev/null && pwd)" || { echo "feature-crew: cannot read $PREFIX" >&2; exit 2; }
  PREFIX="$resolved"
else
  while :; do
    case "$PREFIX" in */.) PREFIX="${PREFIX%/.}" ;; ?*/) PREFIX="${PREFIX%/}" ;; *) break ;; esac
  done
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
# One object per line, so a match never spans two entries. Every CLI call runs
# from /, because a project's .claude/settings.json changes what both CLIs list.
listing() { # cli, marketplace|plugin
  local out
  if [ "$2" = marketplace ]; then
    out="$(cd / && "$1" plugin marketplace list --json 2>/dev/null)" || return 1
  else
    out="$(cd / && "$1" plugin list --json 2>/dev/null)" || return 1
  fi
  printf '%s' "$out" | tr -d '\r\n' | tr '}' '\n'
}

# absent, same (registered from exactly --source), or other; nonzero if the listing failed.
marketplace_state() {
  local rows row src="${SOURCE//\\/\\\\}"
  rows="$(listing "$1" marketplace)" || return 1
  row="$(printf '%s\n' "$rows" | grep -E '"name": *"feature-crew"' | head -1 | sed -E 's/": *"/": "/g' || true)"
  if [ -z "$row" ]; then echo absent; return 0; fi
  case "$row" in
    *"\"path\": \"$src\""*|*"\"repo\": \"$src\""*|*"\"url\": \"$src\""*) echo same ;;
    *"\"source\": \"Local: $src\""*|*"\"source\": \"GitHub: $src\""*|*"\"source\": \"URL: $src\""*) echo same ;;
    *) echo other ;;
  esac
}

# absent, disabled, or enabled: only feature-crew from the feature-crew marketplace,
# and in Claude Code only the user-scope install. Only "enabled": true is enabled.
plugin_state() {
  local rows row
  rows="$(listing "$1" plugin)" || return 1
  if [ "$1" = claude ]; then
    row="$(printf '%s\n' "$rows" | grep -E '"id": *"feature-crew@feature-crew"' | grep -E '"scope": *"user"' | head -1 || true)"
  else
    row="$(printf '%s\n' "$rows" | grep -E '"name": *"feature-crew"' | grep -E '"marketplace": *"feature-crew"' | head -1 || true)"
  fi
  if [ -z "$row" ]; then echo absent
  elif [[ "$row" =~ \"enabled\":[[:space:]]*true([^[:alnum:]_]|$) ]]; then echo enabled
  else echo disabled; fi
}

# Claude Code installs per scope; this installer manages the user scope only.
scope_args() { if [ "$1" = claude ]; then printf '%s\n' --scope user; fi; }

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
    (cd / && "$@")
  fi
}

# A marketplace from another source is replaced, never updated. Claude Code
# replaces it in user settings, and its plugin follows; other scopes keep
# theirs. The old install is removed only after the CLI lists the plugin enabled.
install_cli() {
  local cli="$1" mp pl
  mp="$(marketplace_state "$cli")" || cli_failed "$cli"
  pl="$(plugin_state "$cli")" || cli_failed "$cli"
  if [ "$mp" = same ]; then
    step "$cli" plugin marketplace update "$MARKETPLACE" || cli_failed "$cli"
  else
    if [ "$mp" = other ] && [ "$cli" != claude ]; then
      if [ "$pl" != absent ]; then step "$cli" plugin uninstall "$PLUGIN_ID" || cli_failed "$cli"; fi
      step "$cli" plugin marketplace remove "$MARKETPLACE" || cli_failed "$cli"
    fi
    step "$cli" plugin marketplace add "$SOURCE" $(scope_args "$cli") || cli_failed "$cli"
    if [ "$DRY_RUN" -eq 1 ]; then pl=absent; else pl="$(plugin_state "$cli")" || cli_failed "$cli"; fi
  fi
  case "$pl" in
    enabled) step "$cli" plugin update "$PLUGIN_ID" $(scope_args "$cli") || cli_failed "$cli" ;;
    disabled)
      if [ "$cli" = claude ]; then
        step "$cli" plugin enable "$PLUGIN_ID" $(scope_args "$cli") || cli_failed "$cli"
        step "$cli" plugin update "$PLUGIN_ID" $(scope_args "$cli") || cli_failed "$cli"
      else
        step "$cli" plugin install "$PLUGIN_ID" $(scope_args "$cli") || cli_failed "$cli"
      fi ;;
    *) step "$cli" plugin install "$PLUGIN_ID" $(scope_args "$cli") || cli_failed "$cli" ;;
  esac
  if [ "$DRY_RUN" -eq 0 ]; then
    pl="$(plugin_state "$cli")" || cli_failed "$cli"
    [ "$pl" = enabled ] || cli_failed "$cli"
  fi
}

# Claude Code: remove the marketplace from user settings only. When only a
# project declares it, the CLI says not_configured and it stays for that project.
remove_user_marketplace() {
  local out
  if [ "$DRY_RUN" -eq 1 ]; then say "would run: claude plugin marketplace remove $MARKETPLACE --scope user --json"; return 0; fi
  say "run: claude plugin marketplace remove $MARKETPLACE --scope user --json"
  if out="$(cd / && claude plugin marketplace remove "$MARKETPLACE" --scope user --json 2>&1)"; then
    say "claude: marketplace removed from user settings"
  elif printf '%s' "$out" | grep -qE '"failureCode": *"not_configured"'; then
    say "claude: marketplace not in user settings; left for other scopes"
  else
    printf '%s\n' "$out" >&2; return 1
  fi
}

uninstall_cli() {
  local cli="$1" st
  st="$(plugin_state "$cli")" || cli_failed "$cli"
  if [ "$st" != absent ]; then step "$cli" plugin uninstall "$PLUGIN_ID" $(scope_args "$cli") || cli_failed "$cli"; fi
  st="$(marketplace_state "$cli")" || cli_failed "$cli"
  [ "$st" != absent ] || return 0
  if [ "$cli" = claude ]; then remove_user_marketplace || cli_failed "$cli"
  else step "$cli" plugin marketplace remove "$MARKETPLACE" || cli_failed "$cli"; fi
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
VALIDATE=0
KEPT=()
NOT_REMOVED=()
PLANNED=""
EMPTIED=""
legacy_remove() { # path; rm -rf removes a link itself, never its target
  LEGACY_FOUND=1
  PLANNED="$PLANNED$1"$'\n'
  if [ "$VALIDATE" -eq 1 ]; then
    check_removable "$1"
  elif [ "$CHECK" -eq 1 ]; then
    say "old file: $1"
  elif [ "$DRY_RUN" -eq 1 ]; then
    say "would remove: $1"
  elif rm -rf "$1" 2>/dev/null && [ ! -e "$1" ] && [ ! -L "$1" ]; then
    say "removed: $1"
  else
    NOT_REMOVED+=("$1")
  fi
}

may_empty() { # root, path under it: every folder from the path's parent up to root
  local d="${2%/*}"
  while :; do
    EMPTIED="$EMPTIED$d"$'\n'
    [ "$d" = "$1" ] && break
    d="${d%/*}"
  done
}

# True when DIR, a folder between it and the prefix, or the prefix itself is a
# link: nothing beneath it is removed, because that would reach outside the prefix.
linked_dir() {
  local d="$1"
  while [ -n "$d" ] && [ "$d" != / ]; do
    [ -L "$d" ] && return 0
    [ "$d" != "$PREFIX" ] || break
    [ "${d%/*}" != "$d" ] || break
    d="${d%/*}"
  done
  return 1
}

# Before any change (validate pass, --check, --dry-run) exit 2; once a run has
# changed something, list the path with the other leftovers instead (exit 1).
cannot() { # verb, path
  if [ "$VALIDATE" -eq 1 ] || [ "$CHECK" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    echo "feature-crew: cannot $1 $2" >&2
    exit 2
  fi
  NOT_REMOVED+=("$2")
}

# Under VALIDATE: prove a path can be read and removed, changing nothing.
check_removable() {
  local p="$1" d
  if [ -d "$p" ] && [ ! -L "$p" ]; then
    # find omits an unreadable start folder, but lists unreadable folders below it.
    { [ -r "$p" ] && [ -x "$p" ]; } || cannot read "$p"
    while IFS= read -r d; do { [ -r "$d" ] && [ -x "$d" ]; } || cannot read "$d"; done < <(find "$p" -type d 2>/dev/null)
    while IFS= read -r d; do [ -r "$d" ] || cannot read "$d"; done < <(find "$p" -type f 2>/dev/null)
    while IFS= read -r d; do [ -w "$d" ] || cannot remove "$d"; done < <(find "$p" -type d 2>/dev/null)
  elif [ ! -L "$p" ] && [ ! -r "$p" ]; then
    cannot read "$p"
  fi
  { [ -w "${p%/*}" ] && [ -x "${p%/*}" ]; } || cannot remove "$p"
}

# True when the prefix cannot be reached rather than missing. The OS tells the
# two apart ("Permission denied" vs "No such file"); probing PREFIX/. follows a
# link anywhere in the path, including the prefix itself.
prefix_unreachable() {
  case "$(LC_ALL=C ls -d -- "$PREFIX/." 2>&1 >/dev/null)" in *'ermission denied'*) return 0 ;; esac
  return 1
}

linked_old() { # path: an fc-* path in a linked folder still shadows the plugin
  LEGACY_FOUND=1
  [ "$VALIDATE" -eq 1 ] || say "kept (linked folder): $1"
}

old_skill_files() { # skill dir: its regular files, sorted
  (cd "$1" && find . -type f 2>/dev/null | sed 's#^\./##' | sort)
}

# Run twice: first under VALIDATE, which proves every path this run removes is
# readable and removable before any CLI or file changes (exit 2 otherwise).
clean_legacy() {
  local n p rel d
  KEPT=(); PLANNED=""; EMPTIED=""
  if prefix_unreachable; then cannot read "$PREFIX"; fi
  for d in "$PREFIX" "$PREFIX/agents" "$PREFIX/skills" "$PREFIX/agents/feature-crew"; do
    if [ -d "$d" ] && { [ ! -r "$d" ] || [ ! -x "$d" ]; }; then cannot read "$d"; fi
  done
  for n in "${LEGACY_FC_AGENTS[@]}"; do
    p="$PREFIX/agents/$n.md"
    if [ -e "$p" ] || [ -L "$p" ]; then
      if linked_dir "$PREFIX/agents"; then linked_old "$p"; else legacy_remove "$p"; fi
    fi
  done
  for n in "${LEGACY_FC_SKILLS[@]}"; do
    p="$PREFIX/skills/$n"
    if [ -e "$p" ] || [ -L "$p" ]; then
      if linked_dir "$PREFIX/skills"; then linked_old "$p"; else legacy_remove "$p"; fi
    fi
  done
  p="$PREFIX/feature-crew.sha256"
  if [ -e "$p" ] || [ -L "$p" ]; then
    if linked_dir "$PREFIX"; then linked_old "$p"; else legacy_remove "$p"; fi
  fi
  for n in "${LEGACY_OLD_AGENTS[@]}"; do
    p="$PREFIX/agents/feature-crew/$n.md"
    if [ -f "$p" ] && [ ! -L "$p" ] && ! linked_dir "$PREFIX/agents/feature-crew"; then
      if [ ! -r "$p" ]; then cannot read "$p"; continue; fi
      if published_file "$p" "agents/feature-crew/$n.md"; then legacy_remove "$p"; may_empty "$PREFIX/agents/feature-crew" "$p"; else KEPT+=("$p"); fi
    fi
  done
  for n in "${LEGACY_OLD_SKILLS[@]}"; do
    p="$PREFIX/skills/$n"
    if [ -d "$p" ] && ! linked_dir "$p"; then
      if ! { [ -r "$p" ] && [ -x "$p" ]; }; then cannot read "$p"; continue; fi
      while IFS= read -r d; do { [ -r "$d" ] && [ -x "$d" ]; } || cannot read "$d"; done < <(find "$p" -type d 2>/dev/null)
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        if [ ! -r "$p/$rel" ]; then cannot read "$p/$rel"; continue; fi
        if published_file "$p/$rel" "skills/$n/$rel"; then legacy_remove "$p/$rel"; may_empty "$p" "$p/$rel"; else KEPT+=("$p/$rel"); fi
      done < <(old_skill_files "$p")
    fi
  done
  if [ "$CHECK" -eq 0 ] || [ "$VALIDATE" -eq 1 ]; then remove_emptied; fi
  if [ "${#KEPT[@]}" -gt 0 ] && [ "$VALIDATE" -eq 0 ]; then
    for p in "${KEPT[@]}"; do say "kept (not ours): $p"; done
  fi
  # The checks cannot foresee every refusal (an immutable file, a lock); list
  # what is left and stop. Every step is safe to repeat, so a rerun finishes.
  if [ "${#NOT_REMOVED[@]}" -gt 0 ]; then
    for p in "${NOT_REMOVED[@]}"; do echo "feature-crew: not removed: $p" >&2; done
    echo "feature-crew: fix these and run again; every other step is done." >&2
    exit 1
  fi
}

# Remove only folders this run empties, deepest first; never one that was already empty.
remove_emptied() {
  local d e left
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] && [ ! -L "$d" ] || continue
    left=0
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      case $'\n'"$PLANNED" in *$'\n'"$e"$'\n'*) ;; *) left=1; break ;; esac
    done < <(find "$d" -mindepth 1 -maxdepth 1 2>/dev/null)
    [ "$left" -eq 0 ] || continue
    PLANNED="$PLANNED$d"$'\n'
    if [ "$VALIDATE" -eq 1 ]; then
      { [ -w "${d%/*}" ] && [ -x "${d%/*}" ]; } || cannot remove "$d"
    elif [ "$DRY_RUN" -eq 1 ]; then
      say "would remove: $d"
    else
      if rmdir "$d" 2>/dev/null; then say "removed: $d"; else NOT_REMOVED+=("$d"); fi
    fi
  done < <(printf '%s' "$EMPTIED" | awk 'NF' | sort -u | awk -F/ '{ print NF "\t" $0 }' | sort -t "$(printf '\t')" -k1,1nr -k2,2 | cut -f2-)
}

if [ "$UNINSTALL" -eq 1 ]; then
  say "feature-crew: uninstalling; old install at $PREFIX"
else
  say "feature-crew: plugin source $SOURCE; old install at $PREFIX"
fi

VALIDATE=1; clean_legacy; VALIDATE=0; LEGACY_FOUND=0

if [ "$CHECK" -eq 1 ]; then
  for c in "${CLIS[@]}"; do
    st="$(plugin_state "$c")" || { echo "feature-crew: $c plugin list failed" >&2; exit 2; }
    mp="$(marketplace_state "$c")" || { echo "feature-crew: $c marketplace list failed" >&2; exit 2; }
    case "$st" in
      enabled)
        if [ "$mp" = same ]; then say "$c: feature-crew installed"
        else say "$c: feature-crew installed from another source"; LEGACY_FOUND=1; fi ;;
      disabled) say "$c: feature-crew disabled"; LEGACY_FOUND=1 ;;
      *) say "$c: feature-crew missing"; LEGACY_FOUND=1 ;;
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
