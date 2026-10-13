# feature-crew installer for native Windows PowerShell.
# Mirrors install.sh - same flags, same behavior, same outputs.
# Uses Git for Windows' bash found through git on PATH when present; otherwise
# uses the PowerShell implementation. Unrelated bash commands are never used.
#
# Usage:
#   .\install.ps1                  # or no flags: install or update the plugin in each CLI on PATH, then remove the old install
#   .\install.ps1 --dry-run        # or -DryRun: print every command and removal, change nothing
#   .\install.ps1 --check          # or -Check: read-only, report plugin state and old files
#   .\install.ps1 --uninstall      # or -Uninstall: remove the plugin from each CLI and the old install
#   .\install.ps1 --prefix DIR     # or -Prefix DIR: old install location (default ~/.claude)
#   .\install.ps1 --source SRC     # or -Source SRC: plugin marketplace source (default D0n9X1n/feature-crew)
#   .\install.ps1 --help           # or -Help / -h: show usage
# --check exits 0 when current, 1 when action is needed, 2 on an error.

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DryRun = $false
$Uninstall = $false
$Check = $false
$Help = $false
$Prefix = Join-Path $HOME ".claude"
$Source = "D0n9X1n/feature-crew"

# No param block: PowerShell would bind --prefix/--source itself and fail a
# missing value with exit 1 before this script runs. Parse every token here.
# GNU-style flags are case-sensitive; PowerShell-style ones are not.
$argv = @($args)
for ($i = 0; $i -lt $argv.Count; $i++) {
  $t = [string]$argv[$i]
  $k = if ($t.StartsWith("--")) { $t } else { $t.ToLowerInvariant() }
  switch -CaseSensitive ($k) {
    { $_ -in @("--dry-run", "-dryrun") }     { $DryRun = $true; break }
    { $_ -in @("--uninstall", "-uninstall") } { $Uninstall = $true; break }
    { $_ -in @("--check", "-check") }         { $Check = $true; break }
    { $_ -in @("--help", "-help", "-h") }     { $Help = $true; break }
    { $_ -in @("--prefix", "-prefix", "--source", "-source") } {
      if ($i + 1 -ge $argv.Count) { [Console]::Error.WriteLine("Missing value for $t"); exit 2 }
      $i++
      if ($k -like "*prefix") { $Prefix = [string]$argv[$i] } else { $Source = [string]$argv[$i] }
      break
    }
    default {
      [Console]::Error.WriteLine("Unknown option: $t")
      exit 2
    }
  }
}
if ($Help) {
  Write-Host "Usage: .\install.ps1 [--dry-run|-DryRun] [--check|-Check] [--uninstall|-Uninstall]"
  Write-Host "                     [--prefix DIR|-Prefix DIR] [--source SRC|-Source SRC] [--help|-Help|-h]"
  Write-Host "Installs the Feature-Crew plugin in each CLI on PATH, then removes the old script install."
  Write-Host "--check is read-only; exit 0 when current, 1 when action is needed, 2 on an error."
  exit 0
}
if ($Check -and ($DryRun -or $Uninstall)) {
  [Console]::Error.WriteLine("--check cannot be combined with --dry-run or --uninstall")
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
  if ($DryRun)    { $bashArgs += "--dry-run" }
  if ($Uninstall) { $bashArgs += "--uninstall" }
  if ($Check)     { $bashArgs += "--check" }
  $bashArgs += @("--prefix", $Prefix, "--source", $Source)
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

$PluginId = "feature-crew@feature-crew"
$Marketplace = "feature-crew"

# Every path an old script install wrote, from what tagged installers did
# (T77 regenerates these from v3.1-v5.3.1). Keep in sync with install.sh.
$LEGACY_FC_AGENTS = @("fc-architect", "fc-developer", "fc-pm", "fc-qa-code", "fc-qa-spec", "fc-tech-lead")
$LEGACY_FC_SKILLS = @("fc-brainstorm", "fc-build-or-fix", "fc-debug", "fc-explain", "fc-grill-me", "fc-research", "fc-review", "fc-second-opinion", "fc-ship", "fc-update")
$LEGACY_OLD_AGENTS = @("architect", "developer", "pm", "qa-code-reviewer", "qa-spec-reviewer", "tech-lead")
$LEGACY_OLD_SKILLS = @("build-or-fix", "research")

$PublishedHashes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$publishedTable = Join-Path $ScriptDir "published.sha256"
if (Test-Path -LiteralPath $publishedTable -PathType Leaf) {
  foreach ($line in [IO.File]::ReadAllLines($publishedTable)) { [void]$PublishedHashes.Add($line) }
}

$Clis = New-Object 'System.Collections.Generic.List[string]'
$CliPath = @{}
foreach ($c in @("claude", "copilot")) {
  $cmd = Get-Command $c -CommandType Application,ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { $Clis.Add($c); $CliPath[$c] = $cmd.Path }
}
if ($Clis.Count -eq 0) {
  [Console]::Error.WriteLine("feature-crew: neither claude nor copilot is on PATH; install Claude Code or GitHub Copilot CLI first.")
  exit 2
}

# [IO.File] resolves relative paths against the *process* working directory,
# which is not necessarily PowerShell's current location.
function Resolve-AbsPath($p) {
  if (-not [IO.Path]::IsPathRooted($p)) {
    $p = Join-Path (Get-Location).ProviderPath $p
  }
  return [IO.Path]::GetFullPath($p)
}

# The CLIs' own JSON listings are the only plugin state this script reads.
# 0 listed, 1 not listed, 2 the listing failed.
function Get-Listed($cli, $kind) {
  $ErrorActionPreference = "Continue"
  try {
    if ($kind -eq "marketplace") {
      $out = & $CliPath[$cli] plugin marketplace list --json 2>$null
    } else {
      $out = & $CliPath[$cli] plugin list --json 2>$null
    }
    $rc = $LASTEXITCODE
  } catch { return 2 }
  if ($rc -ne 0) { return 2 }
  $text = ($out | Out-String)
  if ($kind -eq "plugin" -and $cli -eq "claude") {
    if ($text -match '"id":\s*"feature-crew@feature-crew"') { return 0 }
  } elseif ($text -match '"name":\s*"feature-crew"') { return 0 }
  return 1
}

function Stop-Cli($cli) {
  [Console]::Error.WriteLine("feature-crew: $cli step failed; old files left in place.")
  exit 1
}

# Print, then run; under -DryRun only print.
function Invoke-Step($cli, [string[]]$stepArgs) {
  $line = "$cli " + ($stepArgs -join " ")
  if ($DryRun) { Write-Host "would run: $line"; return $true }
  Write-Host "run: $line"
  $ErrorActionPreference = "Continue"
  try {
    & $CliPath[$cli] @stepArgs | ForEach-Object { Write-Host $_ }
    $rc = $LASTEXITCODE
  } catch { $rc = 1 }
  return ($rc -eq 0)
}

function Install-Cli($cli) {
  switch (Get-Listed $cli "marketplace") {
    0 { $ok = Invoke-Step $cli @("plugin", "marketplace", "update", $Marketplace) }
    1 { $ok = Invoke-Step $cli @("plugin", "marketplace", "add", $Source) }
    default { $ok = $false }
  }
  if (-not $ok) { Stop-Cli $cli }
  switch (Get-Listed $cli "plugin") {
    0 { $ok = Invoke-Step $cli @("plugin", "update", $PluginId) }
    1 { $ok = Invoke-Step $cli @("plugin", "install", $PluginId) }
    default { $ok = $false }
  }
  if (-not $ok) { Stop-Cli $cli }
}

function Uninstall-Cli($cli) {
  $ok = $true
  switch (Get-Listed $cli "plugin") {
    0 { $ok = Invoke-Step $cli @("plugin", "uninstall", $PluginId) }
    1 { }
    default { $ok = $false }
  }
  if (-not $ok) { Stop-Cli $cli }
  switch (Get-Listed $cli "marketplace") {
    0 { $ok = Invoke-Step $cli @("plugin", "marketplace", "remove", $Marketplace) }
    1 { }
    default { $ok = $false }
  }
  if (-not $ok) { Stop-Cli $cli }
}

# Hash with CR stripped, so a Windows checkout of a genuine legacy file still matches.
function Get-Sha256Lf($path) {
  $bytes = [IO.File]::ReadAllBytes((Resolve-AbsPath $path))
  $lf = [byte[]]@($bytes | Where-Object { $_ -ne 13 })
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    ($sha.ComputeHash($lf) | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally { $sha.Dispose() }
}

function Test-PublishedFile($file, $relativePath) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $false }
  return $PublishedHashes.Contains((Get-Sha256Lf $file) + "  " + $relativePath)
}

function Test-Link($path) {
  $item = Get-Item -LiteralPath $path -Force
  return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

$script:LegacyFound = $false
$script:Kept = New-Object 'System.Collections.Generic.List[string]'
# Removes a link itself, never its target.
function Remove-Legacy($path) {
  $script:LegacyFound = $true
  if ($Check) { Write-Host "old file: $path"; return }
  if ($DryRun) { Write-Host "would remove: $path"; return }
  $abs = Resolve-AbsPath $path
  $item = Get-Item -LiteralPath $abs -Force
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    if ($item.PSIsContainer) { [IO.Directory]::Delete($abs) } else { [IO.File]::Delete($abs) }
  } elseif ($item.PSIsContainer) {
    Remove-Item -LiteralPath $abs -Recurse -Force
  } else {
    Remove-Item -LiteralPath $abs -Force
  }
  Write-Host "removed: $path"
}

# A skill dir's regular files, as slash-separated relative paths in ordinal order.
function Get-OldSkillFiles($dir) {
  $root = (Resolve-AbsPath $dir).TrimEnd('\', '/')
  $paths = New-Object 'System.Collections.Generic.List[string]'
  foreach ($item in @(Get-ChildItem -LiteralPath $dir -Recurse -Force -File)) {
    $paths.Add($item.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/'))
  }
  $paths.Sort([StringComparer]::Ordinal)
  return ,$paths
}

# Remove only directories the old install made and this run emptied.
function Remove-EmptyDirs($dir) {
  if (-not (Test-Path -LiteralPath $dir -PathType Container) -or (Test-Link $dir)) { return }
  $dirs = @(Get-ChildItem -LiteralPath $dir -Recurse -Force -Directory | Sort-Object { $_.FullName.Length } -Descending)
  $dirs += @(Get-Item -LiteralPath $dir -Force)
  foreach ($d in $dirs) {
    if (@(Get-ChildItem -LiteralPath $d.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $d.FullName -Force }
  }
}

function Clear-Legacy {
  $script:Kept.Clear()
  foreach ($n in $LEGACY_FC_AGENTS) {
    $p = "$Prefix/agents/$n.md"
    if (Test-Path -LiteralPath $p) { Remove-Legacy $p }
  }
  foreach ($n in $LEGACY_FC_SKILLS) {
    $p = "$Prefix/skills/$n"
    if (Test-Path -LiteralPath $p) { Remove-Legacy $p }
  }
  $p = "$Prefix/feature-crew.sha256"
  if (Test-Path -LiteralPath $p) { Remove-Legacy $p }
  foreach ($n in $LEGACY_OLD_AGENTS) {
    $p = "$Prefix/agents/feature-crew/$n.md"
    if ((Test-Path -LiteralPath $p -PathType Leaf) -and -not (Test-Link $p)) {
      if (Test-PublishedFile $p "agents/feature-crew/$n.md") { Remove-Legacy $p } else { $script:Kept.Add($p) }
    }
  }
  foreach ($n in $LEGACY_OLD_SKILLS) {
    $p = "$Prefix/skills/$n"
    if ((Test-Path -LiteralPath $p -PathType Container) -and -not (Test-Link $p)) {
      foreach ($rel in (Get-OldSkillFiles $p)) {
        if (Test-PublishedFile "$p/$rel" "skills/$n/$rel") { Remove-Legacy "$p/$rel" } else { $script:Kept.Add("$p/$rel") }
      }
    }
  }
  if (-not $Check -and -not $DryRun) {
    foreach ($n in $LEGACY_OLD_SKILLS) { Remove-EmptyDirs "$Prefix/skills/$n" }
    $p = "$Prefix/agents/feature-crew"
    if ((Test-Path -LiteralPath $p -PathType Container) -and -not (Test-Link $p) -and
        @(Get-ChildItem -LiteralPath $p -Force).Count -eq 0) { Remove-Item -LiteralPath $p -Force }
  }
  foreach ($p in $script:Kept) { Write-Host "kept (not ours): $p" }
}

if ($Uninstall) {
  Write-Host "feature-crew: uninstalling; old install at $Prefix"
} else {
  Write-Host "feature-crew: plugin source $Source; old install at $Prefix"
}

if ($Check) {
  foreach ($c in $Clis) {
    switch (Get-Listed $c "plugin") {
      0 { Write-Host "${c}: feature-crew installed" }
      1 { Write-Host "${c}: feature-crew missing"; $script:LegacyFound = $true }
      default { [Console]::Error.WriteLine("feature-crew: $c plugin list failed"); exit 2 }
    }
  }
  Clear-Legacy
  if ($script:LegacyFound) { Write-Host "check: action-needed"; exit 1 }
  Write-Host "check: current"
  exit 0
}

foreach ($c in $Clis) {
  if ($Uninstall) { Uninstall-Cli $c } else { Install-Cli $c }
}
Clear-Legacy

if ($DryRun) {
  Write-Host "Dry run: nothing changed."
} elseif ($Uninstall) {
  Write-Host "Done. Feature-Crew is uninstalled."
} else {
  Write-Host "Done. Start a new Claude Code or Copilot CLI session to load the plugin."
  Write-Host "Describe your need naturally in any project; slash commands are optional."
  Write-Host "Available: /fc-build-or-fix, /fc-brainstorm, /fc-debug, /fc-explain, /fc-grill-me, /fc-research,"
  Write-Host "/fc-review, /fc-second-opinion, /fc-ship, /fc-update - or delegate to an fc-* subagent."
}
exit 0
