#!/usr/bin/env bash
# Feature-Crew framework self-test.
#
# Scope note: this harness is dev-only tooling and is not installed by either
# installer. The cross-platform parity rule covers *shipped* artifacts
# (install.sh / install.ps1); T10 is what enforces it.
#
# WHAT THIS SUITE CANNOT DO
#
# Assertions over prose (T7a, T7b, T8, T9) check that a rule is PRESENT. They
# cannot check that it still MEANS what it meant. Mutation audits confirmed
# this directly: reversing "ask one question at a time" to "never ask one
# question at a time", or negating a skill's positive trigger, leaves every
# keyword in place and the suite green.
#
# Adding negation patterns loses an arms race with paraphrase -- there is
# always another way to invert a sentence. Where a rule's meaning is
# load-bearing AND mechanically checkable, the assertion parses or executes
# instead of grepping: T5 parses YAML, T16 parses frontmatter, T17 asserts
# encoding arguments, T18/T22/T27 run the installer, T20/T21 mutate and
# re-run. Those hold under mutation. The prose checks are regression alarms
# for accidental deletion, not proof of semantic correctness -- that remains a
# human review job, and this comment exists so a green run is not mistaken for
# it.
#
# Run: bash tests/framework_test.sh
#      FC_STRICT=1 bash tests/framework_test.sh   # skips become failures (CI)

set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
SKIP=0
ok()   { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); }
# A skipped assertion is not a passing one. Counting it as ok means the suite
# reports green while the thing it claims to check never ran -- the same shape
# as the vacuous T10/T15 bugs. FC_STRICT=1 (set in CI) turns skips into
# failures, so a missing dependency cannot silently drop coverage.
skip() {
  if [ "${FC_STRICT:-0}" = "1" ]; then
    printf '  FAIL  %s\n' "$1"; printf '        skipped under FC_STRICT=1\n'; FAIL=$((FAIL + 1))
  else
    printf '  skip  %s\n' "$1"; SKIP=$((SKIP + 1))
  fi
}

SKILL_NAMES=(fc-research fc-grill-me fc-brainstorm fc-build-or-fix fc-review fc-second-opinion fc-update)
ROLE_AGENTS=(fc-pm fc-architect fc-developer fc-qa-spec fc-qa-code fc-tech-lead)

skill_files() { find .claude/skills -name 'SKILL.md' | sort; }

framework_files() {
  find agents -name '*.md'
  find .claude/skills -name '*.md'
  printf '%s\n' README.md CLAUDE.md
}

echo "== Feature-Crew framework tests =="

# ---------------------------------------------------------------- T1
# Orchestration cap, redefined: pm.md + EVERY SKILL.md (not just build-or-fix).
# The old wording named only two files, so new skills could add orchestration
# text without ever touching the cap.
orch=$( { echo agents/fc-pm.md; skill_files; } | xargs wc -l | tail -1 | awk '{print $1}')
if [ "${orch:-99999}" -le 600 ]; then
  ok "T1 orchestration (pm.md + all SKILL.md) = ${orch} <= 600"
else
  bad "T1 orchestration cap" "pm.md + all SKILL.md = ${orch}, cap 600"
fi

# ---------------------------------------------------------------- T2
total=$(framework_files | xargs wc -l | tail -1 | awk '{print $1}')
if [ "${total:-99999}" -le 1500 ] && [ "${total:-99999}" -lt 1223 ]; then
  ok "T2 framework total = ${total} (<=1500, and < 1223 baseline)"
else
  bad "T2 framework total" "total=${total}; need <=1500 AND <1223 (baseline before this change)"
fi

# ---------------------------------------------------------------- T3
# The hot path must remain tightly ratcheted -- this file is paid for on every
# build/fix request, including Just Do It work.
if [ -f .claude/skills/fc-build-or-fix/SKILL.md ]; then
  bof=$(wc -l < .claude/skills/fc-build-or-fix/SKILL.md)
  if [ "$bof" -le 128 ]; then
    ok "T3 fc-build-or-fix/SKILL.md = ${bof} lines (<= 128 ratchet)"
  else
    bad "T3 hot path exceeded ratchet" "fc-build-or-fix/SKILL.md = ${bof}, cap 128"
  fi
else
  bad "T3 hot path" ".claude/skills/fc-build-or-fix/SKILL.md missing"
fi

# ---------------------------------------------------------------- T4
# git grep, not grep -r: a bare recursive grep walks into .claude/worktrees/,
# vendored copies, and stray checkouts, then reports their contents as ours.
#
# No pathspec exclusion. There is no CHANGELOG.md -- the GitHub release body is
# the changelog, so no tracked file legitimately names a removed model string.
# The exclusion this line used to carry would now be a permanent hiding place.
stale=$(git grep -lE 'gpt-5\.5|claude-opus-4\.7|degraded \(same-vendor\)' -- '*.md' 2>/dev/null || true)
if [ -z "$stale" ]; then
  ok "T4 no stale model strings"
else
  bad "T4 stale model strings" "$(echo "$stale" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------- T5
# All six installed ROLE agents must resolve with no model key. Hard-gate
# reviewers receive an explicit model override at dispatch time from the
# artifact-author selector; frontmatter pins would bypass that provenance rule.
#
# This parses YAML rather than grepping lines: duplicate keys resolve silently
# to the last value, so reject duplicate keys outright before checking the
# resolved mapping.
validate_role_frontmatter() {
  python3 - "$1" <<'PY'
import sys, re, glob, os, yaml
roles = {"fc-pm", "fc-architect", "fc-developer", "fc-qa-spec", "fc-qa-code", "fc-tech-lead"}
errs = []
seen = set()
for f in sorted(glob.glob(sys.argv[1] + "/agents/*.md")):
    name = os.path.basename(f)[:-3]
    seen.add(name)
    txt = open(f, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", txt, re.S)
    if not m:
        errs.append(f"{name}:no-frontmatter"); continue
    block = m.group(1)
    keys = [ln.split(":", 1)[0] for ln in block.splitlines() if re.match(r"^[a-z-]+:", ln)]
    if len(keys) != len(set(keys)):
        errs.append(f"{name}:duplicate-keys"); continue
    d = yaml.safe_load(block) or {}
    if "model" in d:
        errs.append(f"{name}:model={d['model']!r}-must-be-absent")
for name in sorted(roles - seen):
    errs.append(f"{name}:missing")
for name in sorted(seen - roles):
    errs.append(f"{name}:unexpected-role")
print(" ".join(errs))
PY
}

tmp_prefix="$(mktemp -d)"
# The T15 probe lives inside the repo, so it must be cleaned up even if an
# assertion between here and there exits early -- otherwise a failed run leaves
# the working tree dirty. Other tests add their temp paths to this shared list.
T15_PROBE=".claude/skills/t15-probe-$$"
T21_SCRIPT="./t21-noguard-$$.sh"
CLEANUP_PATHS=("$tmp_prefix" "$T15_PROBE" "$T21_SCRIPT")
cleanup() { rm -rf "${CLEANUP_PATHS[@]}"; }
trap cleanup EXIT
if bash install.sh --prefix "$tmp_prefix" --force >/dev/null 2>&1; then
  t5_err=""
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    if t5_out=$(validate_role_frontmatter "$tmp_prefix" 2>&1); then
      [ -n "$t5_out" ] && t5_err="$t5_err$t5_out"
    else
      t5_rc=$?
      t5_err="$t5_err validator-exited-$t5_rc:${t5_out:-no-diagnostic}"
    fi
  else
    # No parser available: line checks cannot prove duplicate-key safety.
    for a in "${ROLE_AGENTS[@]}"; do
      f="$tmp_prefix/agents/$a.md"
      if [ ! -f "$f" ]; then t5_err="$t5_err $a:missing"
      elif head -12 "$f" | grep -q '^model:'; then t5_err="$t5_err $a:model-present"
      fi
    done
    skip "T5 no YAML parser — duplicate-key override unverified"
  fi
  if [ -z "$t5_err" ]; then
    ok "T5 all six installed role agents resolve with no model key"
  else
    bad "T5 installed role-agent model frontmatter" "issues:$t5_err"
  fi
else
  bad "T5 installed role-agent model frontmatter" "install.sh failed against temp prefix"
fi

# ---------------------------------------------------------------- T6
# The cross-family audit rule is stated ONCE; everything else points at it.
# Marker is a phrase only the canonical statement uses -- a passing mention of
# "different family" in an anti-pattern list is a pointer, not a restatement.
# Tracked files only; see T4 on why grep -r is wrong here.
#
# Count OCCURRENCES, not files. `git grep -l` counts each file once, so a
# second contradictory copy of the rule inside the same file passed -- found by
# mutation.
canon=$(git grep -c 'must be audited by a model from a different family' -- '*.md' 2>/dev/null \
        | awk -F: '{ n += $NF } END { print n + 0 }')
canon_files=$(git grep -l 'must be audited by a model from a different family' -- '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$canon" = "1" ] && [ "$canon_files" = "1" ]; then
  ok "T6 cross-family rule stated exactly once, in exactly 1 file"
else
  bad "T6 cross-family rule duplicated" "${canon} occurrences across ${canon_files} files, want 1 and 1"
fi

# ---------------------------------------------------------------- T7
# The grilling mechanic lives in fc-grill-me; fc-brainstorm owns the panel.
g=.claude/skills/fc-grill-me/SKILL.md
if [ -f "$g" ]; then
  miss=""
  grep -qi 'recommended answer'   "$g" || miss="$miss recommended-answer"
  grep -qi 'look it up\|look up'  "$g" || miss="$miss fact-lookup"
  grep -qi 'shared understanding' "$g" || miss="$miss stop-condition"
  grep -qi 'one question at a time\|one at a time' "$g" || miss="$miss one-at-a-time"
  [ -z "$miss" ] && ok "T7a fc-grill-me carries all four grill rules" \
                 || bad "T7a fc-grill-me rules" "missing:$miss"
else
  bad "T7a fc-grill-me rules" "$g missing"
fi

b=.claude/skills/fc-brainstorm/SKILL.md
if [ -f "$b" ]; then
  miss=""
  grep -qi 'stance'              "$b" || miss="$miss distinct-stances"
  grep -qi 'diversity\|converge' "$b" || miss="$miss diversity-check"
  grep -qi 'it depends'          "$b" || miss="$miss opinionated-rec"
  [ -z "$miss" ] && ok "T7b fc-brainstorm carries stances + diversity check" \
                 || bad "T7b fc-brainstorm panel rules" "missing:$miss"
else
  bad "T7b fc-brainstorm panel rules" "$b missing"
fi

# ---------------------------------------------------------------- T8
s=.claude/skills/fc-second-opinion/SKILL.md
if [ -f "$s" ]; then
  miss=""
  grep -qi 'refuted' "$s"                            || miss="$miss refute-default"
  grep -qi 'not a substitute\|never substitute' "$s" || miss="$miss non-substitution"
  grep -qi 'strongest.*case\|steelman' "$s"          || miss="$miss steelman"
  [ -z "$miss" ] && ok "T8 fc-second-opinion carries refute-default, steelman, non-substitution" \
                 || bad "T8 fc-second-opinion rules" "missing:$miss"
else
  bad "T8 fc-second-opinion rules" "$s missing"
fi

# ---------------------------------------------------------------- T9
# Description contract: what it does + when to use + when NOT to. This is what
# keeps 6 sibling skills from fighting over the same triggers.
#
# The extraction must be bounded to the frontmatter block. A `sed` range ending
# at /^[a-z-]*:/ has no terminating match when `description:` is the LAST
# frontmatter key, so it ran to EOF and the greps saw the whole file body --
# vacuous for exactly the 3 skills whose description happens to be last, and
# coverage silently depended on unrelated key ORDER.
t9_err=""
for n in "${SKILL_NAMES[@]}"; do
  f=".claude/skills/$n/SKILL.md"
  if [ ! -f "$f" ]; then t9_err="$t9_err $n:missing"; continue; fi
  desc=$(awk '/^---$/{c++; if(c==2) exit; next} c==1' "$f" \
         | awk '/^[a-z][a-z-]*:/{k=($0 ~ /^description:/)} k')
  echo "$desc" | grep -qi 'use when'        || t9_err="$t9_err $n:no-use-when"
  echo "$desc" | grep -qi 'do not use for'  || t9_err="$t9_err $n:no-anti-trigger"
done
[ -z "$t9_err" ] && ok "T9 all skills carry [what] + [use when] + [do NOT use for]" \
                 || bad "T9 skill description contract" "issues:$t9_err"

# ---------------------------------------------------------------- T10
# Cross-platform parity: the two installers stay feature-mirrored.
#
# Token presence alone is NOT enough. Two independent audits demonstrated that
# replacing the top-level `Install-ClaudeGlobal` with `exit 0`, or commenting
# out the Install-Agent / Copy-Tree calls, leaves every token in place while
# native Windows installs silently install nothing. So the operative call sites
# must also be present, uncommented, and reachable. Factored into functions so
# T20 can replay those exact mutations against them.
ps1_operative_ok() {
  local f="$1"
  grep -qE '^[[:space:]]*Install-Agent[[:space:]]+\$'   "$f" || return 1
  grep -qE '^[[:space:]]*Copy-Tree[[:space:]]+\$'       "$f" || return 1
  grep -qE '^Install-ClaudeGlobal[[:space:]]*$'         "$f" || return 1
  # Presence is not reachability. An unconditional `throw`/`exit` at column 0
  # before the dispatch leaves every token in place while the installer does
  # nothing -- a reviewer demonstrated exactly that and the suite stayed green.
  #
  # Column 0 specifically: install.ps1 legitimately exits from inside `if`
  # blocks (bash delegation, --uninstall), and those are indented. Only an
  # unindented terminator runs unconditionally. Static analysis cannot prove
  # reachability in general; the Windows CI job proves the rest by executing.
  local disp
  disp=$(grep -n '^Install-ClaudeGlobal[[:space:]]*$' "$f" | head -1 | cut -d: -f1)
  [ -n "$disp" ] || return 1
  head -n "$disp" "$f" | grep -qE '^(throw|exit)([[:space:]]|$)' && return 1
  return 0
}
sh_operative_ok() {
  local f="$1"
  grep -qE '^[[:space:]]*install_agent[[:space:]]+"'    "$f" || return 1
  grep -qE '^[[:space:]]*install_skill[[:space:]]+"'    "$f" || return 1
  return 0
}

t10_err=""
for token in fc-pm fc-architect fc-developer fc-qa-spec fc-qa-code fc-tech-lead; do
  grep -q -- "$token" install.sh  || t10_err="$t10_err sh:$token"
  grep -q -- "$token" install.ps1 || t10_err="$t10_err ps1:$token"
done
for flag in force dry-run uninstall prefix; do
  grep -qi -- "$flag" install.sh  || t10_err="$t10_err sh:--$flag"
  grep -qi -- "$flag" install.ps1 || t10_err="$t10_err ps1:--$flag"
done
ps1_operative_ok install.ps1 || t10_err="$t10_err ps1:operative-calls-unreachable"
sh_operative_ok  install.sh  || t10_err="$t10_err sh:operative-calls-unreachable"
[ -z "$t10_err" ] && ok "T10 install.sh / install.ps1 parity + operative calls live" \
                  || bad "T10 installer parity drift" "missing:$t10_err"

# ---------------------------------------------------------------- T11
# Skill bodies stay resident in context once loaded, so every line is a
# recurring cost. Anthropic guidance: keep SKILL.md lean, detail in reference/.
t11_err=""
while IFS= read -r f; do
  n=$(wc -l < "$f")
  [ "$n" -le 500 ] || t11_err="$t11_err $f:$n"
done < <(skill_files)
[ -z "$t11_err" ] && ok "T11 every SKILL.md <= 500 lines" \
                  || bad "T11 oversized SKILL.md" "$t11_err"

# ---------------------------------------------------------------- T12
# Every skill is fc-prefixed. This is what keeps /fc-review from landing in the
# same namespace as the bundled /review and /security-review skills.
# Only tracked dirs count -- an untracked scratch dir isn't ours to rename.
t12_err=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  case "$d" in fc-*) ;; *) t12_err="$t12_err $d" ;; esac
done < <(git ls-files '.claude/skills/*' | cut -d/ -f3 | sort -u)
[ -z "$t12_err" ] && ok "T12 all skills fc-prefixed (no bundled-name collision)" \
                  || bad "T12 unprefixed skill dir" "offenders:$t12_err"

# ---------------------------------------------------------------- T13
# Both installers glob; this guards against someone hardcoding a list later.
if bash install.sh --prefix "$tmp_prefix" --force >/dev/null 2>&1; then
  t13_err=""
  for n in "${SKILL_NAMES[@]}"; do
    [ -f "$tmp_prefix/skills/$n/SKILL.md" ] || t13_err="$t13_err $n"
  done
  [ -z "$t13_err" ] && ok "T13 all skills reach the install prefix" \
                    || bad "T13 skills not installed" "missing:$t13_err"
else
  bad "T13 skills not installed" "install.sh failed"
fi

# ---------------------------------------------------------------- T15
# A directory with no SKILL.md is not a skill. The installer globs, so without
# this guard any scratch dir under .claude/skills/ gets shipped to users.
#
# The probe must NOT be dot-prefixed: `for src in "$SRC_SKILLS_DIR"/*/` never
# enumerates dot dirs, so a hidden probe means the guard under test is never
# executed -- both guards could be deleted and this still reported ok. T21
# proves the current probe actually exercises them.
mkdir -p "$T15_PROBE"
if bash install.sh --prefix "$tmp_prefix" --force >/dev/null 2>&1; then
  if [ -d "$tmp_prefix/skills/$(basename "$T15_PROBE")" ]; then
    bad "T15 scratch dir shipped" "a directory without SKILL.md was installed"
  else
    ok "T15 directories without SKILL.md are not installed"
  fi
else
  bad "T15 scratch dir guard" "install.sh failed"
fi
rmdir "$T15_PROBE" 2>/dev/null

# ---------------------------------------------------------------- T14
# Supporting files must be reachable: if SKILL.md points at reference/x.md,
# that file has to exist. Progressive disclosure breaks silently otherwise.
t14_err=""
while IFS= read -r f; do
  d=$(dirname "$f")
  for ref in $(grep -o '(reference/[a-z0-9-]*\.md)' "$f" 2>/dev/null | tr -d '()'); do
    [ -f "$d/$ref" ] || t14_err="$t14_err $(basename "$d")/$ref"
  done
done < <(skill_files)
[ -z "$t14_err" ] && ok "T14 all referenced supporting files exist" \
                  || bad "T14 dangling reference" "missing:$t14_err"

# ---------------------------------------------------------------- T16
# Installed agent frontmatter must be valid YAML. Role descriptions contain
# ": " (e.g. "Feature-Crew Architect: turns an approved spec into..."), which a
# plain YAML scalar may not -- so the generated description has to be quoted.
# Claude Code 2.1.220 tolerates the unquoted form, but that tolerance is
# undocumented and nothing would warn us when it stops.
if ! command -v python3 >/dev/null 2>&1; then
  skip "T16 python3 unavailable — YAML validity unverified"
elif ! python3 -c 'import yaml' >/dev/null 2>&1; then
  skip "T16 PyYAML unavailable — YAML validity unverified"
elif bash install.sh --prefix "$tmp_prefix" --force >/dev/null 2>&1; then
  if python3 - "$tmp_prefix" <<'PY' >/dev/null 2>&1
import sys, glob, re, yaml
for f in glob.glob(sys.argv[1] + '/agents/*.md'):
    m = re.match(r'^---\n(.*?)\n---\n', open(f, encoding='utf-8').read(), re.S)
    assert m, f
    yaml.safe_load(m.group(1))
PY
  then
    ok "T16 installed agent frontmatter is valid YAML"
  else
    bad "T16 invalid agent frontmatter" "at least one installed agent fails YAML parse"
  fi
else
  bad "T16 invalid agent frontmatter" "install.sh failed"
fi

# ---------------------------------------------------------------- T17
# Agent bodies must stay bytes: even explicit UTF-8 text decoding discards an
# added BOM and makes an edited agent look untouched (#30). Inspect the agent
# functions and their helpers, not unrelated ReadAllBytes calls in skill/hash
# code. Replay #26's Get-Content mutation against this same check.
t17_root=$(mktemp -d)
CLEANUP_PATHS+=("$t17_root")
t17_pwsh="${PWSH:-$(command -v pwsh 2>/dev/null || true)}"
cat > "$t17_root/check.ps1" <<'PS'
param([string]$Path, [string]$Mutant)
$ErrorActionPreference = 'Stop'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors -join "`n") }
$functions = @{}
$ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) |
  ForEach-Object { $functions[$_.Name] = $_ }
function Get-AgentPath($entry) {
  $todo = @($entry); $seen = @{}
  for ($i = 0; $i -lt $todo.Count; $i++) {
    $name = $todo[$i]
    if ($seen.ContainsKey($name)) { continue }
    if (-not $functions.ContainsKey($name)) { throw "missing agent function: $name" }
    $f = $functions[$name]; $seen[$name] = $f
    foreach ($call in $f.Body.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] }, $true)) {
      $called = $call.GetCommandName()
      if ($called -and $functions.ContainsKey($called)) { $todo += $called }
    }
  }
  return @($seen.Values)
}
$install = @(Get-AgentPath 'Install-Agent')
$ownership = @(Get-AgentPath 'Test-InstalledIsOurs')
$installNodes = @($install | ForEach-Object { $_.Body.FindAll({ param($n) $true }, $true) })
$ownNodes = @($ownership | ForEach-Object { $_.Body.FindAll({ param($n) $true }, $true) })
$reads = @($installNodes | Where-Object {
  $_ -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
  $_.Extent.Text -match '^\[(System\.)?IO\.File\]::ReadAllBytes\('
})
if ($Mutant) {
  # Also replay against the old text implementation during RED; once the byte
  # implementation exists this selects its actual ReadAllBytes expression.
  $sourceReads = @($installNodes | Where-Object {
    $_ -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
    $_.Extent.Text -match '^\[(System\.)?IO\.File\]::ReadAll(Bytes|Text)\('
  })
  if ($sourceReads.Count -ne 1) { throw 'agent source read missing or ambiguous; cannot replay mutation' }
  $read = $sourceReads[0]
  $text = [IO.File]::ReadAllText($Path)
  $replacement = '(Get-Content -Raw -LiteralPath ' + $read.Arguments[0].Extent.Text + ')'
  $text = $text.Remove($read.Extent.StartOffset, $read.Extent.EndOffset - $read.Extent.StartOffset).
    Insert($read.Extent.StartOffset, $replacement)
  [IO.File]::WriteAllText($Mutant, $text, (New-Object Text.UTF8Encoding($false)))
  exit 0
}
$issues = @()
if ($reads.Count -ne 1) { $issues += 'agent-source-not-ReadAllBytes' }
if (-not @($installNodes | Where-Object {
  $_ -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
  $_.Extent.Text -match '^\[(System\.)?IO\.File\]::WriteAllBytes\('
}).Count) { $issues += 'agent-destination-not-WriteAllBytes' }
$shared = @($install | Where-Object { $ownership.Name -contains $_.Name })
if (-not @($shared | Where-Object { $_.Body.Extent.Text -match '::ReadAllBytes\(' }).Count) {
  $issues += 'agent-bytes-not-shared-with-ownership'
}
if (-not @($installNodes | Where-Object {
  ($_ -is [Management.Automation.Language.CommandAst] -or
   $_ -is [Management.Automation.Language.InvokeMemberExpressionAst]) -and
  $_.Extent.Text -match 'UTF8Encoding(\]::new)?\(\s*\$false\s*\)'
}).Count) { $issues += 'frontmatter-encoder-not-explicit-no-BOM' }
if (-not @($installNodes | Where-Object {
  $_ -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $_.Member.Value -eq 'GetBytes'
}).Count) { $issues += 'frontmatter-not-encoded-to-bytes' }
foreach ($n in @($installNodes) + @($ownNodes)) {
  if ($n -is [Management.Automation.Language.CommandAst] -and
      $n.GetCommandName() -match '^(Get|Set)-Content$') { $issues += 'text-cmdlet-on-agent-path' }
  if ($n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
      $n.Member.Value -match '^(Read|Write)AllText$') { $issues += 'text-IO-on-agent-path' }
}
if ($issues.Count) { Write-Output (($issues | Select-Object -Unique) -join ' '); exit 1 }
PS
if [ -n "$t17_pwsh" ] && [ -x "$t17_pwsh" ]; then
  t17_err=""
  t17_out=$("$t17_pwsh" -NoProfile -NonInteractive -File "$t17_root/check.ps1" -Path "$(pwd)/install.ps1" 2>&1)
  [ "$?" -eq 0 ] || t17_err="$t17_err $t17_out"
  [ -z "$t17_err" ] && ok "T17 agent bodies use shared bytes with no-BOM frontmatter" \
                    || bad "T17 PowerShell agent byte path" "issues:$t17_err"
  t17_err=""
  if "$t17_pwsh" -NoProfile -NonInteractive -File "$t17_root/check.ps1" \
      -Path "$(pwd)/install.ps1" -Mutant "$t17_root/mutant.ps1" > "$t17_root/mutation.log" 2>&1; then
    t17_out=$("$t17_pwsh" -NoProfile -NonInteractive -File "$t17_root/check.ps1" -Path "$t17_root/mutant.ps1" 2>&1)
    t17_rc=$?
    if [ "$t17_rc" -ne 1 ] || ! printf '%s\n' "$t17_out" | grep -qF 'text-cmdlet-on-agent-path'; then
      t17_err="$t17_err Get-Content-mutation-not-rejected:$t17_rc"
    fi
  else
    t17_err="$t17_err cannot-replay-Get-Content-mutation"
  fi
  [ -z "$t17_err" ] && ok "T17 #26 Get-Content mutation is applied and rejected" \
                    || bad "T17 #26 mutation replay" "issues:$t17_err"
else
  skip "T17 PowerShell AST byte-path and mutation check (pwsh unavailable; set PWSH)"
fi

# ---------------------------------------------------------------- T18
# The bash half of the same property, actually executed: an installed agent's
# body must be byte-identical to its source. T17 can only check ps1 statically
# (no pwsh on this machine), so this is the half we can prove.
#
# Iterates agents/*.md directly -- since the rename, source basename IS the
# installed name, so there is no pair table here to fall out of date.
if bash install.sh --prefix "$tmp_prefix" --force >/dev/null 2>&1; then
  t18_err=""
  for src in agents/*.md; do
    name=$(basename "$src" .md)
    dst="$tmp_prefix/agents/${name}.md"
    if [ ! -f "$dst" ]; then t18_err="$t18_err ${name}:missing"; continue; fi
    # Strip the generated frontmatter block plus its trailing blank line.
    awk 'f{print} /^---$/{c++; if(c==2){f=1; getline}}' "$dst" > "$tmp_prefix/.body"
    cmp -s "$tmp_prefix/.body" "$src" || t18_err="$t18_err ${name}:body-differs"
  done
  [ -z "$t18_err" ] && ok "T18 installed agent bodies are byte-identical to source" \
                    || bad "T18 agent body corrupted on install" "issues:$t18_err"
else
  bad "T18 agent body check" "install.sh failed"
fi

# ---------------------------------------------------------------- T19
# Gate integrity. The user may waive their OWN approvals (track, spec, plan);
# they cannot waive the gates that stop an agent claiming done falsely. Without
# this, "just do it -- comply" reads as permission to skip verification too,
# and no other assertion would notice the difference.
t19_err=""
ov=$(sed -n '/^## User override/,$p' agents/fc-pm.md)
echo "$ov" | grep -qi 'may not waive\|cannot waive'   || t19_err="$t19_err no-nonwaivable-clause"
echo "$ov" | grep -qi 'verification evidence'         || t19_err="$t19_err evidence-not-protected"
echo "$ov" | grep -qi 'spec compliance'               || t19_err="$t19_err spec-compliance-not-protected"
# Assert the REQUIREMENT, not the phrase. "need not be the full suite" still
# contains "full suite" -- found by mutation: the meaning inverted while the
# token survived, and T19 stayed green.
grep -qiE '(must|has to) be the full suite' agents/fc-developer.md \
  || t19_err="$t19_err dev-does-not-require-full-suite"
grep -qiE '(need not|does not have to|no need to) be the full suite' agents/fc-developer.md \
  && t19_err="$t19_err dev-full-suite-negated"
[ -z "$t19_err" ] && ok "T19 non-waivable gates named in override + full-suite required" \
                  || bad "T19 gate language weakened" "issues:$t19_err"

# ---------------------------------------------------------------- T20
# Mutation test: prove T10 actually catches a gutted installer.
#
# Two independent audits gutted install.ps1 and watched the whole suite stay
# green. Both mutations are replayed here against T10's own check. If T10 is
# ever weakened back to token-presence, this fails -- a parity test that can't
# detect an installer which installs nothing is not a parity test.
mut=$(mktemp -d)
t20_err=""

# Attack 1 (audit A): top-level dispatch replaced with `exit 0`.
sed 's/^Install-ClaudeGlobal[[:space:]]*$/exit 0/' install.ps1 > "$mut/a.ps1"
if ! grep -qE '^Install-ClaudeGlobal[[:space:]]*$' "$mut/a.ps1"; then
  ps1_operative_ok "$mut/a.ps1" && t20_err="$t20_err attack1-undetected"
else
  t20_err="$t20_err attack1-not-applied"
fi

# Attack 2 (audit B): operative calls commented out, tokens left intact.
sed -e 's/^\([[:space:]]*\)\(Install-Agent \$\)/\1# \2/' \
    -e 's/^\([[:space:]]*\)\(Copy-Tree \$\)/\1# \2/' install.ps1 > "$mut/b.ps1"
if ! grep -qE '^[[:space:]]*Install-Agent[[:space:]]+\$' "$mut/b.ps1"; then
  ps1_operative_ok "$mut/b.ps1" && t20_err="$t20_err attack2-undetected"
else
  t20_err="$t20_err attack2-not-applied"
fi

# Attack 3: same shape against the bash installer.
sed 's/^\([[:space:]]*\)\(install_agent "\)/\1# \2/' install.sh > "$mut/c.sh"
if ! grep -qE '^[[:space:]]*install_agent[[:space:]]+"' "$mut/c.sh"; then
  sh_operative_ok "$mut/c.sh" && t20_err="$t20_err attack3-undetected"
else
  t20_err="$t20_err attack3-not-applied"
fi

# Attack 4 (reviewer): unconditional `throw` before the top-level dispatch.
# Every token stays, the call site stays present and uncommented, and the
# installer still does nothing. This one survived until a reviewer found it.
sed 's/^Install-ClaudeGlobal[[:space:]]*$/throw "stop"\nInstall-ClaudeGlobal/' install.ps1 > "$mut/d.ps1"
if grep -qE '^[[:space:]]*throw "stop"' "$mut/d.ps1"; then
  ps1_operative_ok "$mut/d.ps1" && t20_err="$t20_err attack4-undetected"
else
  t20_err="$t20_err attack4-not-applied"
fi

# Control: the real installers must still pass, or the check is just broken.
ps1_operative_ok install.ps1 || t20_err="$t20_err control-ps1-false-positive"
sh_operative_ok  install.sh  || t20_err="$t20_err control-sh-false-positive"

rm -rf "$mut"
[ -z "$t20_err" ] && ok "T20 T10 detects a gutted installer (4 mutations + 2 controls)" \
                  || bad "T20 mutation test" "issues:$t20_err"

# ---------------------------------------------------------------- T21
# Mutation test: prove T15's probe actually exercises the guard.
#
# The original probe was dot-prefixed, which the installer's `*/` glob never
# enumerates -- so both SKILL.md guards could be deleted and T15 still reported
# ok. Here the guards are stripped from a copy; the probe MUST then be
# installed. If it isn't, the probe is invisible to the glob and T15 is vacuous.
mut2=$(mktemp -d)
t21_err=""
# The mutated copy must live in the repo root: install.sh resolves SCRIPT_DIR
# from its own location, and from /tmp it cannot find agents/.
sed 's#^\([[:space:]]*\)\[ -f "${src}SKILL.md" \] || continue$#\1true#' install.sh > "$T21_SCRIPT"
if ! grep -qF '[ -f "${src}SKILL.md" ] || continue' "$T21_SCRIPT"; then
  mkdir -p "$T15_PROBE"
  if bash "$T21_SCRIPT" --prefix "$mut2/out" --force >/dev/null 2>&1; then
    if [ -d "$mut2/out/skills/$(basename "$T15_PROBE")" ]; then
      ok "T21 T15's probe is glob-visible (guard removal is detectable)"
    else
      t21_err="probe-invisible-to-glob"
    fi
  else
    t21_err="mutated-installer-failed"
  fi
  rmdir "$T15_PROBE" 2>/dev/null
else
  t21_err="mutation-not-applied"
fi
[ -n "$t21_err" ] && bad "T21 T15 is vacuous" "$t21_err"
rm -rf "$mut2" "$T21_SCRIPT"

# ---------------------------------------------------------------- T22
# Data loss. `research` and `build-or-fix` are plausible names for a user's own
# skill. Three prior versions of the ownership check each destroyed user data a
# different way -- no check, a whole-file grep, then a description prefix.
#
# Probes use REAL published content from git rather than hand-written
# fixtures. A fixture that only approximates what we shipped tests the fixture,
# not the classifier -- which is how the prefix-collision bug survived two
# rounds of this test passing.
t22_prefix=$(mktemp -d)
mkdir -p "$t22_prefix/skills/research" "$t22_prefix/skills/build-or-fix"
# Not ours: shares the opening words of our description, differs after.
cat > "$t22_prefix/skills/research/SKILL.md" <<'PROBE'
---
name: research
description: Multi-agent research pipeline (search my notes, then my bookmarks). Mine, not this framework's.
---
Years of personal notes.
PROBE
# Ours: byte-for-byte what v4.0 published.
git show v4.0:.claude/skills/build-or-fix/SKILL.md > "$t22_prefix/skills/build-or-fix/SKILL.md" 2>/dev/null
if bash install.sh --prefix "$t22_prefix" --force >/dev/null 2>&1; then
  t22_err=""
  [ -f "$t22_prefix/skills/research/SKILL.md" ] || t22_err="$t22_err DESTROYED-user-skill"
  [ -d "$t22_prefix/skills/build-or-fix" ]      && t22_err="$t22_err kept-our-own-legacy-skill"
  [ -z "$t22_err" ] && ok "T22 legacy cleanup removes only skills we published" \
                    || bad "T22 legacy cleanup" "issues:$t22_err"
else
  bad "T22 legacy cleanup" "install.sh failed"
fi
rm -rf "$t22_prefix"

# ---------------------------------------------------------------- T23
# --dry-run must not claim a deletion it did not perform. A user auditing a
# dry run before upgrading would otherwise read "removed" and believe their v3
# skills were already gone.
t23_prefix=$(mktemp -d)
mkdir -p "$t23_prefix/skills/research"
cat > "$t23_prefix/skills/research/SKILL.md" <<'PROBE'
---
name: research
description: Multi-agent research pipeline. audit-pair: degraded
---
PROBE
out=$(bash install.sh --prefix "$t23_prefix" --dry-run 2>&1)
t23_err=""
[ -d "$t23_prefix/skills/research" ] || t23_err="$t23_err dry-run-actually-deleted"
echo "$out" | grep -qE '^removed \(legacy skill\)' && t23_err="$t23_err claims-removed-but-did-not"
[ -z "$t23_err" ] && ok "T23 --dry-run does not claim deletions it did not make" \
                  || bad "T23 dry-run lies" "issues:$t23_err"
rm -rf "$t23_prefix"

# ---------------------------------------------------------------- T24
# Two logic holes both reviewers found in the audit rule.
#
# (a) Family collision. A computed reviewer from the artifact author's known
#     family must differ or the gate is recorded unsatisfied rather than met.
# (b) Standard step 3 skips the spec audit, while the rule says EVERY
#     model-authored hard-gate artifact is audited. Whichever way that is
#     resolved, the exemption has to be stated in the rule -- otherwise a
#     reader who trusts the rule is misled by the flow, and vice versa.
b=.claude/skills/fc-build-or-fix/SKILL.md
t24_err=""
rule=$(sed -n '/^## Cross-family audit/,/^## Dispatch/p' "$b")
echo "$rule" | grep -qi 'collision\|same family'   || t24_err="$t24_err no-collision-check"
echo "$rule" | grep -qi 'unsatisfied'              || t24_err="$t24_err collision-not-recorded"
echo "$rule" | grep -qi 'exempt'                   || t24_err="$t24_err exemption-unstated"
# The FLOW must cite the exemption, not merely contain the word somewhere. A
# loose 'exemption' alternative here was satisfied by the rule itself and by
# "Just Do It is exempt" -- neither of which is step 3 -- so stripping step 3's
# clause left this green. Match the exact phrase step 3 uses.
grep -qF 'one of the two exemptions' "$b" || t24_err="$t24_err flow-does-not-cite-exemption"
[ -z "$t24_err" ] && ok "T24 audit rule handles family collision + names its exemptions" \
                  || bad "T24 audit rule has a logic hole" "issues:$t24_err"

# ---------------------------------------------------------------- T25
# Agent source filenames are fc-prefixed, and the installed subagent name is
# exactly the source basename. Previously the installer carried a
# filename -> name mapping table (pm.md -> fc-pm), which is a second place for
# the two to disagree; renaming the sources deleted that class of bug. This
# asserts the property rather than the table.
t25_err=""
while IFS= read -r f; do
  base=$(basename "$f")
  case "$base" in fc-*) ;; *) t25_err="$t25_err src:$base" ;; esac
done < <(find agents -maxdepth 1 -name '*.md')

if bash install.sh --prefix "$tmp_prefix" --force >/dev/null 2>&1; then
  for f in agents/*.md; do
    base=$(basename "$f" .md)
    inst="$tmp_prefix/agents/${base}.md"
    if [ ! -f "$inst" ]; then
      t25_err="$t25_err notinstalled:$base"
    elif ! head -3 "$inst" | grep -q "^name: ${base}$"; then
      t25_err="$t25_err namemismatch:$base"
    fi
  done
else
  t25_err="$t25_err install-failed"
fi
[ -z "$t25_err" ] && ok "T25 agent source names are fc-prefixed and match installed names" \
                  || bad "T25 agent name drift" "issues:$t25_err"

# ---------------------------------------------------------------- T26
# Every artifact the canonical rule names must have a matching audit step in
# the flow. The rule named `plan` as must-audit while the Complex flow went
# architect -> user approval -> implementation with no audit between; five
# independent reviewers caught it and the tests did not. T6 only counts where
# the rule is *stated*, never whether the flow obeys it.
c=.claude/skills/fc-build-or-fix/reference/complex-track.md
t26_err=""
if [ -f "$c" ]; then
  grep -qi 'cross-audit the spec' "$c" || t26_err="$t26_err spec-unaudited"
  grep -qi 'cross-audit the plan' "$c" || t26_err="$t26_err plan-unaudited"
  grep -qi 'fc-qa-spec\|fc-qa-code' "$c" || t26_err="$t26_err diff-unaudited"
  # Require the tech lead to be DISPATCHED, not merely named. A reviewer
  # replaced the step with "Do not dispatch fc-tech-lead; merge directly" and
  # this stayed green on the bare token.
  grep -qiE 'dispatch `?fc-tech-lead' "$c" || t26_err="$t26_err final-not-dispatched"
  grep -qiE '(do not|don.t|no need to) dispatch.*fc-tech-lead|merge directly' "$c" \
    && t26_err="$t26_err final-audit-negated"
  # The plan audit must come BEFORE the user approves it, or it audits nothing.
  # Case-insensitive to match the presence checks above: a case-only edit would
  # otherwise leave pa empty, and the [ -n "$pa" ] guard would skip this
  # silently while presence still matched.
  pa=$(grep -ni 'cross-audit the plan' "$c" | cut -d: -f1 | head -1)
  ap=$(grep -ni 'user approves the plan' "$c" | cut -d: -f1 | head -1)
  if [ -z "$pa" ] || [ -z "$ap" ]; then
    t26_err="$t26_err plan-audit-or-approval-missing"
  elif [ "$pa" -ge "$ap" ]; then
    t26_err="$t26_err plan-audit-after-approval"
  fi
else
  t26_err=" complex-track-missing"
fi
[ -z "$t26_err" ] && ok "T26 every artifact named in the rule has an audit step in the flow" \
                  || bad "T26 rule/flow mismatch" "issues:$t26_err"

echo
# ---------------------------------------------------------------- T27
# The provenance classifier's real boundaries, both directions. Each case here
# is a bug that actually shipped or a false negative a reviewer demonstrated.
#
# The classifier must delete a file we published and keep everything else. Two
# earlier versions passed a version of this test while still destroying user
# data, because the probes avoided the exact shapes that trigger the bug.
t27_err=""
t27_case() { # name, expect(survive|removed), file-producer
  local label="$1" expect="$2" p; p=$(mktemp -d)
  mkdir -p "$p/skills/research"
  eval "$3" > "$p/skills/research/SKILL.md"
  bash install.sh --prefix "$p" >/dev/null 2>&1
  if [ "$expect" = "survive" ] && [ ! -f "$p/skills/research/SKILL.md" ]; then
    t27_err="$t27_err ${label}:DESTROYED"
  elif [ "$expect" = "removed" ] && [ -d "$p/skills/research" ]; then
    t27_err="$t27_err ${label}:kept"
  fi
  # Uninstall shares the same classifier and is equally destructive.
  if [ "$expect" = "survive" ] && [ -f "$p/skills/research/SKILL.md" ]; then
    bash install.sh --prefix "$p" --uninstall >/dev/null 2>&1
    [ -f "$p/skills/research/SKILL.md" ] || t27_err="$t27_err ${label}:DESTROYED-on-uninstall"
  fi
  rm -rf "$p"
}

# Must survive: personal skills that merely resemble ours.
t27_case mentions-us survive "printf '%s\n' '---' 'name: research' \
  'description: My own skill, loosely inspired by Feature-Crew.' '---' 'Notes. audit-pair too.'"
t27_case shares-prefix survive "printf '%s\n' '---' 'name: research' \
  'description: Multi-agent research pipeline (search my notes, then my bookmarks). Mine.' '---' 'Notes.'"
t27_case edited-legacy survive "git show v3.1:.claude/skills/research/SKILL.md | sed '\$a\\
My own additions.'"

# Must be removed: content we actually published, LF and CRLF alike.
t27_case published-lf   removed "git show v3.1:.claude/skills/research/SKILL.md"
t27_case published-crlf removed "git show v3.1:.claude/skills/research/SKILL.md | sed 's/\$/\r/'"

[ -z "$t27_err" ] && ok "T27 provenance classifier correct on 5 boundary cases" \
                  || bad "T27 provenance boundary" "issues:$t27_err"

# ---------------------------------------------------------------- T28
# The escalation list is stated ONCE. It sets the track floor and decides
# whether the Standard spec cross-audit fires, so two copies that drift give
# two different answers about whether a hard gate applies -- which is what
# happened: SKILL.md listed secrets and deploy behavior, fc-pm.md did not.
t28_err=""
listers=$(git grep -l 'secrets, persistence, public API contract' -- '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$listers" = "1" ] || t28_err="$t28_err stated-in-${listers}-files"
grep -q 'escalation list' agents/fc-pm.md || t28_err="$t28_err pm-does-not-point-at-it"
grep -qE '^- Auth, security, persistence, or config' agents/fc-pm.md \
  && t28_err="$t28_err pm-restates-its-own-list"
[ -z "$t28_err" ] && ok "T28 escalation list stated once; fc-pm.md points at it" \
                  || bad "T28 escalation list split" "issues:$t28_err"

# ---------------------------------------------------------------- T29
# Uninstall must not destroy work install protected. Install SKIPS a
# pre-existing file ("skip (exists)"), then uninstall deleted it anyway -- so a
# personal skill or agent sharing one of our fc- names was silently lost. The
# fc- prefix makes that unlikely, not impossible, and this PR widened the
# surface from 2 names to 12.
t29_prefix=$(mktemp -d)
mkdir -p "$t29_prefix/skills/fc-review" "$t29_prefix/agents"
printf -- '---\nname: fc-review\n---\nMY OWN review skill.\n' > "$t29_prefix/skills/fc-review/SKILL.md"
printf -- '---\nname: fc-pm\n---\nMY OWN pm agent.\n'         > "$t29_prefix/agents/fc-pm.md"
t29_err=""
bash install.sh --prefix "$t29_prefix" >/dev/null 2>&1
grep -q "MY OWN" "$t29_prefix/skills/fc-review/SKILL.md" 2>/dev/null || t29_err="$t29_err install-clobbered-skill"
grep -q "MY OWN" "$t29_prefix/agents/fc-pm.md" 2>/dev/null           || t29_err="$t29_err install-clobbered-agent"
bash install.sh --prefix "$t29_prefix" --uninstall >/dev/null 2>&1
grep -q "MY OWN" "$t29_prefix/skills/fc-review/SKILL.md" 2>/dev/null || t29_err="$t29_err DESTROYED-skill-on-uninstall"
grep -q "MY OWN" "$t29_prefix/agents/fc-pm.md" 2>/dev/null           || t29_err="$t29_err DESTROYED-agent-on-uninstall"
rm -rf "$t29_prefix"

# The other direction: an untouched install must be fully removed, or the
# check above could pass by never deleting anything.
t29b=$(mktemp -d)
bash install.sh --prefix "$t29b" --force >/dev/null 2>&1
bash install.sh --prefix "$t29b" --uninstall >/dev/null 2>&1
[ "$(ls "$t29b/agents" 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ] || t29_err="$t29_err ours-not-removed"
[ "$(ls "$t29b/skills" 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ] || t29_err="$t29_err our-skills-not-removed"
rm -rf "$t29b"

# And a file of ours the user edited is theirs now.
t29c=$(mktemp -d)
bash install.sh --prefix "$t29c" --force >/dev/null 2>&1
printf '\nmy note\n' >> "$t29c/skills/fc-review/SKILL.md"
bash install.sh --prefix "$t29c" --uninstall >/dev/null 2>&1
[ -f "$t29c/skills/fc-review/SKILL.md" ] || t29_err="$t29_err DESTROYED-edited-skill"
rm -rf "$t29c"

[ -z "$t29_err" ] && ok "T29 uninstall removes only untouched files it installed" \
                  || bad "T29 uninstall data loss" "issues:$t29_err"

# ---------------------------------------------------------------- T30
# --uninstall --dry-run must not claim removals it does not perform. The
# install path was fixed for this; the uninstall path still printed "removed:"
# for all 12 artifacts while deleting none.
t30_prefix=$(mktemp -d)
bash install.sh --prefix "$t30_prefix" --force >/dev/null 2>&1
t30_out=$(bash install.sh --prefix "$t30_prefix" --uninstall --dry-run 2>&1)
t30_err=""
echo "$t30_out" | grep -qE '^removed' && t30_err="$t30_err claims-removed-but-did-not"
[ "$(ls "$t30_prefix/agents" 2>/dev/null | wc -l | tr -d ' ')" -eq 6 ] || t30_err="$t30_err dry-run-actually-deleted"
[ -z "$t30_err" ] && ok "T30 --uninstall --dry-run claims nothing it did not do" \
                  || bad "T30 uninstall dry-run lies" "issues:$t30_err"
rm -rf "$t30_prefix"

# ---------------------------------------------------------------- T31
# The GitHub release body is the changelog. A changelog file would be a second
# record to keep in sync, and the file is always the one that drifts -- the
# last one went stale inside a single session, claiming 26 assertions when
# there were 31.
#
# This also protects T4: with no such file there is no tracked document that
# legitimately names a removed model string, so T4 needs no pathspec
# exclusion. Reintroducing the file would invite reinstating that exclusion,
# which would be a permanent hiding place for stale strings.
t31_err=""
[ -f CHANGELOG.md ] && t31_err="$t31_err file-reintroduced"

# Check T4's actual command line, extracted -- not a pattern match over this
# file. Any pattern naming the string matches this very assertion, which is a
# self-reference trap I walked into twice before doing it this way.
t4_line=$(grep -E '^stale=\$\(git grep' tests/framework_test.sh)
case "$t4_line" in *CHANGELOG*) t31_err="$t31_err t4-exclusion-back" ;; esac

# Docs must not LINK to a changelog file. Explaining why there isn't one is
# fine and expected; a markdown link to the path is the failure.
git grep -qE '\]\(\.?/?CHANGELOG\.md\)' -- '*.md' 2>/dev/null \
  && t31_err="$t31_err docs-link-to-file"

# The workflow must generate a body rather than defer to a file.
grep -q 'release-notes.md' .github/workflows/release.yml || t31_err="$t31_err workflow-writes-no-body"
grep -q 'feature-crew ' .github/workflows/release.yml     || t31_err="$t31_err workflow-missing-heading"

[ -z "$t31_err" ] && ok "T31 release body is the changelog; no changelog file in repo" \
                  || bad "T31 changelog duplication" "issues:$t31_err"

# ---------------------------------------------------------------- T32
# Static contract alarm only: shell cannot execute Claude Code Agent dispatches.
# Guard the canonical selector's branches, provenance envelope, explicit model
# override, reviewer non-self-identification, and fail-closed/no-fallback cases.
b=.claude/skills/fc-build-or-fix/SKILL.md
t32_err=""
selector=$(sed -n '/^## Cross-family audit/,/^## Dispatch/p' "$b")
echo "$selector" | grep -qiE 'Sonnet.family author.*model: *opus|author.*Sonnet.family.*`?opus`?' \
  || t32_err="$t32_err sonnet-author-to-opus-missing"
echo "$selector" | grep -qiE '(non-Sonnet.family|known.*other.*family).*model: *sonnet|(non-Sonnet.family|known.*other.*family).*`?sonnet`?' \
  || t32_err="$t32_err non-sonnet-author-to-sonnet-missing"
echo "$selector" | grep -qiE 'Agent.*model.*override|explicit.*model.*override' \
  || t32_err="$t32_err explicit-agent-override-missing"
echo "$selector" | grep -qi 'artifact.*identity' || t32_err="$t32_err artifact-identity-missing"
echo "$selector" | grep -qiE 'author family|author-family' || t32_err="$t32_err author-family-missing"
echo "$selector" | grep -qiE 'audit envelope|gate record' || t32_err="$t32_err gate-envelope-missing"
echo "$selector" | grep -qiE 'must not infer|never infer|do not infer' || t32_err="$t32_err reviewer-self-inference-not-banned"
echo "$selector" | grep -qiE 'unknown.*(family|provenance).*GATE UNSATISFIED|GATE UNSATISFIED.*unknown' \
  || t32_err="$t32_err unknown-provenance-not-fail-closed"
echo "$selector" | grep -qiE 'same.family.*GATE UNSATISFIED|GATE UNSATISFIED.*same.family' \
  || t32_err="$t32_err collision-not-fail-closed"
echo "$selector" | grep -qiE '(failure|unavailable).*(GATE UNSATISFIED)|GATE UNSATISFIED.*(failure|unavailable)' \
  || t32_err="$t32_err dispatch-failure-not-fail-closed"
echo "$selector" | grep -qiE 'no fallback|never.*fallback|do not.*fallback' \
  || t32_err="$t32_err author-family-fallback-not-banned"
echo "$selector" | grep -qiE 'tests-as-spec.*author family|author family.*tests-as-spec' \
  || t32_err="$t32_err tests-as-spec-provenance-missing"
[ -z "$t32_err" ] && ok "T32 static contract alarm: dynamic hard-gate selector retained" \
                   || bad "T32 dynamic selector prose contract" "missing:$t32_err"

# Duplicate YAML keys can hide an override even when installed files look
# superficially right. Mutate one generated agent and require the shared T5
# validator to return the exact duplicate-key diagnostic. A crash, import error,
# empty glob, or unrelated diagnostic is a test failure, not a rejection.
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import yaml' >/dev/null 2>&1; then
  skip "T5 duplicate-key mutation — YAML parser unavailable"
else
  t5_mut="$(mktemp -d)"
  CLEANUP_PATHS+=("$t5_mut")
  if ! bash install.sh --prefix "$t5_mut" --force >/dev/null 2>&1; then
    bad "T5 duplicate-key mutation" "install.sh failed"
  else
    python3 - "$t5_mut/agents/fc-qa-code.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("description:", "model: sonnet\nmodel: opus\ndescription:", 1)
open(p, "w", encoding="utf-8").write(s)
PY
    t5_mut_out=""
    if t5_mut_out=$(validate_role_frontmatter "$t5_mut" 2>&1); then
      if [ "$t5_mut_out" = "fc-qa-code:duplicate-keys" ]; then
        ok "T5 duplicate-key mutation returns expected diagnostic"
      else
        bad "T5 duplicate-key mutation" "got '${t5_mut_out:-<empty>}', want 'fc-qa-code:duplicate-keys'"
      fi
    else
      t5_mut_rc=$?
      bad "T5 duplicate-key mutation" "validator exited $t5_mut_rc: ${t5_mut_out:-<no diagnostic>}"
    fi
  fi
  rm -rf "$t5_mut"
fi

# ---------------------------------------------------------------- T33
# Natural-language, need-based composition is canonical in build-or-fix. The
# alarm checks all five routes and bounded return-to-origin behavior; it is not
# runtime proof that a model will classify every request correctly.
t33_err=""
classifier=$(sed -n '/^## Need classifier/,/^## /p' "$b")
echo "$classifier" | grep -qiE 'one discoverable fact.*look.*up|look.*up.*one discoverable fact' \
  || t33_err="$t33_err direct-fact-route"
echo "$classifier" | grep -qiE 'several places.*fc-research|fc-research.*several places' \
  || t33_err="$t33_err research-route"
echo "$classifier" | grep -qiE 'user-owned.*(requirement|decision).*fc-grill-me|fc-grill-me.*user-owned.*(requirement|decision)' \
  || t33_err="$t33_err grill-route"
echo "$classifier" | grep -qiE '(unresolved solution|approach|options).*fc-brainstorm|fc-brainstorm.*(unresolved solution|approach|options)' \
  || t33_err="$t33_err brainstorm-route"
echo "$classifier" | grep -qiE '(chosen consequential decision|adversarial confidence).*fc-second-opinion|fc-second-opinion.*(chosen consequential decision|adversarial confidence)' \
  || t33_err="$t33_err second-opinion-route"
echo "$classifier" | grep -qiE 'return.*origin|originat(ing|or).*resume' \
  || t33_err="$t33_err return-to-origin"
echo "$classifier" | grep -qiE 'must not self-invoke|no self-invocation|never self-invoke' \
  || t33_err="$t33_err no-self-invocation"
echo "$classifier" | grep -qiE 'do not repeat|never repeat|no repeat' \
  || t33_err="$t33_err no-repeat"
echo "$classifier" | grep -qiE 'recurs|cycle' || t33_err="$t33_err no-cycles"
if grep -q '^disable-model-invocation: true$' .claude/skills/fc-grill-me/SKILL.md; then
  t33_err="$t33_err grill-not-model-invocable"
fi
# Pointer docs must not grow a second copy of the canonical route table.
dup_classifier=$(git grep -lF '| One discoverable fact |' -- README.md CLAUDE.md agents/fc-pm.md \
  '.claude/skills/fc-brainstorm/SKILL.md' 2>/dev/null || true)
[ -z "$dup_classifier" ] || t33_err="$t33_err duplicated-classifier:$(echo "$dup_classifier" | tr '\n' ',')"
[ -z "$t33_err" ] && ok "T33 static contract alarm: five need routes + bounded return-to-origin" \
                   || bad "T33 need-composition prose contract" "missing:$t33_err"

# ---------------------------------------------------------------- T34
# Reject obsolete track/pin language from active shipped content, while leaving
# intentional standalone skill pins (fc-review/fc-second-opinion) outside scope.
t34_err=""
stale_track=$(printf 'Tri%s' 'vial')
stale_track_files=$(git grep -l -w "$stale_track" -- README.md CLAUDE.md agents '*.sh' '*.ps1' '.github/workflows/*' '.claude/skills/**' 2>/dev/null || true)
[ -z "$stale_track_files" ] || t34_err="$t34_err stale-track:$(echo "$stale_track_files" | tr '\n' ',')"
stale_pins=$(git grep -lE 'review (agents|roles).*(pinned|model: sonnet)|pinned to `?model: sonnet|review-family model|review family|different model family|session default model' -- \
  README.md CLAUDE.md agents install.sh install.ps1 '.github/workflows/*' '.claude/skills/fc-build-or-fix/**' '.claude/skills/fc-brainstorm/**' '.claude/skills/fc-research/**' '.claude/skills/fc-update/**' 2>/dev/null || true)
[ -z "$stale_pins" ] || t34_err="$t34_err stale-role-pin:$(echo "$stale_pins" | tr '\n' ',')"
[ -z "$t34_err" ] && ok "T34 no stale legacy-track or role-pin wording in active shipped content" \
                   || bad "T34 stale framework wording" "issues:$t34_err"

# ---------------------------------------------------------------- T35
# Exercise both PowerShell invocation forms, not just parameter-name tokens.
# PATH is controlled: an unrelated bash must never win, and a Git-layout stub
# proves delegation and argv forwarding without requiring Windows on this host.
t35_root=$(mktemp -d)
CLEANUP_PATHS+=("$t35_root")
t35_repo=$(pwd)
mkdir -p "$t35_root/empty-path"
PWSH_BIN="${PWSH:-$(command -v pwsh 2>/dev/null || true)}"

# Quote a path as a PowerShell literal; switches remain unquoted in -Command
# so these are the same calls a user types, not array-splatting approximations.
t35_ps_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"; }
t35_run() {
  local name="$1" path="$2"; shift 2
  t35_case="$t35_root/$name"
  mkdir -p "$t35_case/home/.config/powershell" "$t35_case/cwd"
  printf '%s\n' 'Set-StrictMode -Version Latest' > "$t35_case/home/.config/powershell/Microsoft.PowerShell_profile.ps1"
  ( cd "$t35_case/cwd" && env -i HOME="$t35_case/home" PATH="$path" \
      POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off \
      "$PWSH_BIN" -NonInteractive "$@" ) \
    > "$t35_case/stdout" 2> "$t35_case/stderr"
  t35_rc=$?
  t35_err=""
}
t35_expect_rc() {
  [ "$t35_rc" -eq "$1" ] || t35_err="$t35_err exit=$t35_rc(want-$1)"
}
t35_unchanged() {
  [ ! -e "$t35_prefix" ] || t35_err="$t35_err prefix-created"
  [ ! -e "$t35_case/home/.claude" ] || t35_err="$t35_err HOME-install-created"
  [ -z "$(ls -A "$t35_case/cwd")" ] || t35_err="$t35_err cwd-not-empty"
}
t35_installed() {
  local got src name
  got=$(find "$t35_prefix/agents" -maxdepth 1 -type f -name 'fc-*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$got" -eq "$t35_want_agents" ] || t35_err="$t35_err agents=$got(want-$t35_want_agents)"
  for src in "$t35_repo"/.claude/skills/*/SKILL.md; do
    [ -f "$src" ] || continue
    name=$(basename "$(dirname "$src")")
    [ -f "$t35_prefix/skills/$name/SKILL.md" ] || t35_err="$t35_err missing-skill:$name"
  done
}
t35_result() {
  if [ -z "$t35_err" ]; then
    ok "$1"
  else
    bad "$1" "issues:$t35_err"
    # Keep the actual process diagnostic when binding failed before dispatch.
    sed $'s/\033\\[[0-9;]*m//g; s/^/        /' "$t35_case/stderr"
  fi
}

if [ -n "$PWSH_BIN" ] && [ -x "$PWSH_BIN" ]; then
  PWSH_BIN="$(cd "$(dirname "$PWSH_BIN")" && pwd)/$(basename "$PWSH_BIN")"
  t35_ps1=$(t35_ps_quote "$t35_repo/install.ps1")
  t35_want_agents=$(find agents -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
  t35_decoy="$t35_root/decoy"
  t35_git="$t35_root/git"
  t35_marker="$t35_root/decoy-ran"
  mkdir -p "$t35_decoy" "$t35_git/cmd" "$t35_git/bin"
  cat > "$t35_decoy/bash" <<STUB
#!/bin/sh
printf '%s\n' ran > "$t35_marker"
exit 127
STUB
  chmod +x "$t35_decoy/bash"

  t35_prefix="$t35_root/a-prefix"
  t35_run a "$t35_decoy" -File "$t35_repo/install.ps1" -Prefix "$t35_prefix"
  t35_expect_rc 0
  [ ! -e "$t35_marker" ] || t35_err="$t35_err PATH-decoy-ran"
  t35_installed
  t35_result "T35a unrelated PATH bash is ignored; fallback installs all agents and skills"

  printf '#!/bin/sh\nexit 0\n' > "$t35_git/cmd/git"
  cat > "$t35_git/bin/bash.exe" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$t35_root/git-args"
exit 0
STUB
  chmod +x "$t35_git/cmd/git" "$t35_git/bin/bash.exe"
  rm -f "$t35_marker"
  t35_prefix="$t35_root/b-prefix"
  t35_run b "$t35_git/cmd:$t35_decoy" -File "$t35_repo/install.ps1" --dry-run --prefix "$t35_prefix"
  t35_expect_rc 0
  [ ! -e "$t35_marker" ] || t35_err="$t35_err PATH-decoy-ran"
  if [ -f "$t35_root/git-args" ]; then
    t35_first=$(head -1 "$t35_root/git-args")
    case "$t35_first" in */install.sh) ;; *) t35_err="$t35_err first-arg-not-install.sh" ;; esac
    for t35_arg in --dry-run --prefix "$t35_prefix"; do
      grep -qxF -- "$t35_arg" "$t35_root/git-args" || t35_err="$t35_err arg-not-forwarded:$t35_arg"
    done
  else
    t35_err="$t35_err Git-bash-not-run"
  fi
  t35_unchanged
  t35_result "T35b Git-layout bash receives install.sh and GNU-style flags"

  cat > "$t35_git/bin/bash.exe" <<STUB
#!/bin/sh
printf '%s\n' ran > "$t35_root/git-ran"
exit 127
STUB
  rm -f "$t35_marker"
  t35_prefix="$t35_root/c-prefix"
  t35_run c "$t35_git/cmd:$t35_decoy" -Command "& $t35_ps1 --prefix $(t35_ps_quote "$t35_prefix"); exit \$LASTEXITCODE"
  t35_expect_rc 0
  [ -e "$t35_root/git-ran" ] || t35_err="$t35_err Git-bash-not-run"
  [ ! -e "$t35_marker" ] || t35_err="$t35_err PATH-decoy-ran"
  grep -qF 'using the PowerShell installer' "$t35_case/stderr" || t35_err="$t35_err fallback-warning-missing"
  t35_installed
  t35_result "T35c Git Bash exit 127 falls back, warns, and does not leak its exit code"

  cat > "$t35_git/bin/bash.exe" <<STUB
#!/bin/sh
printf '%s\n' ran > "$t35_root/git-ran"
exit 126
STUB
  rm -f "$t35_marker" "$t35_root/git-ran"
  t35_prefix="$t35_root/m-prefix"
  t35_run m "$t35_git/cmd:$t35_decoy" -Command "& $t35_ps1 --prefix $(t35_ps_quote "$t35_prefix"); exit \$LASTEXITCODE"
  t35_expect_rc 0
  [ -e "$t35_root/git-ran" ] || t35_err="$t35_err Git-bash-not-run"
  [ ! -e "$t35_marker" ] || t35_err="$t35_err PATH-decoy-ran"
  grep -qxF 'feature-crew: Git Bash could not run install.sh (exit 126); using the PowerShell installer.' "$t35_case/stderr" || t35_err="$t35_err fallback-warning-missing"
  t35_installed
  t35_result "T35m Git Bash exit 126 falls back, warns, and does not leak its exit code"

  # A missing interpreter fails to launch; a non-executable file may open in an app.
  cat > "$t35_git/bin/bash.exe" <<STUB
#!$t35_root/missing-interpreter
printf '%s\n' ran > "$t35_root/git-ran"
STUB
  chmod +x "$t35_git/bin/bash.exe"
  rm -f "$t35_marker" "$t35_root/git-ran"
  t35_prefix="$t35_root/n-prefix"
  t35_run n "$t35_git/cmd:$t35_decoy" -Command "& $t35_ps1 --prefix $(t35_ps_quote "$t35_prefix"); exit \$LASTEXITCODE"
  t35_expect_rc 0
  [ ! -e "$t35_root/git-ran" ] || t35_err="$t35_err unstartable-bash-ran"
  [ ! -e "$t35_marker" ] || t35_err="$t35_err PATH-decoy-ran"
  grep -qxF 'feature-crew: Git Bash could not run install.sh (exit 127); using the PowerShell installer.' "$t35_case/stderr" || t35_err="$t35_err fallback-warning-missing"
  t35_installed
  t35_result "T35n Git Bash launch failure falls back, warns, and installs successfully"

  t35_prefix="$t35_root/d-target"
  t35_run d-prefix "$t35_root/empty-path" -Command "& $t35_ps1 --dry-run --prefix $(t35_ps_quote "$t35_prefix"); exit \$LASTEXITCODE"
  t35_expect_rc 0
  grep -qF 'DRY-RUN:' "$t35_case/stdout" || t35_err="$t35_err dry-run-output-missing"
  t35_unchanged
  t35_result "T35d typed GNU-style dry run with prefix changes nothing"

  t35_prefix="$t35_root/d-default-target"
  t35_run d-default "$t35_root/empty-path" -Command "& $t35_ps1 --dry-run; exit \$LASTEXITCODE"
  t35_expect_rc 0
  grep -qF 'DRY-RUN:' "$t35_case/stdout" || t35_err="$t35_err dry-run-output-missing"
  t35_unchanged
  t35_result "T35d typed --dry-run alone creates no HOME install or --dry-run folder"

  t35_prefix="$t35_root/e-prefix"
  t35_run e "$t35_root/empty-path" -File "$t35_repo/install.ps1" --dry-run --prefix "$t35_prefix"
  t35_expect_rc 0
  grep -qF 'DRY-RUN:' "$t35_case/stdout" || t35_err="$t35_err dry-run-output-missing"
  t35_unchanged
  t35_result "T35e -File accepts GNU-style dry run without installing"

  for t35_bad_arg in --bogus foo; do
    t35_prefix="$t35_root/f-prefix"
    t35_run "f-$t35_bad_arg" "$t35_root/empty-path" -Command "& $t35_ps1 $t35_bad_arg; exit \$LASTEXITCODE"
    t35_expect_rc 2
    grep -qxF -- "Unknown option: $t35_bad_arg" "$t35_case/stderr" || t35_err="$t35_err unknown-option-diagnostic-missing"
    t35_unchanged
    t35_result "T35f typed $t35_bad_arg is rejected before changing anything"
  done

  t35_prefix="$t35_root/g-prefix"
  t35_run g "$t35_root/empty-path" -Command "& $t35_ps1 --prefix; exit \$LASTEXITCODE"
  t35_expect_rc 2
  grep -qxF 'Missing value for --prefix' "$t35_case/stderr" || t35_err="$t35_err missing-value-diagnostic-missing"
  t35_unchanged
  t35_result "T35g typed --prefix requires a value before changing anything"

  for t35_help in typed file alias; do
    t35_prefix="$t35_root/h-prefix"
    case "$t35_help" in
      typed) t35_run h-typed "$t35_root/empty-path" -Command "& $t35_ps1 --help; exit \$LASTEXITCODE" ;;
      file)  t35_run h-file "$t35_root/empty-path" -File "$t35_repo/install.ps1" --help ;;
      alias) t35_run h-alias "$t35_root/empty-path" -Command "& $t35_ps1 -h; exit \$LASTEXITCODE" ;;
    esac
    t35_expect_rc 0
    for t35_flag in --dry-run -DryRun; do
      grep -qF -- "$t35_flag" "$t35_case/stdout" || t35_err="$t35_err usage-missing:$t35_flag"
    done
    t35_unchanged
    t35_result "T35h $t35_help help names both flag spellings and changes nothing"
  done

  t35_run j-default "$t35_root/empty-path" -File "$t35_repo/install.ps1"
  t35_prefix="$t35_case/home/.claude"
  t35_expect_rc 0
  t35_installed
  t35_result "T35j strict profile: no arguments installs all agents and skills under HOME"

  t35_prefix="$t35_root/j-dry-target"
  t35_run j-dry-run "$t35_root/empty-path" -Command "& $t35_ps1 -DryRun -Prefix $(t35_ps_quote "$t35_prefix"); exit \$LASTEXITCODE"
  t35_expect_rc 0
  grep -qF 'DRY-RUN:' "$t35_case/stdout" || t35_err="$t35_err dry-run-output-missing"
  t35_unchanged
  t35_result "T35j strict profile: typed PowerShell dry run changes nothing"

  t35_prefix="$t35_root/j-install-target"
  t35_run j-install "$t35_root/empty-path" -File "$t35_repo/install.ps1" -Prefix "$t35_prefix"
  t35_expect_rc 0
  t35_installed
  t35_result "T35j strict profile: native -Prefix installs all agents and skills"

  t35_run j-uninstall "$t35_root/empty-path" -File "$t35_repo/install.ps1" -Prefix "$t35_prefix" -Uninstall
  t35_expect_rc 0
  t35_left=$(find "$t35_prefix/agents" -maxdepth 1 -type f -name 'fc-*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$t35_left" -eq 0 ] || t35_err="$t35_err agents-left:$t35_left"
  [ -z "$(ls -A "$t35_prefix/skills" 2>/dev/null)" ] || t35_err="$t35_err skills-left"
  t35_result "T35j strict profile: native -Uninstall removes installed agents and skills"

  cat > "$t35_git/bin/bash.exe" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$t35_root/j-git-args"
exit 0
STUB
  rm -f "$t35_marker"
  t35_prefix="$t35_root/j-git-target"
  t35_run j-git "$t35_git/cmd:$t35_decoy" -Command "& $t35_ps1 -Prefix $(t35_ps_quote "$t35_prefix"); exit \$LASTEXITCODE"
  t35_expect_rc 0
  [ ! -e "$t35_marker" ] || t35_err="$t35_err PATH-decoy-ran"
  if [ -f "$t35_root/j-git-args" ]; then
    t35_first=$(head -1 "$t35_root/j-git-args")
    case "$t35_first" in */install.sh) ;; *) t35_err="$t35_err first-arg-not-install.sh" ;; esac
    for t35_arg in --prefix "$t35_prefix"; do
      grep -qxF -- "$t35_arg" "$t35_root/j-git-args" || t35_err="$t35_err arg-not-forwarded:$t35_arg"
    done
  else
    t35_err="$t35_err Git-bash-not-run"
  fi
  t35_unchanged
  t35_result "T35j strict profile: native -Prefix delegates to Git-layout bash"

  for t35_form in typed file; do
    for t35_flag in force uninstall; do
      t35_prefix="$t35_root/k-$t35_flag-$t35_form-prefix"
      t35_run "k-$t35_flag-$t35_form-install" "$t35_root/empty-path" -File "$t35_repo/install.ps1" -Prefix "$t35_prefix"
      t35_expect_rc 0
      t35_installed
      if [ -n "$t35_err" ]; then
        t35_result "T35k $t35_form --$t35_flag requires a fresh install"
        continue
      fi
      if [ "$t35_flag" = force ]; then
        cp "$t35_prefix/agents/fc-pm.md" "$t35_root/k-$t35_form-fresh-pm.md"
        printf '\nLocally edited agent.\n' >> "$t35_prefix/agents/fc-pm.md"
      fi
      case "$t35_form" in
        typed) t35_run "k-$t35_flag-typed" "$t35_root/empty-path" -Command "& $t35_ps1 --$t35_flag --prefix $(t35_ps_quote "$t35_prefix"); exit \$LASTEXITCODE" ;;
        file)  t35_run "k-$t35_flag-file" "$t35_root/empty-path" -File "$t35_repo/install.ps1" "--$t35_flag" --prefix "$t35_prefix" ;;
      esac
      t35_expect_rc 0
      if [ "$t35_flag" = force ]; then
        cmp -s "$t35_prefix/agents/fc-pm.md" "$t35_root/k-$t35_form-fresh-pm.md" || t35_err="$t35_err installed-bytes-not-restored"
        t35_result "T35k $t35_form --force restores fresh-install bytes"
      else
        t35_left=$(find "$t35_prefix/agents" -maxdepth 1 -type f -name 'fc-*.md' 2>/dev/null | wc -l | tr -d ' ')
        [ "$t35_left" -eq 0 ] || t35_err="$t35_err agents-left:$t35_left"
        t35_left=$(find "$t35_prefix/skills" -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        [ "$t35_left" -eq 0 ] || t35_err="$t35_err skill-directories-left:$t35_left"
        t35_result "T35k $t35_form --uninstall removes installed agents and skills"
      fi
    done
  done

  # Earlier cases replace this stub; each run must record its own arguments.
  cat > "$t35_git/bin/bash.exe" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$t35_root/git-args"
exit 0
STUB
  for t35_style in gnu native; do
    rm -f "$t35_marker" "$t35_root/git-args"
    t35_prefix="$t35_root/l-$t35_style-prefix"
    case "$t35_style" in
      gnu)    t35_run l-gnu "$t35_git/cmd:$t35_decoy" -Command "& $t35_ps1 --force --uninstall --prefix $(t35_ps_quote "$t35_prefix"); exit \$LASTEXITCODE" ;;
      native) t35_run l-native "$t35_git/cmd:$t35_decoy" -Command "& $t35_ps1 -Force -Uninstall -Prefix $(t35_ps_quote "$t35_prefix"); exit \$LASTEXITCODE" ;;
    esac
    t35_expect_rc 0
    [ ! -e "$t35_marker" ] || t35_err="$t35_err PATH-decoy-ran"
    if [ -f "$t35_root/git-args" ]; then
      for t35_arg in --force --uninstall --prefix "$t35_prefix"; do
        grep -qxF -- "$t35_arg" "$t35_root/git-args" || t35_err="$t35_err arg-not-forwarded:$t35_arg"
      done
    else
      t35_err="$t35_err Git-bash-not-run"
    fi
    t35_unchanged
    t35_result "T35l typed $t35_style force/uninstall flags reach Git-layout bash"
  done
else
  for t35_case_id in a b c m n d-prefix d-default e f-unknown f-stray g h-typed h-file h-alias j-default j-dry-run j-install j-uninstall j-git k-force-typed k-uninstall-typed k-force-file k-uninstall-file l-gnu l-native; do
    skip "T35$t35_case_id PowerShell runtime case (pwsh unavailable; set PWSH)"
  done
fi

# These acceptance checks run even when pwsh is unavailable.
t35_case="$t35_root/g-bash"
t35_prefix="$t35_root/g-bash-prefix"
mkdir -p "$t35_case/home" "$t35_case/cwd"
t35_bash=$(command -v bash)
( cd "$t35_case/cwd" && HOME="$t35_case/home" "$t35_bash" "$t35_repo/install.sh" --prefix ) \
  > "$t35_case/stdout" 2> "$t35_case/stderr"
t35_rc=$?
t35_err=""
t35_expect_rc 2
grep -qxF 'Missing value for --prefix' "$t35_case/stderr" || t35_err="$t35_err missing-value-diagnostic-missing"
t35_unchanged
t35_result "T35g install.sh --prefix requires a value with exit 2"

if grep '^Flags:' README.md | grep -qF -- '-DryRun'; then
  ok "T35i README Flags line names the PowerShell spelling"
else
  bad "T35i README Flags line names the PowerShell spelling" "-DryRun absent from Flags line"
fi

# --------------------------------------------------------- T36-T46 helpers
# Every runtime case gets a scratch prefix. PowerShell uses T35's empty-PATH
# technique, so an installed Git Bash cannot silently replace the fallback.
installer_root=$(mktemp -d)
CLEANUP_PATHS+=("$installer_root")
installer_repo=$(pwd)
installer_bash=$(command -v bash)
mkdir -p "$installer_root/home/.config/powershell" "$installer_root/empty-path"
# A user's profile may enable strict mode. Current installers must inherit it;
# historical table regeneration below intentionally runs the tags as published.
printf 'Set-StrictMode -Version Latest\n' > "$installer_root/home/.config/powershell/Microsoft.PowerShell_profile.ps1"
printf 'my notes\n' > "$installer_root/personal"
printf 'my hidden notes\n' > "$installer_root/hidden"
INSTALLERS=(sh)
if [ -n "$PWSH_BIN" ] && [ -x "$PWSH_BIN" ]; then
  INSTALLERS+=(ps1)
fi
if command -v sha256sum >/dev/null 2>&1; then
  installer_hash=(sha256sum)
else
  installer_hash=(shasum -a 256)
fi
run_installer() { # engine, prefix, flags; preserves nonzero exits for assertions
  local engine="$1" prefix="$2"; shift 2
  if [ "$engine" = sh ]; then
    HOME="$installer_root/home" "$installer_bash" "$installer_repo/install.sh" --prefix "$prefix" "$@" \
      > "$installer_root/run.out" 2>&1
  else
    env -i HOME="$installer_root/home" PATH="$installer_root/empty-path" \
      POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off \
      "$PWSH_BIN" -NonInteractive -File "$installer_repo/install.ps1" --prefix "$prefix" "$@" \
      > "$installer_root/run.out" 2>&1
  fi
  installer_rc=$?
  installer_out=$(cat "$installer_root/run.out")
}
run_installer_at() { # cwd, engine, prefix, flags; retain the child exit code
  local cwd="$1"; shift
  ( cd "$cwd" && run_installer "$@"; exit "$installer_rc" )
  installer_rc=$?
  installer_out=$(cat "$installer_root/run.out")
}
expect_installer_success() {
  if [ "$installer_rc" -ne 0 ]; then
    case_err="$case_err $1:exit-$installer_rc:$(printf '%s\n' "$installer_out" | sed $'s/\033\\[[0-9;]*m//g' | tail -1)"
  fi
}
installer_result() {
  [ -z "$case_err" ] && ok "$1" || bad "$1" "issues:$case_err"
}
seed_legacy_skill() {
  mkdir -p "$1/skills/research" || return 1
  git show v3.1:.claude/skills/research/SKILL.md > "$1/skills/research/SKILL.md" || return 1
  cp "$installer_root/personal" "$1/skills/research/sources.md" || return 1
  cp "$installer_root/hidden" "$1/skills/research/.hidden"
}
seed_v31() {
  if [ ! -f "$installer_root/v3.1/install.sh" ]; then
    mkdir -p "$installer_root/v3.1" || return 1
    git archive v3.1 | tar -x -C "$installer_root/v3.1" || return 1
  fi
  HOME="$installer_root/home" "$installer_bash" "$installer_root/v3.1/install.sh" --prefix "$1" \
    > "$installer_root/seed.log" 2>&1
}
snapshot_tree() {
  ( cd "$1" || exit 1
    find . -type d -print | LC_ALL=C sort
    while IFS= read -r f; do
      printf '%s  %s\n' "$("${installer_hash[@]}" < "$f" | cut -d' ' -f1)" "$f"
    done < <(find . -type f -print | LC_ALL=C sort)
  )
}
normalize_installer_output() { # prefix, source, captured output
  python3 - "$@" <<'PY'
import pathlib, sys
prefix, source, output = sys.argv[1:]
text = pathlib.Path(output).read_bytes().decode('utf-8').replace('\r', '').replace('\\', '/')
text = text.replace(prefix.replace('\\', '/'), '<P>').replace(source.replace('\\', '/'), '<SRC>')
sys.stdout.write(text)
PY
}

# ---------------------------------------------------------------- T36
# A published SKILL.md proves ownership of that file, not of its neighbours.
for engine in "${INSTALLERS[@]}"; do
  p="$installer_root/t36-$engine"
  case_err=""
  if ! seed_legacy_skill "$p"; then
    bad "T36 $engine legacy skill preserves personal and hidden files" "cannot seed published v3.1 skill"
    continue
  fi
  run_installer "$engine" "$p"
  expect_installer_success install
  [ ! -e "$p/skills/research/SKILL.md" ] || case_err="$case_err published-SKILL-left"
  cmp -s "$installer_root/personal" "$p/skills/research/sources.md" || case_err="$case_err personal-file-deleted"
  cmp -s "$installer_root/hidden" "$p/skills/research/.hidden" || case_err="$case_err hidden-file-deleted"
  printf '%s\n' "$installer_out" | grep -qxF "removed (legacy): $p/skills/research/SKILL.md" \
    || case_err="$case_err per-file-removal-not-reported"
  printf '%s\n' "$installer_out" | grep -qxF "kept (not ours — content does not match any published version): $p/skills/research/sources.md" \
    || case_err="$case_err personal-file-not-reported"
  printf '%s\n' "$installer_out" | grep -qxF "kept (not ours — content does not match any published version): $p/skills/research/.hidden" \
    || case_err="$case_err hidden-file-not-reported"
  for name in sources.md .hidden; do
    count=$(printf '%s\n' "$installer_out" | grep -cxF "  if this was an older Feature-Crew you edited, remove it by hand: $p/skills/research/$name" || true)
    [ "$count" -eq 1 ] || case_err="$case_err $name:legacy-hints=$count(want-1)"
  done
  run_installer "$engine" "$p" --uninstall
  expect_installer_success uninstall
  cmp -s "$installer_root/personal" "$p/skills/research/sources.md" || case_err="$case_err personal-file-lost-after-uninstall"
  cmp -s "$installer_root/hidden" "$p/skills/research/.hidden" || case_err="$case_err hidden-file-lost-after-uninstall"
  installer_result "T36 $engine legacy skill preserves personal and hidden files"
done

# ---------------------------------------------------------------- T37
# Use v3.1's OWN installer: copying today's agents would not reproduce the old
# names, unquoted frontmatter, or duplicate fc-pm. Count the six agent removals
# specifically; v3.1 also installed two legacy skills eligible for cleanup.
t37_legacy_case() { # engine, actual prefix, given prefix, cwd, label
  local engine="$1" p="$2" given="$3" cwd="$4" label="$5" action name count
  case_err=""
  if ! seed_v31 "$p"; then
    bad "$label" "v3.1 installer fixture failed"
    return
  fi
  cp "$installer_root/personal" "$p/agents/feature-crew/my-own-agent.md"
  snapshot_tree "$p" > "$installer_root/before"
  for action in install uninstall; do
    if [ "$action" = install ]; then run_installer_at "$cwd" "$engine" "$given" --dry-run
    else run_installer_at "$cwd" "$engine" "$given" --uninstall --dry-run; fi
    expect_installer_success "dry-$action"
    snapshot_tree "$p" > "$installer_root/after"
    cmp -s "$installer_root/before" "$installer_root/after" || case_err="$case_err dry-$action:tree-changed"
    printf '%s\n' "$installer_out" | grep -q '^removed' && case_err="$case_err dry-$action:claims-removed"
    count=$(printf '%s\n' "$installer_out" | grep -cF "DRY-RUN: would remove (legacy): $given/agents/feature-crew/" || true)
    [ "$count" -eq 6 ] || case_err="$case_err dry-$action:legacy-agent-lines=$count(want-6)"
    for name in architect developer pm qa-code-reviewer qa-spec-reviewer tech-lead; do
      printf '%s\n' "$installer_out" | grep -qxF "DRY-RUN: would remove (legacy): $given/agents/feature-crew/$name.md" \
        || case_err="$case_err dry-$action:not-listed:$name"
    done
  done
  run_installer_at "$cwd" "$engine" "$given"
  expect_installer_success install
  for name in architect developer pm qa-code-reviewer qa-spec-reviewer tech-lead; do
    [ ! -e "$p/agents/feature-crew/$name.md" ] || case_err="$case_err legacy-agent-left:$name"
  done
  for name in build-or-fix research; do
    [ ! -d "$p/skills/$name" ] || case_err="$case_err legacy-skill-left:$name"
  done
  cmp -s "$installer_root/personal" "$p/agents/feature-crew/my-own-agent.md" || case_err="$case_err personal-agent-deleted"
  printf '%s\n' "$installer_out" | grep -qxF "kept (not ours — content does not match any published version): $given/agents/feature-crew/my-own-agent.md" \
    || case_err="$case_err personal-agent-not-reported"
  count=$(find "$p/agents" -type f -name '*.md' -exec grep -l '^name: fc-pm$' {} + | wc -l | tr -d ' ')
  [ "$count" -eq 1 ] || case_err="$case_err fc-pm-definitions=$count(want-1)"
  run_installer_at "$cwd" "$engine" "$given" --uninstall
  expect_installer_success uninstall
  cmp -s "$installer_root/personal" "$p/agents/feature-crew/my-own-agent.md" || case_err="$case_err personal-agent-deleted-on-uninstall"
  count=$(find "$p" -type f | wc -l | tr -d ' ')
  [ "$count" -eq 1 ] || case_err="$case_err uninstall-files=$count(want-personal-only)"
  installer_result "$label"
}
for engine in "${INSTALLERS[@]}"; do
  p="$installer_root/t37-$engine"
  t37_legacy_case "$engine" "$p" "$p" "$installer_repo" "T37 $engine v3.1 cleanup is per-file on install and uninstall"
  for form in dot parent; do
    cwd="$installer_root/t37-$engine-$form/feature-crew"
    mkdir -p "$cwd"
    if [ "$form" = dot ]; then given='./p'; p="$cwd/p"
    else given='../p'; p="$(dirname "$cwd")/p"; fi
    t37_legacy_case "$engine" "$p" "$given" "$cwd" "T37 $engine v3.1 cleanup through $given from feature-crew"
  done

  # Both dot forms also cover a fresh install. A long cwd name makes ../'s
  # uncanonicalized root longer than a listed file, exposing Substring errors.
  case_err=""
  for form in dot parent; do
    cwd="$installer_root/t37-fresh-$engine-$form/feature-crew"
    mkdir -p "$cwd"
    if [ "$form" = dot ]; then given='./u'; p="$cwd/u"
    else given='../u'; p="$(dirname "$cwd")/u"; fi
    run_installer_at "$cwd" "$engine" "$given"
    expect_installer_success "$given/install"
    [ -f "$p/agents/fc-pm.md" ] && [ -f "$p/skills/fc-review/SKILL.md" ] \
      || case_err="$case_err $given:not-installed"
    run_installer_at "$cwd" "$engine" "$given" --uninstall
    expect_installer_success "$given/uninstall"
    count=$(find "$p" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 0 ] || case_err="$case_err $given:files-left=$count"
  done
  installer_result "T37 $engine fresh ./u and ../u installs uninstall completely"
done

# ---------------------------------------------------------------- T38
# Brackets are literal path characters, not permission to act on a neighbour.
for engine in "${INSTALLERS[@]}"; do
  p="$installer_root/t38-$engine/br[1]"
  neighbour="$installer_root/t38-$engine/br1/agents/fc-pm.md"
  case_err=""
  run_installer "$engine" "$p"
  expect_installer_success install
  mkdir -p "$(dirname "$neighbour")"
  printf 'MY OWN\n' > "$neighbour"
  run_installer "$engine" "$p" --uninstall
  expect_installer_success uninstall
  [ "$(cat "$neighbour" 2>/dev/null)" = 'MY OWN' ] || case_err="$case_err neighbour-deleted-or-changed"
  count=$(find "$p/agents" -type f -name 'fc-*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 0 ] || case_err="$case_err literal-prefix-agents-left=$count"
  run_installer "$engine" "$p"
  expect_installer_success restore
  printf '\nMY EDIT\n' >> "$p/agents/fc-pm.md"
  cp "$p/agents/fc-pm.md" "$installer_root/edited-agent"
  run_installer "$engine" "$p"
  expect_installer_success reinstall
  cmp -s "$installer_root/edited-agent" "$p/agents/fc-pm.md" || case_err="$case_err reinstall-overwrote-edit"
  installer_result "T38 $engine bracket prefix protects neighbour and edited agent"
done

# ---------------------------------------------------------------- T39
for engine in "${INSTALLERS[@]}"; do
  p="$installer_root/t39-$engine"
  case_err=""
  run_installer "$engine" "$p"
  expect_installer_success install
  cp "$installer_root/hidden" "$p/skills/fc-review/.notes.md"
  run_installer "$engine" "$p" --uninstall
  expect_installer_success uninstall
  [ -d "$p/skills/fc-review" ] || case_err="$case_err skill-dir-deleted"
  cmp -s "$installer_root/hidden" "$p/skills/fc-review/.notes.md" || case_err="$case_err hidden-file-deleted"
  printf '%s\n' "$installer_out" | grep -qxF "kept (yours — differs from what we install): $p/skills/fc-review" \
    || case_err="$case_err kept-line-missing"
  installer_result "T39 $engine uninstall counts hidden personal files"
done

# ---------------------------------------------------------------- T40
for engine in "${INSTALLERS[@]}"; do
  p="$installer_root/t40-$engine"
  case_err=""
  run_installer "$engine" "$p"
  expect_installer_success install
  { printf '\357\273\277'; cat "$p/agents/fc-pm.md"; } > "$installer_root/bom-agent"
  cp "$installer_root/bom-agent" "$p/agents/fc-pm.md"
  run_installer "$engine" "$p" --uninstall
  expect_installer_success uninstall
  cmp -s "$installer_root/bom-agent" "$p/agents/fc-pm.md" || case_err="$case_err BOM-edited-agent-deleted"
  printf '%s\n' "$installer_out" | grep -qxF "kept (yours — differs from what we install): $p/agents/fc-pm.md" \
    || case_err="$case_err kept-line-missing"
  installer_result "T40 $engine BOM-only agent edit is kept byte-for-byte"
done

# ---------------------------------------------------------------- T41
for engine in "${INSTALLERS[@]}"; do
  p="$installer_root/t41-$engine"
  case_err=""
  mkdir -p "$p/skills/research"
  : > "$p/skills/research/SKILL.md"
  for attempt in 1 2; do
    run_installer "$engine" "$p"
    expect_installer_success "install-$attempt"
    [ -f "$p/skills/research/SKILL.md" ] && [ ! -s "$p/skills/research/SKILL.md" ] \
      || case_err="$case_err install-$attempt:empty-skill-changed"
    printf '%s\n' "$installer_out" | grep -qxF "kept (not ours — content does not match any published version): $p/skills/research" \
      || case_err="$case_err install-$attempt:kept-line-missing"
  done
  installer_result "T41 $engine empty legacy SKILL.md is kept without aborting either install"
done
if [ "${#INSTALLERS[@]}" -eq 1 ]; then
  for n in 36 37 38 39 40 41; do skip "T$n ps1 fallback regression (pwsh unavailable; set PWSH)"; done
fi

# ---------------------------------------------------------------- T42
# Query the real index, not a hand-picked file or a grep of .gitattributes.
case_err=""
count=0
while IFS= read -r -d '' tracked; do
  IFS= read -r -d '' attribute
  IFS= read -r -d '' value
  count=$((count + 1))
  [ "$attribute:$value" = 'eol:lf' ] || case_err="$case_err $tracked:$value"
done < <(git ls-files -z | git check-attr -z --stdin eol)
[ "$count" -gt 0 ] || case_err="$case_err no-tracked-files"
installer_result "T42 every tracked file has the LF checkout attribute"

# ---------------------------------------------------------------- T43
# Frozen provenance comes from what tagged installers WROTE, not current source
# files or hand-maintained hashes. Both historical engines contribute, with CR
# stripped exactly as the ownership classifier does. Do not update the table
# during the test: a difference must fail, never bless itself.
case_err=""
t43_root="$installer_root/published"
mkdir -p "$t43_root"
: > "$t43_root/entries"
for tag in v3.1 v4.0 v5.0.0 v5.0.1 v5.1.0; do
  archive="$t43_root/$tag/source"
  mkdir -p "$archive"
  if ! git archive "$tag" | tar -x -C "$archive"; then
    case_err="$case_err $tag:archive-failed"; continue
  fi
  for engine in "${INSTALLERS[@]}"; do
    p="$t43_root/$tag/$engine/prefix"
    home="$t43_root/$tag/$engine/home"
    mkdir -p "$p" "$home"
    if [ "$engine" = sh ]; then
      HOME="$home" "$installer_bash" "$archive/install.sh" --prefix "$p" > "$t43_root/run.log" 2>&1
    else
      env -i HOME="$home" PATH="$installer_root/empty-path" \
        POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off \
        "$PWSH_BIN" -NoProfile -NonInteractive -File "$archive/install.ps1" -Prefix "$p" > "$t43_root/run.log" 2>&1
    fi
    rc=$?
    if [ "$rc" -ne 0 ]; then case_err="$case_err $tag/$engine:exit-$rc"; continue; fi
    while IFS= read -r rel; do
      hash=$(tr -d '\r' < "$p/$rel" | "${installer_hash[@]}" | cut -d' ' -f1)
      printf '%s  %s\n' "$hash" "$rel" >> "$t43_root/entries"
    done < <(cd "$p" && find . -type f -print | sed 's|^\./||' | LC_ALL=C sort)
  done
done
LC_ALL=C sort -u -k2,2 -k1,1 "$t43_root/entries" > "$t43_root/regenerated.sha256"
count=$(wc -l < "$t43_root/regenerated.sha256" | tr -d ' ')
paths=$(cut -d' ' -f3- "$t43_root/regenerated.sha256" | LC_ALL=C sort -u | wc -l | tr -d ' ')
[ "$count/$paths" = '41/23' ] || case_err="$case_err regenerated=$count-entries/$paths-paths(want-41/23)"
if [ ! -f published.sha256 ]; then
  case_err="$case_err published.sha256-missing"
elif ! cmp -s published.sha256 "$t43_root/regenerated.sha256"; then
  case_err="$case_err published.sha256-differs-from-tagged-installs"
fi
installer_result "T43 published.sha256 exactly matches v3.1-v5.1.0 installer output"
[ "${#INSTALLERS[@]}" -eq 2 ] || skip "T43 historical PowerShell fallback hashes (pwsh unavailable; set PWSH)"

# ---------------------------------------------------------------- T44
case_err=""
p="$installer_root/t44/empty"
run_installer sh "$p" --dry-run
expect_installer_success dry-empty
cp "$installer_root/run.out" "$installer_root/t44-empty.out"
printf '%s\n' "$installer_out" | grep -qF '//' && case_err="$case_err dry-empty:double-slash"
# Build the set from source parents, retaining duplicates in the actual output
# so repeating mkdir once per copied file cannot pass as a set comparison.
{
  printf '%s\n' "$p/agents"
  for src in "$installer_repo"/.claude/skills/*/; do
    [ -f "${src}SKILL.md" ] || continue
    skill=$(basename "$src")
    printf '%s\n' "$p/skills/$skill"
    while IFS= read -r rel; do
      printf '%s\n' "$(dirname "$p/skills/$skill/$rel")"
    done < <(cd "$src" && find . -type f -print | sed 's|^\./||')
  done
} | LC_ALL=C sort -u > "$installer_root/expected-dirs"
sed -n 's/^DRY-RUN: mkdir -p //p' "$installer_root/t44-empty.out" | LC_ALL=C sort > "$installer_root/actual-dirs"
cmp -s "$installer_root/expected-dirs" "$installer_root/actual-dirs" || case_err="$case_err missing-or-repeated-mkdir"
[ ! -e "$p" ] || case_err="$case_err dry-run-created-prefix"
run_installer sh "$p"
expect_installer_success install
run_installer sh "$p" --dry-run --force
expect_installer_success dry-force
printf '%s\n' "$installer_out" | grep -q '^DRY-RUN: mkdir' && case_err="$case_err existing-dirs-print-mkdir"
printf '%s\n' "$installer_out" | grep -qF '//' && case_err="$case_err dry-force:double-slash"
run_installer sh "$p"
expect_installer_success reinstall
printf '%s\n' "$installer_out" | grep -q '^skip (exists):' || case_err="$case_err no-skip-lines"
if printf '%s\n' "$installer_out" | grep '^skip (exists):' | grep -qv '  \[use --force to overwrite\]$'; then
  case_err="$case_err noncanonical-skip-hint"
fi
installer_result "T44 canonical bash mkdir, copy paths, and skip hints"

# ---------------------------------------------------------------- T45
# Compare ordered output, not sorted output or substring tokens. Only paths,
# path separators, and CR are normalized; whitespace and wording are contracts.
if [ "${#INSTALLERS[@]}" -ne 2 ]; then
  skip "T45 installer output parity matrix (pwsh unavailable; set PWSH)"
elif ! command -v python3 >/dev/null 2>&1; then
  skip "T45 installer output parity matrix (python3 unavailable)"
else
  for scenario in fresh reinstall dry-force dry-empty uninstall-dry uninstall install-v31 uninstall-dry-v31 edited-agent legacy-skill dot-install-v31 parent-round-trip; do
    case_err=""
    scenario_root="$installer_root/t45-$scenario"
    mkdir -p "$scenario_root"
    for engine in "${INSTALLERS[@]}"; do
      p="$scenario_root/$engine"
      given="$p"
      cwd="$installer_repo"
      raw="$scenario_root/$engine.raw"
      : > "$raw"
      flags=()
      case "$scenario" in
        reinstall|dry-force|uninstall-dry|uninstall|edited-agent)
          run_installer "$engine" "$p"
          expect_installer_success "$engine/setup"
          ;;
        install-v31|uninstall-dry-v31)
          seed_v31 "$p" || case_err="$case_err $engine/v3.1-fixture-failed"
          ;;
        legacy-skill)
          seed_legacy_skill "$p" || case_err="$case_err $engine/legacy-skill-fixture-failed"
          ;;
        dot-install-v31|parent-round-trip)
          cwd="$scenario_root/$engine/feature-crew"
          mkdir -p "$cwd"
          if [ "$scenario" = dot-install-v31 ]; then
            given='./p'; p="$cwd/p"
            seed_v31 "$p" || case_err="$case_err $engine/v3.1-fixture-failed"
          else
            given='../u'; p="$scenario_root/$engine/u"
            run_installer_at "$cwd" "$engine" "$given"
            expect_installer_success "$engine/parent-install"
            cat "$installer_root/run.out" >> "$raw"
          fi
          ;;
      esac
      case "$scenario" in
        dry-force) flags=(--dry-run --force) ;;
        dry-empty) flags=(--dry-run) ;;
        uninstall-dry|uninstall-dry-v31) flags=(--uninstall --dry-run) ;;
        uninstall|parent-round-trip) flags=(--uninstall) ;;
        edited-agent)
          printf '\nmy edit\n' >> "$p/agents/fc-pm.md"
          flags=(--uninstall)
          ;;
      esac
      # Bash 3.2 treats an empty array as unset under nounset.
      if [ "${#flags[@]}" -gt 0 ]; then run_installer_at "$cwd" "$engine" "$given" "${flags[@]}"
      else run_installer_at "$cwd" "$engine" "$given"; fi
      expect_installer_success "$engine/$scenario"
      cat "$installer_root/run.out" >> "$raw"
      # For dot-segment scenarios only normalize the actual absolute prefix;
      # ./p and ../u must remain printed exactly as the caller supplied them.
      normalize_installer_output "$p" "$installer_repo" "$raw" > "$scenario_root/$engine.out" \
        || case_err="$case_err $engine/normalization-failed"
    done
    if ! cmp -s "$scenario_root/sh.out" "$scenario_root/ps1.out"; then
      case_err="$case_err ordered-output-differs"
      # Show the first unequal line; do not flood every test run with two whole
      # installs. The test still compares ALL output, including trailing LF.
      mismatch=$(python3 - "$scenario_root/sh.out" "$scenario_root/ps1.out" <<'PY'
import itertools, pathlib, sys
left, right = [pathlib.Path(p).read_text().splitlines(keepends=True) for p in sys.argv[1:]]
for n, (a, b) in enumerate(itertools.zip_longest(left, right), 1):
    if a != b:
        print(f'line {n}: sh={a!r}; ps1={b!r}')
        break
PY
)
      case_err="$case_err ($mismatch)"
    fi
    installer_result "T45 output parity: $scenario"
  done
fi

# ---------------------------------------------------------------- T46
# Parse commands, not text lines: comments and quoted examples do not count,
# and splitting a command over lines must not evade the -LiteralPath check.
if [ "${#INSTALLERS[@]}" -ne 2 ]; then
  skip "T46 PowerShell literal-path AST check (pwsh unavailable; set PWSH)"
else
  cat > "$installer_root/literal-paths.ps1" <<'PS'
param([string]$Path)
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors -join "`n") }
$issues = @()
foreach ($command in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] }, $true)) {
  $name = $command.GetCommandName()
  $parameters = @($command.CommandElements | Where-Object {
    $_ -is [Management.Automation.Language.CommandParameterAst]
  } | ForEach-Object { $_.ParameterName })
  $where = $name + '@' + $command.Extent.StartLineNumber
  if ($name -in @('Test-Path', 'Remove-Item', 'Get-ChildItem') -and $parameters -notcontains 'LiteralPath') {
    $issues += ($where + ':no-LiteralPath')
  }
  if ($name -eq 'Copy-Item') { $issues += ($where + ':use-byte-copy') }
  if ($name -eq 'Get-ChildItem' -and $parameters -contains 'Recurse' -and $parameters -notcontains 'Force') {
    $issues += ($where + ':recursive-list-hides-files')
  }
}
if ($issues.Count) { Write-Output ($issues -join ' '); exit 1 }
PS
  case_err=""
  t46_out=$("$PWSH_BIN" -NoProfile -NonInteractive -File "$installer_root/literal-paths.ps1" \
    -Path "$installer_repo/install.ps1" 2>&1)
  [ "$?" -eq 0 ] || case_err=" $t46_out"
  installer_result "T46 PowerShell uses literal paths, byte copies, and hidden-aware recursion"
fi

echo
if [ "$SKIP" -gt 0 ]; then
  echo "== ${PASS} passed, ${FAIL} failed, ${SKIP} SKIPPED (coverage incomplete) =="
else
  echo "== ${PASS} passed, ${FAIL} failed =="
fi
[ "$FAIL" -eq 0 ]