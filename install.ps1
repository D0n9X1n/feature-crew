# feature-crew installer for native Windows PowerShell.
# Mirrors install.sh - same flags, same behavior, same outputs.
# Uses Git for Windows' bash found through git on PATH when present; otherwise
# uses the PowerShell implementation. Unrelated bash commands are never used.
#
# Usage:
#   .\install.ps1                           # install for Claude Code globally (~/.claude)
#   .\install.ps1 --force                   # or -Force: overwrite existing files
#   .\install.ps1 --dry-run                 # or -DryRun: print actions, change nothing
#   .\install.ps1 --uninstall               # or -Uninstall: remove installed files
#   .\install.ps1 --prefix DIR              # or -Prefix DIR: override ~/.claude
#   .\install.ps1 --help                    # or -Help / -h: show usage

[CmdletBinding(PositionalBinding=$false)]
param(
  [switch]$Force,
  [switch]$DryRun,
  [switch]$Uninstall,
  [Alias('h')][switch]$Help,
  [string]$Prefix = (Join-Path $HOME ".claude"),
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest = @()
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Typed PowerShell calls and -File bind GNU-style options differently. Parse
# any unbound tokens before dispatch so a switch can never become a prefix.
for ($i = 0; $i -lt $Rest.Count; $i++) {
  switch -CaseSensitive ($Rest[$i]) {
    "--force"     { $Force = $true }
    "--dry-run"   { $DryRun = $true }
    "--uninstall" { $Uninstall = $true }
    "--help"      { $Help = $true }
    "--prefix" {
      if ($i + 1 -ge $Rest.Count) {
        [Console]::Error.WriteLine("Missing value for --prefix")
        exit 2
      }
      $i++
      $Prefix = $Rest[$i]
    }
    default {
      [Console]::Error.WriteLine("Unknown option: $($Rest[$i])")
      exit 2
    }
  }
}
if ($Help) {
  Write-Host "Usage: .\install.ps1 [--force|-Force] [--dry-run|-DryRun] [--uninstall|-Uninstall]"
  Write-Host "                     [--prefix DIR|-Prefix DIR] [--help|-Help|-h]"
  exit 0
}

function Find-GitBash {
  $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $git) { return $null }
  $root = Split-Path -Parent (Split-Path -Parent $git.Path)
  # git lives in <root>/cmd, <root>/bin, or <root>/mingw64/bin.
  for ($level = 0; $level -lt 2 -and $root; $level++) {
    $candidate = Join-Path (Join-Path $root "bin") "bash.exe"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    $root = Split-Path -Parent $root
  }
  return $null
}

$gitBash = Find-GitBash
if ($gitBash) {
  $bashArgs = @()
  if ($Force)     { $bashArgs += "--force" }
  if ($DryRun)    { $bashArgs += "--dry-run" }
  if ($Uninstall) { $bashArgs += "--uninstall" }
  $bashArgs += @("--prefix", $Prefix)
  $bashExitCode = 127
  try {
    # PowerShell 5.1 can turn redirected native stderr into a terminating error
    # under Stop. Only launch failure or exit 126/127 should trigger fallback.
    $ErrorActionPreference = "Continue"
    & $gitBash (Join-Path $ScriptDir "install.sh") @bashArgs
    $bashExitCode = $LASTEXITCODE
  } catch {
    $bashExitCode = 127
  } finally {
    $ErrorActionPreference = "Stop"
  }
  if ($bashExitCode -ne 126 -and $bashExitCode -ne 127) {
    exit $bashExitCode
  }
  [Console]::Error.WriteLine("feature-crew: Git Bash could not run install.sh (exit $bashExitCode); using the PowerShell installer.")
}

# --- Pure-PowerShell fallback (full feature parity with install.sh) ---

$SrcAgents     = Join-Path $ScriptDir "agents"
$SrcSkillsDir  = Join-Path $ScriptDir ".claude\skills"
$DestAgents    = Join-Path $Prefix "agents"
$DestSkillsDir = Join-Path $Prefix "skills"
$EmDash = [char]0x2014
$DryDirs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$PublishedHashes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$publishedTable = Join-Path $ScriptDir "published.sha256"
if (Test-Path -LiteralPath $publishedTable -PathType Leaf) {
  foreach ($line in [IO.File]::ReadAllLines($publishedTable)) {
    [void]$PublishedHashes.Add($line)
  }
}

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

function Ensure-Dir($p) {
  if (Test-Path -LiteralPath $p -PathType Container) { return }
  if ($DryRun) {
    if ($DryDirs.Add($p)) { Write-Host "DRY-RUN: mkdir -p $p" }
  } else {
    [IO.Directory]::CreateDirectory((Resolve-AbsPath $p)) | Out-Null
  }
}

# Sort slash-separated relative paths with an ordinal comparer, not the host's
# culture. -Force includes hidden files just as find does in install.sh.
function Get-SortedChildren($dir, [switch]$Recurse, [switch]$Directories, [string]$Filter = '*') {
  $items = @(Get-ChildItem -LiteralPath $dir -Force -Recurse:$Recurse -Filter $Filter)
  $paths = New-Object 'System.Collections.Generic.List[string]'
  $byPath = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
  $root = (Resolve-AbsPath $dir).TrimEnd('\','/')
  foreach ($item in $items) {
    if ($item.PSIsContainer -ne [bool]$Directories) { continue }
    $rel = $item.FullName.Substring($root.Length).TrimStart('\','/').Replace('\','/')
    $paths.Add($rel)
    $byPath.Add($rel, $item)
  }
  $paths.Sort([StringComparer]::Ordinal)
  foreach ($rel in $paths) { $byPath[$rel] }
}

# [IO.File] resolves relative paths against the *process* working directory,
# which is not necessarily PowerShell's current location. Resolve to absolute
# first so a relative --prefix writes where the user expects.
function Resolve-AbsPath($p) {
  if ([IO.Path]::IsPathRooted($p)) { return $p }
  return (Join-Path (Get-Location).ProviderPath $p)
}

# Shared by install and ownership: never decode agent bodies. Text readers
# discard BOMs and can silently use the system ANSI code page in PowerShell 5.1.
function Get-AgentBytes($src, $name, $desc) {
  $body = [IO.File]::ReadAllBytes((Resolve-AbsPath $src))
  # Match install.sh's first-line predicate exactly: three dashes, LF or EOF.
  $hasFront = ($body.Length -ge 3 -and $body[0] -eq 45 -and $body[1] -eq 45 -and
    $body[2] -eq 45 -and ($body.Length -eq 3 -or $body[3] -eq 10))
  if ($hasFront) { return ,$body }
  # Quote descriptions containing ": " and encode only the new frontmatter.
  $front = "---`nname: $name`ndescription: `"$desc`"`n---`n`n"
  $utf8 = New-Object Text.UTF8Encoding($false)
  return ,([byte[]]($utf8.GetBytes($front) + $body))
}

function Test-BytesEqual([byte[]]$a, [byte[]]$b) {
  if ($a.Length -ne $b.Length) { return $false }
  for ($i = 0; $i -lt $a.Length; $i++) {
    if ($a[$i] -ne $b[$i]) { return $false }
  }
  return $true
}

function Install-Agent($src, $dest, $name, $desc) {
  if ((Test-Path -LiteralPath $dest) -and (-not $Force)) {
    Write-Host "skip (exists): $dest  [use --force to overwrite]"; return
  }
  if ($DryRun) {
    Write-Host "DRY-RUN: install $src -> $dest  (name: $name)"; return
  }
  [IO.File]::WriteAllBytes((Resolve-AbsPath $dest), (Get-AgentBytes $src $name $desc))
  Write-Host "installed: $dest"
}

# Copy a directory tree, file-by-file, honoring -Force / -DryRun.
function Copy-Tree($srcDir, $destDir) {
  Ensure-Dir $destDir
  if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) { return }
  Get-SortedChildren $srcDir -Recurse | ForEach-Object {
    $rel = $_.FullName.Substring($srcDir.Length).TrimStart('\','/')
    $d   = Join-Path $destDir $rel
    if ((Test-Path -LiteralPath $d) -and (-not $Force)) {
      Write-Host "skip (exists): $d  [use --force to overwrite]"; return
    }
    Ensure-Dir (Split-Path -Parent $d)
    if ($DryRun) {
      Write-Host "DRY-RUN: cp $($_.FullName) $d"
    } else {
      [IO.File]::Copy((Resolve-AbsPath $_.FullName), (Resolve-AbsPath $d), $true)
      Write-Host "installed: $d"
    }
  }
}

function Install-ClaudeGlobal {
  if (-not (Test-Path -LiteralPath $SrcAgents -PathType Container)) {
    [Console]::Error.WriteLine("Cannot find agents/ next to install.ps1 ($SrcAgents)"); exit 1
  }
  Write-Host "feature-crew: installing into $Prefix"
  Ensure-Dir $DestAgents

  $count = 0
  Get-SortedChildren $SrcAgents -Filter '*.md' | ForEach-Object {
    $meta = $AgentMeta[$_.Name]
    if (-not $meta) { $meta = "Feature-Crew agent." }
    $name = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    # Flat under ~/.claude/agents/ so they don't collide with personal agents.
    $destFile = Join-Path $DestAgents ($name + ".md")
    Install-Agent $_.FullName $destFile $name $meta
    $count++
  }

  $skillCount = 0
  if (Test-Path -LiteralPath $SrcSkillsDir -PathType Container) {
    Get-SortedChildren $SrcSkillsDir -Directories | ForEach-Object {
      # A directory without SKILL.md is not a skill -- skip scratch dirs
      # rather than shipping them. Mirrored in install.sh.
      if (-not (Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") -PathType Leaf)) { return }
      Copy-Tree $_.FullName (Join-Path $DestSkillsDir $_.Name)
      $skillCount++
    }
  }
  Remove-Legacy

  Write-Host ""
  Write-Host "Done. Installed $count agent file(s) and $skillCount skill(s)."
  Write-Host "Agents:  $DestAgents"
  Write-Host "Skills:  $DestSkillsDir"
  Write-Host ""
  Write-Host "Describe your need naturally in any project; slash commands are optional."
  Write-Host "Available: /fc-build-or-fix, /fc-brainstorm, /fc-grill-me, /fc-research,"
  Write-Host "/fc-review, /fc-second-opinion, /fc-update - or delegate to an fc-* subagent."
}

# Exact content identity, not a description prefix. Three prior attempts each
# destroyed user data a different way: no check at all, a whole-file grep for
# "feature-crew", then a description prefix. Prefix matching cannot answer
# "did we write this file"; a hash can, but only for that file, not neighbours.
# published.sha256 is regenerated from the tagged installers by T43. Missing
# table means nothing is recognized; edited and unknown files stay untouched.

function Get-Sha256Lf($path) {
  $bytes = [IO.File]::ReadAllBytes((Resolve-AbsPath $path))
  # Strip CR so a Windows checkout of a genuine legacy skill still matches.
  $lf = [byte[]]@($bytes | Where-Object { $_ -ne 13 })
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    ($sha.ComputeHash($lf) | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally { $sha.Dispose() }
}

function Test-PublishedFile($file, $relativePath) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $false }
  return $PublishedHashes.Contains((Get-Sha256Lf $file) + '  ' + $relativePath)
}

function Keep-Legacy($path) {
  Write-Host "kept (not ours $EmDash content does not match any published version): $path"
  Write-Host "  if this was an older Feature-Crew you edited, remove it by hand: $path"
}

function Remove-Legacy {
  foreach ($location in @('agents/feature-crew', 'skills/build-or-fix', 'skills/research')) {
    $dir = Join-Path $Prefix $location
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    if ($location -ne 'agents/feature-crew') {
      $skill = Join-Path $dir 'SKILL.md'
      if (-not (Test-Path -LiteralPath $skill -PathType Leaf)) {
        Write-Host "kept (not ours $EmDash no SKILL.md): $dir"; continue
      }
      if (-not (Test-PublishedFile $skill ($location + '/SKILL.md'))) {
        Keep-Legacy $dir; continue
      }
    }
    $root = (Resolve-AbsPath $dir).TrimEnd('\','/')
    foreach ($file in @(Get-SortedChildren $dir -Recurse)) {
      $rel = $file.FullName.Substring($root.Length).TrimStart('\','/').Replace('\','/')
      $path = Join-Path $dir $rel
      if (Test-PublishedFile $path ($location + '/' + $rel)) {
        if ($DryRun) {
          Write-Host "DRY-RUN: would remove (legacy): $path"
        } else {
          Remove-Item -LiteralPath $path -Force
          Write-Host "removed (legacy): $path"
        }
      } else {
        Keep-Legacy $path
      }
    }
    if (-not $DryRun) {
      # Descendants follow their parent in ordinal order. Reverse that order
      # and remove only empty directories; never recurse over unknown files.
      $dirs = @(Get-SortedChildren $dir -Directories -Recurse)
      for ($i = $dirs.Count - 1; $i -ge 0; $i--) {
        $path = $dirs[$i].FullName
        if (@(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) {
          [IO.Directory]::Delete((Resolve-AbsPath $path))
        }
      }
      if (@(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) {
        [IO.Directory]::Delete((Resolve-AbsPath $dir))
      }
    }
  }
}

# Is the installed file byte-identical to what we would install right now?
# Mirrors installed_is_ours() in install.sh.
function Test-InstalledIsOurs($src, $dest, $name, $desc) {
  if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) { return $false }
  $expected = Get-AgentBytes $src $name $desc
  $actual = [IO.File]::ReadAllBytes((Resolve-AbsPath $dest))
  return (Test-BytesEqual $expected $actual)
}

function Uninstall-ClaudeGlobal {
  Write-Host "feature-crew: uninstalling from $Prefix"
  # Remove only files byte-identical to what we install. The fc- prefix makes a
  # collision unlikely, not impossible -- and install deliberately SKIPS a
  # pre-existing file, so deleting it here would destroy work the install path
  # just protected. Keep in sync with install.sh.
  Get-SortedChildren $SrcAgents -Filter '*.md' | ForEach-Object {
    $meta = $AgentMeta[$_.Name]
    if (-not $meta) { $meta = "Feature-Crew agent." }
    $name = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    $d = Join-Path $DestAgents ($name + ".md")
    if (-not (Test-Path -LiteralPath $d)) {
      Write-Host "not present: $d"
    } elseif (Test-InstalledIsOurs $_.FullName $d $name $meta) {
      if ($DryRun) {
        Write-Host "DRY-RUN: would remove $d"
      } else {
        Remove-Item -LiteralPath $d -Force
        Write-Host "removed: $d"
      }
    } else {
      Write-Host "kept (yours $EmDash differs from what we install): $d"
    }
  }
  if (Test-Path -LiteralPath $SrcSkillsDir -PathType Container) {
    Get-SortedChildren $SrcSkillsDir -Directories | ForEach-Object {
      # Only consider what we would have installed.
      if (-not (Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") -PathType Leaf)) { return }
      $d = Join-Path $DestSkillsDir $_.Name
      if (-not (Test-Path -LiteralPath $d -PathType Container)) { Write-Host "not present: $d"; return }
      # Every file we ship must be present and identical, and the directory
      # must hold nothing else -- an extra file means the user put it there.
      $ours = @(Get-SortedChildren $_.FullName -Recurse)
      $theirs = @(Get-SortedChildren $d -Recurse)
      $same = ($ours.Count -eq $theirs.Count)
      if ($same) {
        foreach ($f in $ours) {
          $rel = $f.FullName.Substring($_.FullName.Length).TrimStart('\','/')
          $t = Join-Path $d $rel
          if (-not (Test-Path -LiteralPath $t -PathType Leaf)) { $same = $false; break }
          $a = [IO.File]::ReadAllBytes((Resolve-AbsPath $f.FullName))
          $b = [IO.File]::ReadAllBytes((Resolve-AbsPath $t))
          if (-not (Test-BytesEqual $a $b)) {
            $same = $false; break
          }
        }
      }
      if ($same) {
        if ($DryRun) {
          Write-Host "DRY-RUN: would remove $d"
        } else {
          Remove-Item -LiteralPath $d -Recurse -Force
          Write-Host "removed: $d"
        }
      } else {
        Write-Host "kept (yours $EmDash differs from what we install): $d"
      }
    }
  }
  Remove-Legacy
}

# --- Main dispatch (mirrors install.sh) ---

if ($Uninstall) {
  Uninstall-ClaudeGlobal
  exit 0
}

Install-ClaudeGlobal
exit 0
