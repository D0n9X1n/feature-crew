#!/usr/bin/env bash
# Feature-Crew framework self-test.
#
# Scope note: this harness is dev-only tooling and is not installed by either
# installer. The cross-platform parity rule covers *shipped* artifacts
# (install.sh / install.ps1); T10 is what enforces it.
#
# Run: bash tests/framework_test.sh

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

SKILL_NAMES=(fc-research fc-grill-me fc-brainstorm fc-build-or-fix fc-review fc-second-opinion)
REVIEW_AGENTS=(fc-qa-spec fc-qa-code fc-tech-lead)
OPERATE_AGENTS=(fc-pm fc-architect fc-developer)

skill_files() { find .claude/skills -name 'SKILL.md' | sort; }

framework_files() {
  find agents -name '*.md'
  find .claude/skills -name '*.md'
  # CHANGELOG.md is release metadata, not prompt material an agent loads, so it
  # is deliberately outside the cap. README and CLAUDE are inside it.
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
# The hot path must actually shrink -- this file is paid for on every
# build/fix request, including trivial ones.
if [ -f .claude/skills/fc-build-or-fix/SKILL.md ]; then
  bof=$(wc -l < .claude/skills/fc-build-or-fix/SKILL.md)
  if [ "$bof" -lt 287 ]; then
    ok "T3 fc-build-or-fix/SKILL.md = ${bof} lines (< 287 baseline)"
  else
    bad "T3 hot path did not shrink" "fc-build-or-fix/SKILL.md = ${bof}, baseline 287"
  fi
else
  bad "T3 hot path" ".claude/skills/fc-build-or-fix/SKILL.md missing"
fi

# ---------------------------------------------------------------- T4
# git grep, not grep -r: a bare recursive grep walks into .claude/worktrees/,
# vendored copies, and stray checkouts, then reports their contents as ours.
#
# CHANGELOG.md is excluded for the same reason it sits outside the framework
# cap: it is a historical record, not prompt material an agent loads. Naming a
# field the release removed is what a changelog is for.
stale=$(git grep -lE 'gpt-5\.5|claude-opus-4\.7|degraded \(same-vendor\)' -- '*.md' ':!CHANGELOG.md' 2>/dev/null || true)
if [ -z "$stale" ]; then
  ok "T4 no stale model strings"
else
  bad "T4 stale model strings" "$(echo "$stale" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------- T5
# Review agents carry `model: sonnet` in INSTALLED frontmatter; operate agents
# inherit the session model (no model: key at all).
tmp_prefix="$(mktemp -d)"
# The T15 probe lives inside the repo, so it must be cleaned up even if an
# assertion between here and there exits early -- otherwise a failed run leaves
# the working tree dirty.
T15_PROBE=".claude/skills/t15-probe-$$"
T21_SCRIPT="./t21-noguard-$$.sh"
trap 'rm -rf "$tmp_prefix" "$T15_PROBE" "$T21_SCRIPT"' EXIT
if bash install.sh --prefix "$tmp_prefix" --force >/dev/null 2>&1; then
  t5_err=""
  for a in "${REVIEW_AGENTS[@]}"; do
    f="$tmp_prefix/agents/$a.md"
    if [ ! -f "$f" ]; then t5_err="$t5_err $a:missing"
    elif ! head -12 "$f" | grep -q '^model: sonnet$'; then t5_err="$t5_err $a:no-model-sonnet"
    fi
  done
  for a in "${OPERATE_AGENTS[@]}"; do
    f="$tmp_prefix/agents/$a.md"
    if [ ! -f "$f" ]; then t5_err="$t5_err $a:missing"
    elif head -12 "$f" | grep -q '^model:'; then t5_err="$t5_err $a:should-inherit"
    fi
  done
  if [ -z "$t5_err" ]; then
    ok "T5 review agents pinned to sonnet; operate agents inherit"
  else
    bad "T5 installed agent model frontmatter" "issues:$t5_err"
  fi
else
  bad "T5 installed agent model frontmatter" "install.sh failed against temp prefix"
fi

# ---------------------------------------------------------------- T6
# The cross-family audit rule is stated ONCE; everything else points at it.
# Marker is a phrase only the canonical statement uses -- a passing mention of
# "different family" in an anti-pattern list is a pointer, not a restatement.
# Tracked files only; see T4 on why grep -r is wrong here.
canon=$(git grep -l 'must be audited by a model from a different family' -- '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$canon" = "1" ]; then
  ok "T6 cross-family rule stated in exactly 1 file"
else
  bad "T6 cross-family rule duplicated" "canonical statement in ${canon} files, want 1"
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
# keeps 5 sibling skills from fighting over the same triggers.
t9_err=""
for n in "${SKILL_NAMES[@]}"; do
  f=".claude/skills/$n/SKILL.md"
  if [ ! -f "$f" ]; then t9_err="$t9_err $n:missing"; continue; fi
  desc=$(sed -n '/^description:/,/^[a-z-]*:/p' "$f")
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
for token in fc-pm fc-architect fc-developer fc-qa-spec fc-qa-code fc-tech-lead sonnet; do
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
# install.sh copies agent bodies with cat -- byte-exact, always. PowerShell 5.1
# defaults Get-Content/Set-Content to the system ANSI code page, which silently
# mangles the en-dashes, em-dashes, arrows, and U+2264 in every agent body on a
# CJK code page. Without explicit UTF-8 the two installers disagree, violating
# the cross-platform parity rule -- and the corruption is silent.
t17_err=""
grep -q 'ReadAllText' install.ps1  || t17_err="$t17_err no-explicit-read"
grep -q 'WriteAllText' install.ps1 || t17_err="$t17_err no-explicit-write"
grep -q 'UTF8Encoding' install.ps1 || t17_err="$t17_err no-utf8-nobom"
# A bare Get-/Set-Content on the agent body would reintroduce the bug.
grep -qE '\$body = Get-Content' install.ps1 && t17_err="$t17_err bare-get-content"
[ -z "$t17_err" ] && ok "T17 install.ps1 reads/writes agent bodies as explicit UTF-8" \
                  || bad "T17 PowerShell encoding drift" "issues:$t17_err"

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
grep -qi 'full suite' agents/fc-developer.md             || t19_err="$t19_err dev-allows-task-local-only"
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
# skill. An unconditional rm -rf of those paths destroys hand-written work with
# no prompt and no backup -- which is exactly what the first version of
# remove_legacy_skills did. Deletion now requires proof of ownership.
t22_prefix=$(mktemp -d)
mkdir -p "$t22_prefix/skills/research" "$t22_prefix/skills/build-or-fix"
cat > "$t22_prefix/skills/research/SKILL.md" <<'PROBE'
---
name: research
description: A user's own research skill. Nothing to do with this framework.
---
Years of personal notes.
PROBE
# Ours: correct name AND the exact description we shipped. Ownership is proven
# by matching what we published, not by the file mentioning us somewhere.
cat > "$t22_prefix/skills/build-or-fix/SKILL.md" <<'PROBE'
---
name: build-or-fix
description: Build, fix, change, refactor, implement, add, or extend code. TRIGGER whenever the user asks for any code change.
---
# build-or-fix — Feature-Crew Pipeline (Three Tracks)
PROBE
if bash install.sh --prefix "$t22_prefix" --force >/dev/null 2>&1; then
  t22_err=""
  [ -f "$t22_prefix/skills/research/SKILL.md" ] || t22_err="$t22_err DESTROYED-user-skill"
  [ -d "$t22_prefix/skills/build-or-fix" ]      && t22_err="$t22_err kept-our-own-v3-skill"
  [ -z "$t22_err" ] && ok "T22 legacy cleanup removes only skills we shipped" \
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
# (a) Family collision. Operate = session default, review = sonnet. If the
#     session model IS Sonnet, Sonnet writes and Sonnet reviews, and the gate
#     is satisfied in appearance only. The rule must tell the PM to detect
#     that and record the gate unsatisfied rather than met.
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
# The flow must point at the exemption rather than silently contradicting it.
grep -qi 'one of the two exemptions\|exemption' "$b" || t24_err="$t24_err flow-does-not-cite-exemption"
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
  pa=$(grep -n 'Cross-audit the plan' "$c" | cut -d: -f1)
  ap=$(grep -n 'User approves the plan' "$c" | cut -d: -f1)
  if [ -n "$pa" ] && [ -n "$ap" ] && [ "$pa" -ge "$ap" ]; then
    t26_err="$t26_err plan-audit-after-approval"
  fi
else
  t26_err=" complex-track-missing"
fi
[ -z "$t26_err" ] && ok "T26 every artifact named in the rule has an audit step in the flow" \
                  || bad "T26 rule/flow mismatch" "issues:$t26_err"

echo
# ---------------------------------------------------------------- T27
# Provenance false-positive. The first ownership check grepped the whole file
# for "feature-crew", so a personal skill whose DESCRIPTION merely mentioned
# Feature-Crew was destroyed -- precisely the user most likely to have this
# repo installed. Ownership must match what we shipped, not what mentions us.
t27_prefix=$(mktemp -d)
mkdir -p "$t27_prefix/skills/research"
cat > "$t27_prefix/skills/research/SKILL.md" <<'PROBE'
---
name: research
description: My own research skill. I use it to look into Feature-Crew integrations at work.
---
Years of my own notes. Also mentions audit-pair because I read the docs.
PROBE
t27_err=""
if bash install.sh --prefix "$t27_prefix" >/dev/null 2>&1; then
  [ -f "$t27_prefix/skills/research/SKILL.md" ] || t27_err="$t27_err DESTROYED-on-install"
else
  t27_err="$t27_err install-failed"
fi
if bash install.sh --prefix "$t27_prefix" --uninstall >/dev/null 2>&1; then
  [ -f "$t27_prefix/skills/research/SKILL.md" ] || t27_err="$t27_err DESTROYED-on-uninstall"
fi
[ -z "$t27_err" ] && ok "T27 a personal skill that merely mentions Feature-Crew survives" \
                  || bad "T27 provenance false-positive" "issues:$t27_err"
rm -rf "$t27_prefix"

echo
if [ "$SKIP" -gt 0 ]; then
  echo "== ${PASS} passed, ${FAIL} failed, ${SKIP} SKIPPED (coverage incomplete) =="
else
  echo "== ${PASS} passed, ${FAIL} failed =="
fi
[ "$FAIL" -eq 0 ]