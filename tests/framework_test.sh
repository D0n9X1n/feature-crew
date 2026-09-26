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

SKILL_NAMES=(fc-research fc-grill-me fc-brainstorm fc-debug fc-build-or-fix fc-review fc-second-opinion fc-update fc-ship)
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
t9_contract() { # skills root; prints one diagnostic per missing clause
  local n f desc errors=""
  for n in "${SKILL_NAMES[@]}"; do
    f="$1/$n/SKILL.md"
    if [ ! -f "$f" ]; then errors="$errors $n:missing"; continue; fi
    desc=$(awk '/^---$/{c++; if(c==2) exit; next} c==1' "$f" \
           | awk '/^[a-z][a-z-]*:/{k=($0 ~ /^description:/)} k')
    echo "$desc" | grep -qi 'use when'        || errors="$errors $n:no-use-when"
    echo "$desc" | grep -qi 'do not use for'  || errors="$errors $n:no-anti-trigger"
  done
  printf '%s\n' "$errors"
}
t9_err=$(t9_contract .claude/skills)
[ -z "$t9_err" ] && ok "T9 all skills carry [what] + [use when] + [do NOT use for]" \
                 || bad "T9 skill description contract" "issues:$t9_err"
# Negative checks on scratch copies: removing either clause from fc-debug's
# description must fail this same check with exactly that clause's diagnostic.
for t9_clause in use-when anti-trigger; do
  case "$t9_clause" in
    use-when)     t9_sed='/^description:/s/ Use when [^.]*\.//';       t9_want=' fc-debug:no-use-when' ;;
    anti-trigger) t9_sed='/^description:/s/ Do NOT use for [^.]*\.//'; t9_want=' fc-debug:no-anti-trigger' ;;
  esac
  t9_mut=$(mktemp -d)
  CLEANUP_PATHS+=("$t9_mut")
  cp -R .claude/skills "$t9_mut/skills"
  t9_target="$t9_mut/skills/fc-debug/SKILL.md"
  if [ ! -f "$t9_target" ]; then
    bad "T9 removal mutation: fc-debug $t9_clause" "mutation target fc-debug/SKILL.md missing"
  elif sed "$t9_sed" "$t9_target" > "$t9_mut/mutant" && cmp -s "$t9_mut/mutant" "$t9_target"; then
    bad "T9 removal mutation: fc-debug $t9_clause" "clause not found; mutation not applied"
  else
    cp "$t9_mut/mutant" "$t9_target"
    t9_mut_out=$(t9_contract "$t9_mut/skills")
    if [ "$t9_mut_out" = "$t9_want" ]; then
      ok "T9 removal mutation: fc-debug $t9_clause rejected by its own check"
    else
      bad "T9 removal mutation: fc-debug $t9_clause" "got '${t9_mut_out:-<empty>}', want '$t9_want'"
    fi
  fi
  rm -rf "$t9_mut"
done

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
  # Presence is not reachability. Reject throws outside function bodies even
  # when nested in a top-level `if`, but keep legitimate conditional exits for
  # delegation/help/uninstall. Functions and their closing braces are column 0
  # in this installer. This bounded static check complements Windows execution.
  awk '
    /^[[:space:]]*<#/ { block_comment = 1 }
    block_comment { if (/#>/) block_comment = 0; next }
    /^[[:space:]]*#/ { next }
    /^Install-ClaudeGlobal[[:space:]]*$/ { exit }
    # Retain the original column-0 guard even inside function bodies.
    /^(throw|exit)([[:space:]]|$)/ { bad = 1; exit }
    tolower($0) ~ /^function[[:space:]]/ { in_function = 1 }
    in_function { if (/^}/) in_function = 0; next }
    tolower($0) ~ /(^|[^[:alnum:]_$.-])throw([^[:alnum:]_-]|$)/ { bad = 1; exit }
    END { exit bad }
  ' "$f"
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
t13_contract() { # install prefix; prints each skill whose SKILL.md is absent
  local n errors=""
  for n in "${SKILL_NAMES[@]}"; do
    [ -f "$1/skills/$n/SKILL.md" ] || errors="$errors $n"
  done
  printf '%s\n' "$errors"
}
if bash install.sh --prefix "$tmp_prefix" --force >/dev/null 2>&1; then
  t13_err=$(t13_contract "$tmp_prefix")
  [ -z "$t13_err" ] && ok "T13 all skills reach the install prefix" \
                    || bad "T13 skills not installed" "missing:$t13_err"
  # Negative check on a scratch copy: omitting fc-debug's installed SKILL.md
  # must fail this same check with exactly that skill's diagnostic.
  t13_mut=$(mktemp -d)
  CLEANUP_PATHS+=("$t13_mut")
  cp -R "$tmp_prefix" "$t13_mut/prefix"
  if [ ! -f "$t13_mut/prefix/skills/fc-debug/SKILL.md" ]; then
    bad "T13 removal mutation: fc-debug SKILL.md" "mutation target not installed"
  else
    rm "$t13_mut/prefix/skills/fc-debug/SKILL.md"
    t13_mut_out=$(t13_contract "$t13_mut/prefix")
    if [ "$t13_mut_out" = " fc-debug" ]; then
      ok "T13 removal mutation: omitted fc-debug SKILL.md rejected by its own check"
    else
      bad "T13 removal mutation: fc-debug SKILL.md" "got '${t13_mut_out:-<empty>}', want ' fc-debug'"
    fi
  fi
  rm -rf "$t13_mut"
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

# Attack 5 (#26): a conditional top-level throw bypasses the column-0 check.
awk '/^Install-ClaudeGlobal[[:space:]]*$/ { print "if ($true) { throw \"native-only regression\" }" } { print }' \
  install.ps1 > "$mut/e.ps1"
if grep -qxF 'if ($true) { throw "native-only regression" }' "$mut/e.ps1"; then
  ps1_operative_ok "$mut/e.ps1" && t20_err="$t20_err attack5-undetected"
else
  t20_err="$t20_err attack5-not-applied"
fi

# Attack 6 (#26): parentheses after throw must not hide the keyword.
awk '/^Install-ClaudeGlobal[[:space:]]*$/ { print "if ($true) { throw(\"native-only regression\") }" } { print }' \
  install.ps1 > "$mut/f.ps1"
if grep -qxF 'if ($true) { throw("native-only regression") }' "$mut/f.ps1"; then
  ps1_operative_ok "$mut/f.ps1" && t20_err="$t20_err attack6-undetected"
else
  t20_err="$t20_err attack6-not-applied"
fi

# Attacks 7/8: function skipping must not weaken the original column-0 guard.
# Insert exactly once at the entry to the install function, before any work.
for t20_attack in 7 8; do
  case "$t20_attack" in
    7) t20_terminator='exit 0' ;;
    8) t20_terminator='throw "gutted"' ;;
  esac
  if [ "$(grep -cxF 'function Install-ClaudeGlobal {' install.ps1)" -ne 1 ]; then
    t20_err="$t20_err attack$t20_attack-target-not-unique"
    continue
  fi
  awk -v terminator="$t20_terminator" '
    { print }
    $0 == "function Install-ClaudeGlobal {" { print terminator }
  ' install.ps1 > "$mut/attack$t20_attack.ps1"
  if [ "$(awk '/^function Install-ClaudeGlobal \{$/ { getline; print }' "$mut/attack$t20_attack.ps1")" = "$t20_terminator" ]; then
    ps1_operative_ok "$mut/attack$t20_attack.ps1" && t20_err="$t20_err attack$t20_attack-undetected"
  else
    t20_err="$t20_err attack$t20_attack-not-applied"
  fi
done

# Control: the real installers must still pass, or the check is just broken.
ps1_operative_ok install.ps1 || t20_err="$t20_err control-ps1-false-positive"
sh_operative_ok  install.sh  || t20_err="$t20_err control-sh-false-positive"

rm -rf "$mut"
[ -z "$t20_err" ] && ok "T20 T10 detects a gutted installer (8 mutations + 2 controls)" \
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
# ---------------------------------------------------------------- T61
# Every Standard/Complex design checks both directions and component fitness,
# carries a component map, and compares a blind second design unless it is
# super straightforward. Section-scoped like T55: each clause counts only in
# its own section, and after the unmodified documents pass, removing one clause
# must produce exactly its own diagnostic. Handoff rules include their links,
# so a dropped link trips its own clause. Every match and removal quotes its
# rule, so link brackets match literally, never as a glob.
t61_err=""
t61_docs=(
  .claude/skills/fc-build-or-fix/reference/design-check.md
  .claude/skills/fc-build-or-fix/SKILL.md
  .claude/skills/fc-build-or-fix/reference/complex-track.md
  agents/fc-architect.md agents/fc-qa-code.md agents/fc-tech-lead.md agents/fc-developer.md
)
t61_labels=(
  paste-into-architect
  top-down bottom-up-map reconcile-paths fitness-gate fitness-one-job fitness-home
  fitness-interface fitness-change fitness-testable component-map
  second-opinion-mandatory second-opinion-parallel second-opinion-selector second-opinion-dispatcher second-opinion-blind
  second-opinion-brief second-opinion-one-round comparison-table input-not-author
  audit-not-replaced fail-closed super-straightforward complex-never-exempt waivers-do-not-waive
  parallel-design-exception standard-component-map standard-design-check
  complex-parallel-designer complex-reconcile complex-plan-audit-focus
  architect-design-check architect-output-map architect-output-comparison
  architect-fitness-review architect-report-comparison
  qa-component-map lead-component-map developer-component-map
)
t61_sections=(
  intro
  both both both fitness fitness fitness fitness fitness fitness fitness
  second second second second second second second second second second second second second second
  dispatch standard standard step5 step5 step6 phase1 output output review report qa lead dev
)
t61_rules=(
  "paste it into the architect's task."
  'requirements → responsibilities → components → interfaces. Every requirement has a home; every component traces to a requirement.'
  'map the existing code near the change before creating anything, one row per component: `component | job | key files | depends on | evidence (file:line)`. Mark inferences and unknowns. Reuse or extend before creating.'
  'fit the design to existing seams, walk one normal and one failure path through it, and raise real conflicts as decisions, never guesses.'
  'Every new or changed component passes all five, or is redesigned, merged, or deleted:'
  'One job, stated in one sentence.'
  'The right home, with dependencies pointing one way.'
  'An interface smaller than what it hides.'
  'The most likely future change touches only this component.'
  'Testable through its interface.'
  '`component | job | interface | reuses or extends | likely change | test seam` — and plan audits, `fc-qa-code`, and `fc-tech-lead` check the work against it.'
  'Mandatory unless the design is super straightforward.'
  'When the first design starts, dispatch a blind second designer in parallel'
  "choosing its model with the canonical selector from the first author's recorded model."
  'Only the dispatching session sends it; the architect never does.'
  'Give it the same brief but not the first design.'
  'It leads with the bottom-up view and returns at most 300 words — a component map and key decisions, never artifact text.'
  'One round only.'
  'The first author compares both in a table — `agree | differ | chosen and why` — recorded in the spec or plan.'
  'The second designer is an input, not an author: record its recorded model in the gate record.'
  'It never replaces the cross-family audit, which reviews the reconciled artifact.'
  'Unknown provenance, a family collision, or an unavailable dispatch stops the step, as the selector does.'
  'means all of: reversible; one unambiguous design that extends an existing pattern; objectively verifiable; no new component, interface, or dependency; no unresolved decision. Record the reason in the spec.'
  'Complex work is never exempt'
  'approval waivers do not waive this step.'
  'Exception: the blind second design runs alongside the first ([reference/design-check.md](reference/design-check.md)).'
  'files (each with its one job and the existing code it extends) · component map · 3–8 behavior bullets'
  'Run [reference/design-check.md](reference/design-check.md), including its blind second opinion unless the design is super straightforward.'
  'In parallel, dispatch the blind second designer per [design-check.md](design-check.md)'
  'then resume the architect with its sketch to compare and reconcile in the plan.'
  'components that duplicate existing code or fail the fitness check'
  'Start from the design check pasted into your task: work both directions, top-down and bottom-up; run the fitness check on every new or changed component; and write the component map.'
  'Component Map'
  'Design comparison'
  'every mapped component passes the fitness check, and nothing duplicates existing code'
  'Design approach and design comparison, in brief'
  'Does the change match the planned component map without duplicating an existing component or bypassing an existing seam'
  'does the implementation match the design and its component map'
  "Follow the plan's file structure and component map; if the task needs a component the map lacks, stop and report DONE_WITH_CONCERNS."
)
t61_design_contract() { # the seven t61_docs texts, in order
  local intro both fitness second dispatch standard step5 step6 phase1 review output report
  local qa lead dev section i errors=""
  intro=$(printf '%s\n' "$1" | sed -n '/^# Design check/,/^## /p')
  both=$(printf '%s\n' "$1" | sed -n '/^## Both directions/,/^## /p')
  fitness=$(printf '%s\n' "$1" | sed -n '/^## Fitness check/,/^## /p')
  second=$(printf '%s\n' "$1" | sed -n '/^## Second opinion/,/^## /p')
  dispatch=$(printf '%s\n' "$2" | sed -n '/^## Dispatch rules/,/^## /p')
  standard=$(printf '%s\n' "$2" | sed -n '/^### Standard/,/^### /p' | grep -E '^2\. ')
  step5=$(printf '%s\n' "$3" | sed -n '/^## Flow/,/^## /p' | grep -E '^5\. ')
  step6=$(printf '%s\n' "$3" | sed -n '/^## Flow/,/^## /p' | grep -E '^6\. ')
  phase1=$(printf '%s\n' "$4" | sed -n '/^## Phase 1/,/^## /p')
  review=$(printf '%s\n' "$4" | sed -n '/^## Self-review/,/^## /p')
  # The Output template holds its own ## headings, so it ends at ## Report.
  output=$(printf '%s\n' "$4" | sed -n '/^## Output/,/^## Report/p')
  report=$(printf '%s\n' "$4" | sed -n '/^## Report/,/^## /p')
  qa=$(printf '%s\n' "$5" | sed -n '/^## What to look for/,/^## /p' | grep '^\*\*Architecture\*\*')
  lead=$(printf '%s\n' "$6" | sed -n '/^## What only you can see/,/^## /p' | grep '^\*\*Architecture\*\*')
  dev=$(printf '%s\n' "$7" | sed -n '/^## Code organization/,/^## /p')
  for ((i=0; i<${#t61_rules[@]}; i++)); do
    case "${t61_sections[$i]}" in
      intro) section="$intro" ;;
      both) section="$both" ;;
      fitness) section="$fitness" ;;
      second) section="$second" ;;
      dispatch) section="$dispatch" ;;
      standard) section="$standard" ;;
      step5) section="$step5" ;;
      step6) section="$step6" ;;
      phase1) section="$phase1" ;;
      review) section="$review" ;;
      output) section="$output" ;;
      report) section="$report" ;;
      qa) section="$qa" ;;
      lead) section="$lead" ;;
      dev) section="$dev" ;;
      *) section="" ;;
    esac
    [[ "$section" == *"${t61_rules[$i]}"* ]] || errors="$errors ${t61_labels[$i]}"
  done
  printf '%s\n' "$errors"
}
t61_texts=()
for t61_doc in "${t61_docs[@]}"; do
  [ -f "$t61_doc" ] || t61_err="$t61_err file:$t61_doc"
  t61_texts+=("$(cat "$t61_doc" 2>/dev/null)")
done
[ "${#t61_labels[@]}" -eq "${#t61_rules[@]}" ] && [ "${#t61_sections[@]}" -eq "${#t61_rules[@]}" ] \
  || t61_err="$t61_err rule-table-misaligned"
t61_out=$(t61_design_contract "${t61_texts[@]}")
t61_err="$t61_err$t61_out"
if [ -z "$t61_err" ]; then
  for ((t61_i=0; t61_i<${#t61_rules[@]}; t61_i++)); do
    case "${t61_sections[$t61_i]}" in
      intro|both|fitness|second) t61_doc_i=0 ;;
      dispatch|standard) t61_doc_i=1 ;;
      step5|step6) t61_doc_i=2 ;;
      phase1|review|output|report) t61_doc_i=3 ;;
      qa) t61_doc_i=4 ;;
      lead) t61_doc_i=5 ;;
      *) t61_doc_i=6 ;;
    esac
    t61_rule="${t61_rules[$t61_i]}"
    t61_mut=("${t61_texts[@]}")
    t61_text="${t61_mut[$t61_doc_i]}"
    t61_text="${t61_text/"$t61_rule"/}"
    t61_mut[$t61_doc_i]="$t61_text"
    t61_mut_out=$(t61_design_contract "${t61_mut[@]}")
    if [ "$t61_mut_out" = " ${t61_labels[$t61_i]}" ]; then
      ok "T61 removal mutation: ${t61_labels[$t61_i]} rejected by its own check"
    else
      bad "T61 removal mutation: ${t61_labels[$t61_i]}" \
        "got '${t61_mut_out:-<empty>}', want ' ${t61_labels[$t61_i]}'"
    fi
  done
fi
[ -z "$t61_err" ] && ok "T61 static contract alarm: two-direction design check + component map + blind second design" \
                   || bad "T61 design check and blind second design contract" "missing:$t61_err"

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
# Requested aliases are not runtime provenance: allowlists, fallbacks, and
# gateways can substitute a model without failing the dispatch.
echo "$selector" | grep -qiE 'author family.*model the harness recorded.*not.*requested alias' \
  || t32_err="$t32_err author-not-harness-recorded"
echo "$selector" | grep -qiE 'authoring dispatches.*explicit.*model' \
  || t32_err="$t32_err authoring-model-not-explicit"
echo "$selector" | grep -qiE 'recorded reviewer model.*missing.*GATE UNSATISFIED' \
  || t32_err="$t32_err missing-reviewer-model-not-fail-closed"
echo "$selector" | grep -qiE 'recorded reviewer model.*author.s family.*GATE UNSATISFIED' \
  || t32_err="$t32_err recorded-family-collision-not-fail-closed"
echo "$selector" | grep -qiE 'third family.*recorded as a substitution.*stands' \
  || t32_err="$t32_err third-family-substitution-not-recorded"
echo "$selector" | grep -qiE 'this session.s record.*sonnet.*author.s family.*model: *opus' \
  || t32_err="$t32_err recorded-sonnet-collision-not-rerouted"
echo "$selector" | grep -qF '(reference/gate-provenance.md)' \
  || t32_err="$t32_err provenance-reference-not-linked"
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
# alarm checks all six routes and bounded return-to-origin behavior; it is not
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
echo "$classifier" | grep -qiE '(unexplained failure|unproven cause).*fc-debug|fc-debug.*(unexplained failure|unproven cause)' \
  || t33_err="$t33_err debug-route"
echo "$classifier" | grep -qiE 'return.*origin|originat(ing|or).*resume' \
  || t33_err="$t33_err return-to-origin"
echo "$classifier" | grep -qiE 'must not self-invoke|no self-invocation|never self-invoke' \
  || t33_err="$t33_err no-self-invocation"
echo "$classifier" | grep -qiE 'do not repeat|never repeat|no repeat' \
  || t33_err="$t33_err no-repeat"
echo "$classifier" | grep -qiE 'recurs|cycle' || t33_err="$t33_err no-cycles"
echo "$classifier" | grep -qiE 'fc-grill-me.*leaf.*any flow may call' \
  || t33_err="$t33_err grill-leaf-exception-missing"
brainstorm=.claude/skills/fc-brainstorm/SKILL.md
bs_panel=$(sed -n '/^## 2 — Panel/,/^## /p' "$brainstorm")
bs_spec=$(sed -n '/^## 5 — Spec/,/^## /p' "$brainstorm")
bs_caps=$(sed -n '/^## Caps/,/^## /p' "$brainstorm")
echo "$bs_panel" | grep -qE '^> .*Do not call `Agent`, `Skill`, `Workflow`, or delegate' \
  || t33_err="$t33_err brainstorm-panel-delegation-not-forbidden"
echo "$bs_spec" | grep -qiE 'another flow invoked.*return.*approved spec.*originator' \
  || t33_err="$t33_err brainstorm-does-not-return-approved-spec"
echo "$bs_spec" | grep -qF 'Hand off to `/fc-build-or-fix`' \
  && t33_err="$t33_err brainstorm-unconditional-build-handoff"
echo "$bs_spec" | grep -qiE 'only if the user invoked.*directly.*offer.*fc-build-or-fix' \
  || t33_err="$t33_err brainstorm-direct-invocation-not-distinguished"
echo "$bs_caps" | grep -qiE 'max 7 panel/review dispatches.*3 panel \+ (up to 3|≤3) re-dispatch \+ 1 cross-audit' \
  || t33_err="$t33_err brainstorm-cap-omits-diversity-round"
echo "$bs_caps" | grep -qiE 'descendants.*any depth' \
  || t33_err="$t33_err brainstorm-descendants-not-counted"
echo "$bs_caps" | grep -qiE 'pause.*user.*approval|user.*OK.*first' \
  || t33_err="$t33_err brainstorm-cap-expansion-not-approved"
if grep -q '^disable-model-invocation: true$' .claude/skills/fc-grill-me/SKILL.md; then
  t33_err="$t33_err grill-not-model-invocable"
fi
# Pointer docs must not grow a second copy of the canonical route table.
dup_classifier=$(git grep -lF '| One discoverable fact |' -- README.md CLAUDE.md agents/fc-pm.md \
  '.claude/skills/fc-brainstorm/SKILL.md' 2>/dev/null || true)
[ -z "$dup_classifier" ] || t33_err="$t33_err duplicated-classifier:$(echo "$dup_classifier" | tr '\n' ',')"
[ -z "$t33_err" ] && ok "T33 static contract alarm: six need routes + bounded return-to-origin" \
                   || bad "T33 need-composition prose contract" "missing:$t33_err"

# ---------------------------------------------------------------- T62
# fc-debug diagnoses an unexplained failure before anyone attempts a fix. Each
# clause of its six behaviors is a literal sentence scoped to its own section,
# so a stray mention elsewhere cannot satisfy it. As in T55, each removal
# mutation must produce exactly its own diagnostic, and mutations run only
# after the unmodified skill passes the control.
t62_labels=(
  record-caller record-expected-actual record-environment
  reproduce trace-known-good one-hypothesis three-experiments
  tracked-files-as-found no-masking no-commit no-delegation no-skill-invocation no-fixed-claim
  return-evidence return-root-cause return-file-line return-rejected-hypotheses return-regression-recipe
  blocked-with-evidence caller-pauses
  counter-not-reset direct-offers-build-or-fix
)
t62_sections=(record record record investigate investigate investigate investigate
  boundaries boundaries boundaries boundaries boundaries boundaries
  report report report report report blocked blocked after after)
t62_rules=(
  'Record the caller and resume point.'
  'Record expected vs. actual behavior.'
  'Record the environment.'
  'Reproduce the failure first.'
  'Trace the failing boundary against known-good behavior.'
  'Test one falsifiable hypothesis at a time.'
  'Run at most three experiments.'
  'Leave tracked files as found (scratch reproductions, or a scratch copy for instrumentation).'
  'Never mask a failure.'
  'Never commit.'
  'Never delegate.'
  'Never invoke another skill.'
  'Never claim "fixed".'
  'Return command/output evidence.'
  'State the root cause and your confidence in it.'
  'Cite `file:line` references.'
  'List rejected hypotheses.'
  'Give a regression-test recipe that the calling flow writes as its failing test.'
  'No reproduction, no access, or experiments exhausted: return BLOCKED with the evidence.'
  'The caller pauses.'
  "A diagnosis does not reset the caller's three-fix counter."
  'Invoked directly, fc-debug offers `/fc-build-or-fix` instead of launching it.'
)
t62_debug_contract() { # fc-debug SKILL.md text
  local record investigate boundaries report blocked after section i errors=""
  record=$(printf '%s\n' "$1" | sed -n '/^## Record$/,/^## /p')
  investigate=$(printf '%s\n' "$1" | sed -n '/^## Investigate$/,/^## /p')
  boundaries=$(printf '%s\n' "$1" | sed -n '/^## Boundaries$/,/^## /p')
  report=$(printf '%s\n' "$1" | sed -n '/^## Report$/,/^## /p')
  blocked=$(printf '%s\n' "$1" | sed -n '/^## Blocked$/,/^## /p')
  after=$(printf '%s\n' "$1" | sed -n '/^## After the diagnosis$/,/^## /p')
  for ((i=0; i<${#t62_rules[@]}; i++)); do
    case "${t62_sections[$i]}" in
      record) section="$record" ;;
      investigate) section="$investigate" ;;
      boundaries) section="$boundaries" ;;
      report) section="$report" ;;
      blocked) section="$blocked" ;;
      after) section="$after" ;;
    esac
    printf '%s\n' "$section" | grep -qF "${t62_rules[$i]}" \
      || errors="$errors ${t62_labels[$i]}"
  done
  printf '%s\n' "$errors"
}
t62_text=$(cat .claude/skills/fc-debug/SKILL.md 2>/dev/null)
t62_err=$(t62_debug_contract "$t62_text")
if [ -z "$t62_err" ]; then
  for ((t62_i=0; t62_i<${#t62_rules[@]}; t62_i++)); do
    t62_rule="${t62_rules[$t62_i]}"
    t62_mut="${t62_text/"$t62_rule"/}"
    t62_mut_out=$(t62_debug_contract "$t62_mut")
    if [ "$t62_mut_out" = " ${t62_labels[$t62_i]}" ]; then
      ok "T62 removal mutation: ${t62_labels[$t62_i]} rejected by its own check"
    else
      bad "T62 removal mutation: ${t62_labels[$t62_i]}" \
        "got '${t62_mut_out:-<empty>}', want ' ${t62_labels[$t62_i]}'"
    fi
  done
fi
[ -z "$t62_err" ] && ok "T62 static contract alarm: fc-debug diagnoses without fixing and returns to its caller" \
                   || bad "T62 fc-debug diagnosis contract" "missing:$t62_err"

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

# ---------------------------------------------------------------- T55
# Runtime evidence and environment assumptions belong in the linked reference;
# unrelated mentions outside these sections must not satisfy the contract.
t55_err=""
provenance=.claude/skills/fc-build-or-fix/reference/gate-provenance.md
echo "$selector" | grep -qF '(reference/gate-provenance.md)' \
  || t55_err="$t55_err provenance-reference-not-linked"
if [ -f "$provenance" ]; then
  record=$(sed -n '/^## Read the record/,/^## /p' "$provenance")
  families=$(sed -n '/^## Map model ids to families/,/^## /p' "$provenance")
  assumptions=$(sed -n '/^## Environment assumptions/,/^## /p' "$provenance")
  echo "$record" | grep -qF '~/.claude/projects/<cwd-slug>/<session-id>/subagents/agent-<agentId>.jsonl' \
    || t55_err="$t55_err subagent-record-path-missing"
  echo "$record" | grep -qF '.message.model' || t55_err="$t55_err runtime-model-field-missing"
  echo "$record" | grep -qiE 'meta.json.*requested alias.*not.*runtime' \
    || t55_err="$t55_err metadata-alias-not-distinguished"
  echo "$record" | grep -qiE 'unreadable record.*unknown provenance' \
    || t55_err="$t55_err unreadable-record-not-unknown"
  for family in sonnet opus haiku; do
    echo "$families" | grep -qF "claude-${family}-*" \
      || t55_err="$t55_err ${family}-id-family-mapping-missing"
  done
  echo "$families" | grep -qiE 'non-Claude id.*provider.*family' \
    || t55_err="$t55_err non-claude-family-mapping-missing"
  echo "$families" | grep -qiE 'non-Claude id.*prefix.*`gpt-\*`.*GPT' \
    || t55_err="$t55_err non-claude-vendor-prefix-rule-missing"
  echo "$families" | grep -qiE 'every id.*one vendor line.*one family' \
    || t55_err="$t55_err vendor-line-family-boundary-missing"
  echo "$families" | grep -qiE 'unknown only when.*vendor cannot be (told|identified)' \
    || t55_err="$t55_err unknown-vendor-boundary-missing"
  echo "$families" | grep -qiE 'non-Claude id.*requires.*verified.*mapping|without.*(reliable|verified).*mapping.*unknown' \
    && t55_err="$t55_err verified-mapping-still-required"
  for assumption in 2.1.251 CLAUDE_CODE_SUBAGENT_MODEL_FORCE availableModels 'fallback chains' 'alias-remapping gateways'; do
    echo "$assumptions" | grep -qF "$assumption" \
      || t55_err="$t55_err missing-assumption:$assumption"
  done
  echo "$assumptions" | grep -qiE 'CLAUDE_CODE_SUBAGENT_MODEL_FORCE.*unset' \
    || t55_err="$t55_err force-unset-not-required"
else
  t55_err="$t55_err gate-provenance-missing"
fi
# Pin the caller's choice, not a fixed author family. Each call site must use
# the canonical default so a Sonnet session is not silently moved to Opus.
echo "$selector" | grep -qiE 'authoring dispatches.*explicit.*`model`.*default.*alias.*session.s own model.*unless the user chose another' \
  || t55_err="$t55_err session-authoring-alias-default-missing"
complex_flow=$(sed -n '/^## Flow/,/^## /p' .claude/skills/fc-build-or-fix/reference/complex-track.md)
architect_dispatch=$(echo "$complex_flow" | grep -E '^5\. ')
developer_dispatch=$(echo "$complex_flow" | grep -E '^8\. ')
synthesis_dispatch=$(sed -n '/^## Phase 2/,/^## /p' .claude/skills/fc-research/SKILL.md)
echo "$architect_dispatch" | grep -qE 'fc-architect.*explicit.*`model` override.*authoring rule.*`/fc-build-or-fix`' \
  || t55_err="$t55_err architect-authoring-rule-not-linked"
echo "$developer_dispatch" | grep -qE 'fc-developer.*explicit.*`model` override.*authoring rule.*`/fc-build-or-fix`' \
  || t55_err="$t55_err developer-authoring-rule-not-linked"
echo "$synthesis_dispatch" | grep -qE 'general-purpose.*explicit.*`model` override.*authoring rule.*`/fc-build-or-fix`' \
  || t55_err="$t55_err synthesis-authoring-rule-not-linked"
for authoring_site in architect developer synthesis; do
  case "$authoring_site" in
    architect) authoring_text="$architect_dispatch" ;;
    developer) authoring_text="$developer_dispatch" ;;
    synthesis) authoring_text="$synthesis_dispatch" ;;
  esac
  echo "$authoring_text" | grep -qE 'model: *(opus|sonnet|haiku|fable)' \
    && t55_err="$t55_err $authoring_site:hardcoded-authoring-alias"
done
complex_example=$(sed -n '/^## Worked example/,/^## /p' .claude/skills/fc-build-or-fix/reference/complex-track.md)
echo "$complex_example" | grep -qE '^> .*fc-architect.*requested with `model: sonnet`' \
  || t55_err="$t55_err example-architect-changes-session-family"
echo "$complex_example" | grep -qE '^> .*Developers requested with `model: sonnet`' \
  || t55_err="$t55_err example-developers-change-session-family"
# Delegation can hide contributors from the dispatched agent's own record.
# Keep these literal contract sentences scoped to their operative sections.
# Removal mutations below must produce exactly their own diagnostic, not merely
# some failure, and run only after the unmodified documents pass the control.
t55_boundary_labels=(
  gated-prompts refuter-prompts authoring-call-boundary reviewer-call-boundary
  artifact-change-contributor recursive-records missing-child-records in-record-skills
  author-child-family-set reviewer-child-family-set disjoint-family-sets
  child-record-link child-link-observation-scope unresolved-child-link
)
t55_boundary_sections=(dispatch refute record record record record record record families families families record record record)
t55_boundary_rules=(
  'Every authoring dispatch and every hard-gate review prompt ends with: "Do not call `Agent`, `Skill`, `Workflow`, or delegate any part of the task."'
  'Do not call `Agent`, `Skill`, `Workflow`, or delegate any part of the task.'
  'Only `Agent` or `Workflow` calls made to produce or change the artifact contribute to its author set.'
  'Gate reviews, validators and refuters, and their children, stay in reviewer sets when they only report findings, even if their calls sit in the main-session record; using their findings in a later fix does not make them authors.'
  'A call that changes the artifact is an authoring contributor, whoever made it; if it also reviewed, keep it in both sets.'
  'Read each relevant authoring or review child record recursively, including forked `Skill` runs.'
  'A child record that cannot be found or read makes provenance unknown and the gate unsatisfied.'
  'A `Skill` call without a fork stays in the same record.'
  'Authoring children join the author family set at every depth, according to their task rather than the parent record.'
  'Children doing review join the set for that reviewer at every depth, not the author set unless they changed the artifact.'
  'Every model in a reviewer set must be known and outside the author family set.'
  'Match `.toolUseId` in child `agent-<agentId>.meta.json` to the spawning `Agent` tool_use `.id` in the parent record, then read the matching `agent-<agentId>.jsonl`.'
  'This child-record link has been observed for depth-1 `Agent` calls only; `Workflow` children and depth 2 or greater have not been observed.'
  'If this link cannot locate a contributor record, provenance is unknown and the gate unsatisfied.'
)
t55_delegation_contract() { # build-or-fix, second-opinion, provenance text
  local dispatch refute record families section i errors=""
  dispatch=$(printf '%s\n' "$1" | sed -n '/^## Dispatch rules/,/^## /p')
  refute=$(printf '%s\n' "$2" | sed -n '/^## 3 — Refute/,/^## /p' | grep '^> ')
  record=$(printf '%s\n' "$3" | sed -n '/^## Read the record/,/^## /p')
  families=$(printf '%s\n' "$3" | sed -n '/^## Map model ids to families/,/^## /p')
  for ((i=0; i<${#t55_boundary_rules[@]}; i++)); do
    case "${t55_boundary_sections[$i]}" in
      dispatch) section="$dispatch" ;;
      refute) section="$refute" ;;
      record) section="$record" ;;
      families) section="$families" ;;
    esac
    printf '%s\n' "$section" | grep -qF "${t55_boundary_rules[$i]}" \
      || errors="$errors ${t55_boundary_labels[$i]}"
  done
  printf '%s\n' "$errors"
}
t55_build_text=$(cat .claude/skills/fc-build-or-fix/SKILL.md)
t55_refuter_text=$(cat .claude/skills/fc-second-opinion/SKILL.md)
t55_provenance_text=$(cat "$provenance" 2>/dev/null)
t55_boundary_out=$(t55_delegation_contract "$t55_build_text" "$t55_refuter_text" "$t55_provenance_text")
t55_err="$t55_err$t55_boundary_out"
if [ -z "$t55_boundary_out" ]; then
  for ((t55_i=0; t55_i<${#t55_boundary_rules[@]}; t55_i++)); do
    t55_rule="${t55_boundary_rules[$t55_i]}"
    t55_build_mut="$t55_build_text"
    t55_refuter_mut="$t55_refuter_text"
    t55_provenance_mut="$t55_provenance_text"
    case "${t55_boundary_sections[$t55_i]}" in
      dispatch) t55_build_mut="${t55_build_mut/"$t55_rule"/}" ;;
      refute) t55_refuter_mut="${t55_refuter_mut/"$t55_rule"/}" ;;
      *) t55_provenance_mut="${t55_provenance_mut/"$t55_rule"/}" ;;
    esac
    t55_mut_out=$(t55_delegation_contract "$t55_build_mut" "$t55_refuter_mut" "$t55_provenance_mut")
    if [ "$t55_mut_out" = " ${t55_boundary_labels[$t55_i]}" ]; then
      ok "T55 removal mutation: ${t55_boundary_labels[$t55_i]} rejected by its own check"
    else
      bad "T55 removal mutation: ${t55_boundary_labels[$t55_i]}" \
        "got '${t55_mut_out:-<empty>}', want ' ${t55_boundary_labels[$t55_i]}'"
    fi
  done
fi
[ -z "$t55_err" ] && ok "T55 static contract alarm: recorded-model provenance + pinned authors" \
                   || bad "T55 provenance reference and author dispatch contract" "missing:$t55_err"

# ---------------------------------------------------------------- T56
# One mandatory suffix shared by all three phases closes recursive delegation;
# the Phase 1 profile and the invocation-wide budget are separate safeguards.
t56_err=""
research=.claude/skills/fc-research/SKILL.md
workers=$(sed -n '/^## Worker boundary/,/^## /p' "$research")
search_phase=$(sed -n '/^## Phase 1/,/^## /p' "$research")
research_caps=$(sed -n '/^## Caps/,/^## /p' "$research")
echo "$workers" | grep -qiE 'append.*suffix.*every worker prompt.*Phases 1, 2 and 3' \
  || t56_err="$t56_err no-shared-worker-suffix"
echo "$workers" | grep -qE '^> .*Do not call `Agent`, `Skill`, `Workflow`, or delegate' \
  || t56_err="$t56_err worker-delegation-not-forbidden"
echo "$search_phase" | grep -qiE 'prefer.*`Explore`.*no `Agent` tool' \
  || t56_err="$t56_err phase1-does-not-prefer-explore"
echo "$search_phase" | grep -qE '^> Return raw findings only\.' \
  || t56_err="$t56_err phase1-not-raw-findings"
echo "$research_caps" | grep -qiE 'max 5 dispatches.*descendants.*any depth' \
  || t56_err="$t56_err descendant-dispatches-not-counted"
echo "$research_caps" | grep -qiE 'pause.*user.*approval|user.*OK.*first' \
  || t56_err="$t56_err cap-expansion-not-approved"
[ -z "$t56_err" ] && ok "T56 static contract alarm: research workers cannot delegate past the cap" \
                   || bad "T56 research dispatch boundary" "missing:$t56_err"

# ---------------------------------------------------------------- T57
# Tool/model frontmatter ends with the loading turn. The standalone skills
# promise a read-only policy, not shell-write isolation or a persistent model.
t57_err=""
for skill in fc-review fc-second-opinion; do
  f=".claude/skills/$skill/SKILL.md"
  intro=$(sed -n "/^# $skill\$/,/^## /p" "$f")
  grep -qi 'by construction' "$f" && t57_err="$t57_err $skill:construction-claim"
  echo "$intro" | grep -qi 'read-only by policy' || t57_err="$t57_err $skill:policy-missing"
  echo "$intro" | grep -qiE 'frontmatter removes.*`Write`.*`Edit`.*`NotebookEdit`.*only for the turn that loads the skill' \
    || t57_err="$t57_err $skill:tool-restriction-lifetime-missing"
  echo "$intro" | grep -qiE '`model` override.*only for that turn' \
    || t57_err="$t57_err $skill:model-override-lifetime-missing"
  echo "$intro" | grep -qiE 'Bash and PowerShell.*write-capable' \
    || t57_err="$t57_err $skill:shell-write-limit-unacknowledged"
done
refute=$(sed -n '/^## 3 — Refute/,/^## /p' .claude/skills/fc-second-opinion/SKILL.md)
echo "$refute" | grep -qiE 'each refuter.*explicit.*`model` override.*selector.*`/fc-build-or-fix`' \
  || t57_err="$t57_err refuter-selector-override-missing"
[ -z "$t57_err" ] && ok "T57 static contract alarm: honest read-only policy + explicit refuter models" \
                   || bad "T57 standalone review policy contract" "missing:$t57_err"

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

  # Exit 3 means Git Bash ran the installer and reported failure, not that bash
  # was unavailable. Reuse this guard on confirmed scratch mutations as well.
  cat > "$t35_git/bin/bash.exe" <<STUB
#!/bin/sh
printf '%s\n' ran > "$t35_root/o-git-ran"
exit 3
STUB
  for t35_variant in control exit-zero fallback; do
    t35_script="$t35_repo/install.ps1"
    if [ "$t35_variant" != control ]; then
      if ! command -v python3 >/dev/null 2>&1; then
        skip "T35o $t35_variant mutation replay (python3 unavailable)"
        continue
      fi
      # Like T21, keep the copy beside agents/ so an erroneous fallback really
      # installs files instead of failing for an unrelated missing-source error.
      t35_script="$t35_repo/t35o-$t35_variant-$$.ps1"
      CLEANUP_PATHS+=("$t35_script")
      if ! t35_mutation_out=$(python3 - "$t35_variant" "$t35_script" 2>&1 <<'PY'
import pathlib, sys
old, new = {
    'exit-zero': (b'    exit $bashExitCode\n', b'    exit 0\n'),
    'fallback': (b'  if ($bashExitCode -ne 126 -and $bashExitCode -ne 127) {',
                 b'  if ($bashExitCode -eq 0) {'),
}[sys.argv[1]]
source = pathlib.Path('install.ps1').read_bytes()
assert source.count(old) == 1, 'delegation mutation target missing or ambiguous'
mutant = source.replace(old, new, 1)
assert mutant != source and old not in mutant, 'delegation mutation not applied'
pathlib.Path(sys.argv[2]).write_bytes(mutant)
PY
      ); then
        bad "T35o $t35_variant mutation replay" "$t35_mutation_out"
        continue
      fi
    fi
    rm -f "$t35_marker" "$t35_root/o-git-ran"
    t35_prefix="$t35_root/o-$t35_variant-prefix"
    t35_run "o-$t35_variant" "$t35_git/cmd:$t35_decoy" -File "$t35_script" --prefix "$t35_prefix"
    t35_expect_rc 3
    [ -e "$t35_root/o-git-ran" ] || t35_err="$t35_err Git-bash-not-run"
    [ ! -e "$t35_marker" ] || t35_err="$t35_err PATH-decoy-ran"
    grep -qF 'using the PowerShell installer' "$t35_case/stderr" && t35_err="$t35_err unexpected-fallback-warning"
    t35_unchanged
    if [ "$t35_variant" = control ]; then
      t35_result "T35o delegated exit 3 propagates without a fallback warning or installed files"
    else
      t35_expected=' exit=0(want-3)'
      [ "$t35_variant" = fallback ] && t35_expected="$t35_expected unexpected-fallback-warning prefix-created"
      if [ "$t35_err" = "$t35_expected" ]; then
        ok "T35o $t35_variant mutation applied and rejected:$t35_err"
      else
        bad "T35o $t35_variant mutation replay" "expected '$t35_expected', got '${t35_err:-<no rejection>}'"
      fi
      rm -f "$t35_script"
    fi
  done
else
  for t35_case_id in a b c m n d-prefix d-default e f-unknown f-stray g h-typed h-file h-alias j-default j-dry-run j-install j-uninstall j-git k-force-typed k-uninstall-typed k-force-file k-uninstall-file l-gnu l-native o o-exit-zero o-fallback; do
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
  for form in dot parent absolute-dot absolute-parent; do
    cwd="$installer_root/t37-$engine-$form/feature-crew"
    mkdir -p "$cwd"
    case "$form" in
      dot) given='./p'; p="$cwd/p" ;;
      parent) given='../p'; p="$(dirname "$cwd")/p" ;;
      absolute-dot) given="$cwd/./p"; p="$cwd/p" ;;
      absolute-parent) given="$cwd/../p"; p="$(dirname "$cwd")/p" ;;
    esac
    t37_legacy_case "$engine" "$p" "$given" "$cwd" "T37 $engine v3.1 cleanup through $given from feature-crew"
  done

  # Rooted paths still need normalization before FullName slicing.
  case_err=""
  for form in dot parent absolute-dot absolute-parent; do
    cwd="$installer_root/t37-fresh-$engine-$form/feature-crew"
    mkdir -p "$cwd"
    case "$form" in
      dot) given='./u'; p="$cwd/u" ;;
      parent) given='../u'; p="$(dirname "$cwd")/u" ;;
      absolute-dot) given="$cwd/./u"; p="$cwd/u" ;;
      absolute-parent) given="$cwd/../u"; p="$(dirname "$cwd")/u" ;;
    esac
    run_installer_at "$cwd" "$engine" "$given"
    expect_installer_success "$given/install"
    [ -f "$p/agents/fc-pm.md" ] && [ -f "$p/skills/fc-review/SKILL.md" ] \
      || case_err="$case_err $given:not-installed"
    run_installer_at "$cwd" "$engine" "$given" --uninstall
    expect_installer_success "$given/uninstall"
    count=$(find "$p" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 0 ] || case_err="$case_err $given:files-left=$count"
  done
  installer_result "T37 $engine fresh relative and absolute dot-segment prefixes uninstall completely"
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
  for scenario in fresh reinstall dry-force dry-empty uninstall-dry uninstall install-v31 uninstall-dry-v31 edited-agent legacy-skill dot-install-v31 parent-round-trip invalid-manifest; do
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
        reinstall|dry-force|uninstall-dry|uninstall|edited-agent|invalid-manifest)
          run_installer "$engine" "$p"
          expect_installer_success "$engine/setup"
          cat "$installer_root/run.out" >> "$raw"
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
        invalid-manifest)
          printf 'not a manifest\n' > "$p/feature-crew.sha256"
          run_installer "$engine" "$p"
          expect_installer_success "$engine/invalid-manifest-reinstall"
          cat "$installer_root/run.out" >> "$raw"
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

# --------------------------------------------------------- T47-T54 helpers
# Reuse the real fallback runner and its strict-mode profile. Only historical
# fixtures use git archive; copies of this clone must include uncommitted fixes.
seed_v501() {
  if [ ! -f "$installer_root/v5.0.1/install.sh" ]; then
    mkdir -p "$installer_root/v5.0.1" || return 1
    git -c core.autocrlf=false archive v5.0.1 | tar -x -C "$installer_root/v5.0.1" || return 1
  fi
  HOME="$installer_root/home" "$installer_bash" "$installer_root/v5.0.1/install.sh" --prefix "$1" --force \
    > "$installer_root/seed.log" 2>&1
}
copy_installer_inputs() {
  mkdir -p "$1/.claude" || return 1
  cp "$installer_repo/install.sh" "$installer_repo/install.ps1" "$installer_repo/published.sha256" "$1/" || return 1
  cp -R "$installer_repo/agents" "$1/agents" || return 1
  cp -R "$installer_repo/.claude/skills" "$1/.claude/skills"
}
run_copied_installer() {
  local installer_repo="$1"; shift
  run_installer "$@"
}
raw_files_manifest() {
  local hash rel
  # Independent byte oracle: exact equality also checks lowercase hex, two
  # spaces, the complete path set, ordinal order, no BOM, LF and trailing LF.
  ( cd "$1" || exit 1
    [ -d agents ] && [ -d skills ] || exit 1
    while IFS= read -r rel; do
      hash=$("${installer_hash[@]}" < "$rel" | cut -d' ' -f1) || exit 1
      printf '%s  %s\n' "$hash" "$rel"
    done < <(find agents skills -type f -print | LC_ALL=C sort)
  )
}
check_manifest() {
  # Independent checksum oracle run FROM the prefix; fc-update uses --check.
  ( cd "$1" || exit 1
    if command -v sha256sum >/dev/null 2>&1; then sha256sum -c feature-crew.sha256; else shasum -a 256 -c feature-crew.sha256; fi
  )
}
expect_manifest_bytes() { # prefix, expected manifest, label
  if [ ! -f "$1/feature-crew.sha256" ]; then
    case_err="$case_err $3:manifest-missing"
  elif ! cmp -s "$2" "$1/feature-crew.sha256"; then
    case_err="$case_err $3:manifest-bytes-differ"
  fi
}
expect_output_line() {
  local count
  count=$(printf '%s\n' "$installer_out" | grep -cxF -- "$1" || true)
  [ "$count" -eq 1 ] || case_err="$case_err $2:line-count=$count(want-1)"
}
remaining_files() {
  ( cd "$1" && find . -type f -print | sed 's|^\./||' | LC_ALL=C sort )
}

# ---------------------------------------------------------------- T47
# The expected manifest is computed from files actually written, not sources:
# agents have generated frontmatter and hashes must cover those bytes too.
for engine in "${INSTALLERS[@]}"; do
  p="$installer_root/t47-$engine/absolute"
  case_err=""
  run_installer "$engine" "$p"
  expect_installer_success install
  raw_files_manifest "$p" > "$installer_root/t47-$engine.expected" || case_err="$case_err cannot-hash-installed-files"
  expect_manifest_bytes "$p" "$installer_root/t47-$engine.expected" absolute
  check_manifest "$p" > "$installer_root/check.out" 2>&1 || case_err="$case_err absolute:checksum-check-failed"
  expect_output_line "installed: $p/feature-crew.sha256" manifest-installed

  # run_installer captures in a subshell here so its relative --prefix is
  # interpreted from the parent directory, for both shell and .NET file APIs.
  ( cd "$installer_root/t47-$engine" || exit 1
    run_installer "$engine" relative
    exit "$installer_rc"
  )
  installer_rc=$?
  installer_out=$(cat "$installer_root/run.out")
  expect_installer_success relative-install
  expect_manifest_bytes "$installer_root/t47-$engine/relative" "$installer_root/t47-$engine.expected" relative
  check_manifest "$installer_root/t47-$engine/relative" > "$installer_root/check.out" 2>&1 \
    || case_err="$case_err relative:checksum-check-failed"

  p="$installer_root/t47-$engine/dry-empty"
  run_installer "$engine" "$p" --dry-run
  expect_installer_success dry-install
  expect_output_line "DRY-RUN: write $p/feature-crew.sha256" manifest-dry-write
  [ ! -e "$p" ] || case_err="$case_err dry-run-created-prefix"
  installer_result "T47 $engine writes a canonical raw-byte manifest, including relative prefixes and dry runs"
done
if [ "${#INSTALLERS[@]}" -eq 2 ]; then
  case_err=""
  cmp -s "$installer_root/t47-sh/absolute/feature-crew.sha256" "$installer_root/t47-ps1/absolute/feature-crew.sha256" \
    || case_err=" manifests-missing-or-not-byte-identical"
  installer_result "T47 install.sh and the PowerShell fallback write byte-identical manifests"
else
  skip "T47 manifest byte parity (pwsh unavailable; set PWSH)"
fi

# ---------------------------------------------------------------- T48
# Reproduce #23 with v5.0.1's own installer. Counting the fixture's agents and
# skill directories keeps the removal expectation tied to what it really wrote.
for engine in "${INSTALLERS[@]}"; do
  p="$installer_root/t48-$engine/untouched"
  case_err=""
  if ! seed_v501 "$p"; then
    bad "T48a $engine recognizes an untouched v5.0.1 install" "v5.0.1 installer fixture failed"
    continue
  fi
  raw_files_manifest "$p" > "$installer_root/t48.old" || case_err="$case_err cannot-hash-fixture"
  LC_ALL=C awk 'FILENAME == ARGV[1] { old[substr($0,67)]=$0; next }
    { path=substr($0,67); print (path in old ? old[path] : $0) }' \
    "$installer_root/t48.old" "$installer_root/t47-$engine.expected" > "$installer_root/t48.expected" \
    || case_err="$case_err cannot-build-upgrade-expectation"
  snapshot_tree "$p" > "$installer_root/before"
  { find "$p/agents" -maxdepth 1 -type f -print
    find "$p/skills" -mindepth 1 -maxdepth 1 -type d -print
  } | LC_ALL=C sort > "$installer_root/t48.paths"
  want=$(wc -l < "$installer_root/t48.paths" | tr -d ' ')
  [ "$want" -gt 0 ] || case_err="$case_err empty-fixture"
  run_installer "$engine" "$p" --uninstall --dry-run
  expect_installer_success dry-uninstall
  count=$(printf '%s\n' "$installer_out" | grep -c '^kept (yours' || true)
  [ "$count" -eq 0 ] || case_err="$case_err kept-lines=$count(want-0)"
  printf '%s\n' "$installer_out" | sed -n 's/^DRY-RUN: would remove //p' | LC_ALL=C sort > "$installer_root/t48.removals"
  count=$(wc -l < "$installer_root/t48.removals" | tr -d ' ')
  [ "$count" -eq "$want" ] || case_err="$case_err removal-lines=$count(want-$want)"
  cmp -s "$installer_root/t48.paths" "$installer_root/t48.removals" || case_err="$case_err removal-paths-differ"
  printf '%s\n' "$installer_out" | grep -qF 'feature-crew.sha256' && case_err="$case_err unexpected-manifest-line"
  snapshot_tree "$p" > "$installer_root/after"
  cmp -s "$installer_root/before" "$installer_root/after" || case_err="$case_err dry-run-changed-fixture"
  run_installer "$engine" "$p"
  expect_installer_success nonforce-install
  expect_manifest_bytes "$p" "$installer_root/t48.expected" recognized-v501
  check_manifest "$p" > "$installer_root/check.out" 2>&1 || case_err="$case_err recognized-v501:checksum-check-failed"
  run_installer "$engine" "$p" --uninstall
  expect_installer_success uninstall
  [ -z "$(remaining_files "$p")" ] || case_err="$case_err uninstall-left-files"
  installer_result "T48a $engine recognizes an untouched v5.0.1 install without blaming upstream changes"

  p="$installer_root/t48-$engine/edited"
  case_err=""
  if ! seed_v501 "$p"; then
    bad "T48b $engine keeps only the edited v5.0.1 agent" "v5.0.1 installer fixture failed"
    continue
  fi
  printf '\nMY EDIT\n' >> "$p/agents/fc-pm.md"
  cp "$p/agents/fc-pm.md" "$installer_root/t48.edited"
  raw_files_manifest "$p" > "$installer_root/t48.old" || case_err="$case_err cannot-hash-fixture"
  LC_ALL=C awk 'FILENAME == ARGV[1] { old[substr($0,67)]=$0; next }
    { path=substr($0,67); print (path in old ? old[path] : $0) }' \
    "$installer_root/t48.old" "$installer_root/t47-$engine.expected" \
    | grep -v '  agents/fc-pm.md$' > "$installer_root/t48.expected" \
    || case_err="$case_err cannot-build-upgrade-expectation"
  snapshot_tree "$p" > "$installer_root/before"
  run_installer "$engine" "$p" --uninstall --dry-run
  expect_installer_success dry-uninstall
  count=$(printf '%s\n' "$installer_out" | grep -c '^kept (yours' || true)
  [ "$count" -eq 1 ] || case_err="$case_err kept-lines=$count(want-1)"
  expect_output_line "kept (yours — differs from what we install): $p/agents/fc-pm.md" edited-agent
  snapshot_tree "$p" > "$installer_root/after"
  cmp -s "$installer_root/before" "$installer_root/after" || case_err="$case_err dry-run-changed-fixture"
  run_installer "$engine" "$p"
  expect_installer_success nonforce-install
  expect_manifest_bytes "$p" "$installer_root/t48.expected" excludes-unrecognized-edit
  run_installer "$engine" "$p" --uninstall
  expect_installer_success uninstall
  [ "$(remaining_files "$p")" = 'agents/fc-pm.md' ] || case_err="$case_err uninstall-did-not-keep-exactly-edited-agent"
  cmp -s "$installer_root/t48.edited" "$p/agents/fc-pm.md" || case_err="$case_err edited-agent-changed"
  installer_result "T48b $engine keeps only the edited v5.0.1 agent, without recording its edit as a baseline"
done

# ---------------------------------------------------------------- T49
# An untagged install can be recognized only by its recorded baseline. Include
# CRLF in the changed skill so normalizing its manifest hash would be detected.
t49_source="$installer_root/t49-source"
if ! copy_installer_inputs "$t49_source"; then
  bad "T49 untagged manifest-bearing fixture" "cannot copy this working tree's installer inputs"
else
  printf '\nUntagged agent change.\n' >> "$t49_source/agents/fc-pm.md"
  printf '\r\nUntagged skill change.\r\n' >> "$t49_source/.claude/skills/fc-review/SKILL.md"
  for engine in "${INSTALLERS[@]}"; do
    p="$installer_root/t49-$engine"
    case_err=""
    run_copied_installer "$t49_source" "$engine" "$p" --force
    expect_installer_success untagged-install
    raw_files_manifest "$p" > "$installer_root/t49.expected" || case_err="$case_err cannot-hash-untagged-files"
    expect_manifest_bytes "$p" "$installer_root/t49.expected" untagged-baseline
    snapshot_tree "$p" > "$installer_root/before"
    run_installer "$engine" "$p" --uninstall --dry-run
    expect_installer_success dry-uninstall
    count=$(printf '%s\n' "$installer_out" | grep -c '^kept (yours' || true)
    [ "$count" -eq 0 ] || case_err="$case_err kept-lines=$count(want-0)"
    expect_output_line "DRY-RUN: would remove $p/feature-crew.sha256" dry-manifest-removal
    snapshot_tree "$p" > "$installer_root/after"
    cmp -s "$installer_root/before" "$installer_root/after" || case_err="$case_err dry-run-changed-untagged-install"
    installer_result "T49 $engine recognizes an untagged manifest-bearing agent and skill"
  done
fi

# ---------------------------------------------------------------- T49b
# Retiring a managed path drops its record, not the installed file itself.
t49b_source="$installer_root/t49b-source"
if ! copy_installer_inputs "$t49b_source"; then
  bad "T49b retired-agent fixture" "cannot copy this working tree's installer inputs"
else
  printf '# Fixture-only retired agent\n' > "$t49b_source/agents/fc-retired.md"
  for engine in "${INSTALLERS[@]}"; do
    case_err=""
    for variant in nonforce force; do
      p="$installer_root/t49b-$engine-$variant"
      run_copied_installer "$t49b_source" "$engine" "$p" --force
      expect_installer_success "$variant:fixture-install"
      if ! cp "$p/agents/fc-retired.md" "$installer_root/t49b.retired"; then
        case_err="$case_err $variant:retired-agent-snapshot-missing"
        continue
      fi
      hash=$("${installer_hash[@]}" < "$installer_root/t49b.retired" | cut -d' ' -f1)
      grep -qxF "$hash  agents/fc-retired.md" "$p/feature-crew.sha256" 2>/dev/null \
        || case_err="$case_err $variant:fixture-manifest-missing-retired-entry"
      if [ "$variant" = force ]; then run_installer "$engine" "$p" --force
      else run_installer "$engine" "$p"; fi
      expect_installer_success "$variant:current-install"
      raw_files_manifest "$p" | grep -v '  agents/fc-retired\.md$' > "$installer_root/t49b.expected" \
        || case_err="$case_err $variant:cannot-hash-current-files"
      expect_manifest_bytes "$p" "$installer_root/t49b.expected" "$variant:current-paths-only"
      check_manifest "$p" > "$installer_root/check.out" 2>&1 || case_err="$case_err $variant:checksum-check-failed"
      cmp -s "$installer_root/t49b.retired" "$p/agents/fc-retired.md" || case_err="$case_err $variant:retired-agent-changed"
    done
    installer_result "T49b $engine reinstall drops stale manifest entries without changing retired files, with and without force"
  done
fi

# ---------------------------------------------------------------- T50
for engine in "${INSTALLERS[@]}"; do
  p="$installer_root/t50a-$engine"
  case_err=""
  run_installer "$engine" "$p"
  expect_installer_success install
  raw_files_manifest "$p" | grep '  agents/fc-pm.md$' > "$installer_root/t50.expected"
  printf '\nMY EDIT\n' >> "$p/agents/fc-pm.md"
  cp "$p/agents/fc-pm.md" "$installer_root/t50.edited"
  run_installer "$engine" "$p"
  expect_installer_success nonforce-install
  grep '  agents/fc-pm.md$' "$p/feature-crew.sha256" > "$installer_root/t50.entry" 2>/dev/null
  cmp -s "$installer_root/t50.expected" "$installer_root/t50.entry" || case_err="$case_err nonforce:original-baseline-not-retained"
  for attempt in 1 2; do
    run_installer "$engine" "$p" --uninstall
    expect_installer_success "uninstall-$attempt"
    cmp -s "$installer_root/t50.edited" "$p/agents/fc-pm.md" || case_err="$case_err uninstall-$attempt:edit-changed"
    expect_output_line "kept (yours — differs from what we install): $p/agents/fc-pm.md" "uninstall-$attempt:edited-agent"
    expect_output_line "kept (records the files kept above): $p/feature-crew.sha256" "uninstall-$attempt:kept-manifest"
    expect_manifest_bytes "$p" "$installer_root/t50.expected" "uninstall-$attempt:original-baseline"
  done
  installer_result "T50a $engine never adopts an edited agent as its baseline across reinstall and repeated uninstall"

  p="$installer_root/t50b-$engine"
  case_err=""
  run_installer "$engine" "$p"
  expect_installer_success install
  raw_files_manifest "$p" | grep '  agents/fc-pm.md$' > "$installer_root/t50.expected"
  if ! seed_v501 "$installer_root/t50b-$engine-old"; then
    bad "T50b $engine manifest takes precedence over an older published agent" "v5.0.1 installer fixture failed"
  else
    old="$installer_root/t50b-$engine-old/agents/fc-pm.md"
    cmp -s "$old" "$p/agents/fc-pm.md" && case_err="$case_err old-agent-fixture-matches-current-version"
    cp "$old" "$p/agents/fc-pm.md"
    run_installer "$engine" "$p"
    expect_installer_success nonforce-install
    run_installer "$engine" "$p" --uninstall
    expect_installer_success uninstall
    cmp -s "$old" "$p/agents/fc-pm.md" || case_err="$case_err older-published-edit-was-removed"
    expect_output_line "kept (yours — differs from what we install): $p/agents/fc-pm.md" older-published-edit
    expect_output_line "kept (records the files kept above): $p/feature-crew.sha256" kept-manifest
    expect_manifest_bytes "$p" "$installer_root/t50.expected" original-baseline
    installer_result "T50b $engine manifest takes precedence over an older published agent after non-force reinstall"
  fi

  p="$installer_root/t50c-$engine"
  case_err=""
  run_installer "$engine" "$p"
  expect_installer_success install
  raw_files_manifest "$p" | grep '  skills/fc-build-or-fix/' > "$installer_root/t50.expected"
  printf '\nMY SKILL EDIT\n' >> "$p/skills/fc-build-or-fix/SKILL.md"
  snapshot_tree "$p/skills/fc-build-or-fix" > "$installer_root/t50.skill"
  for attempt in 1 2; do
    run_installer "$engine" "$p" --uninstall
    expect_installer_success "uninstall-$attempt"
    expect_output_line "kept (yours — differs from what we install): $p/skills/fc-build-or-fix" "uninstall-$attempt:edited-skill"
    snapshot_tree "$p/skills/fc-build-or-fix" > "$installer_root/after" 2>/dev/null
    cmp -s "$installer_root/t50.skill" "$installer_root/after" || case_err="$case_err uninstall-$attempt:skill-not-kept-whole"
    expect_output_line "kept (records the files kept above): $p/feature-crew.sha256" "uninstall-$attempt:kept-manifest"
    expect_manifest_bytes "$p" "$installer_root/t50.expected" "uninstall-$attempt:skill-baselines"
  done
  installer_result "T50c $engine keeps an edited skill whole and retains its original manifest entries"

  # Guard: this already passed before manifests existed; T47 separately proves
  # that the fresh install really creates the manifest that must disappear.
  p="$installer_root/t50d-$engine"
  case_err=""
  run_installer "$engine" "$p"
  expect_installer_success install
  run_installer "$engine" "$p" --uninstall
  expect_installer_success uninstall
  [ -z "$(remaining_files "$p")" ] || case_err="$case_err untouched-install-left-files"
  installer_result "T50d $engine untouched install uninstalls every file, including its manifest (guard)"

  p="$installer_root/t50e-$engine"
  case_err=""
  run_installer "$engine" "$p"
  expect_installer_success install
  rm "$p/skills/fc-build-or-fix/reference/meta-work-cap.md" || case_err="$case_err missing-file-fixture-failed"
  run_installer "$engine" "$p" --uninstall
  expect_installer_success uninstall
  [ ! -d "$p/skills/fc-build-or-fix" ] || case_err="$case_err missing-shipped-file-blocks-skill-removal"
  [ -z "$(remaining_files "$p")" ] || case_err="$case_err uninstall-left-files"
  installer_result "T50e $engine a missing shipped file does not protect an otherwise untouched skill"
done

# ---------------------------------------------------------------- T51
# Execute the installers' own read-only modes, which replaced fc-update's inline
# predicate: current means an equal manifest AND every installed file hashed.
# A deleted, edited, or older install needs an update; neither mode writes.
t51_run() { # engine, prefix, want-exit, label, flags...
  local engine="$1" prefix="$2" want="$3" label="$4"; shift 4
  snapshot_tree "$prefix" > "$installer_root/t51.before" 2>/dev/null
  run_installer "$engine" "$prefix" "$@"
  [ "$installer_rc" -eq "$want" ] || case_err="$case_err $label:exit=$installer_rc(want-$want)"
  snapshot_tree "$prefix" > "$installer_root/t51.after" 2>/dev/null
  cmp -s "$installer_root/t51.before" "$installer_root/t51.after" || case_err="$case_err $label:prefix-changed"
}
for engine in "${INSTALLERS[@]}"; do
  case_err=""
  p="$installer_root/t51-$engine/current"
  run_installer "$engine" "$p"
  expect_installer_success install
  t51_run "$engine" "$p" 0 untouched-check --check
  expect_output_line 'check: current' untouched-check
  t51_run "$engine" "$p" 0 untouched-verify --verify
  expect_output_line 'verify: ok' untouched-verify
  rm "$p/agents/fc-pm.md" || case_err="$case_err deletion-fixture-failed"
  t51_run "$engine" "$p" 1 deleted-check --check
  expect_output_line 'missing: agents/fc-pm.md' deleted-check
  expect_output_line 'check: update-needed' deleted-check
  t51_run "$engine" "$p" 1 deleted-verify --verify
  expect_output_line 'verify: failed' deleted-verify

  p="$installer_root/t51-$engine/edited"
  run_installer "$engine" "$p"
  expect_installer_success fresh-install
  printf '\nMY SKILL EDIT\n' >> "$p/skills/fc-review/SKILL.md"
  t51_run "$engine" "$p" 1 edited-check --check
  expect_output_line 'uncertain: skills/fc-review/SKILL.md' edited-check
  expect_output_line 'check: update-needed' edited-check

  p="$installer_root/t51-$engine/old"
  if ! seed_v501 "$p"; then
    case_err="$case_err v501-fixture-failed"
  else
    run_installer "$engine" "$p"
    expect_installer_success nonforce-install
    t51_run "$engine" "$p" 1 old-check --check
    expect_output_line 'outdated: feature-crew.sha256' old-check
    expect_output_line 'check: update-needed' old-check
    run_installer "$engine" "$p" --force
    expect_installer_success force-install
    t51_run "$engine" "$p" 0 forced-check --check
    expect_output_line 'check: current' forced-check
    t51_run "$engine" "$p" 0 forced-verify --verify
    expect_output_line 'verify: ok' forced-verify
  fi
  installer_result "T51 $engine --check/--verify: current means an equal manifest AND every installed file hashed"
done

# ---------------------------------------------------------------- T52
# These malformed fixtures use real installed-file hashes, independently of
# whether the installer can write a manifest yet. That keeps all three RED
# probes live rather than silently skipping CRLF/traversal when it is absent.
for engine in "${INSTALLERS[@]}"; do
  for malformed in text crlf parent-segment; do
    case_err=""
    p="$installer_root/t52-$engine-$malformed"
    run_installer "$engine" "$p"
    expect_installer_success install
    raw_files_manifest "$p" > "$installer_root/t52.valid" || case_err="$case_err cannot-hash-installed-files"
    case "$malformed" in
      text) printf 'not a manifest\n' > "$p/feature-crew.sha256" ;;
      crlf) awk '{ printf "%s\r\n", $0 }' "$installer_root/t52.valid" > "$p/feature-crew.sha256" ;;
      parent-segment) sed 's|  agents/fc-pm.md$|  agents/../fc-pm.md|' "$installer_root/t52.valid" > "$p/feature-crew.sha256" ;;
    esac
    cp "$p/feature-crew.sha256" "$installer_root/t52.invalid"
    for action in install uninstall; do
      if [ "$action" = install ]; then run_installer "$engine" "$p"
      else run_installer "$engine" "$p" --uninstall; fi
      expect_installer_success "$action"
      expect_output_line "kept (not a Feature-Crew manifest): $p/feature-crew.sha256" "$action:invalid-manifest"
      cmp -s "$installer_root/t52.invalid" "$p/feature-crew.sha256" || case_err="$case_err $action:invalid-manifest-changed"
    done
    [ "$(remaining_files "$p")" = 'feature-crew.sha256' ] || case_err="$case_err uninstall-did-not-leave-only-invalid-manifest"
    installer_result "T52 $engine preserves a $malformed manifest while treating it as absent"
  done
done
# ------------------------------------------------------------- T52empty
# Zero lines is valid: install rewrites it; uninstall removes it when empty.
for engine in "${INSTALLERS[@]}"; do
  case_err=""
  p="$installer_root/t52-$engine-empty"
  mkdir -p "$p"
  : > "$p/feature-crew.sha256"
  snapshot_tree "$p" > "$installer_root/before"
  run_installer "$engine" "$p" --dry-run
  expect_installer_success dry-install
  expect_output_line "DRY-RUN: write $p/feature-crew.sha256" dry-empty-manifest-write
  printf '%s\n' "$installer_out" | grep -qF 'kept (not a Feature-Crew manifest):' && case_err="$case_err dry-install:empty-manifest-rejected"
  snapshot_tree "$p" > "$installer_root/after"
  cmp -s "$installer_root/before" "$installer_root/after" || case_err="$case_err dry-install:tree-changed"

  run_installer "$engine" "$p"
  expect_installer_success install
  expect_output_line "installed: $p/feature-crew.sha256" empty-manifest-rewritten
  printf '%s\n' "$installer_out" | grep -qF 'kept (not a Feature-Crew manifest):' && case_err="$case_err install:empty-manifest-rejected"
  raw_files_manifest "$p" > "$installer_root/t52-empty.expected" || case_err="$case_err cannot-hash-installed-files"
  expect_manifest_bytes "$p" "$installer_root/t52-empty.expected" empty-replaced-with-canonical-manifest
  check_manifest "$p" > "$installer_root/check.out" 2>&1 || case_err="$case_err checksum-check-failed"

  : > "$p/feature-crew.sha256"
  snapshot_tree "$p" > "$installer_root/before"
  run_installer "$engine" "$p" --uninstall --dry-run
  expect_installer_success dry-uninstall
  expect_output_line "DRY-RUN: would remove $p/feature-crew.sha256" dry-empty-manifest-removal
  printf '%s\n' "$installer_out" | grep -qF 'kept (not a Feature-Crew manifest):' && case_err="$case_err dry-uninstall:empty-manifest-rejected"
  snapshot_tree "$p" > "$installer_root/after"
  cmp -s "$installer_root/before" "$installer_root/after" || case_err="$case_err dry-uninstall:tree-changed"
  run_installer "$engine" "$p" --uninstall
  expect_installer_success uninstall
  expect_output_line "removed: $p/feature-crew.sha256" empty-manifest-removed
  printf '%s\n' "$installer_out" | grep -qF 'kept (not a Feature-Crew manifest):' && case_err="$case_err uninstall:empty-manifest-rejected"
  [ -z "$(remaining_files "$p")" ] || case_err="$case_err uninstall-left-files"
  installer_result "T52empty $engine accepts and rewrites an empty manifest, then removes it without dry-run mutation"
done
if [ "${#INSTALLERS[@]}" -eq 1 ]; then
  for n in 47 48a 48b 49 49b 50a 50b 50c 50d 50e 51 52-text 52-crlf 52-parent-segment 52empty; do
    skip "T$n ps1 manifest regression (pwsh unavailable; set PWSH)"
  done
fi

# ---------------------------------------------------------------- T53
# Prose alarms cannot prove a reader's interpretation. fc-update delegates its
# predicate to the installers, so pin its commands and consent rules as literal
# sentences within its Flow; removing any one must fail with its own label.
t53_labels=(
  dirty-clone-refused ff-only-pull check-after-any-pull check-exit-codes current-reports-stale
  uncertain-listed backup-offered consent-before-force never-decides force-install
  verify-once errors-stop malformed-manifest-untouched windows-equivalent accepted-limit
)
t53_rules=(
  'Run `git status --short`; if the clone is dirty, stop and ask, never stash or discard its work.'
  'Run `git pull --ff-only` and summarize what arrived.'
  'Always run `./install.sh --check` next, even when the pull was a no-op.'
  'It is read-only and exits 0 when current, 1 when an update is needed, and 2 on any error.'
  'If it reports `check: current`, report its `stale:` lines with the manual `rm` for each, then stop.'
  'Otherwise list every `uncertain:` file, including files inside skill directories.'
  'Offer a backup of each (`cp <file> <file>.bak`).'
  'Get explicit consent before running `--force`.'
  'Never decide backups or overwrites for the user.'
  'Run `./install.sh --force` and report its `kept` lines.'
  'Then run `./install.sh --verify` once and paste its output, with the manual `rm` for each `stale:` line.'
  'Any error stops the flow.'
  'Report a malformed manifest and leave it untouched; never rewrite it to pass the check.'
  'On native Windows without Git Bash, use `.\install.ps1` with `-Check`, `-Force`, and `-Verify`.'
  'Accepted limit: a file edited between `--check` and `--force` is not asked about again (single-user local window).'
)
t53_contract() { # SKILL.md text
  local flow i at last=-1 errors=""
  flow=$(printf '%s\n' "$1" | sed -n '/^## Flow$/,/^## /p')
  for ((i=0; i<${#t53_rules[@]}; i++)); do
    case "$flow" in
      *"${t53_rules[$i]}"*) ;;
      *) errors="$errors ${t53_labels[$i]}" ;;
    esac
  done
  # Check, then consent, then --force, then --verify: among the rules present.
  for i in 2 7 9 10; do
    case "$flow" in *"${t53_rules[$i]}"*) ;; *) continue ;; esac
    at="${flow%%"${t53_rules[$i]}"*}"
    if [ "${#at}" -le "$last" ]; then errors="$errors check-consent-force-verify-order"; break; fi
    last=${#at}
  done
  printf '%s\n' "$errors"
}
case_err=""
s=.claude/skills/fc-update/SKILL.md
t53_text=$(cat "$s")
t53_out=$(t53_contract "$t53_text")
case_err="$case_err$t53_out"
# The predicate lives in the installers now; an inline copy here would drift.
grep -qE 'sha256sum -c|shasum -a 256 -c|cmp -s|mktemp -d' "$s" && case_err="$case_err inline-predicate-returned"
grep -qiF 'If the pull was a no-op, say so and stop' "$s" && case_err="$case_err no-op-pull-still-stops"
count=$(wc -l < "$s" | tr -d ' ')
[ "$count" -le 40 ] || case_err="$case_err fc-update-lines=$count(want-<=40)"
if [ -z "$t53_out" ]; then
  for ((t53_i=0; t53_i<${#t53_rules[@]}; t53_i++)); do
    t53_mut_out=$(t53_contract "${t53_text/"${t53_rules[$t53_i]}"/}")
    if [ "$t53_mut_out" = " ${t53_labels[$t53_i]}" ]; then
      ok "T53 removal mutation: ${t53_labels[$t53_i]} rejected by its own check"
    else
      bad "T53 removal mutation: ${t53_labels[$t53_i]}" "got '${t53_mut_out:-<empty>}', want ' ${t53_labels[$t53_i]}'"
    fi
  done
fi
installer_result "T53 fc-update runs --check after any pull, asks consent before --force, then --verify once"

# ---------------------------------------------------------------- T63
# The installers' read-only --check/--verify modes replaced fc-update's inline
# predicate. Run both engines over each ownership state, compare the whole
# ordered output and exit code, and snapshot the prefix, HOME and cwd: these
# modes never write. Removing hashing, manifest comparison, or the model-key
# check must fail with that mutation's own diagnostic, not merely some failure.
t63_root="$installer_root/t63"
t63_cwd="$t63_root/cwd"
mkdir -p "$t63_cwd" "$t63_root/parity"
t63_usage='--check and --verify cannot be combined with each other, --force, --uninstall, or --dry-run'
t63_shipped=$( { for t63_f in agents/*.md; do printf '%s\n' "$t63_f"; done
  for t63_d in .claude/skills/*/; do
    [ -f "${t63_d}SKILL.md" ] || continue
    ( cd "$t63_d" && find . -type f -print | sed "s|^\./|skills/$(basename "$t63_d")/|" )
  done; } | LC_ALL=C sort)
t63_agents=$(printf '%s\n' "$t63_shipped" | grep -c '^agents/')
t63_skills=$(printf '%s\n' "$t63_shipped" | grep -c '^skills/[^/]*/SKILL\.md$')
t63_record=1
t63_detail=""
t63_normalize() { # prefix, source, captured output
  T63_P="$1" T63_S="$2" awk '
    function swap(s, from, to,   out, i) {
      out = ""
      while (from != "" && (i = index(s, from)) > 0) {
        out = out substr(s, 1, i - 1) to
        s = substr(s, i + length(from))
      }
      return out s
    }
    { sub(/\r$/, ""); print swap(swap($0, ENVIRON["T63_P"], "<P>"), ENVIRON["T63_S"], "<SRC>") }
  ' "$3"
}
t63_expect() { printf '%s\n' "$@" > "$t63_root/expected"; }
t63_run() { # engine, prefix, want-exit, label, installer directory, flags...
  local engine="$1" prefix="$2" want="$3" label="$4" installer_repo="$5"; shift 5
  snapshot_tree "$prefix" > "$t63_root/before" 2>/dev/null
  run_installer_at "$t63_cwd" "$engine" "$prefix" "$@"
  [ "$installer_rc" -eq "$want" ] || case_err="$case_err $label:exit=$installer_rc(want-$want)"
  t63_normalize "$prefix" "$installer_repo" "$installer_root/run.out" > "$t63_root/actual"
  if ! cmp -s "$t63_root/expected" "$t63_root/actual"; then
    case_err="$case_err $label:output-differs"
    [ -n "$t63_detail" ] || t63_detail="$label: $(diff "$t63_root/expected" "$t63_root/actual" | grep -m 1 '^[<>]')"
  fi
  snapshot_tree "$prefix" > "$t63_root/after" 2>/dev/null
  cmp -s "$t63_root/before" "$t63_root/after" || case_err="$case_err $label:prefix-changed"
  [ ! -e "$installer_root/home/.claude" ] || case_err="$case_err $label:HOME-install-created"
  [ -z "$(ls -A "$t63_cwd")" ] || case_err="$case_err $label:cwd-changed"
  if [ "$t63_record" -eq 1 ]; then
    { printf 'exit=%s\n' "$installer_rc"; cat "$t63_root/actual"; } > "$t63_root/parity/$engine-$label"
  fi
}
t63_result() {
  if [ -z "$case_err" ]; then
    ok "$1"
  else
    bad "$1" "issues:$case_err"
    [ -z "$t63_detail" ] || printf '        first difference: %s\n' "$t63_detail"
  fi
  t63_detail=""
}
t63_pin_model() { # copied installer inputs: pin one role agent; add body prose to another
  { printf -- '---\nname: fc-qa-code\ndescription: "Pinned fixture."\nmodel: opus\n---\n\n'
    cat "$1/agents/fc-qa-code.md"
  } > "$t63_root/pin.tmp" && mv "$t63_root/pin.tmp" "$1/agents/fc-qa-code.md" &&
  printf '\nmodel: in body prose is not a frontmatter key.\n' >> "$1/agents/fc-pm.md"
}
t63_published_oracle() { # prefix without a manifest; independent expected --check
  local rel hash name missing="" outdated="" uncertain="" stale=""
  while IFS= read -r rel; do
    if [ ! -e "$1/$rel" ]; then
      missing="$missing$rel"$'\n'
    elif ! cmp -s "$1/$rel" "$t63_root/sh/fresh/$rel"; then
      hash=$(tr -d '\r' < "$1/$rel" | "${installer_hash[@]}" | cut -d' ' -f1)
      if grep -qxF "$hash  $rel" published.sha256; then outdated="$outdated$rel"$'\n'
      else uncertain="$uncertain$rel"$'\n'; fi
    fi
  done <<< "$t63_shipped"
  # A v5.0.1 fc-* name this clone no longer ships would be a stale warning.
  for rel in "$1"/agents/fc-*.md; do
    [ -f "$rel" ] || continue
    name=${rel##*/}
    [ -f "agents/$name" ] || stale="${stale}agents/$name"$'\n'
  done
  for rel in "$1"/skills/fc-*/; do
    [ -d "$rel" ] || continue
    name=$(basename "$rel")
    [ -f ".claude/skills/$name/SKILL.md" ] || stale="${stale}skills/$name"$'\n'
  done
  printf '%s\n' 'feature-crew: checking <P>'
  printf '%sfeature-crew.sha256\n' "$missing" | LC_ALL=C sort | sed 's/^/missing: /'
  printf '%s' "$outdated" | LC_ALL=C sort | sed 's/^/outdated: /'
  printf '%s' "$uncertain" | LC_ALL=C sort | sed 's/^/uncertain: /'
  printf '%s' "$stale" | LC_ALL=C sort | sed 's/^/stale: /'
  printf '%s\n' 'check: update-needed'
}
t63_can_lock=0
printf 'probe\n' > "$t63_root/lock-probe"
chmod 000 "$t63_root/lock-probe"
cat "$t63_root/lock-probe" > /dev/null 2>&1 || t63_can_lock=1
chmod 644 "$t63_root/lock-probe"
[ ! -e "$installer_root/home/.claude" ] || bad "T63 precondition" "$installer_root/home/.claude already exists"

for engine in "${INSTALLERS[@]}"; do
  base="$t63_root/$engine"
  mkdir -p "$base"

  case_err=""
  p="$base/absent"
  { printf '%s\n' 'feature-crew: checking <P>'
    printf '%s\n' feature-crew.sha256 "$t63_shipped" | LC_ALL=C sort | sed 's/^/missing: /'
    printf '%s\n' 'check: update-needed'; } > "$t63_root/expected"
  t63_run "$engine" "$p" 1 absent-check "$installer_repo" --check
  { printf '%s\n' 'feature-crew: verifying <P>'
    printf '%s\n' feature-crew.sha256 "$t63_shipped" | LC_ALL=C sort | sed 's/^/missing: /'
    printf '%s\n' "agents: 0/$t63_agents verified" "skills: 0/$t63_skills verified" 'verify: failed'
  } > "$t63_root/expected"
  t63_run "$engine" "$p" 1 absent-verify "$installer_repo" --verify
  [ ! -e "$p" ] || case_err="$case_err absent:prefix-created"
  t63_result "T63 $engine absent prefix: every shipped file and the manifest missing, nothing created"

  case_err=""
  p="$base/fresh"
  run_installer "$engine" "$p"
  expect_installer_success install
  t63_expect 'feature-crew: checking <P>' 'check: current'
  t63_run "$engine" "$p" 0 fresh-check "$installer_repo" --check
  t63_expect 'feature-crew: verifying <P>' "agents: $t63_agents/$t63_agents verified" \
    "skills: $t63_skills/$t63_skills verified" 'verify: ok'
  t63_run "$engine" "$p" 0 fresh-verify "$installer_repo" --verify
  t63_result "T63 $engine fresh install: check current and verify ok"

  case_err=""
  p="$base/missing"
  run_installer "$engine" "$p"
  expect_installer_success install
  rm "$p/agents/fc-pm.md" "$p/skills/fc-build-or-fix/reference/meta-work-cap.md" || case_err="$case_err fixture-failed"
  t63_expect 'feature-crew: checking <P>' 'missing: agents/fc-pm.md' \
    'missing: skills/fc-build-or-fix/reference/meta-work-cap.md' 'check: update-needed'
  t63_run "$engine" "$p" 1 missing-check "$installer_repo" --check
  t63_expect 'feature-crew: verifying <P>' 'missing: agents/fc-pm.md' \
    'missing: skills/fc-build-or-fix/reference/meta-work-cap.md' \
    "agents: $((t63_agents - 1))/$t63_agents verified" "skills: $((t63_skills - 1))/$t63_skills verified" 'verify: failed'
  t63_run "$engine" "$p" 1 missing-verify "$installer_repo" --verify
  t63_result "T63 $engine missing files are listed prefix-relative and sorted"

  case_err=""
  p="$base/edited"
  run_installer "$engine" "$p"
  expect_installer_success install
  printf '\nMY EDIT\n' >> "$p/skills/fc-review/SKILL.md"
  t63_expect 'feature-crew: checking <P>' 'uncertain: skills/fc-review/SKILL.md' 'check: update-needed'
  t63_run "$engine" "$p" 1 edited-check "$installer_repo" --check
  t63_expect 'feature-crew: verifying <P>' 'uncertain: skills/fc-review/SKILL.md' \
    "agents: $t63_agents/$t63_agents verified" "skills: $((t63_skills - 1))/$t63_skills verified" 'verify: failed'
  t63_run "$engine" "$p" 1 edited-verify "$installer_repo" --verify
  t63_result "T63 $engine an edited file is uncertain, never current"

  case_err=""
  p="$base/bom-crlf"
  run_installer "$engine" "$p"
  expect_installer_success install
  { printf '\357\273\277'; cat "$p/agents/fc-pm.md"; } > "$t63_root/bom" && mv "$t63_root/bom" "$p/agents/fc-pm.md"
  awk '{ printf "%s\r\n", $0 }' "$p/skills/fc-review/SKILL.md" > "$t63_root/crlf" && mv "$t63_root/crlf" "$p/skills/fc-review/SKILL.md"
  t63_expect 'feature-crew: checking <P>' 'uncertain: agents/fc-pm.md' \
    'uncertain: skills/fc-review/SKILL.md' 'check: update-needed'
  t63_run "$engine" "$p" 1 bom-crlf-check "$installer_repo" --check
  t63_result "T63 $engine BOM-only and CRLF-only edits are uncertain: hashes cover raw bytes"

  case_err=""
  p="$base/recorded"
  t63_fixture="$t63_root/recorded-src"
  if [ ! -d "$t63_fixture" ]; then
    copy_installer_inputs "$t63_fixture" || case_err="$case_err fixture-copy-failed"
    printf '\nUntagged agent change.\n' >> "$t63_fixture/agents/fc-pm.md"
    printf '\r\nUntagged skill change.\r\n' >> "$t63_fixture/.claude/skills/fc-review/SKILL.md"
  fi
  run_copied_installer "$t63_fixture" "$engine" "$p" --force
  expect_installer_success untagged-install
  t63_expect 'feature-crew: checking <P>' 'outdated: agents/fc-pm.md' 'outdated: feature-crew.sha256' \
    'outdated: skills/fc-review/SKILL.md' 'check: update-needed'
  t63_run "$engine" "$p" 1 recorded-check "$installer_repo" --check
  t63_result "T63 $engine the recorded baseline marks older bytes outdated, CRLF included"

  case_err=""
  p="$base/published"
  if ! seed_v501 "$p"; then
    case_err="$case_err v501-fixture-failed"
  else
    printf '\nMY EDIT\n' >> "$p/agents/fc-architect.md"
    awk '{ printf "%s\r\n", $0 }' "$p/skills/fc-grill-me/SKILL.md" > "$t63_root/crlf" && mv "$t63_root/crlf" "$p/skills/fc-grill-me/SKILL.md"
    [ ! -e "$p/feature-crew.sha256" ] || case_err="$case_err v501-wrote-a-manifest"
    t63_published_oracle "$p" > "$t63_root/expected"
    grep -qxF 'outdated: skills/fc-grill-me/SKILL.md' "$t63_root/expected" || case_err="$case_err oracle-lost-crlf-outdated"
    grep -qxF 'uncertain: agents/fc-architect.md' "$t63_root/expected" || case_err="$case_err oracle-lost-uncertain"
    t63_run "$engine" "$p" 1 published-check "$installer_repo" --check
  fi
  t63_result "T63 $engine without a manifest, CR-normalized published hashes mark older files outdated"

  case_err=""
  p="$base/precedence"
  run_installer "$engine" "$p"
  expect_installer_success install
  if [ ! -f "$t63_root/v501-pm.md" ]; then
    { seed_v501 "$t63_root/v501" && cp "$t63_root/v501/agents/fc-pm.md" "$t63_root/v501-pm.md"; } \
      || case_err="$case_err v501-fixture-failed"
  fi
  cmp -s "$t63_root/v501-pm.md" "$p/agents/fc-pm.md" && case_err="$case_err v501-agent-matches-current"
  cp "$t63_root/v501-pm.md" "$p/agents/fc-pm.md" || case_err="$case_err fixture-failed"
  t63_expect 'feature-crew: checking <P>' 'uncertain: agents/fc-pm.md' 'check: update-needed'
  t63_run "$engine" "$p" 1 precedence-baseline "$installer_repo" --check
  rm -f "$p/feature-crew.sha256"
  t63_expect 'feature-crew: checking <P>' 'missing: feature-crew.sha256' 'outdated: agents/fc-pm.md' 'check: update-needed'
  t63_run "$engine" "$p" 1 precedence-published "$installer_repo" --check
  t63_result "T63 $engine a recorded baseline outranks published hashes, which apply only without one"

  case_err=""
  p="$base/manifests"
  run_installer "$engine" "$p"
  expect_installer_success install
  cp "$p/feature-crew.sha256" "$t63_root/valid.sha256"
  grep -v '  agents/fc-pm\.md$' "$t63_root/valid.sha256" > "$p/feature-crew.sha256"
  t63_expect 'feature-crew: checking <P>' 'outdated: feature-crew.sha256' 'check: update-needed'
  t63_run "$engine" "$p" 1 incomplete-check "$installer_repo" --check
  { cat "$t63_root/valid.sha256"; printf '%064d  agents/fc-forged.md\n' 0; } > "$p/feature-crew.sha256"
  t63_run "$engine" "$p" 1 forged-entry-check "$installer_repo" --check
  : > "$p/feature-crew.sha256"
  t63_run "$engine" "$p" 1 empty-check "$installer_repo" --check
  # A forged baseline passes sha256sum -c, yet the install is still not current.
  printf '\nMY EDIT\n' >> "$p/skills/fc-review/SKILL.md"
  t63_hash=$("${installer_hash[@]}" < "$p/skills/fc-review/SKILL.md" | cut -d' ' -f1)
  sed "s|^[0-9a-f]\{64\}  skills/fc-review/SKILL\.md\$|$t63_hash  skills/fc-review/SKILL.md|" \
    "$t63_root/valid.sha256" > "$p/feature-crew.sha256"
  check_manifest "$p" > "$installer_root/check.out" 2>&1 || case_err="$case_err forged-baseline-not-checksum-clean"
  t63_expect 'feature-crew: checking <P>' 'outdated: feature-crew.sha256' \
    'outdated: skills/fc-review/SKILL.md' 'check: update-needed'
  t63_run "$engine" "$p" 1 forged-baseline-check "$installer_repo" --check
  t63_result "T63 $engine forged, incomplete, and empty manifests never read as current"

  case_err=""
  p="$base/malformed"
  run_installer "$engine" "$p"
  expect_installer_success install
  cp "$p/feature-crew.sha256" "$t63_root/valid.sha256"
  for t63_kind in text crlf parent-segment bom directory; do
    rm -rf "$p/feature-crew.sha256"
    case "$t63_kind" in
      text) printf 'not a manifest\n' > "$p/feature-crew.sha256" ;;
      crlf) awk '{ printf "%s\r\n", $0 }' "$t63_root/valid.sha256" > "$p/feature-crew.sha256" ;;
      parent-segment) sed 's|  agents/fc-pm\.md$|  agents/../fc-pm.md|' "$t63_root/valid.sha256" > "$p/feature-crew.sha256" ;;
      bom) { printf '\357\273\277'; cat "$t63_root/valid.sha256"; } > "$p/feature-crew.sha256" ;;
      directory) mkdir "$p/feature-crew.sha256" ;;
    esac
    t63_expect 'ERROR: not a Feature-Crew manifest (left untouched): <P>/feature-crew.sha256'
    t63_run "$engine" "$p" 2 "malformed-$t63_kind-check" "$installer_repo" --check
    t63_run "$engine" "$p" 2 "malformed-$t63_kind-verify" "$installer_repo" --verify
  done
  t63_result "T63 $engine malformed manifests (text, CRLF, traversal, BOM, directory) exit 2 untouched"

  case_err=""
  p="$base/stale"
  run_installer "$engine" "$p"
  expect_installer_success install
  mkdir -p "$p/skills/fc-retired" "$p/skills/fc-scratch" "$p/skills/personal"
  printf 'retired\n' > "$p/skills/fc-retired/SKILL.md"
  printf 'retired agent\n' > "$p/agents/fc-retired.md"
  printf 'mine\n' > "$p/agents/personal.md"
  cp "$installer_root/personal" "$p/skills/fc-review/.notes.md"
  t63_expect 'feature-crew: checking <P>' 'stale: agents/fc-retired.md' 'stale: skills/fc-retired' \
    'stale: skills/fc-scratch' 'check: current'
  t63_run "$engine" "$p" 0 stale-check "$installer_repo" --check
  t63_expect 'feature-crew: verifying <P>' 'stale: agents/fc-retired.md' 'stale: skills/fc-retired' \
    'stale: skills/fc-scratch' "agents: $t63_agents/$t63_agents verified" \
    "skills: $t63_skills/$t63_skills verified" 'verify: ok'
  t63_run "$engine" "$p" 0 stale-verify "$installer_repo" --verify
  t63_result "T63 $engine stale fc-* leftovers are warnings: reported, kept, and no update"

  case_err=""
  p="$base/model"
  t63_fixture="$t63_root/model-src"
  if [ ! -d "$t63_fixture" ]; then
    { copy_installer_inputs "$t63_fixture" && t63_pin_model "$t63_fixture"; } || case_err="$case_err fixture-failed"
  fi
  run_copied_installer "$t63_fixture" "$engine" "$p" --force
  expect_installer_success pinned-install
  t63_expect 'feature-crew: checking <P>' 'check: current'
  t63_run "$engine" "$p" 0 model-check "$t63_fixture" --check
  t63_expect 'feature-crew: verifying <P>' 'model key: agents/fc-qa-code.md' \
    "agents: $((t63_agents - 1))/$t63_agents verified" "skills: $t63_skills/$t63_skills verified" 'verify: failed'
  t63_run "$engine" "$p" 1 model-verify "$t63_fixture" --verify
  t63_result "T63 $engine verify rejects a model key in role-agent frontmatter, not model prose"

  case_err=""
  p="$base/fresh"
  t63_fixture="$t63_root/no-agents-src"
  if [ ! -d "$t63_fixture" ]; then
    { copy_installer_inputs "$t63_fixture" && rm -rf "$t63_fixture/agents"; } || case_err="$case_err fixture-failed"
  fi
  t63_expect 'ERROR: cannot find agents/ next to the installer (<SRC>/agents)'
  t63_run "$engine" "$p" 2 no-agents-check "$t63_fixture" --check
  if [ "$t63_can_lock" -eq 1 ]; then
    for t63_locked in agents/fc-pm.md feature-crew.sha256; do
      snapshot_tree "$p" > "$t63_root/locked-before"
      chmod 000 "$p/$t63_locked"
      run_installer_at "$t63_cwd" "$engine" "$p" --verify
      chmod 644 "$p/$t63_locked"
      [ "$installer_rc" -eq 2 ] || case_err="$case_err unreadable-$t63_locked:exit=$installer_rc(want-2)"
      printf '%s\n' "$installer_out" | grep -qE '^(missing|outdated|uncertain|stale|check|verify):' \
        && case_err="$case_err unreadable-$t63_locked:reported-a-verdict"
      snapshot_tree "$p" > "$t63_root/locked-after"
      cmp -s "$t63_root/locked-before" "$t63_root/locked-after" || case_err="$case_err unreadable-$t63_locked:prefix-changed"
    done
  fi
  t63_result "T63 $engine operational errors (no agents/ source, unreadable file) exit 2 without a verdict"

  case_err=""
  p="$base/absent"
  for t63_pair in '--check --verify' '--check --force' '--verify --uninstall' '--check --dry-run' '--verify --force'; do
    t63_expect "$t63_usage"
    # shellcheck disable=SC2086 # split the flag pair on purpose
    t63_run "$engine" "$p" 2 "usage-${t63_pair// /}" "$installer_repo" $t63_pair
  done
  if [ "$engine" = ps1 ]; then
    t63_expect "$t63_usage"
    t63_run "$engine" "$p" 2 usage-native "$installer_repo" -Check -Force
  fi
  t63_result "T63 $engine --check/--verify with each other, --force, --uninstall, or --dry-run is a usage error"
done
[ "$t63_can_lock" -eq 1 ] || skip "T63 unreadable-file exit 2 (file permissions not enforced for this user)"

if [ "${#INSTALLERS[@]}" -eq 2 ]; then
  case_err=""
  t63_count=0
  for t63_f in "$t63_root"/parity/sh-*; do
    [ -f "$t63_f" ] || continue
    t63_label=${t63_f##*/sh-}
    t63_count=$((t63_count + 1))
    cmp -s "$t63_f" "$t63_root/parity/ps1-$t63_label" || case_err="$case_err $t63_label"
  done
  [ "$t63_count" -gt 0 ] || case_err="$case_err no-runs-recorded"
  t63_result "T63 exit-code and output parity: install.sh and the PowerShell fallback agree on all $t63_count runs"

  # Delegation: a Git-layout stub records argv and returns a chosen exit.
  t63_git="$t63_root/git"
  mkdir -p "$t63_git/cmd" "$t63_git/bin"
  printf '#!/bin/sh\nexit 0\n' > "$t63_git/cmd/git"
  chmod +x "$t63_git/cmd/git"
  t63_delegate() { # stub exit, install.ps1 arguments...
    local code="$1"; shift
    cat > "$t63_git/bin/bash.exe" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$t63_root/git-args"
exit $code
STUB
    chmod +x "$t63_git/bin/bash.exe"
    rm -f "$t63_root/git-args"
    ( cd "$t63_cwd" && env -i HOME="$installer_root/home" PATH="$t63_git/cmd" \
        POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off \
        "$PWSH_BIN" -NonInteractive -File "$installer_repo/install.ps1" "$@" ) > "$t63_root/delegate.out" 2>&1
    installer_rc=$?
  }
  case_err=""
  p="$t63_root/delegated"
  t63_delegate 1 -Check -Prefix "$p"
  [ "$installer_rc" -eq 1 ] || case_err="$case_err check:exit=$installer_rc(want-1)"
  [ "$(tail -n +2 "$t63_root/git-args" 2>/dev/null)" = "--check"$'\n'"--prefix"$'\n'"$p" ] \
    || case_err="$case_err check:argv-not-forwarded"
  grep -qF 'using the PowerShell installer' "$t63_root/delegate.out" && case_err="$case_err check:fell-back"
  t63_delegate 2 --verify --prefix "$p"
  [ "$installer_rc" -eq 2 ] || case_err="$case_err verify:exit=$installer_rc(want-2)"
  [ "$(tail -n +2 "$t63_root/git-args" 2>/dev/null)" = "--verify"$'\n'"--prefix"$'\n'"$p" ] \
    || case_err="$case_err verify:argv-not-forwarded"
  grep -qF 'using the PowerShell installer' "$t63_root/delegate.out" && case_err="$case_err verify:fell-back"
  t63_delegate 0 -Check -Force -Prefix "$p"
  [ "$installer_rc" -eq 2 ] || case_err="$case_err conflict:exit=$installer_rc(want-2)"
  [ ! -e "$t63_root/git-args" ] || case_err="$case_err conflict:delegated-before-rejecting"
  grep -qxF -- "$t63_usage" "$t63_root/delegate.out" || case_err="$case_err conflict:usage-missing"
  [ ! -e "$p" ] || case_err="$case_err prefix-created"
  t63_result "T63 ps1 forwards -Check/--verify to Git Bash, propagates exits 1 and 2, and rejects conflicts first"
else
  skip "T63 ps1 check/verify parity and Git Bash delegation (pwsh unavailable; set PWSH)"
fi

case_err=""
t63_flags=$(grep '^Flags:' README.md)
for t63_flag in --check --verify -Check -Verify; do
  printf '%s\n' "$t63_flags" | grep -qF -- "\`$t63_flag\`" || case_err="$case_err README-missing:$t63_flag"
done
HOME="$installer_root/home" "$installer_bash" "$installer_repo/install.sh" --help > "$t63_root/help.out" 2>&1 \
  || case_err="$case_err sh-help-failed"
for t63_flag in --check --verify; do
  grep -qF -- "$t63_flag" "$t63_root/help.out" || case_err="$case_err sh-help-missing:$t63_flag"
done
if [ -n "$PWSH_BIN" ] && [ -x "$PWSH_BIN" ]; then
  ( cd "$t63_cwd" && env -i HOME="$installer_root/home" PATH="$installer_root/empty-path" \
      POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off \
      "$PWSH_BIN" -NonInteractive -File "$installer_repo/install.ps1" --help ) > "$t63_root/help.out" 2>&1 \
    || case_err="$case_err ps1-help-failed"
  for t63_flag in --check -Check --verify -Verify; do
    grep -qF -- "$t63_flag" "$t63_root/help.out" || case_err="$case_err ps1-help-missing:$t63_flag"
  done
fi
t63_result "T63 README Flags line and both installers' help name --check/-Check and --verify/-Verify"

if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import yaml' >/dev/null 2>&1; then
  skip "T63 native Windows check/verify workflow steps (PyYAML unavailable)"
elif t63_out=$(python3 - <<'PY'
import pathlib, sys, yaml
doc = yaml.safe_load(pathlib.Path('.github/workflows/test.yml').read_text())
jobs = doc.get('jobs', {})
errors = []
for job in ('framework', 'powershell', 'powershell-delegation'):
    if job not in jobs or jobs[job].get('name', job) != job:
        errors.append('job-renamed-or-missing:' + job)
script = str(doc.get('env', {}).get('TEST_CHECK_VERIFY', ''))
for token in ('-Check', '-Verify', '--check', '--verify', '-Check -Force', 'Get-Command bash, git',
              'check: update-needed', 'verify: ok', 'feature-crew.sha256', '$global:LASTEXITCODE'):
    if token not in script:
        errors.append('check-verify-script-missing:' + token)
def runs(job, shell, masked):
    for step in jobs.get(job, {}).get('steps', []):
        text = str(step.get('run', ''))
        if step.get('shell') != shell or '$env:TEST_CHECK_VERIFY' not in text:
            continue
        mask = text.find('$env:MASK_BASH')
        engine = str(step.get('env', {}).get('FC_CHECK_ENGINE', ''))
        if masked and engine == 'fallback' and -1 < mask < text.find('$env:TEST_CHECK_VERIFY'):
            return True
        if not masked and engine == 'git-bash' and mask == -1:
            return True
    return False
for shell in ('pwsh', 'powershell'):
    if not runs('powershell', shell, True):
        errors.append('masked-fallback-step-missing:' + shell)
    if not runs('powershell-delegation', shell, False):
        errors.append('delegation-step-missing:' + shell)
print(' '.join(errors))
sys.exit(bool(errors))
PY
); then
  ok "T63 native Windows runs -Check/-Verify in the masked fallback and through Git Bash, pwsh and PowerShell 5.1"
else
  bad "T63 native Windows check/verify workflow steps" "issues:$t63_out"
fi

if ! command -v python3 >/dev/null 2>&1; then
  skip "T63 check/verify mutation replay (python3 unavailable)"
else
  t63_record=0
  for engine in "${INSTALLERS[@]}"; do
    for t63_variant in hashing manifest model-key; do
      case_err=""
      t63_fixture="$t63_root/mut-$engine-$t63_variant-src"
      p="$t63_root/mut-$engine-$t63_variant"
      copy_installer_inputs "$t63_fixture" || case_err="$case_err fixture-copy-failed"
      case "$t63_variant" in
        hashing)
          run_installer "$engine" "$p"
          printf '\nMY EDIT\n' >> "$p/skills/fc-review/SKILL.md"
          t63_mode=--check
          t63_expect 'feature-crew: checking <P>' 'uncertain: skills/fc-review/SKILL.md' 'check: update-needed' ;;
        manifest)
          run_installer "$engine" "$p"
          grep -v '  agents/fc-pm\.md$' "$p/feature-crew.sha256" > "$t63_root/incomplete" \
            && mv "$t63_root/incomplete" "$p/feature-crew.sha256"
          t63_mode=--check
          t63_expect 'feature-crew: checking <P>' 'outdated: feature-crew.sha256' 'check: update-needed' ;;
        model-key)
          t63_pin_model "$t63_fixture" || case_err="$case_err pin-failed"
          run_copied_installer "$t63_fixture" "$engine" "$p" --force
          t63_mode=--verify
          t63_expect 'feature-crew: verifying <P>' 'model key: agents/fc-qa-code.md' \
            "agents: $((t63_agents - 1))/$t63_agents verified" "skills: $t63_skills/$t63_skills verified" 'verify: failed' ;;
      esac
      expect_installer_success fixture-install
      t63_run "$engine" "$p" 1 "$t63_variant-control" "$t63_fixture" "$t63_mode"
      if [ -n "$case_err" ]; then
        t63_result "T63 $engine $t63_variant mutation replay (control must pass first)"
        continue
      fi
      if ! t63_mut=$(python3 - "$engine" "$t63_variant" "$t63_fixture/install.$engine" 2>&1 <<'PY'
import pathlib, sys
engine, variant, path = sys.argv[1:]
old, new = {
    ('sh', 'hashing'): (b'    if [ "$got" = "$want" ]; then\n', b'    if true; then\n'),
    ('ps1', 'hashing'): (b"  if ((Get-Sha256Raw $file) -ceq $want) { return 'current' }\n",
                         b"  if ($true) { return 'current' }\n"),
    ('sh', 'manifest'): (b'  elif ! check_manifest_text | cmp -s - "$MANIFEST"; then\n', b'  elif false; then\n'),
    ('ps1', 'manifest'): (b'  } elseif (-not (Test-BytesEqual $bytes ([IO.File]::ReadAllBytes((Resolve-AbsPath $Manifest))))) {\n',
                          b'  } elseif ($false) {\n'),
    ('sh', 'model-key'): (b'    if [ "$VERIFY" -eq 1 ] && [ -f "$PREFIX/$rel" ] && agent_has_model "$PREFIX/$rel"; then\n',
                          b'    if false; then\n'),
    ('ps1', 'model-key'): (b'    if ($Verify -and (Test-Path -LiteralPath $dest -PathType Leaf) -and (Test-AgentHasModelKey $dest)) {\n',
                           b'    if ($false) {\n'),
}[engine, variant]
target = pathlib.Path(path)
source = target.read_bytes()
assert source.count(old) == 1, 'check/verify mutation target missing or ambiguous'
mutant = source.replace(old, new, 1)
assert mutant != source and old not in mutant, 'check/verify mutation not applied'
target.write_bytes(mutant)
PY
      ); then
        bad "T63 $engine $t63_variant mutation replay" "$t63_mut"
        continue
      fi
      case_err=""
      t63_run "$engine" "$p" 1 "$t63_variant" "$t63_fixture" "$t63_mode"
      t63_detail=""
      if [ "$case_err" = " $t63_variant:exit=0(want-1) $t63_variant:output-differs" ]; then
        ok "T63 $engine $t63_variant mutation applied and rejected:$case_err"
      else
        bad "T63 $engine $t63_variant mutation replay" \
          "expected ' $t63_variant:exit=0(want-1) $t63_variant:output-differs', got '${case_err:-<no rejection>}'"
      fi
    done
  done
  t63_record=1
fi

# ---------------------------------------------------------------- T54
case_err=""
sed -n '/^## Updating$/,/^## Credits$/p' README.md | grep -qF 'feature-crew.sha256' || case_err="$case_err update-paragraph-does-not-name-manifest"
count=$(wc -l < README.md | tr -d ' ')
[ "$count" -eq 94 ] || case_err="$case_err README-lines=$count(want-94)"
installer_result "T54 README explains the install manifest without gaining lines"

# ---------------------------------------------------------------- T58
# Parse the workflow graph: a Linux-only suite in release.yml cannot substantiate
# Windows validation. The release must need the reusable full test workflow and
# build its validation list from the jobs of this run, not static claims.
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import yaml' >/dev/null 2>&1; then
  skip "T58 release workflow gate (PyYAML unavailable)"
else
  if t58_out=$(python3 - <<'PY'
import pathlib, sys, yaml

test = yaml.safe_load(pathlib.Path('.github/workflows/test.yml').read_text())
release_text = pathlib.Path('.github/workflows/release.yml').read_text()
release = yaml.safe_load(release_text)
errors = []
def require(condition, message):
    if not condition:
        errors.append(message)

# PyYAML's YAML 1.1 resolver may interpret the key `on` as boolean True.
triggers = test.get('on', test.get(True, {}))
require(isinstance(triggers, dict) and {'workflow_call', 'push', 'pull_request'} <= set(triggers),
        'test-missing-reusable-or-existing-trigger')
require(release.get('permissions') == {'contents': 'read'}, 'release-default-permissions-not-read-only')
jobs = release.get('jobs', {})
reusable = {name for name, job in jobs.items() if job.get('uses') == './.github/workflows/test.yml'}
require(bool(reusable), 'release-does-not-call-test-workflow')
publish = jobs.get('release', {})
require(publish.get('name') == 'release', 'publishing-job-must-be-named-release')
needs = publish.get('needs', [])
if isinstance(needs, str):
    needs = [needs]
require(bool(reusable.intersection(needs)), 'release-does-not-need-full-tests')
require(publish.get('permissions') == {'contents': 'write', 'actions': 'read'},
        'publishing-permissions-must-be-contents-write-actions-read')
steps = [step for job in jobs.values() for step in job.get('steps', [])]
scripts = '\n'.join(str(step.get('run', '')) for step in steps)
require('tests/framework_test.sh' not in scripts, 'release-runs-its-own-suite')
require(not any('pyyaml' in str(step).lower() for step in steps), 'release-installs-its-own-PyYAML')
require('executed on Windows' not in release_text, 'release-claims-static-Windows-validation')
require(any('gh api' in str(step.get('run', '')) and
            'actions/runs/$GITHUB_RUN_ID/jobs' in str(step.get('run', '')) and
            step.get('env', {}).get('GH_TOKEN') == '${{ github.token }}' for step in steps),
        'release-missing-authenticated-current-run-jobs-query')
require('git fetch origin main' in scripts and
        'git merge-base --is-ancestor "$GITHUB_SHA" origin/main' in scripts,
        'release-missing-tag-on-main-gate')
require('release-notes.md' in scripts and
        all(heading in scripts for heading in ('## feature-crew ', '### Commits', '### Contents', '### Validation', '### Install')),
        'release-missing-generated-body-structure')
require(any('gh release create' in str(step.get('run', '')) and
            '--verify-tag' in str(step.get('run', '')) and
            '--notes-file release-notes.md' in str(step.get('run', '')) for step in steps),
        'release-missing-verified-tag-publication')
print(' '.join(errors))
sys.exit(bool(errors))
PY
  ); then
    ok "T58 release needs the full reusable test workflow and reports this run's validation"
  else
    bad "T58 release workflow gate" "issues:$t58_out"
  fi
fi

# ---------------------------------------------------------------- T59
# T44/T45 compare dry-run output over untouched installs. They do not prove a
# forced dry run preserves edits. Snapshot every path and byte, including any
# manifest, and use the same behavioral guard on originals and four mutants.
t59_dry_force() { # engine, fixture root, installer to exercise in the dry run
  local engine="$1" fixture="$2" script="$3"
  local prefix="$fixture/prefix"
  case_err=""
  mkdir -p "$fixture" || { case_err="fixture-directory-failed"; return; }
  run_installer "$engine" "$prefix"
  expect_installer_success install
  [ -f "$prefix/agents/fc-pm.md" ] || case_err="$case_err missing-agent"
  [ -f "$prefix/skills/fc-review/SKILL.md" ] || case_err="$case_err missing-skill"
  [ -z "$case_err" ] || return
  printf '\nMY AGENT EDIT\n' >> "$prefix/agents/fc-pm.md" || case_err="$case_err agent-edit-failed"
  printf '\nMY SKILL EDIT\n' >> "$prefix/skills/fc-review/SKILL.md" || case_err="$case_err skill-edit-failed"
  cp "$prefix/agents/fc-pm.md" "$fixture/agent" || case_err="$case_err agent-snapshot-failed"
  cp "$prefix/skills/fc-review/SKILL.md" "$fixture/skill" || case_err="$case_err skill-snapshot-failed"
  snapshot_tree "$prefix" > "$fixture/before" || case_err="$case_err before-snapshot-failed"
  [ -z "$case_err" ] || return
  if [ "$engine" = sh ]; then
    HOME="$installer_root/home" "$installer_bash" "$script" --prefix "$prefix" --dry-run --force \
      > "$installer_root/run.out" 2>&1
  else
    env -i HOME="$installer_root/home" PATH="$installer_root/empty-path" \
      POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off \
      "$PWSH_BIN" -NonInteractive -File "$script" --prefix "$prefix" --dry-run --force \
      > "$installer_root/run.out" 2>&1
  fi
  installer_rc=$?
  installer_out=$(cat "$installer_root/run.out")
  expect_installer_success dry-run
  cmp -s "$fixture/agent" "$prefix/agents/fc-pm.md" || case_err="$case_err dry-run:agent-changed"
  cmp -s "$fixture/skill" "$prefix/skills/fc-review/SKILL.md" || case_err="$case_err dry-run:skill-changed"
  snapshot_tree "$prefix" > "$fixture/after" || case_err="$case_err after-snapshot-failed"
  cmp -s "$fixture/before" "$fixture/after" || case_err="$case_err dry-run:tree-changed"
}
for engine in "${INSTALLERS[@]}"; do
  for variant in control agent-return skill-copy; do
    t59_script="$installer_repo/install.$engine"
    if [ "$variant" != control ]; then
      if ! command -v python3 >/dev/null 2>&1; then
        skip "T59 $engine $variant mutation replay (python3 unavailable)"
        continue
      fi
      # Like T21, root-local copies find the real sources. Register before
      # writing so failures cannot leave a mutant in the working tree.
      t59_script="$installer_repo/t59-$engine-$variant-$$.$engine"
      CLEANUP_PATHS+=("$t59_script")
      if ! t59_mutation_out=$(python3 - "$engine" "$variant" "$t59_script" 2>&1 <<'PY'
import pathlib, sys
engine, variant, output = sys.argv[1:]
old, new = {
    ('sh', 'agent-return'): (
        b'    say "DRY-RUN: install $src -> $dest  (name: $name)"\n    return 0\n',
        b'    say "DRY-RUN: install $src -> $dest  (name: $name)"\n'),
    ('ps1', 'agent-return'): (
        b'    Write-Host "DRY-RUN: install $src -> $dest  (name: $name)"; return\n',
        b'    Write-Host "DRY-RUN: install $src -> $dest  (name: $name)"\n'),
    ('sh', 'skill-copy'): (b'    do_or_echo cp "$s" "$d"\n', b'    cp "$s" "$d"\n'),
    ('ps1', 'skill-copy'): (
        b'    if ($DryRun) {\n      Write-Host "DRY-RUN: cp $($_.FullName) $d"\n',
        b'    if ($false) {\n      Write-Host "DRY-RUN: cp $($_.FullName) $d"\n'),
}[engine, variant]
source = pathlib.Path('install.' + engine).read_bytes()
assert source.count(old) == 1, 'dry-run mutation target missing or ambiguous'
mutant = source.replace(old, new, 1)
assert mutant != source and old not in mutant, 'dry-run mutation not applied'
pathlib.Path(output).write_bytes(mutant)
PY
      ); then
        bad "T59 $engine $variant mutation replay" "$t59_mutation_out"
        continue
      fi
    fi
    t59_dry_force "$engine" "$installer_root/t59-$engine-$variant" "$t59_script"
    if [ "$variant" = control ]; then
      installer_result "T59 $engine --dry-run --force preserves edited agent, skill, and the whole install"
    else
      case "$variant" in
        agent-return) t59_expected=' dry-run:agent-changed dry-run:tree-changed' ;;
        skill-copy) t59_expected=' dry-run:skill-changed dry-run:tree-changed' ;;
      esac
      if [ "$case_err" = "$t59_expected" ]; then
        ok "T59 $engine $variant mutation applied and rejected:$case_err"
      else
        bad "T59 $engine $variant mutation replay" "expected '$t59_expected', got '${case_err:-<no rejection>}'"
      fi
      rm -f "$t59_script"
    fi
  done
done
if [ "${#INSTALLERS[@]}" -eq 1 ]; then
  for variant in control agent-return skill-copy; do
    skip "T59 ps1 $variant dry-run guard (pwsh unavailable; set PWSH)"
  done
fi

# ---------------------------------------------------------------- T60
# U3 checks ownership per installed skill file, not by file count. An unknown
# file or an edit to a shipped file must protect the whole skill. Replace only
# that predicate in a root-local copy, then require actual deletion to prove
# this same guard rejects the bypass; a setup failure or nonzero exit is not RED.
t60_skill_ownership() { # engine, fixture root, scenario, uninstall script
  local engine="$1" fixture="$2" scenario="$3" script="$4"
  local prefix="$fixture/prefix" skill personal
  case_err=""
  mkdir -p "$fixture" || { case_err="fixture-directory-failed"; return; }
  run_installer "$engine" "$prefix"
  expect_installer_success install
  skill="$prefix/skills/fc-build-or-fix"
  [ -f "$skill/SKILL.md" ] || case_err="$case_err missing-skill"
  [ -z "$case_err" ] || return
  if [ "$scenario" = extra-file ]; then
    personal="$skill/personal-notes.txt"
    [ ! -e "$personal" ] || { case_err="personal-file-already-shipped"; return; }
    cp "$installer_root/personal" "$personal" || case_err="$case_err personal-file-fixture-failed"
  else
    personal="$skill/SKILL.md"
    printf '\nMY SKILL EDIT\n' >> "$personal" || case_err="$case_err edited-file-fixture-failed"
  fi
  cp "$personal" "$fixture/personal" || case_err="$case_err personal-snapshot-failed"
  snapshot_tree "$skill" > "$fixture/before" || case_err="$case_err before-snapshot-failed"
  [ -z "$case_err" ] || return
  if [ "$engine" = sh ]; then
    HOME="$installer_root/home" "$installer_bash" "$script" --prefix "$prefix" --uninstall \
      > "$installer_root/run.out" 2>&1
  else
    env -i HOME="$installer_root/home" PATH="$installer_root/empty-path" \
      POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off \
      "$PWSH_BIN" -NonInteractive -File "$script" --prefix "$prefix" --uninstall \
      > "$installer_root/run.out" 2>&1
  fi
  installer_rc=$?
  installer_out=$(cat "$installer_root/run.out")
  expect_installer_success uninstall
  if [ ! -f "$personal" ]; then
    case_err="$case_err uninstall:personal-file-deleted"
  elif ! cmp -s "$fixture/personal" "$personal"; then
    case_err="$case_err uninstall:personal-bytes-changed"
  fi
  if [ ! -d "$skill" ]; then
    case_err="$case_err uninstall:skill-deleted"
  else
    snapshot_tree "$skill" > "$fixture/after" || case_err="$case_err after-snapshot-failed"
    cmp -s "$fixture/before" "$fixture/after" || case_err="$case_err uninstall:skill-tree-changed"
  fi
}
for engine in "${INSTALLERS[@]}"; do
  for variant in control ownership-bypass; do
    t60_script="$installer_repo/install.$engine"
    if [ "$variant" = ownership-bypass ]; then
      if ! command -v python3 >/dev/null 2>&1; then
        for scenario in extra-file edited-shipped-file; do
          skip "T60 $engine $scenario ownership-bypass replay (python3 unavailable)"
        done
        continue
      fi
      t60_script="$installer_repo/t60-$engine-ownership-bypass-$$.$engine"
      CLEANUP_PATHS+=("$t60_script")
      if ! t60_mutation_out=$(python3 - "$engine" "$t60_script" 2>&1 <<'PY'
import pathlib, re, sys
engine, output = sys.argv[1:]
pattern, body = {
    'sh': (rb'^skill_file_is_ours\(\) \{\n(.*?)^\}', b'  return 0\n'),
    'ps1': (rb'^function Test-SkillFileIsOurs\(\$src, \$dest, \$relativePath\) \{\n(.*?)^\}',
            b'  return $true\n'),
}[engine]
source = pathlib.Path('install.' + engine).read_bytes()
matches = list(re.finditer(pattern, source, re.M | re.S))
assert len(matches) == 1, 'skill ownership predicate missing or ambiguous'
match = matches[0]
assert match.group(1) != body, 'skill ownership predicate already bypassed'
mutant = source[:match.start(1)] + body + source[match.end(1):]
assert mutant != source and list(re.finditer(pattern, mutant, re.M | re.S))[0].group(1) == body, 'ownership mutation not applied'
pathlib.Path(output).write_bytes(mutant)
PY
      ); then
        bad "T60 $engine ownership-bypass replay" "$t60_mutation_out"
        continue
      fi
    fi
    for scenario in extra-file edited-shipped-file; do
      t60_skill_ownership "$engine" "$installer_root/t60-$engine-$variant-$scenario" "$scenario" "$t60_script"
      if [ "$variant" = control ]; then
        installer_result "T60 $engine $scenario preserves personal bytes and the whole skill"
      elif [ "$case_err" = ' uninstall:personal-file-deleted uninstall:skill-deleted' ]; then
        ok "T60 $engine $scenario ownership-bypass applied and rejected:$case_err"
      else
        bad "T60 $engine $scenario ownership-bypass replay" "expected personal-file and skill deletion, got '${case_err:-<no rejection>}'"
      fi
    done
    [ "$variant" = control ] || rm -f "$t60_script"
  done
done
if [ "${#INSTALLERS[@]}" -eq 1 ]; then
  for variant in control ownership-bypass; do
    for scenario in extra-file edited-shipped-file; do
      skip "T60 ps1 $scenario $variant (pwsh unavailable; set PWSH)"
    done
  done
fi

# ---------------------------------------------------------------- T64
# fc-ship (#39) finishes a PR with no polling loop: the main agent watches CI
# in the background, reads real states when the watch exits, and merges only a
# head that contains the base tip. T9 and T13 are replayed on scratch copies so
# fc-ship cannot slip past either. As in T55, every section-scoped literal has
# a removal mutation that must trip exactly its own label. The behavior half
# runs the documented commands against a gh stand-in with gh 2.101.0's
# observable contract (a CANCELLED check exits 0, --fail-fast stops at the first
# failure, no checks is an error) and a scratch origin, so dropping a flag or
# the eligibility check fails here.
t64_root=$(mktemp -d)
CLEANUP_PATHS+=("$t64_root")
mkdir -p "$t64_root/bin" "$t64_root/home"
t64_ship=.claude/skills/fc-ship/SKILL.md

# T9 replay: an untouched scratch copy passes; removing either clause from the
# fc-ship description is reported for fc-ship alone. A no-op mutation is a
# setup failure, not a rejection.
case_err=""
mkdir -p "$t64_root/skills" && cp -R .claude/skills/. "$t64_root/skills/"
t64_got=$(t9_contract "$t64_root/skills")
[ -z "$t64_got" ] || case_err="$case_err control:$t64_got"
t64_edits=('/^description:/s/ Use when [^.]*\.//' '/^description:/s/ Do NOT use for.*$//')
t64_wants=(' fc-ship:no-use-when' ' fc-ship:no-anti-trigger')
for t64_i in 0 1; do
  if [ ! -f "$t64_ship" ] || ! sed "${t64_edits[$t64_i]}" "$t64_ship" > "$t64_root/skills/fc-ship/SKILL.md" \
     || cmp -s "$t64_ship" "$t64_root/skills/fc-ship/SKILL.md"; then
    case_err="$case_err mutation-$t64_i-not-applied"; continue
  fi
  t64_got=$(t9_contract "$t64_root/skills")
  [ "$t64_got" = "${t64_wants[$t64_i]}" ] || case_err="$case_err mutation-$t64_i:got'$t64_got'"
done
installer_result "T64 T9 rejects fc-ship scratch copies missing Use when or Do NOT use for"

# T13 replay: a fresh scratch install passes; the same prefix without the
# installed fc-ship SKILL.md is reported for fc-ship alone.
case_err=""
t64_prefix="$t64_root/prefix"
if bash install.sh --prefix "$t64_prefix" --force >/dev/null 2>&1; then
  t64_got=$(t13_contract "$t64_prefix")
  [ -z "$t64_got" ] || case_err="$case_err control-missing:$t64_got"
  if [ -f "$t64_prefix/skills/fc-ship/SKILL.md" ]; then
    rm "$t64_prefix/skills/fc-ship/SKILL.md"
    t64_got=$(t13_contract "$t64_prefix")
    [ "$t64_got" = ' fc-ship' ] || case_err="$case_err omission:got'$t64_got'"
  else
    case_err="$case_err fc-ship-not-installed"
  fi
else
  case_err="$case_err install.sh-failed"
fi
installer_result "T64 T13 rejects an install without fc-ship's SKILL.md"

# Static contract: each approved clause, scoped to its own section.
t64_words=(zero one two three four five six seven eight nine ten eleven twelve)
t64_count_word=${t64_words[${#SKILL_NAMES[@]}]:-${#SKILL_NAMES[@]}}
t64_labels=(
  auth-separate auth-one-question
  watch-record-head watch-main-agent-background watch-required-fallback
  outcome-read-real-states outcome-read-commands outcome-report-each outcome-rearm-once outcome-no-loops
  failure-log-evidence failure-callback-route failure-resume-new-head
  merge-reverify merge-base-tip merge-push-feature-only merge-rebase-rerun merge-conflict-rereview merge-pinned-squash
  merge-confirm-tree merge-mismatch-stops
  release-only-approved release-tag-last-watch
  cleanup-mandatory cleanup-check-state cleanup-remove-only-merged cleanup-prune-temp
  cleanup-keep-uncertain cleanup-return-report
  build-or-fix-hands-off readme-direct-command readme-skill-count banner-sh banner-ps1
)
t64_sections=(auth auth watch watch watch outcome outcome outcome outcome outcome
  failure failure failure merge merge merge merge merge merge merge merge release release
  cleanup cleanup cleanup cleanup cleanup cleanup standard commands layout sh ps1)
t64_rules=(
  'Commit, push, PR, merge, tag/publish, and cleanup are separate authorizations; none implies another.'
  'Ask for every missing approval in one question up front, then do only what is approved.'
  'After each push, record the head SHA.'
  'The main agent itself — never a subagent, because a background task notifies whoever started it — starts one background watch on the recorded head, `gh pr checks <pr> --watch --fail-fast --required --interval 30`, and keeps working meanwhile.'
  'When gh reports no required checks, watch all checks instead: drop `--required` here and when reading states.'
  'When the watch exits, read the actual check states and the PR head; the exit code cannot tell success from cancellation, and the watch follows the latest PR commit.'
  'Run `gh pr checks <pr> --required --json name,state,bucket,link` and `gh pr view <pr> --json headRefOid,state,mergeCommit`.'
  'Report each outcome: failure (immediately, via `--fail-fast`), success, cancelled, action-required, timed out, no checks, API error, head changed, PR closed or merged.'
  'A watcher error or time limit re-arms once, then reports.'
  'No loops.'
  'Fetch `gh run view <id> --log-failed`, taking the run id from the failed check link.'
  'Return head, run, and log evidence to the calling flow, which routes it to `/fc-debug` and fixes under its own gates; invoked directly, fc-ship routes it itself.'
  'Shipping resumes only on a new, verified head.'
  'Right before the irreversible step, re-verify head, gates, and approval.'
  'Run `git fetch origin <base>` and require the PR head to contain the current base tip: `git merge-base --is-ancestor origin/<base> <head>`.'
  'If the base advanced: rebase and push only the feature branch with `git push --force-with-lease=<branch>:<old-head> origin <branch>` (fc-ship never pushes the base)'
  'rerun the full suite and CI on the new head, and compare with `git range-diff origin/<base> <old-head> <head>`.'
  'Parts changed by conflict resolution get a cross-family re-review (selector in `/fc-build-or-fix`).'
  'Then run `gh pr merge <pr> --squash --match-head-commit <sha>` with no bypass (`--admin`, `--auto`) and no `--delete-branch`.'
  'Confirm the merge through PR metadata (`state` is `MERGED`), fetch the base, and verify the merged tree equals the head tree: `git diff --quiet <head> <merge-commit>`.'
  'If it still differs: stop, report, and run only safe cleanup.'
  'Release only when approved:'
  'tag the verified base commit, push the tag last, watch the release run in the background (`gh run watch <id> --exit-status`), and verify the published body.'
  'Cleanup is mandatory when shipping ends.'
  'Check status, worktrees, sessions, and locks.'
  'Remove only clean, inactive worktrees and branches still at the merged PR head; after a squash merge `git branch -d` refuses, so use `-D` only once the PR is confirmed merged and the trees match.'
  'Prune stale refs and remove task-owned temp files and processes.'
  'Keep dirty or unmerged work, stashes, and anything uncertain.'
  'Return to the updated base and report the final status and anything kept.'
  '9. Commit only when authorized; use a feature branch, then continue with `/fc-ship`.'
  '`/fc-ship`'
  "# ${t64_count_word} skills"
  '/fc-ship'
  '/fc-ship'
)
t64_contract() { # fc-ship, build-or-fix, README, install.sh, install.ps1 text
  local auth watch outcome failure merge release clean standard commands layout sh ps1
  local i section="" errors=""
  auth=$(printf '%s\n' "$1" | sed -n '/^## 1 — Authorize/,/^## /p')
  watch=$(printf '%s\n' "$1" | sed -n '/^## 2 — Watch CI asynchronously/,/^## /p')
  outcome=$(printf '%s\n' "$1" | sed -n '/^## 3 — Read the outcome/,/^## /p')
  failure=$(printf '%s\n' "$1" | sed -n '/^## 4 — Failure/,/^## /p')
  merge=$(printf '%s\n' "$1" | sed -n '/^## 5 — Merge/,/^## /p')
  release=$(printf '%s\n' "$1" | sed -n '/^## 6 — Release/,/^## /p')
  clean=$(printf '%s\n' "$1" | sed -n '/^## 7 — Clean up/,/^## /p')
  standard=$(printf '%s\n' "$2" | sed -n '/^### Standard/,/^### /p')
  commands=$(printf '%s\n' "$3" | sed -n '/^## Describe the need/,/^## /p')
  layout=$(printf '%s\n' "$3" | sed -n '/^## Layout/,/^## /p')
  sh=$(printf '%s\n' "$4" | sed -n '/Available: \/fc-/,/delegate to an fc-/p')
  ps1=$(printf '%s\n' "$5" | sed -n '/Available: \/fc-/,/delegate to an fc-/p')
  for ((i=0; i<${#t64_rules[@]}; i++)); do
    case "${t64_sections[$i]}" in
      auth) section="$auth" ;;
      watch) section="$watch" ;;
      outcome) section="$outcome" ;;
      failure) section="$failure" ;;
      merge) section="$merge" ;;
      release) section="$release" ;;
      cleanup) section="$clean" ;;
      standard) section="$standard" ;;
      commands) section="$commands" ;;
      layout) section="$layout" ;;
      sh) section="$sh" ;;
      ps1) section="$ps1" ;;
    esac
    case "$section" in *"${t64_rules[$i]}"*) ;; *) errors="$errors ${t64_labels[$i]}" ;; esac
  done
  printf '%s\n' "$errors"
}
t64_ship_text=$(cat "$t64_ship" 2>/dev/null)
t64_build_text=$(cat .claude/skills/fc-build-or-fix/SKILL.md)
t64_readme_text=$(cat README.md)
t64_sh_text=$(cat install.sh)
t64_ps1_text=$(cat install.ps1)
t64_contract_out=$(t64_contract "$t64_ship_text" "$t64_build_text" "$t64_readme_text" "$t64_sh_text" "$t64_ps1_text")
if [ -z "$t64_contract_out" ]; then
  for ((t64_i=0; t64_i<${#t64_rules[@]}; t64_i++)); do
    t64_rule="${t64_rules[$t64_i]}"
    t64_m1="$t64_ship_text"; t64_m2="$t64_build_text"; t64_m3="$t64_readme_text"
    t64_m4="$t64_sh_text"; t64_m5="$t64_ps1_text"
    case "${t64_sections[$t64_i]}" in
      standard) t64_m2="${t64_m2/"$t64_rule"/}" ;;
      commands|layout) t64_m3="${t64_m3/"$t64_rule"/}" ;;
      sh) t64_m4="${t64_m4/"$t64_rule"/}" ;;
      ps1) t64_m5="${t64_m5/"$t64_rule"/}" ;;
      *) t64_m1="${t64_m1/"$t64_rule"/}" ;;
    esac
    t64_mut_out=$(t64_contract "$t64_m1" "$t64_m2" "$t64_m3" "$t64_m4" "$t64_m5")
    if [ "$t64_mut_out" = " ${t64_labels[$t64_i]}" ]; then
      ok "T64 removal mutation: ${t64_labels[$t64_i]} rejected by its own check"
    else
      bad "T64 removal mutation: ${t64_labels[$t64_i]}" \
        "got '${t64_mut_out:-<empty>}', want ' ${t64_labels[$t64_i]}'"
    fi
  done
fi
[ -z "$t64_contract_out" ] && ok "T64 static contract alarm: fc-ship async CI callback, verified merge, gated release, mandatory cleanup" \
                           || bad "T64 fc-ship section contract" "missing:$t64_contract_out"

# Behavior: a gh stand-in that keeps gh 2.101.0's observable contract.
cat > "$t64_root/bin/gh" <<'STUB'
#!/usr/bin/env bash
# gh stand-in for T64; scenario files live in $T64_CASE. A checks row is
# name|required|state,state,...|link: the comma list is the poll sequence and
# its last state repeats. A watch advances polls until nothing is pending, or
# until a failure under --fail-fast; a later read sees that same poll.
set -u
c="${T64_CASE:?}"
die() { printf '%s\n' "$1" >&2; exit "${2:-1}"; }
sorted() { printf '%s\n' "${1//,/ }" | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' '; }
pr_head() { git --git-dir="$c/origin.git" rev-parse refs/heads/feature; }
snapshot() { # required-only (0/1), poll index
  local name req states link state bucket list idx
  rows=(); kept=0; failed=0; pending=0; total=0
  while IFS='|' read -r name req states link; do
    [ -n "$name" ] || continue
    total=$((total + 1))
    if [ "$1" = 1 ] && [ "$req" != yes ]; then continue; fi
    IFS=',' read -r -a list <<< "$states"
    idx=$2; [ "$idx" -lt "${#list[@]}" ] || idx=$((${#list[@]} - 1))
    state=${list[$idx]}
    case "$state" in
      SUCCESS) bucket=pass ;;
      SKIPPED|NEUTRAL) bucket=skipping ;;
      ERROR|FAILURE|TIMED_OUT|ACTION_REQUIRED) bucket=fail; failed=$((failed + 1)) ;;
      CANCELLED) bucket=cancel ;;
      *) bucket=pending; pending=$((pending + 1)) ;;
    esac
    rows[$kept]="$name|$state|$bucket|$link"; kept=$((kept + 1))
  done < "$c/checks"
  [ "$total" -gt 0 ] || die "no checks reported on the 'feature' branch"
  [ "$kept" -gt 0 ] || die "no required checks reported on the 'feature' branch"
}
checks() {
  local pr="" watch=0 failfast=0 required=0 interval="" json="" poll f v obj out="" i
  local name state bucket link
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --watch) watch=1 ;;
      --fail-fast) failfast=1 ;;
      --required) required=1 ;;
      --interval|-i) interval="${2-}"; shift ;;
      --json) json="${2-}"; shift ;;
      -*) die "unknown flag: $1" ;;
      *) pr="$1" ;;
    esac
    shift
  done
  [ "$pr" = 7 ] || die "no pull requests found for branch \"$pr\""
  if [ -n "$json" ] && [ "$watch" = 1 ]; then die 'cannot use `--watch` with `--json` flag'; fi
  if [ "$failfast" = 1 ] && [ "$watch" = 0 ]; then die 'cannot use `--fail-fast` flag without `--watch` flag'; fi
  if [ -n "$interval" ] && [ "$watch" = 0 ]; then die 'cannot use `--interval` flag without `--watch` flag'; fi
  case "$interval" in *[!0-9]*) die "invalid argument \"$interval\" for \"-i, --interval\" flag" ;; esac
  for f in ${json//,/ }; do
    case "$f" in bucket|link|name|state) ;; *) die "Unknown JSON field: \"$f\"" ;; esac
  done
  if [ "$watch" = 1 ] && [ -s "$c/watch-errors" ] && [ "$(cat "$c/watch-errors")" -gt 0 ]; then
    echo $(( $(cat "$c/watch-errors") - 1 )) > "$c/watch-errors"
    die 'HTTP 502: Bad Gateway (https://api.github.com/graphql)'
  fi
  poll=$(cat "$c/poll")
  snapshot "$required" "$poll"
  while [ "$watch" = 1 ] && [ "$pending" -gt 0 ]; do
    if [ "$failfast" = 1 ] && [ "$failed" -gt 0 ]; then break; fi
    poll=$((poll + 1))
    [ "$poll" -le 20 ] || die 'stand-in: checks never settled' 124
    snapshot "$required" "$poll"
  done
  echo "$poll" > "$c/poll"
  for ((i=0; i<kept; i++)); do
    IFS='|' read -r name state bucket link <<< "${rows[$i]}"
    if [ -z "$json" ]; then printf '%s\t%s\t%s\n' "$name" "$bucket" "$link"; continue; fi
    obj=""
    for f in $(sorted "$json"); do
      case "$f" in bucket) v=$bucket ;; link) v=$link ;; name) v=$name ;; state) v=$state ;; esac
      obj="$obj${obj:+,}\"$f\":\"$v\""
    done
    out="$out${out:+,}{$obj}"
  done
  if [ -n "$json" ]; then printf '[%s]\n' "$out"; exit 0; fi
  if [ "$failed" -gt 0 ]; then exit 1; fi
  if [ "$pending" -gt 0 ]; then exit 8; fi
  exit 0
}
view() {
  local pr="" json="" f out="" merged=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) json="${2-}"; shift ;;
      -*) die "unknown flag: $1" ;;
      *) pr="$1" ;;
    esac
    shift
  done
  [ "$pr" = 7 ] || die "no pull requests found for branch \"$pr\""
  [ -n "$json" ] || die 'stand-in: only --json output is modeled'
  [ -f "$c/merge-oid" ] && merged=$(cat "$c/merge-oid")
  for f in $(sorted "$json"); do
    case "$f" in
      headRefOid) out="$out${out:+,}\"headRefOid\":\"$(pr_head)\"" ;;
      state) out="$out${out:+,}\"state\":\"$(cat "$c/pr-state")\"" ;;
      mergeCommit)
        if [ -n "$merged" ]; then out="$out${out:+,}\"mergeCommit\":{\"oid\":\"$merged\"}"
        else out="$out${out:+,}\"mergeCommit\":null"; fi ;;
      *) die "Unknown JSON field: \"$f\"" ;;
    esac
  done
  printf '{%s}\n' "$out"
}
merge() {
  local pr="" squash=0 match="" base tree commit out
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --squash|-s) squash=1 ;;
      --match-head-commit) match="${2-}"; shift ;;
      --admin|--auto|--delete-branch|-d) printf '%s\n' "$1" >> "$c/bypass" ;;
      -*) die "unknown flag: $1" ;;
      *) pr="$1" ;;
    esac
    shift
  done
  [ "$pr" = 7 ] || die "no pull requests found for branch \"$pr\""
  [ "$squash" = 1 ] || die '--merge, --rebase, or --squash required when not running interactively'
  [ "$(cat "$c/pr-state")" = OPEN ] || die 'Pull request #7 is not open'
  if [ -n "$match" ] && [ "$match" != "$(pr_head)" ]; then
    die 'GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)'
  fi
  base=$(git --git-dir="$c/origin.git" rev-parse refs/heads/main) || die 'stand-in: no base'
  out=$(git --git-dir="$c/origin.git" merge-tree --write-tree "$base" "$(pr_head)") \
    || die 'Pull request #7 is not mergeable: the merge commit cannot be cleanly created.'
  read -r tree <<< "$out"
  commit=$(git --git-dir="$c/origin.git" commit-tree "$tree" -p "$base" -m 'feature (#7)') \
    || die 'stand-in: commit failed'
  git --git-dir="$c/origin.git" update-ref refs/heads/main "$commit" "$base" || die 'stand-in: update-ref failed'
  echo MERGED > "$c/pr-state"
  echo "$commit" > "$c/merge-oid"
  printf 'Squashed and merged pull request #7\n'
}
run_view() {
  local id="" logfailed=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --log-failed) logfailed=1 ;;
      -*) die "unknown flag: $1" ;;
      *) id="$1" ;;
    esac
    shift
  done
  [ "$logfailed" = 1 ] || die 'stand-in: only --log-failed is modeled'
  [ -f "$c/run-$id.log" ] || die 'failed to get run: HTTP 404: Not Found'
  cat "$c/run-$id.log"
}
case "${1-} ${2-}" in
  'pr checks') shift 2; checks "$@" ;;
  'pr view') shift 2; view "$@" ;;
  'pr merge') shift 2; merge "$@" ;;
  'run view') shift 2; run_view "$@" ;;
  *) die "stand-in: unsupported gh ${*}" ;;
esac
STUB
chmod +x "$t64_root/bin/gh"
# Scratch git ignores the caller's config, hooks, and repository variables.
t64_env=(-u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY
  -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u XDG_CONFIG_HOME
  HOME="$t64_root/home" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
  GIT_AUTHOR_NAME=T64 GIT_AUTHOR_EMAIL=t64@example.invalid
  GIT_COMMITTER_NAME=T64 GIT_COMMITTER_EMAIL=t64@example.invalid)
t64_git() { env "${t64_env[@]}" git "$@" 2>> "$t64_case/setup.log"; }
t64_fill() { # command template -> this scenario's values
  local c="$1"
  c=${c//'<pr>'/7}; c=${c//'<base>'/main}; c=${c//'<old-head>'/$t64_old}
  c=${c//'<head>'/$t64_head}; c=${c//'<sha>'/$t64_sha}
  c=${c//'<merge-commit>'/$t64_mergeoid}; c=${c//'<id>'/$t64_id}; c=${c//'<branch>'/feature}
  printf '%s\n' "$c"
}
t64_run() { # command template; run in the work clone with the stand-in first on PATH
  local cmd words
  cmd=$(t64_fill "$1")
  set -f; words=($cmd); set +f
  ( cd "$t64_case/work" \
    && env "${t64_env[@]}" T64_CASE="$t64_case" PATH="$t64_root/bin:$PATH" "${words[@]}" ) \
    > "$t64_case/out" 2> "$t64_case/err"
  t64_rc=$?
  t64_stdout=$(cat "$t64_case/out"); t64_stderr=$(cat "$t64_case/err")
}
t64_setup() { # scenario name, checks table; origin has main plus PR #7 on feature
  t64_case="$t64_root/$1"; case_err=""
  mkdir -p "$t64_case"
  printf '%s\n' "$2" > "$t64_case/checks"
  echo OPEN > "$t64_case/pr-state"; echo 0 > "$t64_case/poll"
  t64_git init -q --bare -b main "$t64_case/origin.git" \
    && t64_git init -q -b main "$t64_case/work" \
    && printf 'base\n' > "$t64_case/work/base.txt" \
    && t64_git -C "$t64_case/work" add base.txt \
    && t64_git -C "$t64_case/work" commit -q -m base \
    && t64_git -C "$t64_case/work" remote add origin "$t64_case/origin.git" \
    && t64_git -C "$t64_case/work" push -q origin main \
    && t64_git -C "$t64_case/work" switch -q -c feature \
    && printf 'feature\n' > "$t64_case/work/feature.txt" \
    && t64_git -C "$t64_case/work" add feature.txt \
    && t64_git -C "$t64_case/work" commit -q -m feature \
    && t64_git -C "$t64_case/work" push -q origin feature \
    || { case_err="setup-failed:$(tail -n 1 "$t64_case/setup.log" 2>/dev/null)"; return 1; }
  t64_sha=$(t64_git -C "$t64_case/work" rev-parse HEAD)
  t64_head=$t64_sha; t64_old=$t64_sha; t64_mergeoid=""; t64_id=""
}
t64_expect() { # step label, wanted exit code
  [ "$t64_rc" = "$2" ] || case_err="$case_err $1:exit-$t64_rc(want-$2)"
}
t64_bucket() { # check name -> bucket in the last JSON read
  printf '%s\n' "$t64_stdout" | grep -o '{[^}]*}' | grep -F "\"name\":\"$1\"" \
    | sed -n 's/.*"bucket":"\([^"]*\)".*/\1/p'
}
t64_field() { # key -> string value in the last JSON view
  printf '%s\n' "$t64_stdout" | sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p"
}
t64_span() { # command prefix, required fragment -> first documented span
  grep -o '`[^`]*`' "$t64_ship" 2>/dev/null | tr -d '`' \
    | awk -v p="$1" -v s="$2" 'index($0, p) == 1 && index($0, s) { print; exit }'
}
t64_cmd_watch=$(t64_span 'gh pr checks <pr> ' '--watch')
t64_cmd_read=$(t64_span 'gh pr checks <pr> ' '--json')
t64_cmd_view=$(t64_span 'gh pr view <pr> ' '--json')
t64_cmd_log=$(t64_span 'gh run view ' '--log-failed')
t64_cmd_fetch=$(t64_span 'git fetch ' 'origin')
t64_cmd_eligible=$(t64_span 'git merge-base ' '--is-ancestor')
t64_cmd_rangediff=$(t64_span 'git range-diff ' 'origin/')
t64_cmd_merge=$(t64_span 'gh pr merge <pr> ' '--match-head-commit')
t64_cmd_tree=$(t64_span 'git diff ' '--quiet')
t64_cmd_push=$(t64_span 'git push ' '--force-with-lease=')
t64_cmd_watch_all=${t64_cmd_watch/ --required/}
t64_cmd_read_all=${t64_cmd_read/ --required/}
t64_missing=""
for t64_v in watch read view log fetch eligible push rangediff merge tree; do
  t64_n="t64_cmd_$t64_v"
  [ -n "${!t64_n}" ] || t64_missing="$t64_missing $t64_v"
done
if [ -n "$t64_missing" ]; then
  bad "T64 behavior: documented fc-ship commands" "undocumented:$t64_missing"
else
  # Failure: --fail-fast returns at the first failed check while another is
  # still pending; the run id in its link fetches the failed log as evidence.
  if t64_setup failure $'build|yes|FAILURE|https://github.com/o/r/actions/runs/101/job/1\ntest|yes|IN_PROGRESS,SUCCESS|https://github.com/o/r/actions/runs/102/job/2'; then
    printf '%s\n' 'build  Run tests  ##[error] expected 3 checks, got 2' > "$t64_case/run-101.log"
    t64_run "$t64_cmd_watch"; t64_expect watch 1
    t64_run "$t64_cmd_read"; t64_expect read 0
    [ "$(t64_bucket build)" = fail ] || case_err="$case_err build-not-fail"
    [ "$(t64_bucket test)" = pending ] || case_err="$case_err watch-waited-past-first-failure"
    t64_id=$(printf '%s\n' "$t64_stdout" | grep -o '{[^}]*"bucket":"fail"[^}]*}' \
      | sed -n 's|.*/actions/runs/\([0-9]*\)/.*|\1|p')
    t64_run "$t64_cmd_view"; t64_expect view 0
    [ "$(t64_field headRefOid)" = "$t64_sha" ] || case_err="$case_err head-moved"
    t64_run "$t64_cmd_log"; t64_expect log 0
    case "$t64_stdout" in *'expected 3 checks, got 2'*) ;; *) case_err="$case_err no-failed-log-evidence" ;; esac
  fi
  installer_result "T64 behavior: failure exits fast with the failed run log as evidence"

  # Cancellation: gh exits 0 for a cancelled check, so only the read states
  # can report it.
  if t64_setup cancelled 'build|yes|IN_PROGRESS,CANCELLED|https://github.com/o/r/actions/runs/201/job/1'; then
    t64_run "$t64_cmd_watch"; t64_expect watch 0
    t64_run "$t64_cmd_read"; t64_expect read 0
    [ "$(t64_bucket build)" = cancel ] || case_err="$case_err cancel-not-read"
    t64_run "$t64_cmd_view"; t64_expect view 0
    [ "$(t64_field headRefOid)" = "$t64_sha" ] || case_err="$case_err head-moved"
  fi
  installer_result "T64 behavior: cancellation exits 0, so only the read states report it"

  # Success: --required keeps a failing optional check out of the watch and
  # the read, and the head is still the recorded one.
  if t64_setup success $'build|yes|IN_PROGRESS,SUCCESS|https://github.com/o/r/actions/runs/301/job/1\nlint|no|FAILURE|https://github.com/o/r/actions/runs/302/job/2'; then
    t64_run "$t64_cmd_watch"; t64_expect watch 0
    t64_run "$t64_cmd_read"; t64_expect read 0
    [ "$(t64_bucket build)" = pass ] || case_err="$case_err build-not-pass"
    [ -z "$(t64_bucket lint)" ] || case_err="$case_err optional-check-read"
    t64_run "$t64_cmd_view"; t64_expect view 0
    [ "$(t64_field headRefOid)" = "$t64_sha" ] || case_err="$case_err head-moved"
    [ "$(t64_field state)" = OPEN ] || case_err="$case_err pr-not-open"
  fi
  installer_result "T64 behavior: success on required checks at the recorded head"

  # No checks: with no required checks gh errors and the documented fallback
  # (drop --required) watches all checks; with none at all both report it.
  if t64_setup no-checks 'lint|no|SUCCESS|https://github.com/o/r/actions/runs/401/job/1'; then
    t64_run "$t64_cmd_watch"; t64_expect watch-required 1
    case "$t64_stderr" in *'no required checks reported'*) ;; *) case_err="$case_err no-required-not-reported" ;; esac
    t64_run "$t64_cmd_watch_all"; t64_expect watch-all 0
    t64_run "$t64_cmd_read_all"; t64_expect read-all 0
    [ "$(t64_bucket lint)" = pass ] || case_err="$case_err fallback-not-read"
    : > "$t64_case/checks"
    t64_run "$t64_cmd_watch_all"; t64_expect watch-none 1
    case "$t64_stderr" in *'no checks reported'*) ;; *) case_err="$case_err no-checks-not-reported" ;; esac
    t64_run "$t64_cmd_read_all"; t64_expect read-none 1
  fi
  installer_result "T64 behavior: no required checks falls back to all checks; none at all is reported"

  # Head changed: the watch follows the latest PR commit, so only the head
  # comparison notices, and --match-head-commit refuses the stale SHA.
  if t64_setup head-changed 'build|yes|SUCCESS|https://github.com/o/r/actions/runs/501/job/1'; then
    printf 'more\n' >> "$t64_case/work/feature.txt"
    t64_git -C "$t64_case/work" commit -q -am concurrent \
      && t64_git -C "$t64_case/work" push -q origin feature \
      || case_err="$case_err concurrent-push-failed"
    t64_run "$t64_cmd_watch"; t64_expect watch 0
    t64_run "$t64_cmd_view"; t64_expect view 0
    [ "$(t64_field headRefOid)" != "$t64_sha" ] || case_err="$case_err head-change-missed"
    t64_run "$t64_cmd_merge"; t64_expect merge 1
    case "$t64_stderr" in *'Head branch was modified'*) ;; *) case_err="$case_err stale-head-merge-not-refused" ;; esac
    t64_run "$t64_cmd_view"
    [ "$(t64_field state)" = OPEN ] || case_err="$case_err stale-head-merged"
  fi
  installer_result "T64 behavior: a moved head is detected and the pinned merge refuses it"

  # Watcher error: an API failure exits 1 like a CI failure, but the read
  # shows no verdict; one re-arm settles it.
  if t64_setup watcher-error 'build|yes|IN_PROGRESS,SUCCESS|https://github.com/o/r/actions/runs/601/job/1'; then
    echo 1 > "$t64_case/watch-errors"
    t64_run "$t64_cmd_watch"; t64_expect watch 1
    case "$t64_stderr" in *'HTTP 502'*) ;; *) case_err="$case_err watcher-error-hidden" ;; esac
    t64_run "$t64_cmd_read"; t64_expect read 0
    [ "$(t64_bucket build)" = pending ] || case_err="$case_err watcher-error-read-as-verdict"
    t64_run "$t64_cmd_watch"; t64_expect rearm 0
    t64_run "$t64_cmd_read"; t64_expect reread 0
    [ "$(t64_bucket build)" = pass ] || case_err="$case_err rearm-did-not-settle"
  fi
  installer_result "T64 behavior: a watcher error is not a verdict; one re-arm settles it"

  # Base advance: the head no longer contains the base tip, so the merge is
  # refused until a rebase; the rebased head merges and the trees match.
  if t64_setup base-advance 'build|yes|SUCCESS|https://github.com/o/r/actions/runs/701/job/1'; then
    t64_git clone -q "$t64_case/origin.git" "$t64_case/other" \
      && printf 'base2\n' > "$t64_case/other/base2.txt" \
      && t64_git -C "$t64_case/other" add base2.txt \
      && t64_git -C "$t64_case/other" commit -q -m base2 \
      && t64_git -C "$t64_case/other" push -q origin main \
      || case_err="$case_err base-advance-failed"
    t64_run "$t64_cmd_watch"; t64_expect watch 0
    t64_run "$t64_cmd_fetch"; t64_expect fetch 0
    t64_run "$t64_cmd_eligible"; t64_expect stale-head-contains-base 1
    t64_run "$t64_cmd_view"
    [ "$(t64_field state)" = OPEN ] || case_err="$case_err merged-before-rebase"
    t64_git -C "$t64_case/work" rebase -q origin/main || case_err="$case_err rebase-failed"
    t64_run "$t64_cmd_push"; t64_expect push 0
    t64_head=$(t64_git -C "$t64_case/work" rev-parse HEAD); t64_sha=$t64_head
    t64_run "$t64_cmd_watch"; t64_expect rebased-watch 0
    t64_run "$t64_cmd_eligible"; t64_expect rebased-head-contains-base 0
    t64_run "$t64_cmd_rangediff"; t64_expect range-diff 0
    printf '%s\n' "$t64_stdout" | grep -qE '^1: +[0-9a-f]+ = 1: +[0-9a-f]+ feature$' \
      || case_err="$case_err range-diff-not-unchanged:$(printf '%s' "$t64_stdout" | tr '\n' ' ')"
    t64_run "$t64_cmd_merge"; t64_expect merge 0
    t64_run "$t64_cmd_view"; t64_expect view 0
    [ "$(t64_field state)" = MERGED ] || case_err="$case_err not-merged"
    t64_mergeoid=$(t64_field oid)
    t64_run "$t64_cmd_fetch"; t64_expect refetch 0
    t64_run "$t64_cmd_tree"; t64_expect tree-equal 0
    t64_head=$t64_old; t64_run "$t64_cmd_tree"; t64_expect stale-tree-differs 1; t64_head=$t64_sha
    [ ! -s "$t64_case/bypass" ] || case_err="$case_err bypass:$(tr '\n' ' ' < "$t64_case/bypass")"
  fi
  installer_result "T64 behavior: an advanced base refuses the merge until rebased, then merges the verified tree"

  # Stale base: `git fetch origin <base>` refreshed the base's lease but left
  # the local base behind. Under push.default=matching an unqualified
  # --force-with-lease push would rewind the remote base to that stale tip; the
  # documented push names the feature branch and its old head, so only it moves.
  if t64_setup stale-base-push ''; then
    t64_git -C "$t64_case/work" config push.default matching \
      && t64_git clone -q "$t64_case/origin.git" "$t64_case/other" \
      && printf 'base2\n' > "$t64_case/other/base2.txt" \
      && t64_git -C "$t64_case/other" add base2.txt \
      && t64_git -C "$t64_case/other" commit -q -m base2 \
      && t64_git -C "$t64_case/other" push -q origin main \
      || case_err="$case_err base-advance-failed"
    t64_base=$(t64_git --git-dir="$t64_case/origin.git" rev-parse refs/heads/main)
    t64_run "$t64_cmd_fetch"; t64_expect fetch 0
    t64_git -C "$t64_case/work" rebase -q origin/main || case_err="$case_err rebase-failed"
    t64_head=$(t64_git -C "$t64_case/work" rev-parse HEAD)
    [ "$t64_head" != "$t64_old" ] || case_err="$case_err rebase-did-not-move-head"
    t64_run "$t64_cmd_push"; t64_expect push 0
    t64_refs=$(t64_git --git-dir="$t64_case/origin.git" for-each-ref --format='%(refname) %(objectname)')
    [ "$t64_refs" = "refs/heads/feature $t64_head"$'\n'"refs/heads/main $t64_base" ] \
      || case_err="$case_err remote-refs:$(printf '%s' "$t64_refs" | tr '\n' ' ')"
    # Control: in this same repository the unqualified form does rewind the
    # remote base, so the assertion above is not vacuous.
    t64_git -C "$t64_case/work" push -q --force-with-lease origin || case_err="$case_err control-push-failed"
    [ "$(t64_git --git-dir="$t64_case/origin.git" rev-parse refs/heads/main)" != "$t64_base" ] \
      || case_err="$case_err control-did-not-rewind-base"
  fi
  installer_result "T64 behavior: with push.default=matching and a stale local base, the documented push moves only the feature ref"
fi

echo
if [ "$SKIP" -gt 0 ]; then
  echo "== ${PASS} passed, ${FAIL} failed, ${SKIP} SKIPPED (coverage incomplete) =="
else
  echo "== ${PASS} passed, ${FAIL} failed =="
fi
[ "$FAIL" -eq 0 ]