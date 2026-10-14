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
$Prefix = Join-Path $HOME ".claude"
$Source = "D0n9X1n/feature-crew"

# No param block: PowerShell would bind --prefix/--source itself and fail a
# missing value with exit 1 before this script runs. Parse every token here.
# GNU-style flags are case-sensitive; PowerShell-style ones are not.
$HelpText = @'
Usage: install.sh / install.ps1 [--dry-run] [--check] [--uninstall] [--prefix DIR] [--source SRC]
Installs or updates the Feature-Crew plugin in each of Claude Code and GitHub Copilot CLI found on
PATH, then removes an old script install from the --prefix folder (default ~/.claude).
  --dry-run     print every command and removal, change nothing
  --check       read-only: report plugin state and old files; exit 0 current, 1 action needed, 2 error
  --uninstall   remove the plugin from each CLI and the old install
  --prefix DIR  old install location
  --source SRC  plugin marketplace source (default D0n9X1n/feature-crew)
install.ps1 also accepts -DryRun, -Check, -Uninstall, -Prefix DIR, -Source SRC, -Help.
Old fc-* agents and skills are removed even when edited: they would run instead of the plugin.
Older files are removed only when published.sha256 proves Feature-Crew wrote them.
'@
$argv = @($args)
for ($i = 0; $i -lt $argv.Count; $i++) {
  $t = [string]$argv[$i]
  $k = if ($t.StartsWith("--")) { $t } else { $t.ToLowerInvariant() }
  switch -CaseSensitive ($k) {
    { $_ -in @("--dry-run", "-dryrun") }     { $DryRun = $true; break }
    { $_ -in @("--uninstall", "-uninstall") } { $Uninstall = $true; break }
    { $_ -in @("--check", "-check") }         { $Check = $true; break }
    { $_ -in @("--help", "-help", "-h") }     { Write-Host $HelpText; exit 0 }
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
if ($Check -and ($DryRun -or $Uninstall)) {
  [Console]::Error.WriteLine("--check cannot be combined with --dry-run or --uninstall")
  exit 2
}
# A local -Source is registered as an absolute path, so a rerun from anywhere matches it.
if (Test-Path -LiteralPath $Source -PathType Container) { $Source = (Resolve-Path -LiteralPath $Source).ProviderPath }

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
# One object per entry, so a match never spans two entries; $null if the listing failed.
# Every CLI call runs from the filesystem root, because a project's
# .claude/settings.json changes what both CLIs list.
$NeutralDir = [IO.Path]::GetPathRoot([IO.Path]::GetTempPath())

function Get-Listing($cli, $kind) {
  $ErrorActionPreference = "Continue"
  Push-Location -LiteralPath $NeutralDir
  try {
    if ($kind -eq "marketplace") {
      $out = & $CliPath[$cli] plugin marketplace list --json 2>$null
    } else {
      $out = & $CliPath[$cli] plugin list --json 2>$null
    }
    $rc = $LASTEXITCODE
  } catch { return $null } finally { Pop-Location }
  if ($rc -ne 0) { return $null }
  return ,@((($out | Out-String) -replace "[`r`n]", "") -split '}')
}

# absent, same (registered from exactly -Source), or other; $null if the listing failed.
function Get-MarketplaceState($cli) {
  $rows = Get-Listing $cli "marketplace"
  if ($null -eq $rows) { return $null }
  $row = @($rows | Where-Object { $_ -match '"name":\s*"feature-crew"' } | Select-Object -First 1)
  if ($row.Count -eq 0) { return "absent" }
  $norm = $row[0] -replace '":\s*"', '": "'
  $src = $Source.Replace('\', '\\')
  foreach ($want in @("""path"": ""$src""", """repo"": ""$src""", """url"": ""$src""",
      """source"": ""Local: $src""", """source"": ""GitHub: $src""", """source"": ""URL: $src""")) {
    if ($norm.Contains($want)) { return "same" }
  }
  return "other"
}

# absent, disabled, or enabled: only feature-crew from the feature-crew marketplace,
# and in Claude Code only the user-scope install. Only "enabled": true is enabled.
function Get-PluginState($cli) {
  $rows = Get-Listing $cli "plugin"
  if ($null -eq $rows) { return $null }
  if ($cli -eq "claude") {
    $row = @($rows | Where-Object { ($_ -match '"id":\s*"feature-crew@feature-crew"') -and ($_ -match '"scope":\s*"user"') } | Select-Object -First 1)
  } else {
    $row = @($rows | Where-Object { ($_ -match '"name":\s*"feature-crew"') -and ($_ -match '"marketplace":\s*"feature-crew"') } | Select-Object -First 1)
  }
  if ($row.Count -eq 0) { return "absent" }
  if ($row[0] -match '"enabled":\s*true(?![A-Za-z0-9_])') { return "enabled" }
  return "disabled"
}

# Claude Code installs per scope; this installer manages the user scope only.
function Get-ScopeArgs($cli) { if ($cli -eq "claude") { return @("--scope", "user") }; return @() }

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
  Push-Location -LiteralPath $NeutralDir
  try {
    & $CliPath[$cli] @stepArgs | ForEach-Object { Write-Host $_ }
    $rc = $LASTEXITCODE
  } catch { $rc = 1 } finally { Pop-Location }
  return ($rc -eq 0)
}

# A marketplace from another source is replaced, never updated. Claude Code
# replaces it in user settings, and its plugin follows; other scopes keep
# theirs. The old install is removed only after the CLI lists the plugin enabled.
function Install-Cli($cli) {
  $mp = Get-MarketplaceState $cli
  $pl = Get-PluginState $cli
  if ($null -eq $mp -or $null -eq $pl) { Stop-Cli $cli }
  $sc = @(Get-ScopeArgs $cli)
  if ($mp -eq "same") {
    if (-not (Invoke-Step $cli @("plugin", "marketplace", "update", $Marketplace))) { Stop-Cli $cli }
  } else {
    if ($mp -eq "other" -and $cli -ne "claude") {
      if ($pl -ne "absent" -and -not (Invoke-Step $cli @("plugin", "uninstall", $PluginId))) { Stop-Cli $cli }
      if (-not (Invoke-Step $cli @("plugin", "marketplace", "remove", $Marketplace))) { Stop-Cli $cli }
    }
    if (-not (Invoke-Step $cli (@("plugin", "marketplace", "add", $Source) + $sc))) { Stop-Cli $cli }
    if ($DryRun) { $pl = "absent" } else { $pl = Get-PluginState $cli; if ($null -eq $pl) { Stop-Cli $cli } }
  }
  if ($pl -eq "enabled") { $steps = @(,(@("plugin", "update", $PluginId) + $sc)) }
  elseif ($pl -eq "disabled" -and $cli -eq "claude") { $steps = @((@("plugin", "enable", $PluginId) + $sc), (@("plugin", "update", $PluginId) + $sc)) }
  else { $steps = @(,(@("plugin", "install", $PluginId) + $sc)) }
  foreach ($st in $steps) { if (-not (Invoke-Step $cli $st)) { Stop-Cli $cli } }
  if (-not $DryRun -and (Get-PluginState $cli) -ne "enabled") { Stop-Cli $cli }
}

# Claude Code: remove the marketplace from user settings only. When only a
# project declares it, the CLI says not_configured and it stays for that project.
function Remove-UserMarketplace {
  $line = "claude plugin marketplace remove $Marketplace --scope user --json"
  if ($DryRun) { Write-Host "would run: $line"; return $true }
  Write-Host "run: $line"
  $ErrorActionPreference = "Continue"
  Push-Location -LiteralPath $NeutralDir
  try {
    $out = (& $CliPath["claude"] plugin marketplace remove $Marketplace --scope user --json 2>&1 | Out-String)
    $rc = $LASTEXITCODE
  } catch { $out = "$_"; $rc = 1 } finally { Pop-Location }
  if ($rc -eq 0) { Write-Host "claude: marketplace removed from user settings"; return $true }
  if ($out -match '"failureCode":\s*"not_configured"') {
    Write-Host "claude: marketplace not in user settings; left for other scopes"; return $true
  }
  [Console]::Error.WriteLine($out.TrimEnd())
  return $false
}

function Uninstall-Cli($cli) {
  $pl = Get-PluginState $cli
  if ($null -eq $pl) { Stop-Cli $cli }
  if ($pl -ne "absent" -and -not (Invoke-Step $cli (@("plugin", "uninstall", $PluginId) + @(Get-ScopeArgs $cli)))) { Stop-Cli $cli }
  $mp = Get-MarketplaceState $cli
  if ($null -eq $mp) { Stop-Cli $cli }
  if ($mp -eq "absent") { return }
  if ($cli -eq "claude") { if (-not (Remove-UserMarketplace)) { Stop-Cli $cli } }
  elseif (-not (Invoke-Step $cli @("plugin", "marketplace", "remove", $Marketplace))) { Stop-Cli $cli }
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

# Like bash [ -e ] / -f / -d: false, never an error, when a parent cannot be read.
function Test-Exists($path, $type = "Any") {
  try { return [bool](Test-Path -LiteralPath $path -PathType $type -ErrorAction Stop) } catch { return $false }
}

function Test-PublishedFile($file, $relativePath) {
  if (-not (Test-Exists $file "Leaf")) { return $false }
  try { return $PublishedHashes.Contains((Get-Sha256Lf $file) + "  " + $relativePath) } catch { return $false }
}

function Test-Link($path) {
  $item = Get-Item -LiteralPath $path -Force
  return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

$script:LegacyFound = $false
$script:Validate = $false
$script:NotRemoved = New-Object 'System.Collections.Generic.List[string]'
$script:Kept = New-Object 'System.Collections.Generic.List[string]'
$script:Planned = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$script:Emptied = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
# Removes a link itself, never its target.
function Remove-Legacy($path) {
  $script:LegacyFound = $true
  [void]$script:Planned.Add($path)
  if ($script:Validate) { Test-Removable $path; return }
  if ($Check) { Write-Host "old file: $path"; return }
  if ($DryRun) { Write-Host "would remove: $path"; return }
  $abs = Resolve-AbsPath $path
  try {
    $item = Get-Item -LiteralPath $abs -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      if ($item.PSIsContainer) { [IO.Directory]::Delete($abs) } else { [IO.File]::Delete($abs) }
    } elseif ($item.PSIsContainer) {
      Remove-Item -LiteralPath $abs -Recurse -Force -ErrorAction Stop
    } else {
      Remove-Item -LiteralPath $abs -Force -ErrorAction Stop
    }
  } catch { }
  if (Get-Item -LiteralPath $abs -Force -ErrorAction SilentlyContinue) { $script:NotRemoved.Add($path); return }
  Write-Host "removed: $path"
}

# True when DIR, a folder between it and the prefix, or the prefix itself is a
# link: nothing beneath it is removed, because that would reach outside the prefix.
function Test-LinkedDir($dir) {
  $d = $dir
  while ($d) {
    $item = Get-Item -LiteralPath $d -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $true }
    if ($d -eq $Prefix) { break }
    $i = $d.LastIndexOf('/')
    if ($i -lt 1) { break }
    $d = $d.Substring(0, $i)
  }
  return $false
}

# An fc-* path in a linked folder still shadows the plugin.
function Write-LinkedOld($path) {
  $script:LegacyFound = $true
  if (-not $script:Validate) { Write-Host "kept (linked folder): $path" }
}

# A skill dir's regular files, as slash-separated relative paths in ordinal order.
# Like find -type f: links are skipped and never followed, files or folders.
function Get-OldSkillFiles($dir) {
  $root = (Resolve-AbsPath $dir).TrimEnd('\', '/')
  $paths = New-Object 'System.Collections.Generic.List[string]'
  $todo = New-Object 'System.Collections.Generic.Stack[string]'
  $todo.Push($root)
  while ($todo.Count -gt 0) {
    # Like find, skip a folder that cannot be read; the caller reports it.
    try { $items = @(Get-ChildItem -LiteralPath $todo.Pop() -Force -ErrorAction Stop) } catch { continue }
    foreach ($item in $items) {
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
      if ($item.PSIsContainer) { $todo.Push($item.FullName); continue }
      $paths.Add($item.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/'))
    }
  }
  $paths.Sort([StringComparer]::Ordinal)
  return ,$paths
}

# Before any change (validate pass, -Check, -DryRun) exit 2; once a run has
# changed something, list the path with the other leftovers instead (exit 1).
function Stop-Cannot($verb, $path) {
  if ($script:Validate -or $Check -or $DryRun) {
    [Console]::Error.WriteLine("feature-crew: cannot $verb $path")
    exit 2
  }
  $script:NotRemoved.Add($path)
}

function Test-Readable($path, [bool]$dir) {
  try {
    if ($dir) { [void](Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop) }
    else { (New-Object IO.FileStream((Resolve-AbsPath $path), [IO.FileMode]::Open, [IO.FileAccess]::Read)).Dispose() }
    return $true
  } catch { return $false }
}

# A folder whose entries can be removed, like `test -w DIR -a -x DIR`. Windows
# has no such mode bits; there, a run that cannot remove an entry exits 1.
function Test-Writable($dir) {
  if ([IO.Path]::DirectorySeparatorChar -eq '\') { return $true }
  foreach ($t in '/usr/bin/test', '/bin/test') {
    if (Test-Path -LiteralPath $t -PathType Leaf) {
      & $t -w $dir; $w = ($LASTEXITCODE -eq 0)
      & $t -x $dir; return ($w -and $LASTEXITCODE -eq 0)
    }
  }
  return $true
}

# Every real folder under DIR, DIR first, never through a link; an unreadable one stops the run.
function Get-ReadableDirs($dir) {
  $dirs = New-Object 'System.Collections.Generic.List[string]'
  $todo = New-Object 'System.Collections.Generic.Stack[string]'
  $todo.Push($dir)
  while ($todo.Count -gt 0) {
    $d = $todo.Pop(); $dirs.Add($d)
    try { $kids = @(Get-ChildItem -LiteralPath $d -Force -ErrorAction Stop) } catch { Stop-Cannot "read" $d; continue }
    foreach ($k in $kids) {
      if (-not ($k.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $k.PSIsContainer) { $todo.Push("$d/$($k.Name)") }
    }
  }
  return ,$dirs
}

# Under Validate: prove a path can be read and removed, changing nothing.
function Test-Removable($path) {
  $item = Get-Item -LiteralPath $path -Force
  if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    if ($item.PSIsContainer) {
      $dirs = Get-ReadableDirs $path
      foreach ($rel in (Get-OldSkillFiles $path)) { if (-not (Test-Readable "$path/$rel" $false)) { Stop-Cannot "read" "$path/$rel" } }
      foreach ($d in $dirs) { if (-not (Test-Writable $d)) { Stop-Cannot "remove" $d } }
    } elseif (-not (Test-Readable $path $false)) { Stop-Cannot "read" $path }
  }
  if (-not (Test-Writable $path.Substring(0, $path.LastIndexOf('/')))) { Stop-Cannot "remove" $path }
}

# Resolve the prefix, so a trailing / or /. on a linked prefix cannot hide the
# link from Test-LinkedDir.
function Resolve-Prefix($p) {
  if (Test-Path -LiteralPath $p -PathType Container) {
    if (-not (Test-Readable $p $true)) { Stop-Cannot "read" $p }
    $p = [IO.Path]::GetFullPath((Resolve-AbsPath $p))
  }
  while ($p.Length -gt 1 -and $p -ne [IO.Path]::GetPathRoot($p) -and ($p.EndsWith('/.') -or $p.EndsWith('/') -or $p.EndsWith('\'))) {
    if ($p.EndsWith('/.')) { $p = $p.Substring(0, $p.Length - 2) } else { $p = $p.Substring(0, $p.Length - 1) }
  }
  return $p
}

# Every folder from the path's parent up to root.
function Add-Emptied($root, $path) {
  $d = $path.Substring(0, $path.LastIndexOf('/'))
  while ($true) {
    [void]$script:Emptied.Add($d)
    if ($d -eq $root) { break }
    $d = $d.Substring(0, $d.LastIndexOf('/'))
  }
}

# Remove only folders this run empties, deepest first; never one that was already empty.
function Remove-Emptied {
  $dirs = New-Object 'System.Collections.Generic.List[string]'
  foreach ($d in $script:Emptied) { $dirs.Add($d) }
  $dirs.Sort([Comparison[string]]{ param($a, $b)
    $da = $a.Split('/').Count; $db = $b.Split('/').Count
    if ($da -ne $db) { return $db - $da }
    return [string]::CompareOrdinal($a, $b) })
  foreach ($d in $dirs) {
    if (-not (Test-Exists $d "Container") -or (Test-Link $d)) { continue }
    $left = $false
    try { $entries = @(Get-ChildItem -LiteralPath $d -Force -ErrorAction Stop) } catch { $script:NotRemoved.Add($d); continue }
    foreach ($e in $entries) {
      if (-not $script:Planned.Contains("$d/$($e.Name)")) { $left = $true; break }
    }
    if ($left) { continue }
    [void]$script:Planned.Add($d)
    if ($script:Validate) {
      if (-not (Test-Writable $d.Substring(0, $d.LastIndexOf('/')))) { Stop-Cannot "remove" $d }
      continue
    }
    if ($DryRun) { Write-Host "would remove: $d" }
    else {
      try { Remove-Item -LiteralPath $d -Force -ErrorAction Stop; Write-Host "removed: $d" }
      catch { $script:NotRemoved.Add($d) }
    }
  }
}

# Run twice: first under Validate, which proves every path this run removes is
# readable and removable before any CLI or file changes (exit 2 otherwise).
function Clear-Legacy {
  $script:Kept.Clear(); $script:Planned.Clear(); $script:Emptied.Clear()
  foreach ($d in @($Prefix, "$Prefix/agents", "$Prefix/skills", "$Prefix/agents/feature-crew")) {
    if ((Test-Exists $d "Container") -and -not (Test-Readable $d $true)) { Stop-Cannot "read" $d }
  }
  foreach ($n in $LEGACY_FC_AGENTS) {
    $p = "$Prefix/agents/$n.md"
    if (Test-Exists $p) {
      if (Test-LinkedDir "$Prefix/agents") { Write-LinkedOld $p } else { Remove-Legacy $p }
    }
  }
  foreach ($n in $LEGACY_FC_SKILLS) {
    $p = "$Prefix/skills/$n"
    if (Test-Exists $p) {
      if (Test-LinkedDir "$Prefix/skills") { Write-LinkedOld $p } else { Remove-Legacy $p }
    }
  }
  $p = "$Prefix/feature-crew.sha256"
  if (Test-Exists $p) {
    if (Test-LinkedDir $Prefix) { Write-LinkedOld $p } else { Remove-Legacy $p }
  }
  foreach ($n in $LEGACY_OLD_AGENTS) {
    $p = "$Prefix/agents/feature-crew/$n.md"
    if ((Test-Exists $p "Leaf") -and -not (Test-Link $p) -and -not (Test-LinkedDir "$Prefix/agents/feature-crew")) {
      if (-not (Test-Readable $p $false)) { Stop-Cannot "read" $p; continue }
      if (Test-PublishedFile $p "agents/feature-crew/$n.md") { Remove-Legacy $p; Add-Emptied "$Prefix/agents/feature-crew" $p } else { $script:Kept.Add($p) }
    }
  }
  foreach ($n in $LEGACY_OLD_SKILLS) {
    $p = "$Prefix/skills/$n"
    if ((Test-Exists $p "Container") -and -not (Test-LinkedDir $p)) {
      if (-not (Test-Readable $p $true)) { Stop-Cannot "read" $p; continue }
      [void](Get-ReadableDirs $p)
      foreach ($rel in (Get-OldSkillFiles $p)) {
        if (-not (Test-Readable "$p/$rel" $false)) { Stop-Cannot "read" "$p/$rel"; continue }
        if (Test-PublishedFile "$p/$rel" "skills/$n/$rel") { Remove-Legacy "$p/$rel"; Add-Emptied $p "$p/$rel" } else { $script:Kept.Add("$p/$rel") }
      }
    }
  }
  if (-not $Check -or $script:Validate) { Remove-Emptied }
  if (-not $script:Validate) { foreach ($p in $script:Kept) { Write-Host "kept (not ours): $p" } }
  # The checks cannot foresee every refusal (an immutable file, a lock); list
  # what is left and stop. Every step is safe to repeat, so a rerun finishes.
  if ($script:NotRemoved.Count -gt 0) {
    foreach ($p in $script:NotRemoved) { [Console]::Error.WriteLine("feature-crew: not removed: $p") }
    [Console]::Error.WriteLine("feature-crew: fix these and run again; every other step is done.")
    exit 1
  }
}

$Prefix = Resolve-Prefix $Prefix

if ($Uninstall) {
  Write-Host "feature-crew: uninstalling; old install at $Prefix"
} else {
  Write-Host "feature-crew: plugin source $Source; old install at $Prefix"
}

$script:Validate = $true; Clear-Legacy; $script:Validate = $false; $script:LegacyFound = $false

if ($Check) {
  foreach ($c in $Clis) {
    $st = Get-PluginState $c
    if ($null -eq $st) { [Console]::Error.WriteLine("feature-crew: $c plugin list failed"); exit 2 }
    $mp = Get-MarketplaceState $c
    if ($null -eq $mp) { [Console]::Error.WriteLine("feature-crew: $c marketplace list failed"); exit 2 }
    if ($st -eq "enabled" -and $mp -eq "same") { Write-Host "${c}: feature-crew installed" }
    elseif ($st -eq "enabled") { Write-Host "${c}: feature-crew installed from another source"; $script:LegacyFound = $true }
    elseif ($st -eq "disabled") { Write-Host "${c}: feature-crew disabled"; $script:LegacyFound = $true }
    else { Write-Host "${c}: feature-crew missing"; $script:LegacyFound = $true }
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
