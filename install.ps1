# feature-crew installer for native Windows PowerShell.
# Mirrors install.sh — same flags, same behavior, same outputs.
# Prefers bash (Git Bash / WSL) when available so there's a single source of
# truth; falls back to a pure-PowerShell implementation otherwise.
#
# Usage:
#   .\install.ps1                           # install for Claude Code globally (~/.claude)
#   .\install.ps1 -Project DIR              # ALSO install into project DIR for Copilot
#   .\install.ps1 -Project DIR -CopilotOnly # skip global Claude install
#   .\install.ps1 -Force                    # overwrite existing files
#   .\install.ps1 -DryRun                   # print what would happen, change nothing
#   .\install.ps1 -Uninstall                # remove files this script installs
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

# --- Pure-PowerShell fallback (full feature parity with install.sh) ---

$SrcAgents     = Join-Path $ScriptDir "agents"
$SrcSkillsDir  = Join-Path $ScriptDir ".claude\skills"
$DestAgents    = Join-Path $Prefix "agents\feature-crew"
$DestSkillsDir = Join-Path $Prefix "skills"

$AgentMeta = @{
  "pm.md"               = @("fc-pm", "Feature-Crew Product Manager: picks track (Trivial/Standard/Complex) and orchestrates the pipeline.")
  "architect.md"        = @("fc-architect", "Feature-Crew Architect: turns approved spec into a bounded implementation plan (<=500 lines).")
  "developer.md"        = @("fc-developer", "Feature-Crew Developer: implements one task TDD-style against an approved plan.")
  "qa-spec-reviewer.md" = @("fc-qa-spec", "Feature-Crew QA spec reviewer: verifies implementation matches approved spec (one-clue mode).")
  "qa-code-reviewer.md" = @("fc-qa-code", "Feature-Crew QA code reviewer: code-quality pass on a diff (one-clue mode).")
  "tech-lead.md"        = @("fc-tech-lead", "Feature-Crew Tech Lead: final cross-family review before merging Complex work.")
}

$CopilotInstructions = @'
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
'@

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
    Install-Agent $_.FullName (Join-Path $DestAgents $_.Name) $meta[0] $meta[1]
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

function Install-Project($projPath) {
  if (-not (Test-Path $projPath)) {
    Write-Error "--Project path does not exist: $projPath"; exit 1
  }
  $proj = (Resolve-Path $projPath).Path
  Write-Host ""
  Write-Host "feature-crew: installing into project $proj (for Copilot)"

  $projRoot = Join-Path $proj ".feature-crew"
  Ensure-Dir (Join-Path $projRoot "agents")
  Ensure-Dir (Join-Path $projRoot ".claude\skills")
  Ensure-Dir (Join-Path $proj ".github")

  # Raw agent files (no Claude frontmatter — Copilot reads them as docs).
  Get-ChildItem -Path $SrcAgents -Filter *.md | ForEach-Object {
    $d = Join-Path (Join-Path $projRoot "agents") $_.Name
    if ((Test-Path $d) -and (-not $Force)) {
      Write-Host "skip (exists): $d  [use -Force to overwrite]"; return
    }
    if ($DryRun) {
      Write-Host "DRY-RUN: cp $($_.FullName) -> $d"
    } else {
      Copy-Item -Path $_.FullName -Destination $d -Force
      Write-Host "installed: $d"
    }
  }

  # Skills.
  if (Test-Path $SrcSkillsDir) {
    Get-ChildItem -Directory -Path $SrcSkillsDir | ForEach-Object {
      Copy-Tree $_.FullName (Join-Path $projRoot ".claude\skills\$($_.Name)")
    }
  }

  # AGENTS.md.
  $agentsDoc = Join-Path $ScriptDir "AGENTS.md"
  if (Test-Path $agentsDoc) {
    $d = Join-Path $projRoot "AGENTS.md"
    if ((Test-Path $d) -and (-not $Force)) {
      Write-Host "skip (exists): $d"
    } elseif ($DryRun) {
      Write-Host "DRY-RUN: cp $agentsDoc -> $d"
    } else {
      Copy-Item -Path $agentsDoc -Destination $d -Force
      Write-Host "installed: $d"
    }
  }

  # Copilot pointer file.
  $copilotMd = Join-Path $proj ".github\copilot-instructions.md"
  if ((Test-Path $copilotMd) -and (-not $Force)) {
    Write-Host "skip (exists): $copilotMd  [use -Force to overwrite]"
  } elseif ($DryRun) {
    Write-Host "DRY-RUN: write $copilotMd"
  } else {
    Set-Content -Path $copilotMd -Value $CopilotInstructions -NoNewline
    Write-Host "installed: $copilotMd"
  }

  Write-Host ""
  Write-Host "Done. Project-installed at $projRoot and $copilotMd"
}

function Uninstall-ClaudeGlobal {
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
}

function Uninstall-Project($projPath) {
  $proj = (Resolve-Path $projPath).Path
  Write-Host "feature-crew: uninstalling from project $proj"
  foreach ($p in @((Join-Path $proj ".feature-crew"), (Join-Path $proj ".github\copilot-instructions.md"))) {
    if (Test-Path $p) {
      Do-Or-Echo "removed: $p" { Remove-Item -Recurse -Force $p }
    } else { Write-Host "not present: $p" }
  }
}

# --- Main dispatch (mirrors install.sh) ---

if ($Uninstall) {
  if (-not $CopilotOnly) { Uninstall-ClaudeGlobal }
  if ($Project)          { Uninstall-Project $Project }
  exit 0
}

if (-not $CopilotOnly) { Install-ClaudeGlobal }
if ($Project)          { Install-Project $Project }
