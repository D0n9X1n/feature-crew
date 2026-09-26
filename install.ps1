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
#   .\install.ps1 --check                   # or -Check: read-only, report whether an update is needed
#   .\install.ps1 --verify                  # or -Verify: read-only, verify the install against this clone
#   .\install.ps1 --prefix DIR              # or -Prefix DIR: override ~/.claude
#   .\install.ps1 --help                    # or -Help / -h: show usage
# --check/--verify exit 0 when current/verified, 1 on any mismatch, 2 on an error.

[CmdletBinding(PositionalBinding=$false)]
param(
  [switch]$Force,
  [switch]$DryRun,
  [switch]$Uninstall,
  [switch]$Check,
  [switch]$Verify,
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
    "--check"     { $Check = $true }
    "--verify"    { $Verify = $true }
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
  Write-Host "                     [--check|-Check] [--verify|-Verify]"
  Write-Host "                     [--prefix DIR|-Prefix DIR] [--help|-Help|-h]"
  Write-Host "--check/--verify are read-only; exit 0 when current/verified, 1 on any mismatch, 2 on an error."
  exit 0
}
if (($Check -or $Verify) -and (($Check -and $Verify) -or $Force -or $DryRun -or $Uninstall)) {
  [Console]::Error.WriteLine("--check and --verify cannot be combined with each other, --force, --uninstall, or --dry-run")
  exit 2
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
  if ($Check)     { $bashArgs += "--check" }
  if ($Verify)    { $bashArgs += "--verify" }
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
$Manifest = Join-Path $Prefix "feature-crew.sha256"
$ManifestPresent = $false
$ManifestValid = $true
$ManifestEntries = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
$NextEntries = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
$RemovedRoots = New-Object 'System.Collections.Generic.List[string]'
$EmDash = [char]0x2014
$DryDirs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$PublishedHashes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$publishedTable = Join-Path $ScriptDir "published.sha256"
$PublishedUnreadable = $false
function Read-PublishedTable {
  foreach ($line in [IO.File]::ReadAllLines($publishedTable)) {
    [void]$PublishedHashes.Add($line)
  }
}
if (Test-Path -LiteralPath $publishedTable -PathType Leaf) {
  # -Check and -Verify report an unreadable table as an operational error
  # (Invoke-InstallCheck); every other mode stops on the read error, as before.
  if ($Check -or $Verify) {
    try { Read-PublishedTable } catch { $PublishedUnreadable = $true }
  } else {
    Read-PublishedTable
  }
}

# Map agent filename -> description. The subagent NAME is the filename without
# .md, so source and installed names cannot drift. Role frontmatter carries no
# model key: hard-gate dispatchers select an explicit override from artifact
# author provenance. Keep in sync with agent_meta() in install.sh.
$AgentMeta = @{
  "fc-pm.md"        = "Feature-Crew Product Manager role for the main session: selects Just Do It/Standard/Complex and runs /fc-build-or-fix. Never dispatch it as a subagent: it collects user approvals, and gate provenance is observed only one dispatch deep."
  "fc-architect.md" = "Feature-Crew Architect: turns an approved spec into a bounded implementation plan (<=500 lines). Dispatched by /fc-build-or-fix with the spec inline; not for ad-hoc design questions."
  "fc-developer.md" = "Feature-Crew Developer: implements one planned task TDD-style. Dispatched by /fc-build-or-fix with the task text inline; not for open-ended coding requests."
  "fc-qa-spec.md"   = "Feature-Crew QA spec reviewer: checks an implementation against its approved spec (one-clue mode). Dispatched by /fc-build-or-fix at a hard gate; for ad-hoc review use /fc-review."
  "fc-qa-code.md"   = "Feature-Crew QA code reviewer: reviews a diff in one-clue mode, spec and quality on Standard, quality only on Complex. Dispatched by /fc-build-or-fix at a hard gate; for ad-hoc review use /fc-review."
  "fc-tech-lead.md" = "Feature-Crew Tech Lead: final cross-family review of Complex work before merge. Dispatched by /fc-build-or-fix; for ad-hoc review use /fc-review."
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
# which is not necessarily PowerShell's current location. Join that location
# first, then collapse dot segments so roots match Get-ChildItem's FullName
# before taking a relative-path substring. Printed paths keep the given prefix.
function Resolve-AbsPath($p) {
  if (-not [IO.Path]::IsPathRooted($p)) {
    $p = Join-Path (Get-Location).ProviderPath $p
  }
  return [IO.Path]::GetFullPath($p)
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
  $skill = Split-Path -Leaf $srcDir
  Get-SortedChildren $srcDir -Recurse | ForEach-Object {
    $rel = $_.FullName.Substring($srcDir.Length).TrimStart('\','/').Replace('\','/')
    $d   = Join-Path $destDir $rel
    $manifestRel = 'skills/' + $skill + '/' + $rel
    if ((Test-Path -LiteralPath $d) -and (-not $Force)) {
      Write-Host "skip (exists): $d  [use --force to overwrite]"
      if (-not $DryRun -and $ManifestValid) {
        if ($ManifestEntries.ContainsKey($manifestRel)) {
          $NextEntries[$manifestRel] = $ManifestEntries[$manifestRel]
        } elseif (Test-SkillFileIsOurs $_.FullName $d $manifestRel) {
          $NextEntries[$manifestRel] = Get-Sha256Raw $d
        }
      }
      return
    }
    Ensure-Dir (Split-Path -Parent $d)
    if ($DryRun) {
      Write-Host "DRY-RUN: cp $($_.FullName) $d"
    } else {
      [IO.File]::Copy((Resolve-AbsPath $_.FullName), (Resolve-AbsPath $d), $true)
      if ($ManifestValid) { $NextEntries[$manifestRel] = Get-Sha256Raw $d }
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
    $skipped = (Test-Path -LiteralPath $destFile) -and (-not $Force)
    Install-Agent $_.FullName $destFile $name $meta
    if (-not $DryRun -and $ManifestValid) {
      $rel = 'agents/' + $name + '.md'
      if ($skipped -and $ManifestEntries.ContainsKey($rel)) {
        $NextEntries[$rel] = $ManifestEntries[$rel]
      } elseif (-not $skipped -or (Test-InstalledIsOurs $_.FullName $destFile $name $meta)) {
        $NextEntries[$rel] = Get-Sha256Raw $destFile
      }
    }
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
  Write-InstallManifest
  Remove-Legacy

  Write-Host ""
  Write-Host "Done. Installed $count agent file(s) and $skillCount skill(s)."
  Write-Host "Agents:  $DestAgents"
  Write-Host "Skills:  $DestSkillsDir"
  Write-Host ""
  Write-Host "Describe your need naturally in any project; slash commands are optional."
  Write-Host "Available: /fc-build-or-fix, /fc-brainstorm, /fc-debug, /fc-explain, /fc-grill-me, /fc-research,"
  Write-Host "/fc-review, /fc-second-opinion, /fc-ship, /fc-update - or delegate to an fc-* subagent."
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

function Get-Sha256Raw($path) {
  $stream = [IO.File]::OpenRead((Resolve-AbsPath $path))
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally { $stream.Dispose(); $sha.Dispose() }
}

function Read-InstallManifest {
  $script:ManifestPresent = Test-Path -LiteralPath $Manifest
  if (-not $ManifestPresent) { return }
  if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
    $script:ManifestValid = $false
    return
  }
  $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Resolve-AbsPath $Manifest)))
  if ($text.Length -eq 0) { return }
  $lines = $text.Split([char]10)
  for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]
    if ($i -eq $lines.Length - 1 -and $line.Length -eq 0) { break }
    if ($line -cnotmatch '^[0-9a-f]{64}  (agents|skills)/.+$' -or
        $line.Contains("`r") -or $line.Contains('\') -or $line -match '/\.\.(/|$)') {
      $script:ManifestValid = $false
      $ManifestEntries.Clear()
      return
    }
    $ManifestEntries[$line.Substring(66)] = $line.Substring(0, 64)
  }
}

# A recorded mismatch is an edit, even if its bytes match an older release.
function Test-HistoricalFileIsOurs($file, $relativePath) {
  if ($ManifestEntries.ContainsKey($relativePath)) {
    return ((Get-Sha256Raw $file) -ceq $ManifestEntries[$relativePath])
  }
  return (Test-PublishedFile $file $relativePath)
}

function Test-SkillFileIsOurs($src, $dest, $relativePath) {
  if (-not (Test-Path -LiteralPath $src -PathType Leaf) -or
      -not (Test-Path -LiteralPath $dest -PathType Leaf)) { return $false }
  $expected = [IO.File]::ReadAllBytes((Resolve-AbsPath $src))
  $actual = [IO.File]::ReadAllBytes((Resolve-AbsPath $dest))
  if (Test-BytesEqual $expected $actual) { return $true }
  return (Test-HistoricalFileIsOurs $dest $relativePath)
}

function Write-ManifestEntries {
  $paths = New-Object 'System.Collections.Generic.List[string]'
  foreach ($rel in $NextEntries.Keys) { $paths.Add($rel) }
  $paths.Sort([StringComparer]::Ordinal)
  $text = New-Object Text.StringBuilder
  foreach ($rel in $paths) {
    [void]$text.Append($NextEntries[$rel]).Append('  ').Append($rel).Append("`n")
  }
  $utf8 = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllBytes((Resolve-AbsPath $Manifest), $utf8.GetBytes($text.ToString()))
}

function Write-InstallManifest {
  if (-not $ManifestValid) {
    Write-Host "kept (not a Feature-Crew manifest): $Manifest"
  } elseif ($DryRun) {
    Write-Host "DRY-RUN: write $Manifest"
  } else {
    Write-ManifestEntries
    Write-Host "installed: $Manifest"
  }
}

function Update-UninstallManifest {
  if (-not $ManifestPresent) { return }
  if (-not $ManifestValid) {
    Write-Host "kept (not a Feature-Crew manifest): $Manifest"
    return
  }
  $NextEntries.Clear()
  foreach ($rel in $ManifestEntries.Keys) {
    if (-not (Test-Path -LiteralPath (Join-Path $Prefix $rel) -PathType Leaf)) { continue }
    $removed = $false
    foreach ($root in $RemovedRoots) {
      if ($rel -ceq $root -or $rel.StartsWith($root + '/', [StringComparison]::Ordinal)) {
        $removed = $true
        break
      }
    }
    if (-not $removed) { $NextEntries[$rel] = $ManifestEntries[$rel] }
  }
  if ($NextEntries.Count -eq 0) {
    if ($DryRun) {
      Write-Host "DRY-RUN: would remove $Manifest"
    } else {
      Remove-Item -LiteralPath $Manifest -Force
      Write-Host "removed: $Manifest"
    }
  } else {
    if (-not $DryRun) { Write-ManifestEntries }
    Write-Host "kept (records the files kept above): $Manifest"
  }
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

# Current generated bytes win; otherwise consult the recorded baseline first.
function Test-InstalledIsOurs($src, $dest, $name, $desc) {
  if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) { return $false }
  $expected = Get-AgentBytes $src $name $desc
  $actual = [IO.File]::ReadAllBytes((Resolve-AbsPath $dest))
  if (Test-BytesEqual $expected $actual) { return $true }
  return (Test-HistoricalFileIsOurs $dest ('agents/' + $name + '.md'))
}

function Uninstall-ClaudeGlobal {
  Write-Host "feature-crew: uninstalling from $Prefix"
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
      $RemovedRoots.Add('agents/' + $name + '.md')
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
      # Only files actually present matter; any unknown file protects the dir.
      $root = (Resolve-AbsPath $d).TrimEnd('\','/')
      $same = $true
      foreach ($f in @(Get-SortedChildren $d -Recurse)) {
        $rel = $f.FullName.Substring($root.Length).TrimStart('\','/').Replace('\','/')
        $source = Join-Path $_.FullName $rel
        $manifestRel = 'skills/' + $_.Name + '/' + $rel
        if (-not (Test-SkillFileIsOurs $source $f.FullName $manifestRel)) {
          $same = $false; break
        }
      }
      if ($same) {
        if ($DryRun) {
          Write-Host "DRY-RUN: would remove $d"
        } else {
          Remove-Item -LiteralPath $d -Recurse -Force
          Write-Host "removed: $d"
        }
        $RemovedRoots.Add('skills/' + $_.Name)
      } else {
        Write-Host "kept (yours $EmDash differs from what we install): $d"
      }
    }
  }
  Update-UninstallManifest
  Remove-Legacy
}

# --- Read-only -Check / -Verify (mirrors check_install in install.sh) ---
# Compare the prefix with what this clone would install, using the same
# ownership order as install and uninstall: current bytes, then the recorded
# baseline, then published hashes only when no baseline exists. Never create
# the prefix, rewrite the manifest, or clean anything up.

function Get-Sha256Bytes([byte[]]$bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally { $sha.Dispose() }
}

# A model key in role-agent frontmatter would bypass the dispatch-time
# selector. Only the leading --- block counts; body prose may say "model:".
function Test-AgentHasModelKey($path) {
  $lines = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Resolve-AbsPath $path))).Split([char]10)
  for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]
    if ($line.Length -gt 0 -and $line[$line.Length - 1] -eq [char]13) { $line = $line.Substring(0, $line.Length - 1) }
    if ($i -eq 0) {
      if (-not $line.Equals('---')) { return $false }
    } elseif ($line.Equals('---')) {
      return $false
    } elseif ($line.StartsWith('model:', [StringComparison]::Ordinal)) {
      return $true
    }
  }
  return $false
}

# Classify one expected file: current, outdated, uncertain, or missing.
function Get-CheckState($rel, $want) {
  $file = Join-Path $Prefix $rel
  if (-not (Test-Path -LiteralPath $file)) { return 'missing' }
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return 'uncertain' }
  if ((Get-Sha256Raw $file) -ceq $want) { return 'current' }
  if (Test-HistoricalFileIsOurs $file $rel) { return 'outdated' }
  return 'uncertain'
}

# Name a source path relative to the installer directory with forward slashes,
# as source_error does in install.sh, so both engines print the same line
# however each resolved its own directory.
function Get-SourceRelative($path) {
  $p = [string]$path
  $root = $ScriptDir + [IO.Path]::DirectorySeparatorChar
  if ($p.StartsWith($root, [StringComparison]::Ordinal)) { $p = $p.Substring($root.Length) }
  return $p.Replace([string][IO.Path]::DirectorySeparatorChar, '/')
}

# An unreadable source is an operational error, never a mismatch: report the
# path that failed, exactly as source_error does in install.sh.
function Read-Source($path, [scriptblock]$read) {
  try { & $read } catch { throw "cannot read installer source ($(Get-SourceRelative $path))" }
}

# Get-ChildItem lists an unreadable directory as empty when it filters without
# recursing, so probe with the .NET listing, which throws (source_list in install.sh).
function Get-SourceChildren($root, [switch]$Directories, [string]$Filter = '*') {
  Read-Source $root {
    [void][IO.Directory]::GetFileSystemEntries((Resolve-AbsPath $root))
    Get-SortedChildren $root -Directories:$Directories -Filter $Filter
  }
}

# Sets $script:CheckExitCode instead of returning it, so no stream can leak
# into the exit code: 0 current/verified, 1 mismatch, 2 error.
function Invoke-InstallCheck {
  if (-not (Test-Path -LiteralPath $SrcAgents -PathType Container)) {
    [Console]::Error.WriteLine("ERROR: cannot find agents/ next to the installer ($SrcAgents)")
    $script:CheckExitCode = 2
    return
  }
  if (-not $ManifestValid) {
    [Console]::Error.WriteLine("ERROR: not a Feature-Crew manifest (left untouched): $Manifest")
    $script:CheckExitCode = 2
    return
  }
  # The table was read at startup; the dispatch turns this into exit 2.
  if ($PublishedUnreadable) { throw "cannot read installer source ($(Get-SourceRelative $publishedTable))" }
  $found = @{}
  foreach ($kind in @('missing', 'outdated', 'uncertain', 'stale', 'model key')) {
    $found[$kind] = New-Object 'System.Collections.Generic.List[string]'
  }
  $expected = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
  $agents = 0; $agentsOk = 0; $skills = 0; $skillsOk = 0
  foreach ($src in @(Get-SourceChildren $SrcAgents -Filter '*.md')) {
    $meta = $AgentMeta[$src.Name]
    if (-not $meta) { $meta = "Feature-Crew agent." }
    $name = [IO.Path]::GetFileNameWithoutExtension($src.Name)
    $rel = 'agents/' + $name + '.md'
    $want = Read-Source $src.FullName { Get-Sha256Bytes (Get-AgentBytes $src.FullName $name $meta) }
    $expected[$rel] = $want
    $state = Get-CheckState $rel $want
    if ($state -ne 'current') { $found[$state].Add($rel) }
    $agents++
    $dest = Join-Path $Prefix $rel
    if ($Verify -and (Test-Path -LiteralPath $dest -PathType Leaf) -and (Test-AgentHasModelKey $dest)) {
      $found['model key'].Add($rel)
    } elseif ($state -eq 'current') {
      $agentsOk++
    }
  }
  if (Test-Path -LiteralPath $SrcSkillsDir -PathType Container) {
    foreach ($dir in @(Get-SourceChildren $SrcSkillsDir -Directories)) {
      # Walk before the SKILL.md test: an unreadable directory is an error, not a non-skill.
      $files = @(Read-Source $dir.FullName { Get-SortedChildren $dir.FullName -Recurse })
      if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName "SKILL.md") -PathType Leaf)) { continue }
      $skills++
      $skillOk = $true
      foreach ($file in $files) {
        $rel = 'skills/' + $dir.Name + '/' + $file.FullName.Substring($dir.FullName.Length).TrimStart('\','/').Replace('\','/')
        $want = Read-Source $file.FullName { Get-Sha256Raw $file.FullName }
        $expected[$rel] = $want
        $state = Get-CheckState $rel $want
        if ($state -ne 'current') { $found[$state].Add($rel); $skillOk = $false }
      }
      if ($skillOk) { $skillsOk++ }
    }
  }
  # fc-* entries this clone no longer ships linger; report them, never delete.
  if (Test-Path -LiteralPath $DestAgents -PathType Container) {
    foreach ($file in @(Get-SortedChildren $DestAgents)) {
      if ($file.Name -clike 'fc-*.md' -and
          -not (Test-Path -LiteralPath (Join-Path $SrcAgents $file.Name) -PathType Leaf)) {
        $found['stale'].Add('agents/' + $file.Name)
      }
    }
  }
  if (Test-Path -LiteralPath $DestSkillsDir -PathType Container) {
    foreach ($dir in @(Get-SortedChildren $DestSkillsDir -Directories)) {
      if ($dir.Name -clike 'fc-*' -and
          -not (Test-Path -LiteralPath (Join-Path (Join-Path $SrcSkillsDir $dir.Name) "SKILL.md") -PathType Leaf)) {
        $found['stale'].Add('skills/' + $dir.Name)
      }
    }
  }
  $paths = New-Object 'System.Collections.Generic.List[string]'
  foreach ($rel in $expected.Keys) { $paths.Add($rel) }
  $paths.Sort([StringComparer]::Ordinal)
  $text = New-Object Text.StringBuilder
  foreach ($rel in $paths) {
    [void]$text.Append($expected[$rel]).Append('  ').Append($rel).Append("`n")
  }
  $utf8 = New-Object Text.UTF8Encoding($false)
  $bytes = $utf8.GetBytes($text.ToString())
  if (-not $ManifestPresent) {
    $found['missing'].Add('feature-crew.sha256')
  } elseif (-not (Test-BytesEqual $bytes ([IO.File]::ReadAllBytes((Resolve-AbsPath $Manifest))))) {
    $found['outdated'].Add('feature-crew.sha256')
  }

  if ($Verify) { Write-Host "feature-crew: verifying $Prefix" } else { Write-Host "feature-crew: checking $Prefix" }
  $bad = 0
  foreach ($kind in @('missing', 'outdated', 'uncertain', 'stale', 'model key')) {
    $list = $found[$kind]
    $list.Sort([StringComparer]::Ordinal)
    foreach ($rel in $list) { Write-Host "${kind}: $rel" }
    if ($kind -ne 'stale') { $bad += $list.Count }
  }
  if ($Verify) {
    Write-Host "agents: $agentsOk/$agents verified"
    Write-Host "skills: $skillsOk/$skills verified"
    if ($bad -eq 0) { Write-Host "verify: ok" } else { Write-Host "verify: failed" }
  } elseif ($bad -eq 0) {
    Write-Host "check: current"
  } else {
    Write-Host "check: update-needed"
  }
  $script:CheckExitCode = [int]($bad -ne 0)
}

# --- Main dispatch (mirrors install.sh) ---

# Read-only modes: any operational failure exits 2, never 1.
if ($Check -or $Verify) {
  $CheckExitCode = 2
  try {
    Read-InstallManifest
    Invoke-InstallCheck
  } catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 2
  }
  exit $CheckExitCode
}
Read-InstallManifest
if ($Uninstall) {
  Uninstall-ClaudeGlobal
  exit 0
}

Install-ClaudeGlobal
exit 0
