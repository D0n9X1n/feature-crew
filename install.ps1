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

$AgentMeta = @{
  "pm.md"               = @("fc-pm", "Feature-Crew Product Manager: picks track (Trivial/Standard/Complex) and orchestrates the pipeline.")
  "architect.md"        = @("fc-architect", "Feature-Crew Architect: turns approved spec into a bounded implementation plan (<=500 lines).")
  "developer.md"        = @("fc-developer", "Feature-Crew Developer: implements one task TDD-style against an approved plan.")
  "qa-spec-reviewer.md" = @("fc-qa-spec", "Feature-Crew QA spec reviewer: verifies implementation matches approved spec (one-clue mode).")
  "qa-code-reviewer.md" = @("fc-qa-code", "Feature-Crew QA code reviewer: code-quality pass on a diff (one-clue mode).")
  "tech-lead.md"        = @("fc-tech-lead", "Feature-Crew Tech Lead: final cross-family review before merging Complex work.")
}

function Do-Or-Echo($msg, [scriptblock]$action) {
  if ($DryRun) { Write-Host "DRY-RUN: $msg" } else { & $action; Write-Host $msg }
}

function Ensure-Dir($p) {
  if (-not (Test-Path $p)) {
    Do-Or-Echo "mkdir $p" { New-Item -ItemType Directory -Path $p -Force | Out-Null }
  }
}

function Install-Agent($src, $dest, $name, $desc) {
  if ((Test-Path $dest) -and (-not $Force)) {
    Write-Host "skip (exists): $dest  [use -Force to overwrite]"; return
  }
  if ($DryRun) {
    Write-Host "DRY-RUN: install $src -> $dest  (name: $name)"; return
  }
  $body = Get-Content -Raw -Path $src
  $needFront = -not ($body -match '^\s*---\s*\r?\n')
  $front = if ($needFront) { "---`nname: $name`ndescription: $desc`n---`n`n" } else { "" }
  Set-Content -Path $dest -Value ($front + $body) -NoNewline
  Write-Host "installed: $dest"
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
    if (-not $meta) { $meta = @("fc-" + [IO.Path]::GetFileNameWithoutExtension($_.Name), "Feature-Crew agent.") }
    # Install flat under ~/.claude/agents/ with the fc-* name so they don't
    # collide with personal agents.
    $destFile = Join-Path $DestAgents ($meta[0] + ".md")
    Install-Agent $_.FullName $destFile $meta[0] $meta[1]
    $count++
  }

  $skillCount = 0
  if (Test-Path $SrcSkillsDir) {
    Get-ChildItem -Directory -Path $SrcSkillsDir | ForEach-Object {
      Copy-Tree $_.FullName (Join-Path $DestSkillsDir $_.Name)
      $skillCount++
    }
  }

  Write-Host ""
  Write-Host "Done. Installed $count agent file(s) and $skillCount skill(s)."
  Write-Host "Agents:  $DestAgents"
  Write-Host "Skills:  $DestSkillsDir"
}

function Uninstall-ClaudeGlobal {
  Write-Host "feature-crew: uninstalling from $Prefix"
  # Remove only our fc-* files; leave personal agents in the dir alone.
  Get-ChildItem -Path $SrcAgents -Filter *.md | ForEach-Object {
    $meta = $AgentMeta[$_.Name]
    if (-not $meta) { $meta = @("fc-" + [IO.Path]::GetFileNameWithoutExtension($_.Name), "Feature-Crew agent.") }
    $d = Join-Path $DestAgents ($meta[0] + ".md")
    if (Test-Path $d) {
      Do-Or-Echo "removed: $d" { Remove-Item -Force $d }
    } else { Write-Host "not present: $d" }
  }
  if (Test-Path $SrcSkillsDir) {
    Get-ChildItem -Directory -Path $SrcSkillsDir | ForEach-Object {
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
}

# --- Main dispatch (mirrors install.sh) ---

if ($Uninstall) {
  Uninstall-ClaudeGlobal
  exit 0
}

Install-ClaudeGlobal
