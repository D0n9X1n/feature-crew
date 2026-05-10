# feature-crew installer for native Windows PowerShell.
# Thin wrapper that prefers bash (Git Bash / WSL) when available; otherwise
# performs the same install in pure PowerShell.
#
# Usage:
#   .\install.ps1
#   .\install.ps1 -Force
#   .\install.ps1 -DryRun
#   .\install.ps1 -Uninstall
#   .\install.ps1 -Prefix C:\Users\me\.claude

[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$DryRun,
  [switch]$Uninstall,
  [string]$Prefix = (Join-Path $HOME ".claude"),
  [string]$Project = "",
  [switch]$CopilotOnly
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
  if ($Project)      { $args += @("--project", $Project) }
  if ($CopilotOnly)  { $args += "--copilot-only" }
  & bash (Join-Path $ScriptDir "install.sh") @args
  exit $LASTEXITCODE
}

if ($Project -or $CopilotOnly) {
  Write-Error "Native PowerShell fallback does not yet support --Project / --CopilotOnly. Install Git Bash or WSL and re-run."
  exit 1
}

# --- Pure-PowerShell fallback ---

$SrcAgents = Join-Path $ScriptDir "agents"
$SrcSkillsDir = Join-Path $ScriptDir ".claude\skills"
$DestAgents = Join-Path $Prefix "agents\feature-crew"
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

if ($Uninstall) {
  Write-Host "feature-crew: uninstalling from $Prefix"
  if (Test-Path $DestAgents) {
    Do-Or-Echo "removed: $DestAgents" { Remove-Item -Recurse -Force $DestAgents }
  } else { Write-Host "not present: $DestAgents" }
  if (Test-Path $SrcSkillsDir) {
    Get-ChildItem -Directory -Path $SrcSkillsDir | ForEach-Object {
      $d = Join-Path $DestSkillsDir $_.Name
      if (Test-Path $d) {
        Do-Or-Echo "removed: $d" { Remove-Item -Recurse -Force $d }
      } else { Write-Host "not present: $d" }
    }
  }
  exit 0
}

if (-not (Test-Path $SrcAgents)) {
  Write-Error "Cannot find agents/ next to install.ps1 ($SrcAgents)"; exit 1
}

Write-Host "feature-crew: installing into $Prefix"
Ensure-Dir $DestAgents

$count = 0
Get-ChildItem -Path $SrcAgents -Filter *.md | ForEach-Object {
  $src  = $_.FullName
  $base = $_.Name
  $dest = Join-Path $DestAgents $base
  if ((Test-Path $dest) -and (-not $Force)) {
    Write-Host "skip (exists): $dest  [use -Force to overwrite]"
    return
  }
  $meta = $AgentMeta[$base]
  if (-not $meta) { $meta = @("fc-" + [IO.Path]::GetFileNameWithoutExtension($base), "Feature-Crew agent.") }
  $name = $meta[0]; $desc = $meta[1]
  if ($DryRun) {
    Write-Host "DRY-RUN: install $src -> $dest  (name: $name)"
  } else {
    $body = Get-Content -Raw -Path $src
    $needFront = -not ($body -match '^\s*---\s*\r?\n')
    $front = if ($needFront) { "---`nname: $name`ndescription: $desc`n---`n`n" } else { "" }
    Set-Content -Path $dest -Value ($front + $body) -NoNewline
    Write-Host "installed: $dest"
  }
  $count++
}

# Skills copy — install every directory under .claude/skills/.
$skillCount = 0
if (Test-Path $SrcSkillsDir) {
  Get-ChildItem -Directory -Path $SrcSkillsDir | ForEach-Object {
    $skillSrc = $_.FullName
    $skillDest = Join-Path $DestSkillsDir $_.Name
    Ensure-Dir $skillDest
    Get-ChildItem -Recurse -File -Path $skillSrc | ForEach-Object {
      $rel = $_.FullName.Substring($skillSrc.Length).TrimStart('\','/')
      $d   = Join-Path $skillDest $rel
      if ((Test-Path $d) -and (-not $Force)) {
        Write-Host "skip (exists): $d  [use -Force to overwrite]"
        return
      }
      Ensure-Dir (Split-Path -Parent $d)
      if ($DryRun) {
        Write-Host "DRY-RUN: cp $($_.FullName) -> $d"
      } else {
        Copy-Item -Path $_.FullName -Destination $d -Force
        Write-Host "installed: $d"
      }
    }
    $skillCount++
  }
}

Write-Host ""
Write-Host "Done. Installed $count agent file(s) and $skillCount skill(s)."
Write-Host "Agents:  $DestAgents"
Write-Host "Skills:  $DestSkillsDir"
