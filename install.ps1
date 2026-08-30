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

# Map agent filename -> description. The subagent NAME is the filename without
# .md, so source and installed names cannot drift. Role frontmatter carries no
# model key: hard-gate dispatchers select an explicit override from artifact
# author provenance. Keep in sync with agent_meta() in install.sh.
$AgentMeta = @{
  "fc-pm.md"        = "Feature-Crew Product Manager: selects Just Do It/Standard/Complex and orchestrates the pipeline."
  "fc-architect.md" = "Feature-Crew Architect: turns approved spec into a bounded implementation plan (<=500 lines)."
  "fc-developer.md" = "Feature-Crew Developer: implements one task TDD-style against an approved plan."
  "fc-qa-spec.md"   = "Feature-Crew QA spec reviewer: verifies implementation matches approved spec (one-clue mode)."
  "fc-qa-code.md"   = "Feature-Crew QA code reviewer: code-quality pass on a diff (one-clue mode)."
  "fc-tech-lead.md" = "Feature-Crew Tech Lead: final cross-family review before merging Complex work."
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

function Install-Agent($src, $dest, $name, $desc) {
  if ((Test-Path $dest) -and (-not $Force)) {
    Write-Host "skip (exists): $dest  [use -Force to overwrite]"; return
  }
  if ($DryRun) {
    Write-Host "DRY-RUN: install $src -> $dest  (name: $name)"; return
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
    # Description is quoted: role descriptions contain ": ", which a plain YAML
    # scalar may not. Keep in sync with install.sh.
    $front = "---`nname: $name`ndescription: `"$desc`"`n---`n`n"
  }
  [IO.File]::WriteAllText((Resolve-AbsPath $dest), ($front + $body), (New-Object System.Text.UTF8Encoding($false)))
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
    if (-not $meta) { $meta = "Feature-Crew agent." }
    $name = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    # Flat under ~/.claude/agents/ so they don't collide with personal agents.
    $destFile = Join-Path $DestAgents ($name + ".md")
    Install-Agent $_.FullName $destFile $name $meta
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
  Write-Host "Describe your need naturally in any project; slash commands are optional."
  Write-Host "Available: /fc-build-or-fix, /fc-brainstorm, /fc-grill-me, /fc-research,"
  Write-Host "/fc-review, /fc-second-opinion, /fc-update - or delegate to an fc-* subagent."
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
# SHA-256 of every SKILL.md this project has ever published under the legacy
# unprefixed names, hashed after normalizing CRLF to LF. Keep in sync with
# legacy_hashes() in install.sh.
#
# Exact content identity, not a description prefix. Three prior attempts each
# destroyed user data a different way: no check at all, a whole-file grep for
# "feature-crew", then a description prefix. Prefix matching cannot answer
# "did we write this file"; a hash can.
$LegacyHashes = @{
  "build-or-fix" = @(
    "f11a81aff11703559827198e66f2d237d2bdab263ad43199e82972ec52d9cf72"  # v3.0, v3.1
    "13cd94d534d0ed87d2b8d4edbf9bc904761a92ef826780ed9d7138f7258cd808"  # v4.0
  )
  "research" = @(
    "e119bc4fe7ab4d528fd1fc2394a33e1aff6a7821be2182ae2903e1ecb925b94a"  # v3.1, v4.0
  )
}

function Get-Sha256Lf($path) {
  $bytes = [IO.File]::ReadAllBytes((Resolve-AbsPath $path))
  # Strip CR so a Windows checkout of a genuine legacy skill still matches.
  $lf = [byte[]]($bytes | Where-Object { $_ -ne 13 })
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    ($sha.ComputeHash($lf) | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally { $sha.Dispose() }
}

function Remove-LegacySkills {
  foreach ($old in @("build-or-fix", "research")) {
    $d = Join-Path $DestSkillsDir $old
    if (-not (Test-Path $d)) { continue }
    $f = Join-Path $d "SKILL.md"
    if (-not (Test-Path $f)) {
      Write-Host "kept (not ours - no SKILL.md): $d"; continue
    }
    $got = Get-Sha256Lf $f
    if ($LegacyHashes[$old] -notcontains $got) {
      Write-Host "kept (not ours - content does not match any published version): $d"
      Write-Host "  if this was an older Feature-Crew you edited, remove it by hand: $d"
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

# Is the installed file byte-identical to what we would install right now?
# Mirrors installed_is_ours() in install.sh.
function Test-InstalledIsOurs($src, $dest, $name, $desc) {
  if (-not (Test-Path $dest)) { return $false }
  $body = [IO.File]::ReadAllText((Resolve-AbsPath $src), [Text.Encoding]::UTF8)
  $needFront = -not ($body -match '^\s*---\s*\r?\n')
  $front = ""
  if ($needFront) {
    $front = "---`nname: $name`ndescription: `"$desc`"`n---`n`n"
  }
  $expected = $front + $body
  $actual = [IO.File]::ReadAllText((Resolve-AbsPath $dest), [Text.Encoding]::UTF8)
  return $expected -ceq $actual
}

function Uninstall-ClaudeGlobal {
  Write-Host "feature-crew: uninstalling from $Prefix"
  # Remove only files byte-identical to what we install. The fc- prefix makes a
  # collision unlikely, not impossible -- and install deliberately SKIPS a
  # pre-existing file, so deleting it here would destroy work the install path
  # just protected. Keep in sync with install.sh.
  Get-ChildItem -Path $SrcAgents -Filter *.md | ForEach-Object {
    $meta = $AgentMeta[$_.Name]
    if (-not $meta) { $meta = "Feature-Crew agent." }
    $name = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    $d = Join-Path $DestAgents ($name + ".md")
    if (-not (Test-Path $d)) {
      Write-Host "not present: $d"
    } elseif (Test-InstalledIsOurs $_.FullName $d $name $meta) {
      Do-Or-Echo "removed: $d" { Remove-Item -Force $d }
    } else {
      Write-Host "kept (yours - differs from what we install): $d"
    }
  }
  if (Test-Path $SrcSkillsDir) {
    Get-ChildItem -Directory -Path $SrcSkillsDir | ForEach-Object {
      # Only consider what we would have installed.
      if (-not (Test-Path (Join-Path $_.FullName "SKILL.md"))) { return }
      $d = Join-Path $DestSkillsDir $_.Name
      if (-not (Test-Path $d)) { Write-Host "not present: $d"; return }
      # Every file we ship must be present and identical, and the directory
      # must hold nothing else -- an extra file means the user put it there.
      $ours = @(Get-ChildItem -Recurse -File -Path $_.FullName)
      $theirs = @(Get-ChildItem -Recurse -File -Path $d)
      $same = ($ours.Count -eq $theirs.Count)
      if ($same) {
        foreach ($f in $ours) {
          $rel = $f.FullName.Substring($_.FullName.Length).TrimStart('\','/')
          $t = Join-Path $d $rel
          if (-not (Test-Path $t)) { $same = $false; break }
          $a = [IO.File]::ReadAllBytes((Resolve-AbsPath $f.FullName))
          $b = [IO.File]::ReadAllBytes((Resolve-AbsPath $t))
          if ($a.Length -ne $b.Length -or (Compare-Object $a $b -SyncWindow 0)) {
            $same = $false; break
          }
        }
      }
      if ($same) {
        Do-Or-Echo "removed: $d" { Remove-Item -Recurse -Force $d }
      } else {
        Write-Host "kept (yours - differs from what we install): $d"
      }
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
