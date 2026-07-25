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
ok()  { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); }

SKILL_NAMES=(fc-research fc-grill-me fc-brainstorm fc-build-or-fix fc-review fc-second-opinion)
REVIEW_AGENTS=(fc-qa-spec fc-qa-code fc-tech-lead)
OPERATE_AGENTS=(fc-pm fc-architect fc-developer)

skill_files() { find .claude/skills -name 'SKILL.md' | sort; }

framework_files() {
  find agents -name '*.md'
  find .claude/skills -name '*.md'
  printf '%s\n' README.md AGENTS.md CLAUDE.md
}

echo "== Feature-Crew framework tests =="

# ---------------------------------------------------------------- T1
# Orchestration cap, redefined: pm.md + EVERY SKILL.md (not just build-or-fix).
# The old wording named only two files, so new skills could add orchestration
# text without ever touching the cap.
orch=$( { echo agents/pm.md; skill_files; } | xargs wc -l | tail -1 | awk '{print $1}')
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
stale=$(git grep -lE 'gpt-5\.5|claude-opus-4\.7|degraded \(same-vendor\)' -- '*.md' 2>/dev/null || true)
if [ -z "$stale" ]; then
  ok "T4 no stale model strings"
else
  bad "T4 stale model strings" "$(echo "$stale" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------- T5
# Review agents carry `model: sonnet` in INSTALLED frontmatter; operate agents
# inherit the session model (no model: key at all).
tmp_prefix="$(mktemp -d)"
trap 'rm -rf "$tmp_prefix"' EXIT
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
t10_err=""
for token in fc-pm fc-architect fc-developer fc-qa-spec fc-qa-code fc-tech-lead sonnet; do
  grep -q -- "$token" install.sh  || t10_err="$t10_err sh:$token"
  grep -q -- "$token" install.ps1 || t10_err="$t10_err ps1:$token"
done
for flag in force dry-run uninstall prefix; do
  grep -qi -- "$flag" install.sh  || t10_err="$t10_err sh:--$flag"
  grep -qi -- "$flag" install.ps1 || t10_err="$t10_err ps1:--$flag"
done
[ -z "$t10_err" ] && ok "T10 install.sh / install.ps1 feature parity" \
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
scratch="$tmp_prefix/../fc-scratch-$$"
mkdir -p ".claude/skills/.t15-probe"
if bash install.sh --prefix "$tmp_prefix" --force >/dev/null 2>&1; then
  if [ -d "$tmp_prefix/skills/.t15-probe" ]; then
    bad "T15 scratch dir shipped" "a directory without SKILL.md was installed"
  else
    ok "T15 directories without SKILL.md are not installed"
  fi
else
  bad "T15 scratch dir guard" "install.sh failed"
fi
rmdir ".claude/skills/.t15-probe" 2>/dev/null
rm -rf "$scratch" 2>/dev/null

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

echo
echo "== ${PASS} passed, ${FAIL} failed =="
[ "$FAIL" -eq 0 ]
