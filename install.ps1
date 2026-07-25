# feature-crew installer for native Windows PowerShell.
# Mirrors install.sh — same flags, same behavior, same outputs.
# Prefers bash (Git Bash / WSL) when available so there's a single source of
# truth; falls back to a pure-PowerShell implementation otherwise.
#
# Usage:
#   .\install.ps1                           # install for Claude Code globally (~/.claude)
#   .\install.ps1 -Force                    # overwrite existing files
#   .\install.ps1 -DryRun                   # print what would happen, change nothing
#   .\install.ps1 -Uninstall                # remove files this script installs
#   .\install.ps1 -Prefix C:\Users\me\.claude

[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$DryRun,
  [switch]$Uninstall,
  [string]$Prefix = (Join-Path $HOME ".claude")
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Prefer bash if present — single source of truth.
$bash = Get-Command bash -ErrorAction SilentlyContinue
if ($bash) {
  $args = @()
  if ($Force)        { $args += "--force" }
  if ($DryRun)       { $args += "--dry-run" }
  if ($Uninstall)    { $args += "--uninstall" }
  if ($Prefix)       { $args += @("--prefix", $Prefix) }
  & bash (Join-Path $ScriptDir "install.sh") @args
  exit $LASTEXITCODE
}

# --- Pure-PowerShell fallback (full feature parity with install.sh) ---

$SrcAgents     = Join-Path $ScriptDir "agents"
$SrcSkillsDir  = Join-Path $ScriptDir ".claude\skills"
$DestAgents    = Join-Path $Prefix "agents"
$DestSkillsDir = Join-Path $Prefix "skills"

# Map agent filename -> (description, model). The subagent NAME is the filename
# without .md -- source files are fc-prefixed, so there is no mapping to keep in
# sync and no way for source and installed names to drift apart.
#
# The model field is what makes cross-family review structural rather than a
# rule the PM has to remember at dispatch time:
#   operate roles (pm, architect, developer) -> "", inherit the session model
#   review roles  (qa-spec, qa-code, tech-lead) -> sonnet, a different family
# Keep in sync with agent_meta() in install.sh.
$AgentMeta = @{
  "fc-pm.md"        = @("Feature-Crew Product Manager: picks track (Trivial/Standard/Complex) and orchestrates the pipeline.", "")
  "fc-architect.md" = @("Feature-Crew Architect: turns approved spec into a bounded implementation plan (<=500 lines).", "")
  "fc-developer.md" = @("Feature-Crew Developer: implements one task TDD-style against an approved plan.", "")
  "fc-qa-spec.md"   = @("Feature-Crew QA spec reviewer: verifies implementation matches approved spec (one-clue mode).", "sonnet")
  "fc-qa-code.md"   = @("Feature-Crew QA code reviewer: code-quality pass on a diff (one-clue mode).", "sonnet")
  "fc-tech-lead.md" = @("Feature-Crew Tech Lead: final cross-family review before merging Complex work.", "sonnet")
}

function Do-Or-Echo($msg, [scriptblock]$action) {
  if ($DryRun) { Write-Host "DRY-RUN: $msg" } else { & $action; Write-Host $msg }
}

function Ensure-Dir($p) {
  if (-not (Test-Path $p)) {
    Do-Or-Echo "mkdir $p" { New-Item -ItemType Directory -Path $p -Force | Out-Null }
  }
}

# [IO.File] resolves relative paths against the *process* working directory,
# which is not necessarily PowerShell's current location. Resolve to absolute
# first so a relative --prefix writes where the user expects.
function Resolve-AbsPath($p) {
  if ([IO.Path]::IsPathRooted($p)) { return $p }
  return (Join-Path (Get-Location).ProviderPath $p)
}

function Install-Agent($src, $dest, $name, $desc, $model) {
  if ((Test-Path $dest) -and (-not $Force)) {
    Write-Host "skip (exists): $dest  [use -Force to overwrite]"; return
  }
  if ($DryRun) {
    $m = if ($model) { ", model: $model" } else { "" }
    Write-Host "DRY-RUN: install $src -> $dest  (name: $name$m)"; return
  }
  # Explicit UTF-8, no BOM. PowerShell 5.1 defaults Get-Content/Set-Content to
  # the system ANSI code page, which silently mangles the en-dashes, em-dashes,
  # arrows, and U+2264 in the agent bodies on CJK code pages. install.sh copies
  # byte-for-byte via cat, so without this the two installers disagree -- and
  # the corruption is silent, producing agents that install "successfully".
  $body = [IO.File]::ReadAllText((Resolve-AbsPath $src), [Text.Encoding]::UTF8)
  $needFront = -not ($body -match '^\s*---\s*\r?\n')
  $front = ""
  if ($needFront) {
    $modelLine = if ($model) { "model: $model`n" } else { "" }
    # Description is quoted: role descriptions contain ": ", which a plain YAML
    # scalar may not. Keep in sync with install.sh.
    $front = "---`nname: $name`ndescription: `"$desc`"`n$modelLine---`n`n"
  }
  [IO.File]::WriteAllText((Resolve-AbsPath $dest), ($front + $body), (New-Object System.Text.UTF8Encoding($false)))
  $m = if ($model) { "  (model: $model)" } else { "" }
  Write-Host "installed: $dest$m"
}

# Copy a directory tree, file-by-file, honoring -Force / -DryRun.
function Copy-Tree($srcDir, $destDir, [bool]$preserveAgentFrontmatter = $false) {
  Ensure-Dir $destDir
  if (-not (Test-Path $srcDir)) { return }
  Get-ChildItem -Recurse -File -Path $srcDir | ForEach-Object {
    $rel = $_.FullName.Substring($srcDir.Length).TrimStart('\','/')
    $d   = Join-Path $destDir $rel
    if ((Test-Path $d) -and (-not $Force)) {
      Write-Host "skip (exists): $d  [use -Force to overwrite]"; return
    }
    Ensure-Dir (Split-Path -Parent $d)
    if ($DryRun) {
      Write-Host "DRY-RUN: cp $($_.FullName) -> $d"
    } else {
      Copy-Item -Path $_.FullName -Destination $d -Force
      Write-Host "installed: $d"
    }
  }
}

function Install-ClaudeGlobal {
  if (-not (Test-Path $SrcAgents)) {
    Write-Error "Cannot find agents/ next to install.ps1 ($SrcAgents)"; exit 1
  }
  Write-Host "feature-crew: installing into $Prefix"
  Ensure-Dir $DestAgents

  $count = 0
  Get-ChildItem -Path $SrcAgents -Filter *.md | ForEach-Object {
    $meta = $AgentMeta[$_.Name]
    if (-not $meta) { $meta = @("Feature-Crew agent.", "") }
    $name = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    # Flat under ~/.claude/agents/ so they don't collide with personal agents.
    $destFile = Join-Path $DestAgents ($name + ".md")
    Install-Agent $_.FullName $destFile $name $meta[0] $meta[1]
    $count++
  }

  $skillCount = 0
  if (Test-Path $SrcSkillsDir) {
    Get-ChildItem -Directory -Path $SrcSkillsDir | ForEach-Object {
      # A directory without SKILL.md is not a skill -- skip scratch dirs
      # rather than shipping them. Mirrored in install.sh.
      if (-not (Test-Path (Join-Path $_.FullName "SKILL.md"))) { return }
      Copy-Tree $_.FullName (Join-Path $DestSkillsDir $_.Name)
      $skillCount++
    }
  }
  Remove-LegacySkills

  Write-Host ""
  Write-Host "Done. Installed $count agent file(s) and $skillCount skill(s)."
  Write-Host "Agents:  $DestAgents"
  Write-Host "Skills:  $DestSkillsDir"
  Write-Host ""
  Write-Host "Use in any project: /fc-build-or-fix, /fc-brainstorm, /fc-grill-me,"
  Write-Host "/fc-research, /fc-review, /fc-second-opinion - or delegate to an fc-* subagent."
}

# Skills gained the fc- prefix in v5.0.0. Remove the unprefixed directories so
# an upgrade doesn't leave both installed and /build-or-fix still resolving.
#
# ONLY remove a directory we can prove we shipped. `research` and `build-or-fix`
# are plausible names for a user's own skill, and deleting one would destroy
# work with no prompt and no backup. Each candidate must carry both the exact
# legacy `name:` field and a Feature-Crew provenance marker; anything else is
# left alone and reported so the user can decide.
# Mirrors remove_legacy_skills() in install.sh.
function Remove-LegacySkills {
  foreach ($old in @("build-or-fix", "research")) {
    $d = Join-Path $DestSkillsDir $old
    if (-not (Test-Path $d)) { continue }
    $f = Join-Path $d "SKILL.md"
    if (-not (Test-Path $f)) {
      Write-Host "kept (not ours - no SKILL.md): $d"; continue
    }
    $body = [IO.File]::ReadAllText((Resolve-AbsPath $f), [Text.Encoding]::UTF8)
    if ($body -notmatch "(?m)^name: $([regex]::Escape($old))`$") {
      Write-Host "kept (not ours - name mismatch): $d"; continue
    }
    # Provenance: v3 build-or-fix says "Feature-Crew Pipeline"; v3 research
    # carries the audit-pair telemetry field. A user's own skill won't.
    if ($body -notmatch '(?i)feature-crew|audit-pair') {
      Write-Host "kept (not ours - no Feature-Crew marker): $d"
      Write-Host "  if this was v3 Feature-Crew, remove it by hand: $d"
      continue
    }
    if ($DryRun) {
      Write-Host "DRY-RUN: would remove (legacy skill): $d"
    } else {
      Remove-Item -Recurse -Force $d
      Write-Host "removed (legacy skill): $d"
    }
  }
}

function Uninstall-ClaudeGlobal {
  Write-Host "feature-crew: uninstalling from $Prefix"
  # Remove only our fc-* files; leave personal agents in the dir alone.
  Get-ChildItem -Path $SrcAgents -Filter *.md | ForEach-Object {
    $name = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    $d = Join-Path $DestAgents ($name + ".md")
    if (Test-Path $d) {
      Do-Or-Echo "removed: $d" { Remove-Item -Force $d }
    } else { Write-Host "not present: $d" }
  }
  if (Test-Path $SrcSkillsDir) {
    Get-ChildItem -Directory -Path $SrcSkillsDir | ForEach-Object {
      # Only remove what we would have installed.
      if (-not (Test-Path (Join-Path $_.FullName "SKILL.md"))) { return }
      $d = Join-Path $DestSkillsDir $_.Name
      if (Test-Path $d) {
        Do-Or-Echo "removed: $d" { Remove-Item -Recurse -Force $d }
      } else { Write-Host "not present: $d" }
    }
  }
  # Best-effort cleanup of legacy nested folder from older installer versions.
  $legacy = Join-Path $DestAgents "feature-crew"
  if (Test-Path $legacy) {
    Do-Or-Echo "removed (legacy): $legacy" { Remove-Item -Recurse -Force $legacy }
  }
  Remove-LegacySkills
}

# --- Main dispatch (mirrors install.sh) ---

if ($Uninstall) {
  Uninstall-ClaudeGlobal
  exit 0
}

Install-ClaudeGlobal
