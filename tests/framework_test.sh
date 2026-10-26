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

SKILL_NAMES=(fc-research fc-grill-me fc-brainstorm fc-debug fc-explain fc-build-or-fix fc-review fc-second-opinion fc-update fc-ship fc-clean)
ROLE_AGENTS=(fc-pm fc-architect fc-developer fc-qa-spec fc-qa-code fc-tech-lead)

skill_files() { find skills -name 'SKILL.md' | sort; }

framework_files() {
  find agents -name '*.md'
  find skills -name '*.md'
  printf '%s\n' README.md .claude/CLAUDE.md hooks/routing.json
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
# Baseline raised from 1223 to 1251 for /fc-clean by explicit user override
# (framework-cap-override, 2026-10-24). It is the new total + 1: any growth
# needs another override.
total=$(framework_files | xargs wc -l | tail -1 | awk '{print $1}')
if [ "${total:-99999}" -le 1500 ] && [ "${total:-99999}" -lt 1251 ]; then
  ok "T2 framework total = ${total} (<=1500, and < 1251 baseline)"
else
  bad "T2 framework total" "total=${total}; need <=1500 AND <1251 (baseline before this change)"
fi

# ---------------------------------------------------------------- T3
# The hot path must remain tightly ratcheted -- this file is paid for on every
# build/fix request, including Just Do It work.
if [ -f skills/fc-build-or-fix/SKILL.md ]; then
  bof=$(wc -l < skills/fc-build-or-fix/SKILL.md)
  if [ "$bof" -le 128 ]; then
    ok "T3 fc-build-or-fix/SKILL.md = ${bof} lines (<= 128 ratchet)"
  else
    bad "T3 hot path exceeded ratchet" "fc-build-or-fix/SKILL.md = ${bof}, cap 128"
  fi
else
  bad "T3 hot path" "skills/fc-build-or-fix/SKILL.md missing"
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
# The plugin loads agents/*.md as committed, so their frontmatter is the
# contract. No role carries a model key: hard-gate dispatchers select an
# explicit override from artifact-author provenance. The five dispatched roles
# carry a least-privilege tools allowlist, which both Claude Code and Copilot
# CLI enforce, plus disallowedTools: Agent, Skill, which Claude Code also
# enforces. fc-pm runs as the main session and is unrestricted.
#
# This parses YAML rather than grepping lines: duplicate keys resolve silently
# to the last value, so reject duplicate keys outright before checking the
# resolved mapping.
validate_role_frontmatter() {
  python3 - "$1" <<'PY'
import sys, re, glob, os, yaml
review = {"Read", "Grep", "Glob", "Bash", "WebFetch", "WebSearch", "TodoWrite"}
want = {"fc-pm": None, "fc-architect": review, "fc-developer": review | {"Edit", "Write"},
        "fc-qa-spec": review, "fc-qa-code": review, "fc-tech-lead": review}
def tools(v):
    return {str(t).strip() for t in (v if isinstance(v, list) else str(v or "").split(",")) if str(t).strip()}
errs, seen = [], set()
for f in sorted(glob.glob(sys.argv[1] + "/agents/*.md")):
    name = os.path.basename(f)[:-3]
    seen.add(name)
    m = re.match(r"^---\n(.*?)\n---\n", open(f, encoding="utf-8").read(), re.S)
    if not m:
        errs.append(f"{name}:no-frontmatter"); continue
    block = m.group(1)
    keys = [ln.split(":", 1)[0] for ln in block.splitlines() if re.match(r"^[A-Za-z][A-Za-z-]*:", ln)]
    if len(keys) != len(set(keys)):
        errs.append(f"{name}:duplicate-keys"); continue
    try:
        d = yaml.safe_load(block) or {}
    except yaml.YAMLError:
        errs.append(f"{name}:invalid-yaml"); continue
    if d.get("name") != name:
        errs.append(f"{name}:name-mismatch")
    if not str(d.get("description") or "").startswith("Feature-Crew "):
        errs.append(f"{name}:description")
    if "model" in d:
        errs.append(f"{name}:model={d['model']!r}-must-be-absent")
    if name not in want:
        continue
    if want[name] is None:
        if "tools" in d or "disallowedTools" in d:
            errs.append(f"{name}:main-session-role-restricted")
        continue
    got = tools(d.get("tools"))
    if got != want[name]:
        errs.append(f"{name}:tools={','.join(sorted(got))}")
    denied = tools(d.get("disallowedTools"))
    if "Agent" not in denied:
        errs.append(f"{name}:can-delegate")
    if "Skill" not in denied:
        errs.append(f"{name}:can-invoke-skills")
for name in sorted(set(want) - seen):
    errs.append(f"{name}:missing")
for name in sorted(seen - set(want)):
    errs.append(f"{name}:unexpected-role")
print(" ".join(errs))
PY
}

scratch_root="$(mktemp -d)"
# Other tests add their temp paths to this shared list.
CLEANUP_PATHS=("$scratch_root")
cleanup() { chmod -R u+rwX "${CLEANUP_PATHS[@]}" 2>/dev/null; rm -rf "${CLEANUP_PATHS[@]}"; }
trap cleanup EXIT
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  if t5_out=$(validate_role_frontmatter . 2>&1) && [ -z "$t5_out" ]; then
    ok "T5 committed role agents: valid YAML, own name, no model key, least-privilege tools; fc-pm unrestricted"
  else
    bad "T5 committed role-agent frontmatter" "issues:${t5_out:-validator-failed}"
  fi
else
  skip "T5 no YAML parser — role frontmatter unverified"
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
g=skills/fc-grill-me/SKILL.md
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

b=skills/fc-brainstorm/SKILL.md
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
s=skills/fc-second-opinion/SKILL.md
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
t9_err=$(t9_contract skills)
[ -z "$t9_err" ] && ok "T9 all skills carry [what] + [use when] + [do NOT use for]" \
                 || bad "T9 skill description contract" "issues:$t9_err"
# Negative checks on scratch copies: removing either clause from fc-debug's or
# fc-explain's description must fail this same check with exactly that
# clause's diagnostic.
for t9_skill in fc-debug fc-explain; do
  for t9_clause in use-when anti-trigger; do
    case "$t9_clause" in
      use-when)     t9_sed='/^description:/s/ Use when [^.]*\.//';       t9_want=" $t9_skill:no-use-when" ;;
      anti-trigger) t9_sed='/^description:/s/ Do NOT use for [^.]*\.//'; t9_want=" $t9_skill:no-anti-trigger" ;;
    esac
    t9_mut=$(mktemp -d)
    CLEANUP_PATHS+=("$t9_mut")
    cp -R skills "$t9_mut/skills"
    t9_target="$t9_mut/skills/$t9_skill/SKILL.md"
    if [ ! -f "$t9_target" ]; then
      bad "T9 removal mutation: $t9_skill $t9_clause" "mutation target $t9_skill/SKILL.md missing"
    elif sed "$t9_sed" "$t9_target" > "$t9_mut/mutant" && cmp -s "$t9_mut/mutant" "$t9_target"; then
      bad "T9 removal mutation: $t9_skill $t9_clause" "clause not found; mutation not applied"
    else
      cp "$t9_mut/mutant" "$t9_target"
      t9_mut_out=$(t9_contract "$t9_mut/skills")
      if [ "$t9_mut_out" = "$t9_want" ]; then
        ok "T9 removal mutation: $t9_skill $t9_clause rejected by its own check"
      else
        bad "T9 removal mutation: $t9_skill $t9_clause" "got '${t9_mut_out:-<empty>}', want '$t9_want'"
      fi
    fi
    rm -rf "$t9_mut"
  done
done

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
done < <(git ls-files 'skills/*' | cut -d/ -f2 | sort -u)
[ -z "$t12_err" ] && ok "T12 all skills fc-prefixed (no bundled-name collision)" \
                  || bad "T12 unprefixed skill dir" "offenders:$t12_err"

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

# ---------------------------------------------------------------- T24
# Two logic holes both reviewers found in the audit rule.
#
# (a) Family collision. A computed reviewer from the artifact author's known
#     family must differ or the gate is recorded unsatisfied rather than met.
# (b) Standard step 3 skips the spec audit, while the rule says EVERY
#     model-authored hard-gate artifact is audited. Whichever way that is
#     resolved, the exemption has to be stated in the rule -- otherwise a
#     reader who trusts the rule is misled by the flow, and vice versa.
b=skills/fc-build-or-fix/SKILL.md
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

# ---------------------------------------------------------------- T26
# Every artifact the canonical rule names must have a matching audit step in
# the flow. The rule named `plan` as must-audit while the Complex flow went
# architect -> user approval -> implementation with no audit between; five
# independent reviewers caught it and the tests did not. T6 only counts where
# the rule is *stated*, never whether the flow obeys it.
c=skills/fc-build-or-fix/reference/complex-track.md
t26_err=""
if [ -f "$c" ]; then
  grep -qi 'cross-audit the spec' "$c" || t26_err="$t26_err spec-unaudited"
  grep -qi 'cross-audit the plan' "$c" || t26_err="$t26_err plan-unaudited"
  grep -qi 'fc-qa-spec\|fc-qa-code' "$c" || t26_err="$t26_err diff-unaudited"
  # Require the tech lead to be DISPATCHED, not merely named. A reviewer
  # replaced the step with "Do not dispatch fc-tech-lead; merge directly" and
  # this stayed green on the bare token.
  grep -qiE 'dispatch `?(feature-crew:)?fc-tech-lead' "$c" || t26_err="$t26_err final-not-dispatched"
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
  skills/fc-build-or-fix/reference/design-check.md
  skills/fc-build-or-fix/SKILL.md
  skills/fc-build-or-fix/reference/complex-track.md
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

# ---------------------------------------------------------------- T72
# Standard/Complex design and fc-brainstorm start from a cited industry survey,
# and a better approach that needs a stated requirement relaxed becomes a
# trade-off row the user decides. One canonical reference holds the contract;
# the other docs point to it. Section-scoped like T61: after the unmodified
# documents pass, removing one clause must produce exactly its own diagnostic.
t72_err=""
t72_docs=(
  skills/fc-build-or-fix/reference/industry-survey.md
  skills/fc-build-or-fix/SKILL.md
  skills/fc-build-or-fix/reference/complex-track.md
  skills/fc-build-or-fix/reference/design-check.md
  skills/fc-brainstorm/SKILL.md
  skills/fc-research/SKILL.md
)
t72_labels=(
  research-informs survey-before-design jdi-never reuse
  route-research own-survey-step caller-surveys-first broad-then-narrow angles
  cite-every-claim primary-first training-hypothesis gaps-reported
  prior-art-table same-evidence
  research-firewall no-silent-drop tradeoff-row compliant-default user-decides
  standard-survey-first standard-spec-carries complex-survey-first reconcile-tradeoff
  brainstorm-reuse brainstorm-own-survey brainstorm-caller-returns brainstorm-survey-no-delegation panel-cites
  converge-tradeoff brainstorm-survey-cap research-source-rules
)
t72_sections=(
  intro when when when
  how how how how how
  sources sources sources sources
  output output
  tradeoffs tradeoffs tradeoffs tradeoffs tradeoffs
  standard standard complex2 both
  frame frame frame frame panel
  converge caps phase1
)
t72_rules=(
  'research informs the design, never the requirements.'
  'Survey before the first design unless the design is super straightforward'
  'Just Do It never surveys.'
  'Reuse a survey for an unchanged problem; never repeat it.'
  'Route it through `/fc-research`: the focused path for one bounded question, the full pipeline for a broad one.'
  'A flow that cannot invoke `/fc-research` follows its own survey step.'
  'A flow that invokes `/fc-brainstorm` surveys through `/fc-research` first and passes the survey in.'
  'Start broad, then narrow; stop when new searches stop changing the answer.'
  'Cover official docs and standards, published designs and RFCs, real projects, and postmortems or known failure modes.'
  'Every claim carries a URL, publisher, and date.'
  'Primary sources outrank secondary ones'
  'Treat what you remember from training as a hypothesis until a source confirms it.'
  'Report every unreachable source as a gap, never as coverage.'
  '`practice | source | fit with our constraints | evidence`'
  "Give both designers the same table, never the other designer's proposal."
  'Research never changes a requirement by itself.'
  'do not drop it silently'
  '`requirement | alternative + evidence | gain | sacrifice | reversibility | compliant fallback`'
  'keep the compliant design until the user decides.'
  'The user decides each row; approval waivers do not decide it.'
  'Survey per [reference/industry-survey.md](reference/industry-survey.md), then write a bullet spec'
  'prior-art table and any trade-off rows'
  'Survey first per [industry-survey.md](industry-survey.md); its evidence goes into the spec and, unchanged, to the architect and the blind second designer.'
  'A better design that needs a stated requirement relaxed follows the trade-off rule in [industry-survey.md](industry-survey.md).'
  'Then survey industry practice per [industry-survey.md](../fc-build-or-fix/reference/industry-survey.md): reuse a survey the caller passed in;'
  'when the user invoked this skill directly without one, dispatch one search author with an explicit `model` override from the authoring rule in `/fc-build-or-fix`, then one validator chosen by its selector, in the `/fc-research` focused-path format.'
  'When another flow invoked it without a survey, return to that flow to survey first.'
  'Each survey prompt ends with: "Do not call `Agent`, `Skill`, `Workflow`, or delegate any part of the task."'
  "Paste the survey's prior-art table into every panel prompt; each approach cites it."
  'If an approach needs a stated requirement relaxed, show its trade-off row from [industry-survey.md](../fc-build-or-fix/reference/industry-survey.md); the user decides it.'
  '2 survey (author and validator, only on a direct invocation without a survey)'
  'Apply the source rules in [industry-survey.md](../fc-build-or-fix/reference/industry-survey.md).'
)
t72_survey_contract() { # the six t72_docs texts, in order
  local intro when how sources output tradeoffs standard complex2 both frame panel converge caps phase1
  local section i errors=""
  intro=$(printf '%s\n' "$1" | sed -n '/^# Industry survey/,/^## /p')
  when=$(printf '%s\n' "$1" | sed -n '/^## When/,/^## /p')
  how=$(printf '%s\n' "$1" | sed -n '/^## How/,/^## /p')
  sources=$(printf '%s\n' "$1" | sed -n '/^## Sources/,/^## /p')
  output=$(printf '%s\n' "$1" | sed -n '/^## Output/,/^## /p')
  tradeoffs=$(printf '%s\n' "$1" | sed -n '/^## Requirement trade-offs/,/^## /p')
  standard=$(printf '%s\n' "$2" | sed -n '/^### Standard/,/^### /p' | grep -E '^2\. ')
  complex2=$(printf '%s\n' "$3" | sed -n '/^## Flow/,/^## /p' | grep -E '^2\. ')
  both=$(printf '%s\n' "$4" | sed -n '/^## Both directions/,/^## /p')
  frame=$(printf '%s\n' "$5" | sed -n '/^## 1 — Frame/,/^## /p')
  panel=$(printf '%s\n' "$5" | sed -n '/^## 2 — Panel/,/^## /p')
  converge=$(printf '%s\n' "$5" | sed -n '/^## 4 — Converge/,/^## /p')
  caps=$(printf '%s\n' "$5" | sed -n '/^## Caps/,/^## /p')
  phase1=$(printf '%s\n' "$6" | sed -n '/^## Phase 1/,/^## /p')
  for ((i=0; i<${#t72_rules[@]}; i++)); do
    case "${t72_sections[$i]}" in
      intro) section="$intro" ;;
      when) section="$when" ;;
      how) section="$how" ;;
      sources) section="$sources" ;;
      output) section="$output" ;;
      tradeoffs) section="$tradeoffs" ;;
      standard) section="$standard" ;;
      complex2) section="$complex2" ;;
      both) section="$both" ;;
      frame) section="$frame" ;;
      panel) section="$panel" ;;
      converge) section="$converge" ;;
      caps) section="$caps" ;;
      phase1) section="$phase1" ;;
      *) section="" ;;
    esac
    [[ "$section" == *"${t72_rules[$i]}"* ]] || errors="$errors ${t72_labels[$i]}"
  done
  printf '%s\n' "$errors"
}
t72_texts=()
for t72_doc in "${t72_docs[@]}"; do
  [ -f "$t72_doc" ] || t72_err="$t72_err file:$t72_doc"
  t72_texts+=("$(cat "$t72_doc" 2>/dev/null)")
done
[ "${#t72_labels[@]}" -eq "${#t72_rules[@]}" ] && [ "${#t72_sections[@]}" -eq "${#t72_rules[@]}" ] \
  || t72_err="$t72_err rule-table-misaligned"
t72_out=$(t72_survey_contract "${t72_texts[@]}")
t72_err="$t72_err$t72_out"
if [ -z "$t72_err" ]; then
  for ((t72_i=0; t72_i<${#t72_rules[@]}; t72_i++)); do
    case "${t72_sections[$t72_i]}" in
      intro|when|how|sources|output|tradeoffs) t72_doc_i=0 ;;
      standard) t72_doc_i=1 ;;
      complex2) t72_doc_i=2 ;;
      both) t72_doc_i=3 ;;
      frame|panel|converge|caps) t72_doc_i=4 ;;
      *) t72_doc_i=5 ;;
    esac
    t72_rule="${t72_rules[$t72_i]}"
    t72_mut=("${t72_texts[@]}")
    t72_text="${t72_mut[$t72_doc_i]}"
    t72_text="${t72_text/"$t72_rule"/}"
    t72_mut[$t72_doc_i]="$t72_text"
    t72_mut_out=$(t72_survey_contract "${t72_mut[@]}")
    if [ "$t72_mut_out" = " ${t72_labels[$t72_i]}" ]; then
      ok "T72 removal mutation: ${t72_labels[$t72_i]} rejected by its own check"
    else
      bad "T72 removal mutation: ${t72_labels[$t72_i]}" \
        "got '${t72_mut_out:-<empty>}', want ' ${t72_labels[$t72_i]}'"
    fi
  done
fi
[ -z "$t72_err" ] && ok "T72 static contract alarm: cited industry survey before design + requirement trade-offs the user decides" \
                   || bad "T72 industry survey and requirement trade-off contract" "missing:$t72_err"

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
b=skills/fc-build-or-fix/SKILL.md
t32_err=""
selector=$(sed -n '/^## Cross-family audit/,/^## Dispatch/p' "$b")
# The agent chooses the pair itself, in any harness: the two most capable
# models it can dispatch, from different families (#54, #57).
echo "$selector" | grep -qiE 'review pair.*two most capable.*different mapped families' \
  || t32_err="$t32_err review-pair-missing"
echo "$selector" | grep -qiE 'Claude Code.*`opus`.*`sonnet`' || t32_err="$t32_err claude-code-pair-example-missing"
echo "$selector" | grep -qiE 'Copilot.*Opus.*GPT-6 Astra' || t32_err="$t32_err copilot-pair-example-missing"
echo "$selector" | grep -qiE 'first pair member outside.*author family' \
  || t32_err="$t32_err pair-reviewer-rule-missing"
echo "$selector" | grep -qiE 'non-Sonnet.family' && t32_err="$t32_err stale-sonnet-centric-rule"
echo "$selector" | grep -qF 'Opus and Sonnet as the pair' && t32_err="$t32_err stale-opus-sonnet-pair"
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
echo "$selector" | grep -qiE 'skip.*member.*this session.s record shows.*author.s family' \
  || t32_err="$t32_err recorded-alias-collision-not-skipped"
echo "$selector" | grep -qiE 'no member.*left.*same.family collision' \
  || t32_err="$t32_err exhausted-pair-not-collision"
echo "$selector" | grep -qF '(reference/gate-provenance.md)' \
  || t32_err="$t32_err provenance-reference-not-linked"
# A hard-gate reviewer that delegates hides models from its own record, and
# the child-record link is observed only one dispatch deep, so any Agent,
# Skill, or Workflow call in the review record fails the gate. Stated once.
echo "$selector" | grep -qiE 'recorded reviewer model and the reviewer record.s tool calls.*any `Agent`, `Skill`, or `Workflow` call.*GATE UNSATISFIED' \
  || t32_err="$t32_err reviewer-delegation-not-fail-closed"
t32_calls=$(git grep -cF "reviewer record's tool calls" -- '*.md' 2>/dev/null | awk -F: '{ n += $NF } END { print n + 0 }')
[ "$t32_calls" = "1" ] || t32_err="$t32_err reviewer-delegation-rule-stated-${t32_calls}-times"
# The delegated-reviewer predicate is stated once, in the canonical rule; other docs link to it.
t32_pred=$(git grep -cF '`Agent`, `Skill`, or `Workflow`' -- '*.md' 2>/dev/null | awk -F: '{ n += $NF } END { print n + 0 }')
[ "$t32_pred" = "1" ] || t32_err="$t32_err reviewer-delegation-predicate-stated-${t32_pred}-times"
# Each selector clause and each worked outcome is pinned literally, so rewriting
# one (an Opus author sent to `opus`, a lost family requirement) fails its own
# check, not just a regex. The agent chooses the pair; no harness config (#57).
t32_pair_labels=(
  choose-pair most-capable-cross-family harness-examples request-own-way no-relay-probe
  pair-recorded fewer-than-two-families opus-author-to-sonnet other-author-to-opus
  example-pair-condition alias-scope
)
t32_pair_rules=(
  'At each gate, choose the **review pair** yourself'
  'the two most capable models you can dispatch, from different mapped families, most capable first'
  'such as Opus and GPT: Claude Code `opus` and `sonnet` (a relay may route `sonnet` to GPT-6 Astra; the record decides), or GitHub Copilot Opus, GPT-6 Astra'
  'Request each model the way your harness does'
  'never look behind a model into a relay or gateway'
  'Record the pair in the gate record'
  'fewer than two qualifying families → `GATE UNSATISFIED`'
  'an Opus-family author is reviewed by `sonnet`'
  'any other author by `opus`'
  'with Opus and GPT as the pair, requested in Claude Code as `opus` and `sonnet`'
  'In Claude Code, use family aliases for requests, not version-specific IDs; other harnesses use their own model names'
)
t32_pair_contract() { # selector text
  local i errors=""
  for ((i=0; i<${#t32_pair_rules[@]}; i++)); do
    printf '%s\n' "$1" | grep -qF -- "${t32_pair_rules[$i]}" || errors="$errors ${t32_pair_labels[$i]}"
  done
  printf '%s\n' "$errors"
}
t32_pair_out=$(t32_pair_contract "$selector")
t32_err="$t32_err$t32_pair_out"
# Agent aliases are dispatch vocabulary, not the list of selectable models.
printf '%s\n' "$selector" | grep -qF 'the aliases the Agent tool' && t32_err="$t32_err stale-alias-inventory"
printf '%s\n' "$selector" | grep -qF 'modelPicker' && t32_err="$t32_err stale-picker-inventory"
t32_dispatch=$(sed -n '/^## Dispatch rules/,/^## /p' "$b")
printf '%s\n' "$t32_dispatch" | grep -qF 'the exact explicit `model` override above' \
  || t32_err="$t32_err dispatch-override-not-general"
[ -z "$t32_err" ] && ok "T32 static contract alarm: dynamic hard-gate selector retained" \
                   || bad "T32 dynamic selector prose contract" "missing:$t32_err"
if [ -z "$t32_pair_out" ]; then
  for ((t32_i=0; t32_i<${#t32_pair_rules[@]}; t32_i++)); do
    t32_mut_out=$(t32_pair_contract "${selector/"${t32_pair_rules[$t32_i]}"/}")
    if [ "$t32_mut_out" = " ${t32_pair_labels[$t32_i]}" ]; then
      ok "T32 removal mutation: ${t32_pair_labels[$t32_i]} rejected by its own check"
    else
      bad "T32 removal mutation: ${t32_pair_labels[$t32_i]}" \
        "got '${t32_mut_out:-<empty>}', want ' ${t32_pair_labels[$t32_i]}'"
    fi
  done
  # Rewrites that send an author to its own family must fail.
  for t32_case in 'opus-author-sent-to-opus|an Opus-family author is reviewed by `sonnet`|an Opus-family author is reviewed by `opus`|opus-author-to-sonnet' \
                  'other-author-sent-to-sonnet|any other author by `opus`|any other author by `sonnet`|other-author-to-opus' \
                  'once-per-session|At each gate, choose|Only once per session, choose|choose-pair'; do
    IFS='|' read -r t32_label t32_from t32_to t32_want <<<"$t32_case"
    t32_mut_out=$(t32_pair_contract "${selector/"$t32_from"/$t32_to}")
    if [ "$t32_mut_out" = " $t32_want" ]; then
      ok "T32 rewrite mutation: $t32_label rejected by its own check"
    else
      bad "T32 rewrite mutation: $t32_label" "got '${t32_mut_out:-<empty>}', want ' $t32_want'"
    fi
  done
fi

# Duplicate YAML keys can hide an override even when committed files look
# superficially right. Mutate one copied agent and require the shared T5
# validator to return the exact duplicate-key diagnostic. A crash, import error,
# empty glob, or unrelated diagnostic is a test failure, not a rejection.
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import yaml' >/dev/null 2>&1; then
  skip "T5 duplicate-key mutation — YAML parser unavailable"
else
  t5_mut="$(mktemp -d)"
  CLEANUP_PATHS+=("$t5_mut")
  rm -rf "$t5_mut/agents"
  if ! cp -R agents "$t5_mut/agents"; then
    bad "T5 duplicate-key mutation" "copy failed"
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
  # A permissive deny key ahead of the committed one: a first-wins parser would
  # let the role delegate, PyYAML keeps the last. Reject the ambiguity itself.
  rm -rf "$t5_mut/agents"
  if ! cp -R agents "$t5_mut/agents"; then
    bad "T5 duplicate deny-key mutation" "copy failed"
  else
    python3 - "$t5_mut/agents/fc-tech-lead.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("description:", "disallowedTools: Read\ndescription:", 1)
open(p, "w", encoding="utf-8").write(s)
PY
    if t5_mut_out=$(validate_role_frontmatter "$t5_mut" 2>&1); then
      if [ "$t5_mut_out" = "fc-tech-lead:duplicate-keys" ]; then
        ok "T5 duplicate deny-key mutation returns expected diagnostic"
      else
        bad "T5 duplicate deny-key mutation" "got '${t5_mut_out:-<empty>}', want 'fc-tech-lead:duplicate-keys'"
      fi
    else
      t5_mut_rc=$?
      bad "T5 duplicate deny-key mutation" "validator exited $t5_mut_rc: ${t5_mut_out:-<no diagnostic>}"
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
brainstorm=skills/fc-brainstorm/SKILL.md
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
echo "$bs_caps" | grep -qiE 'max 9 panel/review dispatches.*3 panel \+ (up to 3|≤3) re-dispatch \+ 1 cross-audit \+ 2 survey' \
  || t33_err="$t33_err brainstorm-cap-omits-diversity-round"
echo "$bs_caps" | grep -qiE 'descendants.*any depth' \
  || t33_err="$t33_err brainstorm-descendants-not-counted"
echo "$bs_caps" | grep -qiE 'pause.*user.*approval|user.*OK.*first' \
  || t33_err="$t33_err brainstorm-cap-expansion-not-approved"
if grep -q '^disable-model-invocation: true$' skills/fc-grill-me/SKILL.md; then
  t33_err="$t33_err grill-not-model-invocable"
fi
# Pointer docs must not grow a second copy of the canonical route table.
dup_classifier=$(git grep -lF '| One discoverable fact |' -- README.md .claude/CLAUDE.md 'wiki/*.md' agents/fc-pm.md \
  'skills/fc-brainstorm/SKILL.md' 2>/dev/null || true)
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
t62_text=$(cat skills/fc-debug/SKILL.md 2>/dev/null)
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

# ---------------------------------------------------------------- T66
# fc-explain explains an existing project with readable diagrams tied to code
# evidence. Its eight behaviors and the Worker boundary suffix on every helper
# prompt are literal sentences scoped to their own sections, and fc-research's
# pointer to it must sit in fc-research's own "Do NOT use for" list, so a stray
# mention elsewhere cannot satisfy either. As T64 does for /fc-ship, the wiki Usage
# direct-command list and both installer "Available:" banners must name
# /fc-explain, and README line 3 must carry the live release badge. The skill
# stays within its approved 30 lines, counted byte-exactly so trailing blank
# lines count. As in T62, each mutation must produce exactly its own
# diagnostic, and mutations run only after the unmodified documents pass the
# control.
t66_labels=(
  infer-scope bottom-up-map default-views mermaid-only readable-diagrams
  after-each-diagram verify-evidence chat-output
  helper-worker-suffix research-pointer
  usage-direct-command readme-release-badge banner-sh banner-ps1 line-budget
)
t66_sections=(map map diagrams diagrams diagrams answer verify answer map research
  commands version sh ps1 budget)
t66_rules=(
  'Run in the main conversation. Infer the scope (the whole project, a subsystem, or one flow) and ask only when it is genuinely ambiguous.'
  'Build the component map with the bottom-up mapping contract in [design-check.md](../fc-build-or-fix/reference/design-check.md): read small scopes directly; for large ones use at most three read-only `Explore` helpers, each helper prompt ending with the Worker boundary suffix below. Keep the map for follow-ups and refresh its evidence before answering them.'
  'Default to one overview (containers or building blocks) plus one evidenced key flow; add a context, component drill-down, or deployment view only when useful or requested.'
  'Use fenced Mermaid only: `flowchart` for structure and `sequenceDiagram` for interactions. No experimental C4 or `architecture-beta`, and never ASCII art.'
  'Keep each diagram professional and readable: a title, scope, and legend; one abstraction level; 5–12 nodes, split above 15; short responsibility labels; labeled directional arrows; consistent shapes; minimal styling and never color-only meaning; citations beside nodes, not inside them.'
  'After each diagram give the takeaway, a short walkthrough, and a component table with file links. Separate verified facts, inferences, and unknowns, and end with where to start reading.'
  'Trace every node and edge to evidence. Parse or render only with an already-installed renderer (never install one or upload source), with at most two fix attempts; otherwise state "not render-checked".'
  'Answer in chat; write a repository file or publish a page only on request.'
  '> Perform the assigned work yourself. Do not call `Agent`, `Skill`, `Workflow`, or delegate any part of the task.'
  "explaining a project's structure with diagrams (use /fc-explain)"
  '`/fc-explain`'
  '[![Release](https://img.shields.io/github/v/release/D0n9X1n/feature-crew?sort=semver)](https://github.com/D0n9X1n/feature-crew/releases/latest)'
  '/fc-explain'
  '/fc-explain'
  30
)
t66_load() { # file -> t66_loaded, byte-exact: $(cat) alone drops trailing blank lines
  t66_loaded=$(cat "$1" 2>/dev/null; printf x)
  t66_loaded=${t66_loaded%x}
}
t66_explain_contract() { # fc-explain, fc-research, README, install.sh, install.ps1, wiki Usage text
  local map diagrams verify answer pointer commands version sh ps1 lines section i errors=""
  map=$(printf '%s\n' "$1" | sed -n '/^## Scope and map$/,/^## /p')
  diagrams=$(printf '%s\n' "$1" | sed -n '/^## Diagrams$/,/^## /p')
  verify=$(printf '%s\n' "$1" | sed -n '/^## Verify$/,/^## /p')
  answer=$(printf '%s\n' "$1" | sed -n '/^## Answer$/,/^## /p')
  lines=$(printf '%s' "$1" | wc -l | tr -d ' ')
  # Only fc-research's own frontmatter "Do NOT use for" list counts.
  pointer=$(printf '%s\n' "$2" | awk '/^---$/{c++; if(c==2) exit; next} c==1' \
    | grep '^description:' | sed -n 's/.*Do NOT use for //p')
  commands=$(printf '%s\n' "$6" | sed -n '/^## Describe the need/,/^## /p')
  version=$(printf '%s\n' "$3" | sed -n '3p')
  sh=$(printf '%s\n' "$4" | sed -n '/Available: \/fc-/,/delegate to an fc-/p')
  ps1=$(printf '%s\n' "$5" | sed -n '/Available: \/fc-/,/delegate to an fc-/p')
  for ((i=0; i<${#t66_rules[@]}; i++)); do
    case "${t66_sections[$i]}" in
      map) section="$map" ;;
      diagrams) section="$diagrams" ;;
      verify) section="$verify" ;;
      answer) section="$answer" ;;
      research) section="$pointer" ;;
      commands) section="$commands" ;;
      version) section="$version" ;;
      sh) section="$sh" ;;
      ps1) section="$ps1" ;;
      budget)
        [ "$lines" -le "${t66_rules[$i]}" ] || errors="$errors ${t66_labels[$i]}"
        continue ;;
    esac
    printf '%s\n' "$section" | grep -qF -- "${t66_rules[$i]}" \
      || errors="$errors ${t66_labels[$i]}"
  done
  printf '%s\n' "$errors"
}
t66_load skills/fc-explain/SKILL.md
t66_explain_text=$t66_loaded
t66_research_text=$(cat skills/fc-research/SKILL.md 2>/dev/null)
t66_readme_text=$(cat README.md 2>/dev/null)
t66_usage_text=$(cat wiki/Usage.md 2>/dev/null)
t66_sh_text=$(cat install.sh 2>/dev/null)
t66_ps1_text=$(cat install.ps1 2>/dev/null)
t66_err=$(t66_explain_contract "$t66_explain_text" "$t66_research_text" \
  "$t66_readme_text" "$t66_sh_text" "$t66_ps1_text" "$t66_usage_text")
if [ -z "$t66_err" ]; then
  t66_root=$(mktemp -d)
  CLEANUP_PATHS+=("$t66_root")
  for ((t66_i=0; t66_i<${#t66_rules[@]}; t66_i++)); do
    t66_rule="${t66_rules[$t66_i]}"
    t66_kind=removal
    t66_explain_mut="$t66_explain_text"
    t66_research_mut="$t66_research_text"
    t66_readme_mut="$t66_readme_text"
    t66_usage_mut="$t66_usage_text"
    t66_sh_mut="$t66_sh_text"
    t66_ps1_mut="$t66_ps1_text"
    case "${t66_sections[$t66_i]}" in
      research) t66_research_mut="${t66_research_mut/"$t66_rule"/}" ;;
      commands) t66_usage_mut="${t66_usage_mut/"$t66_rule"/}" ;;
      version) t66_readme_mut="${t66_readme_mut/"$t66_rule"/}" ;;
      sh) t66_sh_mut="${t66_sh_mut/"$t66_rule"/}" ;;
      ps1) t66_ps1_mut="${t66_ps1_mut/"$t66_rule"/}" ;;
      budget)
        # A real copy one line over budget, padded with blank lines and read
        # back the same way as the skill, so trailing blank lines cannot hide.
        t66_kind="$((t66_rule + 1))-line copy"
        printf '%s' "$t66_explain_text" > "$t66_root/SKILL.md"
        t66_pad=$((t66_rule + 1 - $(wc -l < "$t66_root/SKILL.md")))
        for ((t66_j=0; t66_j<t66_pad; t66_j++)); do printf '\n' >> "$t66_root/SKILL.md"; done
        t66_load "$t66_root/SKILL.md"
        t66_explain_mut=$t66_loaded
        ;;
      *) t66_explain_mut="${t66_explain_mut/"$t66_rule"/}" ;;
    esac
    t66_mut_out=$(t66_explain_contract "$t66_explain_mut" "$t66_research_mut" \
      "$t66_readme_mut" "$t66_sh_mut" "$t66_ps1_mut" "$t66_usage_mut")
    if [ "$t66_mut_out" = " ${t66_labels[$t66_i]}" ]; then
      ok "T66 ${t66_kind} mutation: ${t66_labels[$t66_i]} rejected by its own check"
    else
      bad "T66 ${t66_kind} mutation: ${t66_labels[$t66_i]}" \
        "got '${t66_mut_out:-<empty>}', want ' ${t66_labels[$t66_i]}'"
    fi
  done
  rm -rf "$t66_root"
fi
[ -z "$t66_err" ] && ok "T66 static contract alarm: fc-explain explains from code evidence with readable Mermaid diagrams; wiki Usage entry, README release badge, banners, and 30-line budget pinned" \
                   || bad "T66 fc-explain explanation contract" "missing:$t66_err"
# A typed version goes stale on the next release (v5.2.1 sat in the README
# through v5.3.0); the release badge is the only version the README shows.
t66_typed=$(grep -noE '(^|[^0-9A-Za-z.])v[0-9]+[.][0-9]+[.][0-9]+' README.md wiki/*.md | head -3 | tr '\n' ' ')
[ -z "$t66_typed" ] && ok "T66 README and wiki show no typed version; the release badge is live" \
                    || bad "T66 README typed version" "found: $t66_typed"
# The README says MIT licensed; a LICENSE file and a badge must back the claim.
t66_lic=""
head -1 LICENSE 2>/dev/null | grep -qx 'MIT License' || t66_lic="$t66_lic license-file-missing"
grep -qF 'Permission is hereby granted, free of charge' LICENSE 2>/dev/null || t66_lic="$t66_lic mit-grant-missing"
sed -n 3p README.md | grep -qF '](LICENSE)' || t66_lic="$t66_lic readme-license-badge-missing"
[ -z "$t66_lic" ] && ok "T66 README's MIT claim is backed by LICENSE and a badge" \
                  || bad "T66 license" "missing:$t66_lic"

# ---------------------------------------------------------------- T34
# Reject obsolete track/pin language from active shipped content. Skill model
# pins in frontmatter are rejected separately by T71.
t34_err=""
stale_track=$(printf 'Tri%s' 'vial')
stale_track_files=$(git grep -l -w "$stale_track" -- README.md .claude/CLAUDE.md 'wiki/*.md' agents '*.sh' '*.ps1' '.github/workflows/*' 'skills/**' 2>/dev/null || true)
[ -z "$stale_track_files" ] || t34_err="$t34_err stale-track:$(echo "$stale_track_files" | tr '\n' ',')"
stale_pins=$(git grep -lE 'review (agents|roles).*(pinned|model: sonnet)|pinned to `?model: sonnet|review-family model|review family|different model family|session default model' -- \
  README.md .claude/CLAUDE.md 'wiki/*.md' agents install.sh install.ps1 '.github/workflows/*' 'skills/fc-build-or-fix/**' 'skills/fc-brainstorm/**' 'skills/fc-research/**' 'skills/fc-update/**' 2>/dev/null || true)
[ -z "$stale_pins" ] || t34_err="$t34_err stale-role-pin:$(echo "$stale_pins" | tr '\n' ',')"
[ -z "$t34_err" ] && ok "T34 no stale legacy-track or role-pin wording in active shipped content" \
                   || bad "T34 stale framework wording" "issues:$t34_err"

# ---------------------------------------------------------------- T55
# Runtime evidence and environment assumptions belong in the linked reference;
# unrelated mentions outside these sections must not satisfy the contract.
t55_err=""
provenance=skills/fc-build-or-fix/reference/gate-provenance.md
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
  echo "$families" | grep -qF 'Opus and GPT are the families in use; Sonnet and Haiku stay mapped so an older record still classifies.' \
    || t55_err="$t55_err families-in-use-missing"
  echo "$families" | grep -qF 'All four are separate families; any two are cross-family.' \
    || t55_err="$t55_err four-families-missing"
  echo "$families" | grep -qiE 'unmapped.*never qualifies for the review pair' \
    || t55_err="$t55_err unmapped-family-qualifies"
  echo "$record" | grep -qiE 'harness without this record.*own per-dispatch record.*unknown' \
    || t55_err="$t55_err other-harness-record-missing"
  # The pair is the agent's choice; no harness picker section remains (#57).
  grep -qF 'modelPicker' "$provenance" && t55_err="$t55_err stale-picker-section"
  echo "$families" | grep -qiE 'non-Claude id.*requires.*verified.*mapping|without.*(reliable|verified).*mapping.*unknown' \
    && t55_err="$t55_err verified-mapping-still-required"
  for assumption in 2.1.251 CLAUDE_CODE_SUBAGENT_MODEL_FORCE availableModels 'fallback chains' 'alias-remapping gateways'; do
    echo "$assumptions" | grep -qF "$assumption" \
      || t55_err="$t55_err missing-assumption:$assumption"
  done
  echo "$assumptions" | grep -qiE 'CLAUDE_CODE_SUBAGENT_MODEL_FORCE.*unset' \
    || t55_err="$t55_err force-unset-not-required"
  [ "$(printf '%s\n' "$assumptions" | grep -c '^- In Claude Code, require')" = 2 ] \
    || t55_err="$t55_err claude-code-prereqs-not-scoped"
  echo "$assumptions" | grep -qF 'If these Claude Code prerequisites cannot be verified, stop the gate' \
    || t55_err="$t55_err claude-code-prereqs-not-fail-closed"
else
  t55_err="$t55_err gate-provenance-missing"
fi
# Pin the caller's choice, not a fixed author family. Each call site must use
# the canonical default so a GPT session is not silently moved to Opus.
echo "$selector" | grep -qiE 'authoring dispatches.*explicit.*`model`.*default.*pair member in the session.s own family.*otherwise the first pair member.*unless the user chose another' \
  || t55_err="$t55_err session-authoring-alias-default-missing"
complex_flow=$(sed -n '/^## Flow/,/^## /p' skills/fc-build-or-fix/reference/complex-track.md)
architect_dispatch=$(echo "$complex_flow" | grep -E '^5\. ')
developer_dispatch=$(echo "$complex_flow" | grep -E '^8\. ')
synthesis_dispatch=$(sed -n '/^## Phase 2/,/^## /p' skills/fc-research/SKILL.md)
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
complex_example=$(sed -n '/^## Worked example/,/^## /p' skills/fc-build-or-fix/reference/complex-track.md)
echo "$complex_example" | grep -qE '^> .*fc-architect.*requested with `model: opus`' \
  || t55_err="$t55_err example-architect-changes-session-family"
echo "$complex_example" | grep -qE '^> .*Developers requested with `model: opus`' \
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
t55_build_text=$(cat skills/fc-build-or-fix/SKILL.md)
t55_refuter_text=$(cat skills/fc-second-opinion/SKILL.md)
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
research=skills/fc-research/SKILL.md
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
# The focused path drops the fan-out, never the safeguards: one pinned author,
# one selector-chosen validator, raw evidence, the shared suffix, the cap, and
# one revise cycle. Scope the clauses to the intro that chooses the path;
# removal mutations run only after the control passes and must each produce
# exactly their own diagnostic.
t56_focused_labels=(
  focused-author-model focused-raw-evidence focused-validator-selector
  focused-safeguards focused-broader-full-pipeline
)
t56_focused_rules=(
  'For one bounded question or angle, dispatch one author with an explicit `model` override from the authoring rule in `/fc-build-or-fix` to search and synthesize in the Phase 2 format; record its actual author model for the selector.'
  'The author returns raw evidence beside the synthesis: each claim with a concrete source (`file:line`, URL, or command output).'
  'One validator chosen by the canonical selector then checks both as in Phase 3: two dispatches.'
  'The Worker boundary suffix, the five-dispatch cap, and one revise cycle still apply.'
  'Broader questions keep the full pipeline below.'
)
t56_focused_contract() { # research text
  local intro i errors=""
  intro=$(printf '%s\n' "$1" | sed -n '/^# fc-research$/,/^## /p')
  for ((i=0; i<${#t56_focused_rules[@]}; i++)); do
    printf '%s\n' "$intro" | grep -qF "${t56_focused_rules[$i]}" \
      || errors="$errors ${t56_focused_labels[$i]}"
  done
  printf '%s\n' "$errors"
}
t56_research_text=$(cat "$research")
t56_focused_out=$(t56_focused_contract "$t56_research_text")
t56_err="$t56_err$t56_focused_out"
if [ -z "$t56_focused_out" ]; then
  for ((t56_i=0; t56_i<${#t56_focused_rules[@]}; t56_i++)); do
    t56_rule="${t56_focused_rules[$t56_i]}"
    t56_research_mut="${t56_research_text/"$t56_rule"/}"
    t56_mut_out=$(t56_focused_contract "$t56_research_mut")
    if [ "$t56_mut_out" = " ${t56_focused_labels[$t56_i]}" ]; then
      ok "T56 removal mutation: ${t56_focused_labels[$t56_i]} rejected by its own check"
    else
      bad "T56 removal mutation: ${t56_focused_labels[$t56_i]}" \
        "got '${t56_mut_out:-<empty>}', want ' ${t56_focused_labels[$t56_i]}'"
    fi
  done
fi
[ -z "$t56_err" ] && ok "T56 static contract alarm: research workers cannot delegate past the cap" \
                   || bad "T56 research dispatch boundary" "missing:$t56_err"

# ---------------------------------------------------------------- T57
# Tool frontmatter ends with the loading turn. The standalone skills promise a
# read-only policy, not shell-write isolation, and pin no model (issue #54).
t57_err=""
for skill in fc-review fc-second-opinion; do
  f="skills/$skill/SKILL.md"
  intro=$(sed -n "/^# $skill\$/,/^## /p" "$f")
  grep -qi 'by construction' "$f" && t57_err="$t57_err $skill:construction-claim"
  echo "$intro" | grep -qi 'read-only by policy' || t57_err="$t57_err $skill:policy-missing"
  echo "$intro" | grep -qiE 'frontmatter removes.*`Write`.*`Edit`.*`NotebookEdit`.*only for the turn that loads the skill' \
    || t57_err="$t57_err $skill:tool-restriction-lifetime-missing"
  echo "$intro" | grep -qiE '`model` override.*only for that turn' \
    && t57_err="$t57_err $skill:stale-model-override-claim"
  echo "$intro" | grep -qiE 'Bash and PowerShell.*write-capable' \
    || t57_err="$t57_err $skill:shell-write-limit-unacknowledged"
done
refute=$(sed -n '/^## 3 — Refute/,/^## /p' skills/fc-second-opinion/SKILL.md)
echo "$refute" | grep -qiE 'each refuter.*explicit.*`model` override.*selector.*`/fc-build-or-fix`' \
  || t57_err="$t57_err refuter-selector-override-missing"
# Review lenses carry their own model: an unpinned lens runs whatever the
# harness resolves, and an excluded lens must never read as PASS. Scope the
# clauses to the lens section; each removal mutation must produce exactly its
# own diagnostic, and runs only after the unmodified skill passes the control.
t57_lens_labels=(
  lens-always-dispatched lens-every-finding lens-inline-notes-same-session lens-selector-model
  lens-unknown-author-advisory lens-recorded-model-exclusion lens-zero-usable-unavailable
)
t57_lens_rules=(
  'Dispatch at least one lens subagent for every review, whatever the diff size; add parallel lenses when the diff is large.'
  'One lens per agent; each returns every finding that has a failure scenario, most severe first.'
  'Notes the main session writes itself are labeled same-session and never count as the independent review.'
  'Every lens dispatch carries an explicit `model` override chosen by the canonical selector in `/fc-build-or-fix` when the artifact has a known model author.'
  'For a human or unknown author, request the first review-pair member and label the review advisory with independence unverified.'
  'Read the recorded model of each lens as [gate-provenance.md](../fc-build-or-fix/reference/gate-provenance.md) describes and exclude any result with missing or unknown provenance or a model in the author family.'
  'Zero usable lenses makes the review unavailable, never PASS or an inline review.'
)
t57_lens_contract() { # review text
  local lenses i errors=""
  lenses=$(printf '%s\n' "$1" | sed -n '/^## 2 — Pick lenses/,/^## /p')
  for ((i=0; i<${#t57_lens_rules[@]}; i++)); do
    printf '%s\n' "$lenses" | grep -qF "${t57_lens_rules[$i]}" \
      || errors="$errors ${t57_lens_labels[$i]}"
  done
  # A one-clue lens would cap the uncapped report at one finding per lens.
  printf '%s\n' "$lenses" | grep -qi 'one-clue' && errors="$errors lens-one-clue-returned"
  # Issue #55: a size-gated dispatch let small diffs be reviewed inline, same-family.
  printf '%s\n' "$lenses" | grep -qF 'Run lenses as parallel subagents when the diff is large.' \
    && errors="$errors lens-size-gated-dispatch"
  printf '%s\n' "$errors"
}
t57_review_text=$(cat skills/fc-review/SKILL.md)
t57_lens_out=$(t57_lens_contract "$t57_review_text")
t57_err="$t57_err$t57_lens_out"
if [ -z "$t57_lens_out" ]; then
  for ((t57_i=0; t57_i<${#t57_lens_rules[@]}; t57_i++)); do
    t57_rule="${t57_lens_rules[$t57_i]}"
    t57_review_mut="${t57_review_text/"$t57_rule"/}"
    t57_mut_out=$(t57_lens_contract "$t57_review_mut")
    if [ "$t57_mut_out" = " ${t57_lens_labels[$t57_i]}" ]; then
      ok "T57 removal mutation: ${t57_lens_labels[$t57_i]} rejected by its own check"
    else
      bad "T57 removal mutation: ${t57_lens_labels[$t57_i]}" \
        "got '${t57_mut_out:-<empty>}', want ' ${t57_lens_labels[$t57_i]}'"
    fi
  done
fi
[ -z "$t57_err" ] && ok "T57 static contract alarm: honest read-only policy + explicit refuter and lens models" \
                   || bad "T57 standalone review policy contract" "missing:$t57_err"

# ---------------------------------------------------------------- T65
# Run discipline loads at entry and on resume. Each clause is checked inside
# its own section, so an unrelated mention elsewhere cannot satisfy it; each
# removal mutation must produce exactly its own diagnostic, and runs only after
# the unmodified documents pass the control.
t65_err=""
discipline=skills/fc-build-or-fix/reference/run-discipline.md
[ -f "$discipline" ] || t65_err="$t65_err run-discipline-missing"
t65_labels=(
  run-discipline-pointer
  feedback-checked-against-code-and-spec feedback-reproduce-before-fix feedback-reject-unsupported
  checkpoint-refresh-git-private checkpoint-contents checkpoint-resume-reconcile
  runtime-proof-executed runtime-proof-static-insufficient runtime-proof-unavailable-not-done
  runtime-proof-non-behavioral-na
)
t65_sections=(pointer feedback feedback feedback checkpoint checkpoint checkpoint runtime runtime runtime runtime)
t65_rules=(
  'Load [reference/run-discipline.md](reference/run-discipline.md) at entry and on resume.'
  'Check every incoming finding, such as QA results or PR comments, against the code and spec before acting on it.'
  'Reproduce a runnable failure before fixing it.'
  'Reject or defer an unsupported claim with a stated reason.'
  'After each task or gate transition, and before a requested handoff or compaction, refresh a checkpoint of at most 25 lines at `$(git rev-parse --git-path fc-checkpoint.md)`, which is git-private and worktree-local.'
  'Record worktree and HEAD, approvals, stage, next action, blockers, and evidence and provenance links.'
  'On resume, reconcile HEAD, status, and diff against it, and re-verify stale evidence.'
  'Changed user-visible behavior needs actual CLI/API execution or rendered interaction, with output or screenshot evidence.'
  'Existing end-to-end evidence counts; static or unit tests alone do not.'
  'If the runtime is unavailable, do not claim done.'
  'Non-behavioral changes state "N/A".'
)
t65_discipline_contract() { # build-or-fix text, run-discipline text
  local pointer feedback checkpoint runtime section i errors=""
  pointer=$(printf '%s\n' "$1" | sed -n '/^# fc-build-or-fix$/,/^## /p')
  feedback=$(printf '%s\n' "$2" | sed -n '/^## Feedback/,/^## /p')
  checkpoint=$(printf '%s\n' "$2" | sed -n '/^## Checkpoint/,/^## /p')
  runtime=$(printf '%s\n' "$2" | sed -n '/^## Runtime proof/,/^## /p')
  for ((i=0; i<${#t65_rules[@]}; i++)); do
    case "${t65_sections[$i]}" in
      pointer) section="$pointer" ;;
      feedback) section="$feedback" ;;
      checkpoint) section="$checkpoint" ;;
      runtime) section="$runtime" ;;
    esac
    printf '%s\n' "$section" | grep -qF "${t65_rules[$i]}" \
      || errors="$errors ${t65_labels[$i]}"
  done
  printf '%s\n' "$errors"
}
t65_build_text=$(cat skills/fc-build-or-fix/SKILL.md)
t65_discipline_text=$(cat "$discipline" 2>/dev/null)
t65_out=$(t65_discipline_contract "$t65_build_text" "$t65_discipline_text")
t65_err="$t65_err$t65_out"
if [ -z "$t65_err" ]; then
  for ((t65_i=0; t65_i<${#t65_rules[@]}; t65_i++)); do
    t65_rule="${t65_rules[$t65_i]}"
    t65_build_mut="$t65_build_text"
    t65_discipline_mut="$t65_discipline_text"
    case "${t65_sections[$t65_i]}" in
      pointer) t65_build_mut="${t65_build_mut/"$t65_rule"/}" ;;
      *) t65_discipline_mut="${t65_discipline_mut/"$t65_rule"/}" ;;
    esac
    t65_mut_out=$(t65_discipline_contract "$t65_build_mut" "$t65_discipline_mut")
    if [ "$t65_mut_out" = " ${t65_labels[$t65_i]}" ]; then
      ok "T65 removal mutation: ${t65_labels[$t65_i]} rejected by its own check"
    else
      bad "T65 removal mutation: ${t65_labels[$t65_i]}" \
        "got '${t65_mut_out:-<empty>}', want ' ${t65_labels[$t65_i]}'"
    fi
  done
fi
[ -z "$t65_err" ] && ok "T65 static contract alarm: feedback checks, resumable checkpoints, runtime proof" \
                   || bad "T65 run-discipline contract" "missing:$t65_err"

# ---------------------------------------------------------------- T70
# v5.2.1 prompt audit: QA and review reports list every blocking finding,
# worker length caps become guidance, cost telemetry records dispatch tokens
# and recorded models, and routing descriptions say when not to use a role.
# Section-scoped like T61: each clause counts only in its own section, the
# wording it replaced must stay gone, and after the unmodified documents pass,
# removing one clause must produce exactly its own diagnostic.
t70_err=""
t70_doc_bof=skills/fc-build-or-fix/SKILL.md
t70_doc_qacode=agents/fc-qa-code.md
t70_doc_qaspec=agents/fc-qa-spec.md
t70_doc_review=skills/fc-review/SKILL.md
t70_doc_research=skills/fc-research/SKILL.md
t70_doc_brainstorm=skills/fc-brainstorm/SKILL.md
t70_doc_complex=skills/fc-build-or-fix/reference/complex-track.md
t70_doc_meta=skills/fc-build-or-fix/reference/meta-work-cap.md
t70_doc_grill=skills/fc-grill-me/SKILL.md
t70_doc_lead=agents/fc-tech-lead.md
t70_doc_architect=agents/fc-architect.md
t70_doc_pm=agents/fc-pm.md
t70_doc_developer=agents/fc-developer.md
t70_docs=(bof qacode qaspec review research brainstorm complex meta grill lead architect pm developer)
# label|doc|section start|section end|clause
t70_rules=(
  'bof-description-routes|bof|^name: fc-build-or-fix$|^---$|Do NOT use for an open question whose primary need is facts (look them up, or use /fc-research), an approach (use /fc-brainstorm), or review of an artifact this pipeline did not produce (use /fc-review).'
  'qa-verdict-lists-blockers|bof|^## One-clue mode$|^## |List every blocking finding, each CRITICAL and each unmet or untested requirement, because each one blocks on its own; otherwise report the single most material finding.'
  'qa-code-lists-blockers|qacode|^## Report format$|^## |List every CRITICAL finding and, on Standard, every spec gap, one block each: each blocks on its own.'
  'qa-spec-lists-violations|qaspec|^## Report format$|^## |List every violated or untested requirement, one block each: each one blocks the gate on its own, and nothing collects deferred findings.'
  'review-reports-every-finding|review|^## 3 — Report$|^## |Report every finding that has a failure scenario; keep lower-severity ones to one line each.'
  'research-worker-no-padding|research|^## Phase 1|^## |Do not synthesize, do not recommend. If a search returns nothing relevant, say so explicitly rather than padding.'
  'research-synthesis-concise|research|^## Phase 2|^## |Surface disagreements between inputs rather than averaging them. Keep it concise.'
  'brainstorm-comparable-length|brainstorm|^## 2 — Panel$|^## |argue your stance. Keep it short enough to compare side by side.'
  'cost-line|bof|^## Cost telemetry$|^## |Standard and Complex append `Cost: <N> dispatches, ~<T> dispatch tokens, ~<M> min wall-clock, models: <recorded models>` to the PR description'
  'cost-tokens-once-per-message-id|bof|^## Cost telemetry$|^## |Sum `.message.usage` tokens once per unique `.message.id` in each dispatch record'
  'cost-unknown-usage|bof|^## Cost telemetry$|^## |write `?` for `<T>` when a record has no usage.'
  'cost-recorded-models|bof|^## Cost telemetry$|^## |Name the models those records show, not the requested aliases.'
  'complex-cost-pointer|complex|^## Flow$|^## |Append the `Cost:` line defined in `/fc-build-or-fix` to the PR description.'
  'research-cost-line|research|^## Output$|^## |Cost: <N> dispatches, ~<T> dispatch tokens, ~<M> min wall-clock, models: <recorded models>'
  'complex-example-family-note|complex|^## Worked example$|^## |In Claude Code the same rules request `model: opus` for authoring and `model: sonnet` for review; a relay may route `sonnet` to GPT-6 Astra, and the records decide the families.'
  'complex-example-cost|complex|^## Worked example$|^## |`Cost: 17 dispatches, ~30M dispatch tokens, ~3h wall-clock, models: Opus + GPT (recorded)`'
  'meta-cap-every-skill|meta|^## Numeric caps$|^## |not a named list, so a new skill cannot add orchestration text outside the cap.'
  'grill-user-owned-scope|grill|^# fc-grill-me$|^## |Interview the user about each user-owned decision this work depends on until you reach a shared understanding.'
  'lead-approve-quickly|lead|^## Rules$|^## |- If the work is genuinely good, approve quickly.'
  'architect-project-tests|architect|^## Phase 1|^## |define the test before the implementation, using the kinds of test the project already runs where they fit.'
  'pm-main-session-only|pm|^---$|^---$|role for the main session: selects Just Do It/Standard/Complex and runs /fc-build-or-fix. Never dispatch it as a subagent'
  'architect-when-not|architect|^---$|^---$|Dispatched by /fc-build-or-fix with the spec inline; not for ad-hoc design questions.'
  'developer-when-not|developer|^---$|^---$|Dispatched by /fc-build-or-fix with the task text inline; not for open-ended coding requests.'
  'qa-spec-when-not|qaspec|^---$|^---$|(one-clue mode). Dispatched by /fc-build-or-fix at a hard gate; for ad-hoc review use /fc-review.'
  'qa-code-when-not|qacode|^---$|^---$|quality only on Complex. Dispatched by /fc-build-or-fix at a hard gate; for ad-hoc review use /fc-review.'
  'lead-when-not|lead|^---$|^---$|before merge. Dispatched by /fc-build-or-fix; for ad-hoc review use /fc-review.'
)
# label|doc|replaced wording that must stay absent from the whole document
t70_stale=(
  'bof-one-finding|bof|One finding, not a list.'
  'bof-selected-overrides|bof|<selected overrides>'
  'bof-route-with-classifier|bof|route that need with the classifier below'
  'qa-code-one-only|qacode|Finding (one only'
  'qa-code-one-finding|qacode|One finding. No strengths section'
  'qa-spec-one-only|qaspec|Finding (one only'
  'qa-spec-save-for-later|qaspec|save the rest for follow-up'
  'review-top-five|review|Cap the report at the top'
  'review-dropped-count|review|how many you dropped'
  'research-worker-cap|research|Cap 400 words'
  'research-synthesis-cap|research|≤600 words'
  'research-models-list|research|models: <list>'
  'brainstorm-word-cap|brainstorm|≤300 words'
  'complex-selected-aliases|complex|exact selected aliases'
  'complex-history|complex|for two versions and five reviewers'
  'meta-history|meta|An earlier version named only two files'
  'grill-booster|grill|Interview the user relentlessly'
  'lead-booster|lead|Thorough but pragmatic'
  'architect-test-catalog|architect|UI → component tests'
  'pm-orchestrates|pm|and orchestrates the pipeline.'
)
t70_contract() { # root holding the t70_doc_* paths
  local entry label doc from to text path section errors=""
  for entry in "${t70_rules[@]}"; do
    IFS='|' read -r label doc from to text <<< "$entry"
    path="t70_doc_$doc"
    section=$(sed -n "/$from/,/$to/p" "$1/${!path}" 2>/dev/null)
    [[ "$section" == *"$text"* ]] || errors="$errors $label"
  done
  for entry in "${t70_stale[@]}"; do
    IFS='|' read -r label doc text <<< "$entry"
    path="t70_doc_$doc"
    grep -qF -- "$text" "$1/${!path}" 2>/dev/null && errors="$errors stale:$label"
  done
  printf '%s\n' "$errors"
}
t70_out=$(t70_contract .)
t70_err="$t70_err$t70_out"
if [ -z "$t70_err" ]; then
  t70_mut=$(mktemp -d)
  CLEANUP_PATHS+=("$t70_mut")
  for t70_doc in "${t70_docs[@]}"; do
    t70_path="t70_doc_$t70_doc"
    mkdir -p "$t70_mut/$(dirname "${!t70_path}")" && cp "${!t70_path}" "$t70_mut/${!t70_path}"
  done
  for t70_entry in "${t70_rules[@]}"; do
    IFS='|' read -r t70_label t70_doc t70_from t70_to t70_text <<< "$t70_entry"
    t70_path="t70_doc_$t70_doc"
    t70_orig=$(cat "${!t70_path}")
    printf '%s\n' "${t70_orig/"$t70_text"/}" > "$t70_mut/${!t70_path}"
    t70_mut_out=$(t70_contract "$t70_mut")
    cp "${!t70_path}" "$t70_mut/${!t70_path}"
    if [ "$t70_mut_out" = " $t70_label" ]; then
      ok "T70 removal mutation: $t70_label rejected by its own check"
    else
      bad "T70 removal mutation: $t70_label" "got '${t70_mut_out:-<empty>}', want ' $t70_label'"
    fi
  done
fi
[ -z "$t70_err" ] && ok "T70 static contract alarm: v5.2.1 prompt-audit clauses pinned, replaced wording absent" \
                   || bad "T70 prompt-audit contract" "missing:$t70_err"

# ------------------------------------------------------ installer helpers
# Scratch space for installer runs. PowerShell runs with an emptied PATH, so a
# Git Bash on the machine cannot silently replace the native engine. A strict
# profile proves the current installer works under the user's strict mode.
installer_root=$(mktemp -d)
CLEANUP_PATHS+=("$installer_root")
installer_repo=$(pwd)
installer_bash=$(command -v bash)
PWSH_BIN="${PWSH:-$(command -v pwsh 2>/dev/null || true)}"
if [ -n "$PWSH_BIN" ] && [ -x "$PWSH_BIN" ]; then
  PWSH_BIN="$(cd "$(dirname "$PWSH_BIN")" && pwd)/$(basename "$PWSH_BIN")"
fi
mkdir -p "$installer_root/home/.config/powershell" "$installer_root/empty-path"
printf 'Set-StrictMode -Version Latest\n' > "$installer_root/home/.config/powershell/Microsoft.PowerShell_profile.ps1"
INSTALLERS=(sh)
if [ -n "$PWSH_BIN" ] && [ -x "$PWSH_BIN" ]; then
  INSTALLERS+=(ps1)
fi
if command -v sha256sum >/dev/null 2>&1; then
  installer_hash=(sha256sum)
else
  installer_hash=(shasum -a 256)
fi
installer_result() {
  [ -z "$case_err" ] && ok "$1" || bad "$1" "issues:$case_err"
}

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

# ---------------------------------------------------------------- T53
# fc-update drives each CLI's own plugin commands; it never copies files and
# never deletes anything. Pin each command and rule as a literal sentence in
# its Flow; removing any one must fail with its own label.
t53_labels=(
  only-where-installed claude-update copilot-update version-reported
  legacy-reported user-migrates reload errors-stop
)
t53_rules=(
  'Run `claude plugin list --json` and `copilot plugin list --json` for each CLI on PATH; update only where `feature-crew` is installed.'
  'Claude Code: run `claude plugin marketplace update feature-crew`, then `claude plugin update feature-crew@feature-crew`.'
  'Copilot CLI: run `copilot plugin marketplace update feature-crew`, then `copilot plugin update feature-crew@feature-crew`.'
  'List the plugins again and report the installed version for each CLI.'
  'Run `./install.sh --check` from a Feature-Crew clone; it only reads and reports any old script install, which shadows the plugin.'
  'If it reports old files, tell the user to run `./install.sh --dry-run`, then `./install.sh`, themselves; this skill never runs them.'
  'Remind the user to start a new session, or run `/reload-plugins` in Claude Code.'
  'Any error stops the flow; report the command and its output.'
)
t53_contract() { # SKILL.md text
  local flow i errors=""
  flow=$(printf '%s\n' "$1" | sed -n '/^## Flow$/,/^## /p')
  for ((i=0; i<${#t53_rules[@]}; i++)); do
    case "$flow" in
      *"${t53_rules[$i]}"*) ;;
      *) errors="$errors ${t53_labels[$i]}" ;;
    esac
  done
  printf '%s\n' "$errors"
}
case_err=""
s=skills/fc-update/SKILL.md
t53_text=$(cat "$s")
t53_out=$(t53_contract "$t53_text")
case_err="$case_err$t53_out"
# The copy installer's flow is gone; a leftover step would run removed flags.
grep -qE -- '--force|--verify|git pull' "$s" && case_err="$case_err copy-installer-flow-returned"
# fc-update never deletes; the migration installer does, so only the user runs it.
grep -qE '(^|[0-9]\. )(Run|run) `\./install\.sh( --dry-run)?`' "$s" && case_err="$case_err fc-update-runs-installer"
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
installer_result "T53 fc-update updates through each CLI's plugin commands and only reports old files"

# ---------------------------------------------------------------- T54
case_err=""
t54_install=$(sed -n '/^## Install$/,/^## /p' wiki/Usage.md)
for t54_cmd in 'claude plugin marketplace add D0n9X1n/feature-crew' 'claude plugin install feature-crew@feature-crew' \
    'copilot plugin marketplace add D0n9X1n/feature-crew' 'copilot plugin install feature-crew@feature-crew'; do
  case "$t54_install" in *"$t54_cmd"*) ;; *) case_err="$case_err usage-install-missing:${t54_cmd// /_}" ;; esac
  grep -qF "$t54_cmd" README.md || case_err="$case_err readme-missing:${t54_cmd// /_}"
done
sed -n '/^## Updating$/,/^## /p' wiki/Usage.md | grep -qF '/fc-update' || case_err="$case_err update-section-does-not-name-fc-update"
t54_heads=$(grep -E '^#{1,6} ' README.md | tr '\n' '|')
[ "$t54_heads" = "# Feature-Crew|## Quick start|## Features|" ] || case_err="$case_err README-headings=$t54_heads"
count=$(wc -l < README.md | tr -d ' ')
[ "$count" -le 40 ] || case_err="$case_err README-lines=$count(want<=40)"
grep -qF 'https://github.com/D0n9X1n/feature-crew/wiki' README.md || case_err="$case_err README-no-wiki-link"
t54_stale=$(grep -nE '`--force`|`--verify`|feature-crew\.sha256|install manifest|Copy agents|adding frontmatter|复制代理|check, force, verify|hash manifest|clean.prefix|check、force、verify|哈希清单|干净前缀' wiki/*.md | head -3 | tr '\n' ' ')
[ -z "$t54_stale" ] || case_err="$case_err wiki-describes-copy-installer:$t54_stale"
installer_result "T54 README and wiki Usage install through each CLI's plugin commands; README keeps only an introduction, quick start, and features"

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
t64_ship=skills/fc-ship/SKILL.md

# T9 replay: an untouched scratch copy passes; removing either clause from the
# fc-ship description is reported for fc-ship alone. A no-op mutation is a
# setup failure, not a rejection.
case_err=""
mkdir -p "$t64_root/skills" && cp -R skills/. "$t64_root/skills/"
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
  cleanup-mandatory cleanup-handoff
  build-or-fix-hands-off readme-direct-command readme-skill-count banner-sh banner-ps1
)
t64_sections=(auth auth watch watch watch outcome outcome outcome outcome outcome
  failure failure failure merge merge merge merge merge merge merge merge release release
  cleanup cleanup standard commands layout sh ps1)
t64_rules=(
  'Commit, push, PR, merge, and tag/publish are separate authorizations; none implies another.'
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
  'If it still differs: stop and report; the goal is unfinished, so do not clean up.'
  'Release only when approved:'
  'tag the verified base commit, push the tag last, watch the release run in the background (`gh run watch <id> --exit-status`), and verify the published body.'
  'Cleanup is mandatory when shipping ends.'
  'Once the goal is achieved, finish with `/fc-clean`; until then, keep the receipts.'
  '9. Commit only when authorized; use a feature branch, then continue with `/fc-ship`.'
  '`/fc-ship`'
  "# ${t64_count_word} skills"
  '/fc-ship'
  '/fc-ship'
)
t64_contract() { # fc-ship, build-or-fix, wiki Usage and Development-and-Release, install.sh, install.ps1 text
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
t64_build_text=$(cat skills/fc-build-or-fix/SKILL.md)
t64_readme_text=$(cat wiki/Usage.md wiki/Development-and-Release.md 2>/dev/null)
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

# ---------------------------------------------------------------- T73
# Feature-Crew ships as one plugin that Claude Code and Copilot CLI both read
# from .claude-plugin/. plugin.json owns the version, and a release tag must
# equal it: an unchanged version blocks the plugin cache from refreshing.
# Every shipped name keeps the fc- prefix, so a reader knows the plugin is the
# one running; agents register as feature-crew:<name>, so every dispatch names
# the qualified agent while skills keep their bare names.
if ! command -v python3 >/dev/null 2>&1; then
  skip "T73 plugin package (python3 unavailable)"
elif t73_out=$(python3 - <<'PY'
import json, os, re, pathlib
errs = []
def load(p):
    try:
        return json.loads(pathlib.Path(p).read_text())
    except Exception:
        errs.append(f"{p}:unreadable"); return {}
plugin = load(".claude-plugin/plugin.json")
market = load(".claude-plugin/marketplace.json")
if plugin.get("name") != "feature-crew": errs.append("plugin-name")
if not re.fullmatch(r"\d+\.\d+\.\d+", str(plugin.get("version", ""))): errs.append("plugin-version-not-semver")
if not (plugin.get("author") or {}).get("name"): errs.append("plugin-author")
if plugin.get("repository") != "https://github.com/D0n9X1n/feature-crew": errs.append("plugin-repository")
if plugin.get("license") != "MIT": errs.append("plugin-license")
for key in ("skills", "agents", "commands"):
    if key in plugin: errs.append(f"plugin-overrides-default-{key}-path")
if market.get("name") != "feature-crew": errs.append("marketplace-name")
if not (market.get("owner") or {}).get("name"): errs.append("marketplace-owner")
entries = market.get("plugins") or []
if len(entries) != 1: errs.append("marketplace-entries")
else:
    e = entries[0]
    if e.get("name") != "feature-crew": errs.append("marketplace-entry-name")
    if e.get("source") != "./": errs.append("marketplace-entry-source")
    if "version" in e: errs.append("marketplace-entry-duplicates-version")
for d in sorted(n for n in os.listdir("skills") if not n.startswith(".")):
    if not d.startswith("fc-"): errs.append(f"skill-unprefixed:{d}")
    sk = pathlib.Path("skills", d, "SKILL.md")
    if not sk.is_file(): errs.append(f"skill-no-SKILL.md:{d}"); continue
    m = re.search(r"^name: (.+)$", sk.read_text(), re.M)
    if not m or m.group(1).strip() != d: errs.append(f"skill-name-mismatch:{d}")
for f in sorted(n for n in os.listdir("agents") if not n.startswith(".")):
    if not f.startswith("fc-"): errs.append(f"agent-unprefixed:{f}")
roles = "architect|developer|qa-spec|qa-code|tech-lead"
bare = re.compile(r"`fc-(%s)`" % roles)
for line in pathlib.Path("skills/fc-build-or-fix/SKILL.md").read_text().splitlines():
    if re.search(r"[Dd]ispatch", line) and bare.search(line): errs.append("bare-dispatch-in-build-or-fix")
flow = re.search(r"^## Flow\n(.*?)^## ", pathlib.Path("skills/fc-build-or-fix/reference/complex-track.md").read_text(), re.S | re.M)
if not flow or bare.search(flow.group(1)): errs.append("bare-role-in-complex-flow")
for role in roles.split("|"):
    if not flow or f"`feature-crew:fc-{role}`" not in flow.group(1): errs.append(f"complex-flow-unqualified:{role}")
if "`feature-crew:fc-qa-code`" not in pathlib.Path("skills/fc-build-or-fix/SKILL.md").read_text():
    errs.append("standard-qa-unqualified")
test_yml = pathlib.Path(".github/workflows/test.yml").read_text()
if not re.search(r"npm install -g @anthropic-ai/claude-code@\d+\.\d+\.\d+", test_yml): errs.append("ci-claude-cli-not-pinned")
if "claude plugin validate . --strict" not in test_yml: errs.append("ci-no-plugin-validate")
release = pathlib.Path(".github/workflows/release.yml").read_text()
if 'scripts/check-release-version.sh "$GITHUB_REF_NAME"' not in release: errs.append("release-no-version-check")
print(" ".join(errs))
PY
) && [ -z "$t73_out" ]; then
  ok "T73 one feature-crew plugin with its marketplace, fc- names, qualified agent dispatch, CI validate"
else
  bad "T73 plugin package" "issues:${t73_out:-python-failed}"
fi
case_err=""
t73_version=$(python3 -c 'import json;print(json.load(open(".claude-plugin/plugin.json"))["version"])' 2>/dev/null)
if [ -z "$t73_version" ]; then
  case_err="$case_err no-version"
else
  bash scripts/check-release-version.sh "v$t73_version" >/dev/null 2>&1 || case_err="$case_err matching-tag-rejected"
  bash scripts/check-release-version.sh "v0.0.0-not-$t73_version" >/dev/null 2>&1 && case_err="$case_err mismatched-tag-accepted"
  bash scripts/check-release-version.sh "$t73_version" >/dev/null 2>&1 && case_err="$case_err tag-without-v-accepted"
fi
installer_result "T73 release version check accepts only v + plugin.json version"

# ---------------------------------------------------------------- T74
# On Copilot CLI the gate reads ~/.copilot/session-state/<session>/events.jsonl.
# Run the reference's own two queries against fixtures: the first must list
# every model that answered one dispatch, the second must expose any task or
# skill call made inside it, and neither may pick up another dispatch's events.
case_err=""
t74_doc=skills/fc-build-or-fix/reference/gate-provenance.md
t74_section=$(sed -n '/^## Copilot CLI record$/,/^## /p' "$t74_doc")
for t74_phrase in '~/.copilot/session-state/<session>/events.jsonl' 'GATE UNSATISFIED' 'totalTokens' '`model`' \
    'A missing or unreadable file' 'no `subagent.completed` event for the dispatch' 'an `UNKNOWN` model'; do
  case "$t74_section" in *"$t74_phrase"*) ;; *) case_err="$case_err missing-phrase:$t74_phrase" ;; esac
done
t74_models=$(printf '%s\n' "$t74_section" | grep -E '^jq -r --arg call ' | sed -n 1p)
t74_nested=$(printf '%s\n' "$t74_section" | grep -E '^jq -r --arg call ' | sed -n 2p)
t74_done=$(printf '%s\n' "$t74_section" | grep -E '^jq -r --arg call ' | sed -n 3p)
[ -n "$t74_models" ] && [ -n "$t74_nested" ] && [ -n "$t74_done" ] || case_err="$case_err queries-missing"
if ! command -v jq >/dev/null 2>&1; then
  skip "T74 Copilot record queries (jq unavailable)"
elif [ -n "$t74_models" ] && [ -n "$t74_nested" ] && [ -n "$t74_done" ]; then
  t74_dir=$(mktemp -d); CLEANUP_PATHS+=("$t74_dir")
  ev() { printf '%s\n' "$1" >> "$t74_dir/$2"; }
  for f in clean fallback delegated unknown incomplete; do
    ev '{"type":"tool.execution_start","data":{"toolCallId":"call_R","toolName":"task","model":"claude-opus-5.5"}}' "$f"
    ev '{"type":"subagent.started","data":{"toolCallId":"call_R","agentName":"feature-crew:fc-qa-code","model":"gpt-6-astra"}}' "$f"
    ev '{"type":"assistant.message","data":{"parentToolCallId":"call_R","model":"gpt-6-astra"}}' "$f"
    ev '{"type":"assistant.message","data":{"model":"claude-opus-5.5"}}' "$f"
    ev '{"type":"subagent.started","data":{"toolCallId":"call_OTHER","agentName":"general-purpose","model":"claude-sonnet-5"}}' "$f"
    ev '{"type":"tool.execution_start","data":{"toolCallId":"call_X","toolName":"task","parentToolCallId":"call_OTHER"}}' "$f"
  done
  ev '{"type":"assistant.message","data":{"parentToolCallId":"call_R","model":"claude-haiku-4.5"}}' fallback
  ev '{"type":"tool.execution_start","data":{"toolCallId":"call_N","toolName":"task","parentToolCallId":"call_R"}}' delegated
  ev '{"type":"tool.execution_start","data":{"toolCallId":"call_S","toolName":"skill","parentToolCallId":"call_R"}}' delegated
  ev '{"type":"assistant.message","data":{"parentToolCallId":"call_R"}}' unknown
  for f in clean fallback delegated unknown; do
    ev '{"type":"subagent.completed","data":{"toolCallId":"call_R","model":"gpt-6-astra","totalTokens":1200}}' "$f"
  done
  t74_run() { # query, fixture
    local call=call_R events="$t74_dir/$2"
    eval "$1" 2>&1 | tr '\n' ' ' | sed 's/ $//'
  }
  [ "$(t74_run "$t74_models" clean)" = 'gpt-6-astra' ] || case_err="$case_err clean-models:'$(t74_run "$t74_models" clean)'"
  [ "$(t74_run "$t74_models" fallback)" = 'claude-haiku-4.5 gpt-6-astra' ] || case_err="$case_err fallback-models:'$(t74_run "$t74_models" fallback)'"
  [ -z "$(t74_run "$t74_nested" clean)" ] || case_err="$case_err clean-nested:'$(t74_run "$t74_nested" clean)'"
  [ "$(t74_run "$t74_nested" delegated)" = 'task skill' ] || case_err="$case_err delegated-nested:'$(t74_run "$t74_nested" delegated)'"
  # Fail closed: an unknown model is visible, and a missing completion or file proves nothing.
  case " $(t74_run "$t74_models" unknown) " in *' UNKNOWN '*) ;; *) case_err="$case_err unknown-model-hidden" ;; esac
  [ "$(t74_run "$t74_done" clean)" = call_R ] || case_err="$case_err completed-not-found:'$(t74_run "$t74_done" clean)'"
  [ -z "$(t74_run "$t74_done" incomplete)" ] || case_err="$case_err incomplete-reads-completed"
  case "$(t74_run "$t74_done" missing)" in *call_R*) case_err="$case_err missing-file-reads-completed" ;; esac
  case "$(t74_run "$t74_models" missing)" in *gpt-*|*claude-*) case_err="$case_err missing-file-reads-a-model" ;; esac
fi
installer_result "T74 Copilot record queries list every model of one dispatch, expose nested task or skill calls, and fail closed"

# ---------------------------------------------------------------- T76
# The installers install the plugin through each CLI found on PATH, then
# remove the old script install: every fc-era path even when edited (the
# user's decision; edited copies would shadow the plugin's bare skill names),
# and pre-fc files only when published.sha256 proves them ours. Stub CLIs
# record every call and keep marketplace/plugin state in files, so no real CLI
# or network is touched. Both engines must print the same lines.
t76_root="$installer_root/t76"
mkdir -p "$t76_root/stub"
cp tests/stub-cli "$t76_root/stub/cli"
chmod +x "$t76_root/stub/cli"
t76_run() { # engine, clis(both|claude|none), prefix, flags...
  local engine="$1" clis="$2" prefix="$3" bin="$t76_root/bin-$2"; shift 3
  if [ ! -d "$bin" ]; then
    mkdir -p "$bin"
    case "$clis" in both) cp "$t76_root/stub/cli" "$bin/claude"; cp "$t76_root/stub/cli" "$bin/copilot" ;;
      claude) cp "$t76_root/stub/cli" "$bin/claude" ;; esac
  fi
  if [ "$engine" = sh ]; then
    env -i HOME="$installer_root/home" PATH="$bin:/usr/bin:/bin" FC_STUB_STATE="$t76_state" FC_STUB_FAIL="${t76_fail:-}" FC_STUB_GHOST="${t76_ghost:-}" FC_STUB_LOCK="${t76_stub_lock:-}" FC_STUB_HIDE="${t76_stub_hide:-}" \
      "$installer_bash" "$installer_repo/install.sh" --prefix "$prefix" "$@" > "$t76_root/out" 2> "$t76_root/err"
  else
    env -i HOME="$installer_root/home" PATH="$bin" FC_STUB_STATE="$t76_state" FC_STUB_FAIL="${t76_fail:-}" FC_STUB_GHOST="${t76_ghost:-}" FC_STUB_LOCK="${t76_stub_lock:-}" FC_STUB_HIDE="${t76_stub_hide:-}" \
      POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off \
      "$PWSH_BIN" -NonInteractive -File "$installer_repo/install.ps1" --prefix "$prefix" "$@" > "$t76_root/out" 2> "$t76_root/err"
  fi
  t76_rc=$?
  t76_out=$(sed "s#$prefix#<P>#g" "$t76_root/out")
  t76_err=$(sed "s#$prefix#<P>#g" "$t76_root/err")
  t76_calls=$(cat "$t76_state/calls" 2>/dev/null)
}
t76_seed() { # prefix: v5.3.1 then v3.1 installed by their own installers, plus edits
  local t
  if [ ! -d "$t76_root/seed" ]; then
    for t in v5.3.1 v3.1; do
      mkdir -p "$t76_root/src/$t" && git -c core.autocrlf=false archive "$t" | tar -x -C "$t76_root/src/$t" || return 1
      HOME="$installer_root/home" "$installer_bash" "$t76_root/src/$t/install.sh" --prefix "$t76_root/seed" --force \
        > "$t76_root/seed.log" 2>&1 || return 1
    done
    printf '\nMY EDIT\n' >> "$t76_root/seed/skills/fc-update/SKILL.md"
    printf 'my notes\n' > "$t76_root/seed/skills/fc-review/notes.md"
    printf '\nMY EDIT\n' >> "$t76_root/seed/agents/feature-crew/pm.md"
    printf 'my sources\n' > "$t76_root/seed/skills/research/sources.md"
    awk '{ printf "%s\r\n", $0 }' "$t76_root/seed/skills/build-or-fix/SKILL.md" > "$t76_root/crlf" \
      && mv "$t76_root/crlf" "$t76_root/seed/skills/build-or-fix/SKILL.md"
    printf 'my own agent\n' > "$t76_root/seed/agents/pm.md"
    mkdir -p "$t76_root/seed/skills/fc-mine" && printf 'mine\n' > "$t76_root/seed/skills/fc-mine/SKILL.md"
    mkdir -p "$t76_root/seed/skills/research/empty-notes"
  fi
  rm -rf "$1" && cp -R "$t76_root/seed" "$1"
}
t76_tree() { (cd "$1" 2>/dev/null && find . \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r f; do
  printf '%s %s\n' "$("${installer_hash[@]}" < "$f" | cut -d' ' -f1)" "$f"; done); }
t76_left=$'./agents/feature-crew/pm.md\n./agents/pm.md\n./skills/fc-mine/SKILL.md\n./skills/research/sources.md'
T76_FC_AGENTS=(fc-architect fc-developer fc-pm fc-qa-code fc-qa-spec fc-tech-lead)
T76_FC_SKILLS=(fc-brainstorm fc-build-or-fix fc-debug fc-explain fc-grill-me fc-research fc-review fc-second-opinion fc-ship fc-update)
t76_removals() { # verb: removed | would remove | old file
  local v="$1" n
  for n in "${T76_FC_AGENTS[@]}"; do printf '%s: <P>/agents/%s.md\n' "$v" "$n"; done
  for n in "${T76_FC_SKILLS[@]}"; do printf '%s: <P>/skills/%s\n' "$v" "$n"; done
  printf '%s: <P>/feature-crew.sha256\n' "$v"
  for n in architect developer qa-code-reviewer qa-spec-reviewer tech-lead; do printf '%s: <P>/agents/feature-crew/%s.md\n' "$v" "$n"; done
  printf '%s: <P>/skills/build-or-fix/SKILL.md\n%s: <P>/skills/research/SKILL.md\n' "$v" "$v"
  # A folder goes only when this run empties it; check mode reports files only.
  [ "$v" = 'old file' ] || printf '%s: <P>/skills/build-or-fix\n' "$v"
}
t76_kept() { printf 'kept (not ours): <P>/agents/feature-crew/pm.md\nkept (not ours): <P>/skills/research/sources.md\n'; }
t76_sc() { [ "$1" != claude ] || printf ' --scope user'; } # Claude commands act on the user scope only
t76_steps() { # mode: fresh|rerun|dry, clis...
  local mode="$1" c; shift
  for c in "$@"; do
    case "$mode" in
      fresh) printf 'run: %s plugin marketplace add D0n9X1n/feature-crew%s\nstub: marketplace added\n' "$c" "$(t76_sc "$c")"
             printf 'run: %s plugin install feature-crew@feature-crew%s\nstub: plugin installed\n' "$c" "$(t76_sc "$c")" ;;
      rerun) printf 'run: %s plugin marketplace update feature-crew\nstub: marketplace updated\n' "$c"
             printf 'run: %s plugin update feature-crew@feature-crew%s\nstub: plugin updated\n' "$c" "$(t76_sc "$c")" ;;
      dry)   printf 'would run: %s plugin marketplace add D0n9X1n/feature-crew%s\n' "$c" "$(t76_sc "$c")"
             printf 'would run: %s plugin install feature-crew@feature-crew%s\n' "$c" "$(t76_sc "$c")" ;;
    esac
  done
}
t76_banner=$'Done. Start a new Claude Code or Copilot CLI session to load the plugin.\nDescribe your need naturally in any project; slash commands are optional.\nAvailable: /fc-build-or-fix, /fc-brainstorm, /fc-clean, /fc-debug, /fc-explain, /fc-grill-me,\n/fc-research, /fc-review, /fc-second-opinion, /fc-ship, /fc-update - or delegate to an fc-* subagent.'
t76_head() { printf 'feature-crew: plugin source D0n9X1n/feature-crew; old install at <P>\n'; }
t76_expect() { # label, want-rc, want-out
  [ "$t76_rc" = "$2" ] || case_err="$case_err $1:rc=$t76_rc(want-$2):$(printf '%s' "$t76_err" | tail -1)"
  [ "$t76_out" = "$3" ] || case_err="$case_err $1:out-differs"$'\n'"--- want"$'\n'"$3"$'\n'"--- got"$'\n'"$t76_out"$'\n'
}
for engine in "${INSTALLERS[@]}"; do
  case_err=""
  p="$t76_root/$engine/p"

  # Fresh: no old install, both CLIs present; then a rerun updates.
  t76_state="$t76_root/$engine/state-fresh"; rm -rf "$t76_state" "$p"
  t76_run "$engine" both "$p"
  t76_expect fresh 0 "$(t76_head; t76_steps fresh claude copilot; printf '%s' "$t76_banner")"
  [ "$t76_calls" = "$(printf '%s\n' 'claude plugin marketplace list --json' \
    'claude plugin list --json' \
    'claude plugin marketplace add D0n9X1n/feature-crew --scope user' \
    'claude plugin list --json' \
    'claude plugin install feature-crew@feature-crew --scope user' \
    'claude plugin list --json' \
    'copilot plugin marketplace list --json' \
    'copilot plugin list --json' \
    'copilot plugin marketplace add D0n9X1n/feature-crew' \
    'copilot plugin list --json' \
    'copilot plugin install feature-crew@feature-crew' \
    'copilot plugin list --json')" ] \
    || case_err="$case_err fresh:calls:$(printf '%s' "$t76_calls" | tr '\n' '|')"
  [ ! -e "$p" ] || case_err="$case_err fresh:created-prefix"
  [ "$(sort -u "$t76_state/cwds")" = / ] || case_err="$case_err fresh:cli-called-from:$(sort -u "$t76_state/cwds" | tr '\n' ' ')"
  t76_run "$engine" both "$p"
  t76_expect rerun 0 "$(t76_head; t76_steps rerun claude copilot; printf '%s' "$t76_banner")"

  # Migrate: install first, then remove the old install; edits to pre-fc files survive.
  t76_state="$t76_root/$engine/state-migrate"; rm -rf "$t76_state"
  t76_seed "$p" || case_err="$case_err seed-failed"
  t76_run "$engine" both "$p" --dry-run
  t76_expect dry-run 0 "$(t76_head; t76_steps dry claude copilot; t76_removals 'would remove'; t76_kept; printf 'Dry run: nothing changed.')"
  printf '%s\n' "$t76_calls" | grep -qvE ' list --json$' && case_err="$case_err dry-run:mutating-call"
  t76_dry=$(printf '%s\n' "$t76_out" | sed -n 's/^would remove: //p' | LC_ALL=C sort)
  t76_before=$(t76_tree "$p")
  t76_run "$engine" both "$p" --check
  t76_expect check-before 1 "$(t76_head; printf 'claude: feature-crew missing\ncopilot: feature-crew missing\n'; t76_removals 'old file'; t76_kept; printf 'check: action-needed')"
  [ "$(t76_tree "$p")" = "$t76_before" ] || case_err="$case_err check:changed-tree"
  printf '%s\n' "$t76_calls" | grep -qvE ' list --json$' && case_err="$case_err check:mutating-call"
  t76_fail='copilot plugin install'
  t76_run "$engine" both "$p"
  t76_fail=''
  [ "$t76_rc" = 1 ] || case_err="$case_err cli-failure:rc=$t76_rc"
  case "$t76_err" in *'feature-crew: copilot step failed; old files left in place.'*) ;; *) case_err="$case_err cli-failure:no-message" ;; esac
  [ "$(t76_tree "$p")" = "$t76_before" ] || case_err="$case_err cli-failure:touched-old-install"
  t76_run "$engine" both "$p"
  t76_expect migrate 0 "$(t76_head; printf 'run: claude plugin marketplace update feature-crew\nstub: marketplace updated\nrun: claude plugin update feature-crew@feature-crew --scope user\nstub: plugin updated\n'
    printf 'run: copilot plugin marketplace update feature-crew\nstub: marketplace updated\nrun: copilot plugin install feature-crew@feature-crew\nstub: plugin installed\n'
    t76_removals removed; t76_kept; printf '%s' "$t76_banner")"
  [ "$(cd "$p" && find . \( -type f -o -type l \) | LC_ALL=C sort)" = "$t76_left" ] || case_err="$case_err migrate:left=$(cd "$p" && find . -type f | LC_ALL=C sort | tr '\n' ' ')"
  [ ! -e "$p/skills/build-or-fix" ] || case_err="$case_err migrate:empty-dir-kept"
  [ -d "$p/skills/research/empty-notes" ] || case_err="$case_err migrate:removed-a-folder-it-did-not-empty"
  [ "$(printf '%s\n' "$t76_out" | sed -n 's/^removed: //p' | LC_ALL=C sort)" = "$t76_dry" ] || case_err="$case_err dry-run-and-run-remove-different-paths"
  t76_run "$engine" both "$p" --check
  t76_expect check-after 0 "$(t76_head; printf 'claude: feature-crew installed\ncopilot: feature-crew installed\n'; t76_kept; printf 'check: current')"

  # Uninstall removes the plugin from each CLI and keeps the user's files.
  t76_run "$engine" both "$p" --uninstall
  t76_expect uninstall 0 "$(printf 'feature-crew: uninstalling; old install at <P>\n'
    printf 'run: claude plugin uninstall feature-crew@feature-crew --scope user\nstub: plugin uninstalled\nrun: claude plugin marketplace remove feature-crew --scope user --json\nclaude: marketplace removed from user settings\n'
    printf 'run: copilot plugin uninstall feature-crew@feature-crew\nstub: plugin uninstalled\nrun: copilot plugin marketplace remove feature-crew\nstub: marketplace removed\n'
    t76_kept; printf 'Done. Feature-Crew is uninstalled.')"
  [ ! -e "$t76_state/claude.marketplace" ] && [ ! -e "$t76_state/copilot.plugin" ] || case_err="$case_err uninstall:state-left"
  [ "$(cd "$p" && find . -type f | LC_ALL=C sort)" = "$t76_left" ] || case_err="$case_err uninstall:touched-user-files"

  # A marketplace from another source is replaced, never silently updated.
  t76_state="$t76_root/$engine/state-stale"; rm -rf "$t76_state" "$p"; mkdir -p "$t76_state"
  for c in claude copilot; do printf 'someone/fork' > "$t76_state/$c.marketplace"; : > "$t76_state/$c.plugin"; done
  : > "$t76_state/claude.user"
  t76_run "$engine" both "$p" --check
  t76_expect stale-check 1 "$(t76_head; printf 'claude: feature-crew installed from another source\ncopilot: feature-crew installed from another source\ncheck: action-needed')"
  t76_run "$engine" both "$p"
  t76_expect stale-source 0 "$(t76_head
    printf 'run: claude plugin marketplace add D0n9X1n/feature-crew --scope user\nstub: marketplace added\nrun: claude plugin update feature-crew@feature-crew --scope user\nstub: plugin updated\n'
    printf 'run: copilot plugin uninstall feature-crew@feature-crew\nstub: plugin uninstalled\nrun: copilot plugin marketplace remove feature-crew\nstub: marketplace removed\n'
    printf 'run: copilot plugin marketplace add D0n9X1n/feature-crew\nstub: marketplace added\nrun: copilot plugin install feature-crew@feature-crew\nstub: plugin installed\n'
    printf '%s' "$t76_banner")"
  [ "$(cat "$t76_state/claude.marketplace" 2>/dev/null)" = D0n9X1n/feature-crew ] || case_err="$case_err stale-source:not-replaced"

  # A disabled plugin is enabled, and checked, before anything old goes.
  t76_state="$t76_root/$engine/state-disabled"; rm -rf "$t76_state"; mkdir -p "$t76_state"
  printf 'D0n9X1n/feature-crew' > "$t76_state/claude.marketplace"; : > "$t76_state/claude.plugin"; : > "$t76_state/claude.disabled"
  t76_seed "$p"; t76_before=$(t76_tree "$p")
  t76_fail='claude plugin enable'
  t76_run "$engine" claude "$p"
  t76_fail=''
  [ "$t76_rc" = 1 ] && [ "$(t76_tree "$p")" = "$t76_before" ] || case_err="$case_err disabled:enable-failure-removed-old-files(rc=$t76_rc)"
  t76_run "$engine" claude "$p"
  t76_expect disabled 0 "$(t76_head; printf 'run: claude plugin marketplace update feature-crew\nstub: marketplace updated\nrun: claude plugin enable feature-crew@feature-crew --scope user\nstub: plugin enabled\nrun: claude plugin update feature-crew@feature-crew --scope user\nstub: plugin updated\n'
    t76_removals removed; t76_kept; printf '%s' "$t76_banner")"

  # Only the feature-crew marketplace's plugin counts, not a same-named one elsewhere.
  t76_state="$t76_root/$engine/state-other"; rm -rf "$t76_state" "$p"; mkdir -p "$t76_state"
  printf '  {\n    "name": "feature-crew",\n    "marketplace": "another-market",\n    "enabled": true\n  },\n' > "$t76_state/copilot.extra"
  printf 'D0n9X1n/feature-crew' > "$t76_state/copilot.marketplace"
  t76_run "$engine" both "$p" --check
  t76_expect other-check 1 "$(t76_head; printf 'claude: feature-crew missing\ncopilot: feature-crew disabled\ncheck: action-needed')"
  t76_run "$engine" both "$p"
  case "$t76_out" in *'run: copilot plugin install feature-crew@feature-crew'*) ;; *) case_err="$case_err other-market:skipped-install" ;; esac

  # A source that merely contains --source is another source: it is replaced.
  t76_state="$t76_root/$engine/state-near"; rm -rf "$t76_state" "$p"; mkdir -p "$t76_state"
  for c in claude copilot; do printf 'D0n9X1n/feature-crew-old' > "$t76_state/$c.marketplace"; done
  t76_run "$engine" both "$p"
  case "$t76_out" in *'run: claude plugin marketplace add D0n9X1n/feature-crew --scope user'*'run: copilot plugin marketplace remove feature-crew'*) ;;
    *) case_err="$case_err near-source:not-replaced" ;; esac
  for c in claude copilot; do
    [ "$(cat "$t76_state/$c.marketplace" 2>/dev/null)" = D0n9X1n/feature-crew ] || case_err="$case_err near-source:$c-kept-old-source"
  done

  # A relative local source is registered as an absolute path, so a rerun matches it.
  t76_state="$t76_root/$engine/state-relative"; rm -rf "$t76_state" "$p" "$t76_root/$engine/rel"
  mkdir -p "$t76_root/$engine/rel/src"
  pushd "$t76_root/$engine/rel" >/dev/null
  t76_run "$engine" claude "$p" --source src
  t76_run "$engine" claude "$p" --source src
  popd >/dev/null
  [ "$(cat "$t76_state/claude.marketplace" 2>/dev/null)" = "$(cd "$t76_root/$engine/rel/src" && pwd -P)" ] || case_err="$case_err relative-source:stored-$(cat "$t76_state/claude.marketplace" 2>/dev/null)"
  case "$t76_out" in *'run: claude plugin marketplace update feature-crew'*) ;; *) case_err="$case_err relative-source:rerun-not-update" ;; esac

  # A project-scoped Claude plugin does not count: the user scope is installed.
  t76_state="$t76_root/$engine/state-project"; rm -rf "$t76_state" "$p"; mkdir -p "$t76_state"
  printf 'D0n9X1n/feature-crew' > "$t76_state/claude.marketplace"
  printf '  {\n    "id": "feature-crew@feature-crew",\n    "scope": "project",\n    "enabled": true\n  },\n' > "$t76_state/claude.extra"
  t76_run "$engine" claude "$p" --check
  t76_expect project-check 1 "$(t76_head; printf 'claude: feature-crew missing\ncheck: action-needed')"
  t76_run "$engine" claude "$p"
  t76_expect project-scope 0 "$(t76_head; printf 'run: claude plugin marketplace update feature-crew\nstub: marketplace updated\nrun: claude plugin install feature-crew@feature-crew --scope user\nstub: plugin installed\n'; printf '%s' "$t76_banner")"

  # A link in an old skill folder is never followed or removed, in either engine.
  t76_state="$t76_root/$engine/state-link"; rm -rf "$t76_state"
  t76_seed "$p"
  mv "$p/skills/research/SKILL.md" "$t76_root/$engine/outside.md"
  ln -s "$t76_root/$engine/outside.md" "$p/skills/research/SKILL.md"
  t76_run "$engine" both "$p"
  [ "$t76_rc" = 0 ] || case_err="$case_err link:rc=$t76_rc"
  [ -L "$p/skills/research/SKILL.md" ] && [ -f "$t76_root/$engine/outside.md" ] || case_err="$case_err link:followed-or-removed"
  case "$t76_out" in *'research/SKILL.md'*) case_err="$case_err link:reported" ;; esac

  # Uninstall never removes a marketplace that only a project declares.
  t76_state="$t76_root/$engine/state-project-only"; rm -rf "$t76_state" "$p"; mkdir -p "$t76_state"
  printf 'D0n9X1n/feature-crew' > "$t76_state/claude.marketplace"
  printf '  {\n    "id": "feature-crew@feature-crew",\n    "scope": "project",\n    "enabled": true\n  },\n' > "$t76_state/claude.extra"
  t76_run "$engine" claude "$p" --uninstall
  t76_expect project-only-uninstall 0 "$(printf 'feature-crew: uninstalling; old install at <P>\n'
    printf 'run: claude plugin marketplace remove feature-crew --scope user --json\nclaude: marketplace not in user settings; left for other scopes\n'
    printf 'Done. Feature-Crew is uninstalled.')"
  [ -e "$t76_state/claude.marketplace" ] || case_err="$case_err project-only:removed-project-marketplace"
  printf '%s\n' "$t76_calls" | grep -qxE 'claude plugin (uninstall .*|marketplace remove feature-crew)' && case_err="$case_err project-only:unscoped-call"

  # Old files go only once the CLI lists the plugin "enabled": true.
  for t76_row in '{"id": "feature-crew@feature-crew", "scope": "user"}' '{"id": "feature-crew@feature-crew", "scope": "user", "enabled":	false}'; do
    t76_state="$t76_root/$engine/state-unproven"; rm -rf "$t76_state"; mkdir -p "$t76_state"
    printf 'D0n9X1n/feature-crew' > "$t76_state/claude.marketplace"; : > "$t76_state/claude.user"
    printf '[%s]\n' "$t76_row" > "$t76_state/claude.raw"
    t76_seed "$p"; t76_before=$(t76_tree "$p")
    t76_run "$engine" claude "$p"
    [ "$t76_rc" = 1 ] && [ "$(t76_tree "$p")" = "$t76_before" ] || case_err="$case_err unproven-enabled:removed-old-files(rc=$t76_rc,row=$t76_row)"
  done

  # A linked agents or skills folder is never cleaned through; its fc-* entries are reported.
  t76_state="$t76_root/$engine/state-linkdir"; rm -rf "$t76_state" "$t76_root/$engine/outside"
  t76_seed "$p"; mkdir -p "$t76_root/$engine/outside"
  for d in agents skills; do mv "$p/$d" "$t76_root/$engine/outside/$d"; ln -s "$t76_root/$engine/outside/$d" "$p/$d"; done
  t76_outside=$(t76_tree "$t76_root/$engine/outside")
  t76_run "$engine" both "$p" --check
  [ "$t76_rc" = 1 ] || case_err="$case_err linkdir-check:rc=$t76_rc"
  t76_run "$engine" both "$p"
  [ "$t76_rc" = 0 ] || case_err="$case_err linkdir:rc=$t76_rc"
  [ "$(t76_tree "$t76_root/$engine/outside")" = "$t76_outside" ] || case_err="$case_err linkdir:changed-files-outside-prefix"
  [ "$(printf '%s\n' "$t76_out" | grep -E '^(removed|would remove): ')" = 'removed: <P>/feature-crew.sha256' ] || case_err="$case_err linkdir:removed-through-link"
  case "$t76_out" in *'kept (linked folder): <P>/agents/fc-pm.md'*'kept (linked folder): <P>/skills/fc-review'*) ;;
    *) case_err="$case_err linkdir:not-reported" ;; esac

  # A Copilot URL source is matched like any other, so a rerun updates it.
  t76_state="$t76_root/$engine/state-url"; rm -rf "$t76_state" "$p"
  t76_run "$engine" both "$p" --source https://example.invalid/feature-crew.git
  t76_run "$engine" both "$p" --source https://example.invalid/feature-crew.git --check
  [ "$t76_rc" = 0 ] || case_err="$case_err url-source:check-rc=$t76_rc"
  t76_run "$engine" both "$p" --source https://example.invalid/feature-crew.git
  case "$t76_out" in *'run: copilot plugin marketplace update feature-crew'*) ;; *) case_err="$case_err url-source:rerun-not-update" ;; esac

  # A linked prefix is never cleaned through, however it is spelled.
  for t76_spell in '' / /.; do
    t76_state="$t76_root/$engine/state-linkprefix"; rm -rf "$t76_state" "$p" "$t76_root/$engine/outside-p"
    t76_seed "$t76_root/$engine/outside-p"; ln -s "$t76_root/$engine/outside-p" "$p"
    t76_outside=$(t76_tree "$t76_root/$engine/outside-p")
    t76_run "$engine" both "$p$t76_spell"
    [ "$t76_rc" = 0 ] || case_err="$case_err linkprefix[$t76_spell]:rc=$t76_rc"
    [ "$(t76_tree "$t76_root/$engine/outside-p")" = "$t76_outside" ] || case_err="$case_err linkprefix[$t76_spell]:changed-files-outside-prefix"
    printf '%s\n' "$t76_out" | grep -qE '^(removed|would remove): ' && case_err="$case_err linkprefix[$t76_spell]:removed-through-link"
    case "$t76_out" in *'kept (linked folder): '*'fc-pm.md'*) ;; *) case_err="$case_err linkprefix[$t76_spell]:not-reported" ;; esac
    rm -f "$p"
  done

  # An unreadable old file or folder is an error (exit 2) before anything is removed.
  if [ "$(id -u)" != 0 ]; then
    for t76_lock in skills/research skills/research/SKILL.md skills/fc-review agents/fc-pm.md feature-crew.sha256; do
      t76_state="$t76_root/$engine/state-unreadable"; rm -rf "$t76_state"
      t76_seed "$p"; t76_before=$(t76_tree "$p")
      chmod 000 "$p/$t76_lock"
      t76_run "$engine" both "$p" --check; t76_check_rc=$t76_rc; t76_check_err=$t76_err
      t76_run "$engine" both "$p"
      chmod 755 "$p/$t76_lock"; [ -d "$p/$t76_lock" ] || chmod 644 "$p/$t76_lock"
      [ "$t76_check_rc" = 2 ] && [ "$t76_rc" = 2 ] || case_err="$case_err unreadable[$t76_lock]:rc=$t76_check_rc/$t76_rc"
      case "$t76_check_err$t76_err" in *"feature-crew: cannot read <P>/$t76_lock"*) ;; *) case_err="$case_err unreadable[$t76_lock]:no-message" ;; esac
      [ "$(t76_tree "$p")" = "$t76_before" ] || case_err="$case_err unreadable[$t76_lock]:removed-files"
      printf '%s\n' "$t76_calls" | grep -vE ' list --json$' | grep -q . && case_err="$case_err unreadable[$t76_lock]:changed-cli-state"
    done
    # A folder whose entries cannot be removed is an error too, before anything changes.
    t76_state="$t76_root/$engine/state-unremovable"; rm -rf "$t76_state"
    t76_seed "$p"; t76_before=$(t76_tree "$p")
    chmod 555 "$p/skills/fc-review"
    t76_run "$engine" both "$p"
    chmod 755 "$p/skills/fc-review"
    [ "$t76_rc" = 2 ] || case_err="$case_err unremovable:rc=$t76_rc"
    case "$t76_err" in *'feature-crew: cannot remove <P>/skills/fc-review'*) ;; *) case_err="$case_err unremovable:no-message" ;; esac
    [ "$(t76_tree "$p")" = "$t76_before" ] || case_err="$case_err unremovable:removed-files"
    printf '%s\n' "$t76_calls" | grep -vE ' list --json$' | grep -q . && case_err="$case_err unremovable:changed-cli-state"
  fi

  # A removal the OS refuses after the checks passed stops with exit 1, lists
  # what is left, and prints no success banner; a rerun finishes the job.
  if [ "$(id -u)" != 0 ]; then
    t76_state="$t76_root/$engine/state-refused"; rm -rf "$t76_state"
    t76_seed "$p"
    t76_stub_lock="$p/skills/fc-review"
    t76_run "$engine" both "$p"
    t76_stub_lock=''
    chmod 755 "$p/skills/fc-review"
    [ "$t76_rc" = 1 ] || case_err="$case_err refused:rc=$t76_rc"
    case "$t76_err" in *'feature-crew: not removed: <P>/skills/fc-review'*'run again'*) ;; *) case_err="$case_err refused:not-listed" ;; esac
    case "$t76_out" in *'Done.'*) case_err="$case_err refused:printed-done" ;; esac
    [ -d "$p/skills/fc-review" ] && [ ! -e "$p/agents/fc-pm.md" ] || case_err="$case_err refused:unexpected-tree"
    t76_run "$engine" both "$p"
    [ "$t76_rc" = 0 ] && [ "$(cd "$p" && find . \( -type f -o -type l \) | LC_ALL=C sort)" = "$t76_left" ] || case_err="$case_err refused:rerun-did-not-finish(rc=$t76_rc)"
    # A read failure after the run changed something is listed too, with exit 1, never 2.
    t76_state="$t76_root/$engine/state-refused-read"; rm -rf "$t76_state"
    t76_seed "$p"
    t76_stub_lock="$p/skills/fc-review"; t76_stub_hide="$p/skills/research"
    t76_run "$engine" both "$p"
    t76_stub_lock=''; t76_stub_hide=''
    chmod 755 "$p/skills/fc-review" "$p/skills/research"
    [ "$t76_rc" = 1 ] || case_err="$case_err refused-read:rc=$t76_rc"
    case "$t76_err" in *'not removed: <P>/skills/fc-review'*) ;; *) case_err="$case_err refused-read:fc-review-not-listed" ;; esac
    case "$t76_err" in *'not removed: <P>/skills/research'*'run again'*) ;; *) case_err="$case_err refused-read:research-not-listed" ;; esac
    case "$t76_out" in *'Done.'*) case_err="$case_err refused-read:printed-done" ;; esac
    t76_run "$engine" both "$p"
    [ "$t76_rc" = 0 ] && [ "$(cd "$p" && find . \( -type f -o -type l \) | LC_ALL=C sort)" = "$t76_left" ] || case_err="$case_err refused-read:rerun-did-not-finish(rc=$t76_rc)"
    # The same holds when a parent folder (agents, skills) changes mid-run.
    t76_state="$t76_root/$engine/state-refused-parent"; rm -rf "$t76_state"
    t76_seed "$p"
    t76_stub_lock="$p/agents"; t76_stub_hide="$p/skills"
    t76_run "$engine" both "$p"
    t76_stub_lock=''; t76_stub_hide=''
    chmod 755 "$p/agents" "$p/skills"
    [ "$t76_rc" = 1 ] || case_err="$case_err refused-parent:rc=$t76_rc"
    case "$t76_err" in *'not removed: <P>/skills'*) ;; *) case_err="$case_err refused-parent:skills-not-listed" ;; esac
    case "$t76_err" in *'not removed: <P>/agents/fc-pm.md'*) ;; *) case_err="$case_err refused-parent:agent-not-listed" ;; esac
    [ ! -e "$p/feature-crew.sha256" ] || case_err="$case_err refused-parent:stopped-before-the-rest"
    t76_run "$engine" both "$p"
    [ "$t76_rc" = 0 ] && [ "$(cd "$p" && find . \( -type f -o -type l \) | LC_ALL=C sort)" = "$t76_left" ] || case_err="$case_err refused-parent:rerun-did-not-finish(rc=$t76_rc)"
    # A folder above the prefix that cannot be entered makes the old install
    # unreachable, not absent: exit 2 before any change, exit 1 after one. The
    # OS decides, so a path through a link, or a prefix that is a link, behaves the same.
    for t76_lay in direct alias link; do
      t76_par="$t76_root/$engine/par"; rm -rf "$t76_par" "$t76_root/$engine/alias" "$t76_root/$engine/linkp"; mkdir -p "$t76_par/private"
      case "$t76_lay" in
        direct) t76_pp="$t76_par/old"; t76_seed "$t76_pp" ;;
        alias) ln -s "$t76_par/private" "$t76_root/$engine/alias"; t76_pp="$t76_root/$engine/alias/old"; t76_seed "$t76_pp" ;;
        link) t76_seed "$t76_par/private/old"; ln -s "$t76_par/private/old" "$t76_root/$engine/linkp"; t76_pp="$t76_root/$engine/linkp" ;;
      esac
      t76_state="$t76_root/$engine/state-ancestor"; rm -rf "$t76_state"
      t76_before=$(t76_tree "$t76_pp")
      chmod 000 "$t76_par"
      for t76_flags in '' --check --dry-run; do
        t76_run "$engine" both "$t76_pp" $t76_flags
        [ "$t76_rc" = 2 ] || case_err="$case_err ancestor-$t76_lay[$t76_flags]:rc=$t76_rc"
        case "$t76_err" in *'feature-crew: cannot read <P>'*) ;; *) case_err="$case_err ancestor-$t76_lay[$t76_flags]:no-message" ;; esac
      done
      chmod 755 "$t76_par"
      printf '%s\n' "$t76_calls" | grep -vE ' list --json$' | grep -q . && case_err="$case_err ancestor-$t76_lay:changed-cli-state"
      [ "$(t76_tree "$t76_pp")" = "$t76_before" ] || case_err="$case_err ancestor-$t76_lay:changed-files"
      t76_state="$t76_root/$engine/state-ancestor-late"; rm -rf "$t76_state"
      t76_stub_hide="$t76_par"
      t76_run "$engine" both "$t76_pp"
      t76_stub_hide=''
      chmod 755 "$t76_par"
      [ "$t76_rc" = 1 ] || case_err="$case_err ancestor-$t76_lay-late:rc=$t76_rc"
      case "$t76_err" in *'feature-crew: not removed: <P>'*'run again'*) ;; *) case_err="$case_err ancestor-$t76_lay-late:not-listed" ;; esac
      case "$t76_out" in *'Done.'*) case_err="$case_err ancestor-$t76_lay-late:printed-done" ;; esac
      t76_run "$engine" both "$t76_pp"
      if [ "$t76_lay" = link ]; then
        # A linked prefix is never cleaned through: the rerun only reports it.
        [ "$t76_rc" = 0 ] && [ "$(t76_tree "$t76_pp")" = "$t76_before" ] || case_err="$case_err ancestor-link-late:rerun(rc=$t76_rc)"
        case "$t76_out" in *'kept (linked folder): '*) ;; *) case_err="$case_err ancestor-link-late:not-reported" ;; esac
      else
        [ "$t76_rc" = 0 ] && [ "$(cd "$t76_pp" && find . \( -type f -o -type l \) | LC_ALL=C sort)" = "$t76_left" ] || case_err="$case_err ancestor-$t76_lay-late:rerun-did-not-finish(rc=$t76_rc)"
      fi
      rm -rf "$t76_par" "$t76_root/$engine/alias" "$t76_root/$engine/linkp"
    done
    # Any OS failure other than "missing" makes a folder unreachable, not absent:
    # a linked agents folder behind one that cannot be entered, or a link loop.
    t76_par="$t76_root/$engine/par"; rm -rf "$t76_par"; mkdir -p "$t76_par/private/agents"
    printf 'mine\n' > "$t76_par/private/agents/fc-pm.md"
    t76_state="$t76_root/$engine/state-linked-agents"; rm -rf "$t76_state"
    t76_seed "$p"; rm -rf "$p/agents"; ln -s "$t76_par/private/agents" "$p/agents"
    t76_before=$(t76_tree "$p")
    chmod 000 "$t76_par"
    for t76_flags in '' --check --dry-run; do
      t76_run "$engine" both "$p" $t76_flags
      [ "$t76_rc" = 2 ] || case_err="$case_err linked-agents[$t76_flags]:rc=$t76_rc"
      case "$t76_err" in *'feature-crew: cannot read <P>/agents'*) ;; *) case_err="$case_err linked-agents[$t76_flags]:no-message" ;; esac
    done
    chmod 755 "$t76_par"
    printf '%s\n' "$t76_calls" | grep -vE ' list --json$' | grep -q . && case_err="$case_err linked-agents:changed-cli-state"
    [ "$(t76_tree "$p")" = "$t76_before" ] || case_err="$case_err linked-agents:changed-files"
    t76_state="$t76_root/$engine/state-linked-agents-late"; rm -rf "$t76_state"
    t76_stub_hide="$t76_par"
    t76_run "$engine" both "$p"
    t76_stub_hide=''
    chmod 755 "$t76_par"
    [ "$t76_rc" = 1 ] || case_err="$case_err linked-agents-late:rc=$t76_rc"
    case "$t76_err" in *'feature-crew: not removed: <P>/agents'*'run again'*) ;; *) case_err="$case_err linked-agents-late:not-listed" ;; esac
    case "$t76_out" in *'Done.'*) case_err="$case_err linked-agents-late:printed-done" ;; esac
    [ -f "$t76_par/private/agents/fc-pm.md" ] || case_err="$case_err linked-agents-late:removed-outside-file"
    rm -rf "$t76_par" "$p"
    t76_state="$t76_root/$engine/state-loop"; rm -rf "$t76_state"
    ln -s "$p" "$p"
    for t76_flags in '' --check --dry-run; do
      t76_run "$engine" both "$p" $t76_flags
      [ "$t76_rc" = 2 ] || case_err="$case_err link-loop[$t76_flags]:rc=$t76_rc"
      case "$t76_err" in *'feature-crew: cannot read <P>'*) ;; *) case_err="$case_err link-loop[$t76_flags]:no-message" ;; esac
    done
    printf '%s\n' "$t76_calls" | grep -vE ' list --json$' | grep -q . && case_err="$case_err link-loop:changed-cli-state"
    rm -f "$p"

    # An old fc-* file that becomes unreadable during the run is listed, not deleted.
    t76_state="$t76_root/$engine/state-fc-unreadable-late"; rm -rf "$t76_state"
    t76_seed "$p"
    t76_stub_hide="$p/agents/fc-pm.md"
    t76_run "$engine" both "$p"
    t76_stub_hide=''
    [ -f "$p/agents/fc-pm.md" ] && chmod 644 "$p/agents/fc-pm.md"
    [ "$t76_rc" = 1 ] || case_err="$case_err fc-unreadable-late:rc=$t76_rc"
    case "$t76_err" in *'feature-crew: not removed: <P>/agents/fc-pm.md'*'run again'*) ;; *) case_err="$case_err fc-unreadable-late:not-listed" ;; esac
    case "$t76_out" in *'Done.'*) case_err="$case_err fc-unreadable-late:printed-done" ;; esac
    [ -f "$p/agents/fc-pm.md" ] || case_err="$case_err fc-unreadable-late:deleted"
    t76_run "$engine" both "$p"
    [ "$t76_rc" = 0 ] && [ "$(cd "$p" && find . \( -type f -o -type l \) | LC_ALL=C sort)" = "$t76_left" ] || case_err="$case_err fc-unreadable-late:rerun-did-not-finish(rc=$t76_rc)"
  fi

  # An install that reports success but leaves the plugin unlisted removes nothing.
  t76_state="$t76_root/$engine/state-ghost"; rm -rf "$t76_state"
  t76_seed "$p"; t76_before=$(t76_tree "$p")
  t76_ghost=copilot
  t76_run "$engine" both "$p"
  t76_ghost=''
  [ "$t76_rc" = 1 ] || case_err="$case_err ghost:rc=$t76_rc"
  [ "$(t76_tree "$p")" = "$t76_before" ] || case_err="$case_err ghost:removed-old-files"

  # Help wins over any other token, in both engines alike.
  t76_run "$engine" both "$p" --help --bogus
  [ "$t76_rc" = 0 ] || case_err="$case_err help:rc=$t76_rc"
  case "$t76_out" in *'removed even when edited'*) ;; *) case_err="$case_err help:no-edited-warning" ;; esac
  printf '%s' "$t76_out" > "$t76_root/help-$engine"

  # Only the CLIs on PATH are used; neither on PATH changes nothing.
  t76_state="$t76_root/$engine/state-claude"; rm -rf "$t76_state" "$p"
  t76_run "$engine" claude "$p" --source /src/feature-crew
  t76_expect claude-only 0 "$(printf 'feature-crew: plugin source /src/feature-crew; old install at <P>\n'
    printf 'run: claude plugin marketplace add /src/feature-crew --scope user\nstub: marketplace added\nrun: claude plugin install feature-crew@feature-crew --scope user\nstub: plugin installed\n'; printf '%s' "$t76_banner")"
  t76_state="$t76_root/$engine/state-none"; rm -rf "$t76_state"
  t76_seed "$p"; t76_before=$(t76_tree "$p")
  t76_run "$engine" none "$p"
  [ "$t76_rc" = 2 ] || case_err="$case_err no-cli:rc=$t76_rc"
  case "$t76_err" in *'feature-crew: neither claude nor copilot is on PATH'*) ;; *) case_err="$case_err no-cli:no-message" ;; esac
  [ "$(t76_tree "$p")" = "$t76_before" ] || case_err="$case_err no-cli:touched-old-install"

  # Usage errors exit 2 before touching anything.
  for t76_bad in '--bogus' '--check --dry-run' '--check --uninstall' '--source' '--force'; do
    t76_run "$engine" both "$p" $t76_bad
    [ "$t76_rc" = 2 ] || case_err="$case_err usage[$t76_bad]:rc=$t76_rc"
  done
  [ "$(t76_tree "$p")" = "$t76_before" ] || case_err="$case_err usage:touched-old-install"
  installer_result "T76 $engine installs the plugin per CLI, then removes the old install; dry-run, check, failure, uninstall, usage"
done
[ "${#INSTALLERS[@]}" -eq 2 ] || skip "T76 ps1 installer (pwsh unavailable; set PWSH)"
if [ -f "$t76_root/help-sh" ] && [ -f "$t76_root/help-ps1" ]; then
  cmp -s "$t76_root/help-sh" "$t76_root/help-ps1" && ok "T76 both engines print the same help" \
    || bad "T76 help parity" "install.sh and install.ps1 print different help"
fi

# ---------------------------------------------------------------- T77
# The installers' fixed old-install lists must equal what tagged installers
# actually wrote (v3.1 through v5.3.1; v3.0's installer does not run), and
# every pre-fc file must have a published hash. Both engines carry the same lists.
case_err=""
t77_list() { # file, variable name: the quoted words of its one-line array
  grep -E "^\\\$?$2 *= *(@)?\(" "$1" | head -1 | grep -oE "[\"'][a-z-]+[\"']" | tr -d "\"'" | tr '\n' ' '
}
for t77_v in LEGACY_FC_AGENTS LEGACY_FC_SKILLS LEGACY_OLD_AGENTS LEGACY_OLD_SKILLS; do
  [ -n "$(t77_list install.sh "$t77_v")" ] || case_err="$case_err sh-missing:$t77_v"
  [ "$(t77_list install.sh "$t77_v")" = "$(t77_list install.ps1 "$t77_v")" ] || case_err="$case_err engines-differ:$t77_v"
done
{
  for n in $(t77_list install.sh LEGACY_FC_AGENTS); do echo "agents/$n.md"; done
  for n in $(t77_list install.sh LEGACY_FC_SKILLS); do echo "skills/$n"; done
  echo feature-crew.sha256
  for n in $(t77_list install.sh LEGACY_OLD_AGENTS); do echo "agents/feature-crew/$n.md"; done
  for n in $(t77_list install.sh LEGACY_OLD_SKILLS); do echo "skills/$n"; done
} | LC_ALL=C sort -u > "$installer_root/t77.want"
: > "$installer_root/t77.files"
for t77_tag in v3.1 v4.0 v5.0.0 v5.0.1 v5.1.0 v5.1.1 v5.2.0 v5.2.1 v5.3.0 v5.3.1; do
  t77_src="$installer_root/t77/$t77_tag"; t77_p="$installer_root/t77/$t77_tag-p"
  mkdir -p "$t77_src" && git -c core.autocrlf=false archive "$t77_tag" | tar -x -C "$t77_src" \
    || { case_err="$case_err $t77_tag:archive"; continue; }
  HOME="$installer_root/home" "$installer_bash" "$t77_src/install.sh" --prefix "$t77_p" --force > /dev/null 2>&1 \
    || { case_err="$case_err $t77_tag:install"; continue; }
  (cd "$t77_p" && find . -type f | sed 's#^\./##') >> "$installer_root/t77.files"
done
sed -E 's#^(skills/[^/]+)/.*#\1#' "$installer_root/t77.files" | LC_ALL=C sort -u > "$installer_root/t77.got"
cmp -s "$installer_root/t77.want" "$installer_root/t77.got" \
  || case_err="$case_err lists-differ:$(diff "$installer_root/t77.want" "$installer_root/t77.got" | grep '^[<>]' | tr '\n' ' ')"
for t77_rel in $(LC_ALL=C sort -u "$installer_root/t77.files" | grep -vE '^(agents/fc-|skills/fc-|feature-crew\.sha256$)'); do
  grep -qE "  $t77_rel\$" published.sha256 || case_err="$case_err unpublished:$t77_rel"
done
installer_result "T77 old-install lists equal what v3.1-v5.3.1 installed, in both engines; pre-fc files all have published hashes"

# ---------------------------------------------------------------- T78
# fc-clean removes a finished goal's leftovers: never while the goal is
# unfinished, only what a receipt proves this task created, and it asks once
# about the rest. Each clause is a literal sentence scoped to its own section;
# the flows that finish with it must name it; the wiki Usage direct-command
# list and both installer banners must name /fc-clean; and the skill stays
# within its approved 31 lines, counted byte-exactly as in T66. As in T62, each
# mutation must produce exactly its own diagnostic. The behavior checks then
# run the skill's own prune, compare-and-delete, and ignored-file commands in a
# fixture repository; each must catch the weaker command it replaces.
t78_labels=(
  no-backups
  goal-never-unfinished goal-active-unmet goal-ended-unachieved goal-archive-first goal-autopilot-before-complete
  receipt-identities receipt-recorded-returned receipt-names-not-proof
  remove-check-state remove-only-receipted remove-worktree remove-branch remove-stale-refs
  remove-stash remove-temp remove-process remove-checkpoint-last
  keep-uncertain keep-ask-once keep-report
  wire-bof-finish wire-classifier-receipts wire-discipline-receipt wire-debug-receipts
  usage-direct-command banner-sh banner-ps1 line-budget
)
t78_sections=(intro goal goal goal goal goal receipts receipts receipts
  remove remove remove remove remove remove remove remove remove keep keep keep
  bof classifier discipline debug commands sh ps1 budget)
t78_rules=(
  'with no backups'
  'Never clean while the goal is unfinished.'
  'An active `/goal` or Copilot autopilot objective not yet shown met is unfinished'
  'so is a goal that ended without being achieved, so ask instead.'
  'Archive first: the outcome is committed, pushed, and merged as authorized, and reported to the user with its evidence.'
  'In Copilot autopilot, clean before `task_complete`.'
  'A receipt names what a task created: the absolute path and inode of a `mktemp -d` root, a worktree path, a branch and its OID, a stash OID, a harness task id, or a PID with its start time and command.'
  'Flows record receipts in the checkpoint or their returned result; nested skills return them and never clean.'
  'Names alone never prove ownership.'
  'Check status, worktrees, sessions, and locks.'
  'Remove automatically only what a receipt covers, plus stale references, and re-check each receipt right before removing its item.'
  "**Worktree:** \`git worktree remove\`, never \`--force\`, only when it is unlocked, no session's working directory, its HEAD is in the base or among its merged PR's commits, and \`git status --porcelain --ignored --untracked-files=all\` lists nothing beyond its receipts."
  "**Branch:** only when no worktree has it checked out and its head is in the base or among its merged PR's commits, via \`git update-ref -d refs/heads/<branch> <oid>\` so a moved branch is kept."
  "**Stale references:** \`git worktree prune\` and \`git fetch --prune --no-prune-tags <remote> '+refs/heads/*:refs/remotes/<remote>/*'\`, which keep locked worktrees and local tags."
  '**Stash:** only by its recorded OID, once its content has landed.'
  '**Temp root:** only at its recorded path and inode; never empty, `/`, home, or a repository root, never through a link, never by glob.'
  "**Process:** through the harness's task controls, or by a PID whose start time and command still match its receipt."
  '**Checkpoint:** `$(git rev-parse --git-path fc-checkpoint.md)`, last.'
  'Keep dirty or unmerged work, stashes without a receipt, and anything uncertain'
  'list in one question everything kept that may be removable.'
  'Return to the updated base and report the final status and anything kept.'
  'Once the goal is achieved, finish with `/fc-clean`.'
  'returns its result, with receipts for anything it created, to the originating flow'
  'Record a receipt, as `/fc-clean` defines it, for each leftover you create, with temp files under one `mktemp -d` root.'
  'Return receipts for any scratch you created.'
  '`/fc-clean`'
  '/fc-clean'
  '/fc-clean'
  31
)
t78_contract() { # fc-clean (byte-exact), build-or-fix, run-discipline, fc-debug, wiki Usage, install.sh, install.ps1
  local intro goal receipts remove keep bof classifier discipline debug commands sh ps1 lines section i errors=""
  intro=$(printf '%s\n' "$1" | sed -n '/^# fc-clean$/,/^## /p')
  goal=$(printf '%s\n' "$1" | sed -n '/^## Goal gate$/,/^## /p')
  receipts=$(printf '%s\n' "$1" | sed -n '/^## Receipts$/,/^## /p')
  remove=$(printf '%s\n' "$1" | sed -n '/^## Remove$/,/^## /p')
  keep=$(printf '%s\n' "$1" | sed -n '/^## Keep, ask once, report$/,/^## /p')
  lines=$(printf '%s' "$1" | wc -l | tr -d ' ')
  bof=$(printf '%s\n' "$2" | sed -n '/^# fc-build-or-fix$/,/^## /p')
  classifier=$(printf '%s\n' "$2" | sed -n '/^## Need classifier/,/^## /p')
  discipline=$(printf '%s\n' "$3" | sed -n '/^## Checkpoint/,/^## /p')
  debug=$(printf '%s\n' "$4" | sed -n '/^## Report$/,/^## /p')
  commands=$(printf '%s\n' "$5" | sed -n '/^## Describe the need/,/^## /p')
  sh=$(printf '%s\n' "$6" | sed -n '/Available: \/fc-/,/delegate to an fc-/p')
  ps1=$(printf '%s\n' "$7" | sed -n '/Available: \/fc-/,/delegate to an fc-/p')
  for ((i=0; i<${#t78_rules[@]}; i++)); do
    case "${t78_sections[$i]}" in
      intro) section="$intro" ;;
      goal) section="$goal" ;;
      receipts) section="$receipts" ;;
      remove) section="$remove" ;;
      keep) section="$keep" ;;
      bof) section="$bof" ;;
      classifier) section="$classifier" ;;
      discipline) section="$discipline" ;;
      debug) section="$debug" ;;
      commands) section="$commands" ;;
      sh) section="$sh" ;;
      ps1) section="$ps1" ;;
      budget)
        [ "$lines" -le "${t78_rules[$i]}" ] || errors="$errors ${t78_labels[$i]}"
        continue ;;
    esac
    printf '%s\n' "$section" | grep -qF -- "${t78_rules[$i]}" \
      || errors="$errors ${t78_labels[$i]}"
  done
  printf '%s\n' "$errors"
}
t66_load skills/fc-clean/SKILL.md
t78_clean_text=$t66_loaded
t78_bof_text=$(cat skills/fc-build-or-fix/SKILL.md 2>/dev/null)
t78_discipline_text=$(cat skills/fc-build-or-fix/reference/run-discipline.md 2>/dev/null)
t78_debug_text=$(cat skills/fc-debug/SKILL.md 2>/dev/null)
t78_usage_text=$(cat wiki/Usage.md 2>/dev/null)
t78_sh_text=$(cat install.sh 2>/dev/null)
t78_ps1_text=$(cat install.ps1 2>/dev/null)
t78_err=$(t78_contract "$t78_clean_text" "$t78_bof_text" "$t78_discipline_text" "$t78_debug_text" \
  "$t78_usage_text" "$t78_sh_text" "$t78_ps1_text")
if [ -z "$t78_err" ]; then
  t78_root=$(mktemp -d)
  CLEANUP_PATHS+=("$t78_root")
  for ((t78_i=0; t78_i<${#t78_rules[@]}; t78_i++)); do
    t78_rule="${t78_rules[$t78_i]}"
    t78_kind=removal
    t78_m1="$t78_clean_text"; t78_m2="$t78_bof_text"; t78_m3="$t78_discipline_text"; t78_m4="$t78_debug_text"
    t78_m5="$t78_usage_text"; t78_m6="$t78_sh_text"; t78_m7="$t78_ps1_text"
    case "${t78_sections[$t78_i]}" in
      bof|classifier) t78_m2="${t78_m2/"$t78_rule"/}" ;;
      discipline) t78_m3="${t78_m3/"$t78_rule"/}" ;;
      debug) t78_m4="${t78_m4/"$t78_rule"/}" ;;
      commands) t78_m5="${t78_m5/"$t78_rule"/}" ;;
      sh) t78_m6="${t78_m6/"$t78_rule"/}" ;;
      ps1) t78_m7="${t78_m7/"$t78_rule"/}" ;;
      budget)
        t78_kind="$((t78_rule + 1))-line copy"
        printf '%s' "$t78_clean_text" > "$t78_root/SKILL.md"
        t78_pad=$((t78_rule + 1 - $(wc -l < "$t78_root/SKILL.md")))
        for ((t78_j=0; t78_j<t78_pad; t78_j++)); do printf '\n' >> "$t78_root/SKILL.md"; done
        t66_load "$t78_root/SKILL.md"
        t78_m1=$t66_loaded
        ;;
      *) t78_m1="${t78_m1/"$t78_rule"/}" ;;
    esac
    t78_mut_out=$(t78_contract "$t78_m1" "$t78_m2" "$t78_m3" "$t78_m4" "$t78_m5" "$t78_m6" "$t78_m7")
    if [ "$t78_mut_out" = " ${t78_labels[$t78_i]}" ]; then
      ok "T78 ${t78_kind} mutation: ${t78_labels[$t78_i]} rejected by its own check"
    else
      bad "T78 ${t78_kind} mutation: ${t78_labels[$t78_i]}" \
        "got '${t78_mut_out:-<empty>}', want ' ${t78_labels[$t78_i]}'"
    fi
  done
fi
[ -z "$t78_err" ] && ok "T78 static contract alarm: fc-clean cleans only a finished goal's receipted leftovers and asks once; flows finish with it; Usage, banners, and 31-line budget pinned" \
                   || bad "T78 fc-clean cleanup contract" "missing:$t78_err"

# Behavior: the skill's own commands, run in fixture repositories isolated from
# the user's git configuration.
t78_env() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
}
t78_prune_check() { # prune command -> diagnostics; a local tag must survive, a stale ref must go
  local d err=""
  t78_env; d=$(mktemp -d "$t78_root/prune.XXXXXX")
  git init -q --bare "$d/o.git" && git init -q "$d/w" && cd "$d/w" || return
  git remote add origin "$d/o.git"
  git commit -q --allow-empty -m init && git push -q origin HEAD:refs/heads/main HEAD:refs/heads/gone 2>/dev/null
  # Delete on the remote side only: a push deletion would also drop the local
  # tracking ref and leave nothing stale to prune.
  git fetch -q origin && git --git-dir="$d/o.git" update-ref -d refs/heads/gone
  git config fetch.pruneTags true && git tag local-only
  git rev-parse -q --verify refs/remotes/origin/gone >/dev/null || { printf ' fixture-without-stale-ref\n'; return; }
  eval "${1//<remote>/origin}" >/dev/null 2>&1
  git rev-parse -q --verify refs/tags/local-only >/dev/null || err="$err tag-deleted"
  git rev-parse -q --verify refs/remotes/origin/gone >/dev/null && err="$err stale-ref-kept"
  printf '%s\n' "$err"
}
t78_cas_check() { # delete command -> diagnostics; a moved branch must survive, the receipted one must go
  local d old new cmd err=""
  t78_env; d=$(mktemp -d "$t78_root/cas.XXXXXX")
  git init -q "$d/w" && cd "$d/w" || return
  git commit -q --allow-empty -m init && git branch feat
  old=$(git rev-parse feat)
  new=$(git commit-tree -p "$old" -m moved "$(git rev-parse "$old^{tree}")") && git update-ref refs/heads/feat "$new"
  cmd=${1//<branch>/feat}
  eval "${cmd//<oid>/$old}" >/dev/null 2>&1
  git rev-parse -q --verify refs/heads/feat >/dev/null || err="$err moved-branch-deleted"
  eval "${cmd//<oid>/$new}" >/dev/null 2>&1
  git rev-parse -q --verify refs/heads/feat >/dev/null && err="$err receipted-branch-kept"
  printf '%s\n' "$err"
}
t78_ignored_check() { # status command -> diagnostics; it must list a worktree's ignored and untracked files
  local d out err=""
  t78_env; d=$(mktemp -d "$t78_root/ignored.XXXXXX")
  git init -q "$d/w" && cd "$d/w" || return
  printf 'ign.db\n' > .gitignore && git add .gitignore && git commit -q -m gi
  # Hides untracked (and so ignored) files from a bare `status --ignored`;
  # plain `git worktree remove` then deletes them without a word.
  git config status.showUntrackedFiles no
  git worktree add -q "$d/wt" -b wtb 2>/dev/null && printf 'data\n' > "$d/wt/ign.db" && printf 'mine\n' > "$d/wt/user.txt" && cd "$d/wt" || return
  out=$(eval "$1" 2>/dev/null)
  printf '%s\n' "$out" | grep -q 'ign.db' || err="$err ignored-file-hidden"
  printf '%s\n' "$out" | grep -q 'user.txt' || err="$err untracked-file-hidden"
  printf '%s\n' "$err"
}
t78_behavior() { # label, check function, skill command, weaker command, its expected diagnostic
  local got weak
  if [ -z "$3" ]; then bad "T78 behavior: $1" "command missing from fc-clean"; return; fi
  got=$("$2" "$3"); weak=$("$2" "$4")
  [ -z "$got" ] && ok "T78 behavior: $1 holds with the skill's command" \
                || bad "T78 behavior: $1" "skill command failed:$got"
  [ "$weak" = " $5" ] && ok "T78 behavior mutation: \`$4\` caught as$weak" \
                      || bad "T78 behavior mutation: $1" "got '${weak:-<empty>}', want ' $5'"
}
t78_root=${t78_root:-$(mktemp -d)}; CLEANUP_PATHS+=("$t78_root")
t78_prune_cmd=$(printf '%s\n' "$t78_clean_text" | grep -o '`git fetch --prune[^`]*`' | head -1 | tr -d '`')
t78_cas_cmd=$(printf '%s\n' "$t78_clean_text" | grep -o '`git update-ref -d [^`]*`' | head -1 | tr -d '`')
t78_ignored_cmd=$(printf '%s\n' "$t78_clean_text" | grep -o '`git status --porcelain --ignored[^`]*`' | head -1 | tr -d '`')
t78_behavior "stale-ref prune keeps local tags" t78_prune_check "$t78_prune_cmd" 'git fetch --prune <remote>' tag-deleted
t78_behavior "stale-ref prune removes stale refs" t78_prune_check "$t78_prune_cmd" \
  "git fetch --no-prune-tags <remote> '+refs/heads/*:refs/remotes/<remote>/*'" stale-ref-kept
t78_behavior "branch delete keeps a moved branch" t78_cas_check "$t78_cas_cmd" 'git branch -D <branch>' moved-branch-deleted
t78_behavior "worktree check sees ignored and untracked files" t78_ignored_check "$t78_ignored_cmd" \
  'git status --porcelain --ignored' 'ignored-file-hidden untracked-file-hidden'

# ---------------------------------------------------------------- T67
# T67: the wiki publisher mirrors wiki/ exactly, and its test catches drift.
# scripts/test-wiki-publish.sh (also a named CI step) holds the checks. Each
# replay removes one rule from a scratch copy; the copy's test must fail with
# that rule's diagnostic, and the unmutated control must pass.
if [ ! -f scripts/test-wiki-publish.sh ]; then
  bad "T67 wiki publisher test exists" "scripts/test-wiki-publish.sh is missing"
elif ! t67_out=$(bash scripts/test-wiki-publish.sh 2>&1 < /dev/null); then
  bad "T67 wiki publisher test passes on the real tree" "$t67_out"
else
  t67_dir=$(mktemp -d)
  # Replace the first literal occurrence, and fail when it is absent, so a
  # replay can never pass by changing nothing.
  t67_sub() {
    python3 - "$@" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if old not in text:
    sys.exit("t67: pattern not found in " + path)
open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
PY
  }
  t67_missed=""
  t67_count=0
  while IFS='|' read -r t67_name t67_expect t67_cmd; do
    [ -n "$t67_name" ] || continue
    rm -rf -- "$t67_dir/copy"
    mkdir -p "$t67_dir/copy/.github/workflows"
    mkdir -p "$t67_dir/copy/.claude"
    cp -R scripts wiki "$t67_dir/copy/"
    cp .claude/CLAUDE.md "$t67_dir/copy/.claude/"
    cp .github/workflows/publish-wiki.yml "$t67_dir/copy/.github/workflows/"
    if ! ( cd "$t67_dir/copy" && eval "$t67_cmd" ) < /dev/null > /dev/null 2>&1; then
      t67_missed="$t67_missed $t67_name(apply)"
      continue
    fi
    t67_msg=$(bash "$t67_dir/copy/scripts/test-wiki-publish.sh" 2>&1 < /dev/null) && t67_rc=0 || t67_rc=$?
    if [ "$t67_name" = control ]; then
      [ "$t67_rc" -eq 0 ] || t67_missed="$t67_missed control"
    elif [ "$t67_rc" -eq 0 ] || ! printf '%s\n' "$t67_msg" | grep -Fq -- "$t67_expect"; then
      t67_missed="$t67_missed $t67_name"
    else
      t67_count=$((t67_count + 1))
    fi
  done <<'T67'
control||true
push-line|workflow is missing: HEAD:master|t67_sub .github/workflows/publish-wiki.yml 'push origin HEAD:master' 'push origin'
fresh-main|workflow is missing: ref: main|t67_sub .github/workflows/publish-wiki.yml 'ref: main' 'ref: ${{ github.sha }}'
paths-filter|filters main pushes|t67_sub .github/workflows/publish-wiki.yml 'branches: [main]' $'branches: [main]\n    paths: ["wiki/**"]'
unpinned-action|not pinned to a full commit SHA|t67_sub .github/workflows/publish-wiki.yml '@3d3c42e5aac5ba805825da76410c181273ba90b1' '@v7'
permission-swap|default permissions must be contents: read|t67_sub .github/workflows/publish-wiki.yml 'contents: read' 'contents: SWAP' && t67_sub .github/workflows/publish-wiki.yml 'contents: write' 'contents: read' && t67_sub .github/workflows/publish-wiki.yml 'contents: SWAP' 'contents: write'
job-guard|publish job must run only on main|t67_sub .github/workflows/publish-wiki.yml "if: github.ref == 'refs/heads/main'" 'if: true'
serialized|serialized without cancellation|t67_sub .github/workflows/publish-wiki.yml 'cancel-in-progress: false' 'cancel-in-progress: true'
stale-deletion|retained a deleted page|t67_sub scripts/publish-wiki.sh ' -delete' ''
nested-deletion|touched a nested destination page|t67_sub scripts/publish-wiki.sh ' -maxdepth 1' ''
nested-copy|copied a nested source page|t67_sub scripts/publish-wiki.sh 'pages=("$source_dir"/*.md)' 'pages=("$source_dir"/*.md "$source_dir"/*/*.md)'
branch-guard|not on master|t67_sub scripts/publish-wiki.sh '== "master" ]] ||' '== "master" ]] || true ||'
canonical-rule|makes wiki/ canonical|t67_sub .claude/CLAUDE.md 'only source of truth' 'primary source'
verify-rule|post-merge publish check|t67_sub .claude/CLAUDE.md 'confirm the `Publish wiki` run' 'watch the wiki'
broken-link|target does not exist: Missing-Page|printf '\n[Gone](Missing-Page)\n' >> wiki/Home.md
md-link|must omit .md|printf '\n[Home](Home.md)\n' >> wiki/Home.md
home-coverage|missing link to Architecture|t67_sub wiki/Home.md '](Architecture)' '](Development-and-Release)'
doc-center-rule|documentation center|t67_sub .claude/CLAUDE.md 'documentation center' 'documentation home'
english-only-rule|English-only agent context|t67_sub .claude/CLAUDE.md 'Load only the English wiki pages for routine agent context' 'Load the wiki pages'
zh-naming-rule|name the separate Chinese files|t67_sub .claude/CLAUDE.md '<Page>-zh-CN.md' '<Page>-cn.md'
zh-mention|outside the naming rule|printf '\nSee Home-zh-CN.\n' >> .claude/CLAUDE.md
home-zh-coverage|missing link to Usage-zh-CN|t67_sub wiki/Home-zh-CN.md '](Usage-zh-CN)' '](Architecture-zh-CN)'
missing-counterpart|missing language counterpart: Usage-zh-CN|rm wiki/Usage-zh-CN.md
missing-switch|missing language-switch link to Usage-zh-CN|t67_sub wiki/Usage.md '[简体中文](Usage-zh-CN)' ''
cross-language|must stay in the same language|printf '\n[Other](Architecture-zh-CN)\n' >> wiki/Usage.md
heading-parity|heading-depth sequences differ|printf '\n## Extra\n' >> wiki/Usage.md
legacy-marker|legacy language marker|printf '\n## English\n' >> wiki/Usage.md
title|does not start with a title|t67_sub wiki/Usage.md '# Usage' 'Usage'
nested-page|nested Markdown pages are not allowed|mkdir wiki/sub && printf '# Nested\n' > wiki/sub/Deep.md
ascii-name|flat ASCII name|printf '# Page\n' > wiki/Über.md
english-cjk|Chinese text in an English page|printf '\n中文\n' >> wiki/Usage.md
chinese-without-cjk|no Chinese text in a Chinese page|printf '# Usage\n\n[English](Usage)\n' > wiki/Usage-zh-CN.md
ref-missing|target does not exist: Missing-Ref|printf '\n[gone]: Missing-Ref\n' >> wiki/Home.md
ref-md|must omit .md: Usage.md|printf '\n[md]: Usage.md\n' >> wiki/Home.md
ref-cross-language|must stay in the same language: Development-and-Release-zh-CN|printf '\n[zh]: Development-and-Release-zh-CN\n' >> wiki/Usage.md
ref-switch|missing language-switch link to Usage-zh-CN|t67_sub wiki/Usage.md '[简体中文](Usage-zh-CN)' '[zh]: Usage-zh-CN'
ref-home|missing link to Architecture|t67_sub wiki/Home.md '[Architecture](Architecture)' 'Architecture' && printf '\n[arch]: Architecture\n' >> wiki/Home.md
code-switch|missing language-switch link to Usage-zh-CN|t67_sub wiki/Usage.md '[简体中文](Usage-zh-CN)' '`[简体中文](Usage-zh-CN)`'
code-home|missing link to Architecture|t67_sub wiki/Home.md '[Architecture](Architecture)' '`[Architecture](Architecture)`'
indented-switch|missing language-switch link to Usage-zh-CN|t67_sub wiki/Usage.md '[简体中文](Usage-zh-CN)' '    [简体中文](Usage-zh-CN)'
raw-html|raw HTML is not allowed|t67_sub wiki/Home.md '- [Architecture](Architecture)' $'<!--\n- [Architecture](Architecture)\n-->'
html-link|raw HTML is not allowed|printf '\nSee <a href="Missing">this</a>.\n' >> wiki/Home.md
switch-label|missing language-switch link to Usage-zh-CN|t67_sub wiki/Usage.md '[简体中文](Usage-zh-CN)' '[Chinese](Usage-zh-CN)'
home-pipe|missing link to Architecture|t67_sub wiki/Home.md '[Architecture](Architecture)' '[Archi|tecture](Architecture)'
home-escape|missing link to Architecture|t67_sub wiki/Home.md '[Architecture](Architecture)' '[Architecture\](Architecture)'
home-backtick|missing link to Architecture|t67_sub wiki/Home.md '[Architecture](Architecture)' '[Arch`itecture](Architecture) x`'
fence-info|missing link to Usage|t67_sub wiki/Home.md '- [Usage](Usage)' $'```\n```text\n- [Usage](Usage)\n```'
fence-backtick-info|raw HTML is not allowed|printf '\n``` a`b\n<details>\n' >> wiki/Home.md
fence-indent|code fences must start at column 0|printf '\n\t```\n' >> wiki/Home.md
html-details|raw HTML is not allowed|printf '\nSee <details>\n' >> wiki/Home.md
multiline-link|target does not exist: Missing-Multi|printf '\n[broken\nlink](Missing-Multi)\n' >> wiki/Home.md
nested-link|target does not exist: Missing-Nested|printf '\n[a [b] c](Missing-Nested)\n' >> wiki/Home.md
quote-def|target does not exist: Missing-Quote|printf '\n> [q]: Missing-Quote\n' >> wiki/Home.md
nextline-def|target does not exist: Missing-Next|printf '\n[n]:\n  Missing-Next\n' >> wiki/Home.md
multiline-def|target does not exist: Missing-Label|printf '\n[multi\nlabel]: Missing-Label\n' >> wiki/Home.md
T67
  rm -rf -- "$t67_dir"
  if [ -z "$t67_missed" ]; then
    ok "T67 wiki publisher mirrors wiki/ exactly; ${t67_count} removal replays each fail with their diagnostic"
  else
    bad "T67 wiki publisher replays" "not caught:$t67_missed"
  fi
fi

# ---------------------------------------------------------------- T71
# A skill's frontmatter `model` switches the main session for the rest of the
# turn, which hardcodes the main agent's model (issue #54). Only the leading
# --- block counts; body prose may say "model:".
# Each engine exits 0 when the leading frontmatter sets a `model` key.
t71_has_model_yaml() {
  python3 - "$1" <<'T71PY'
import sys, yaml
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
if not lines or lines[0].rstrip("\r") != "---":
    sys.exit(1)
ends = [i for i in range(1, len(lines)) if lines[i].rstrip("\r") == "---"]
if not ends:
    sys.exit(1)
try:
    data = yaml.safe_load("\n".join(lines[1:ends[0]])) or {}
except yaml.YAMLError:
    sys.exit(0)  # unparsable frontmatter fails closed, as pinned
sys.exit(0 if isinstance(data, dict) and "model" in data else 1)
T71PY
}
t71_has_model_awk() { # fallback: ignore spaces and quotes around the key
  awk -v q="'" 'NR == 1 { sub(/\r$/, ""); if ($0 != "---") exit 1; next }
       { sub(/\r$/, "") } $0 == "---" { exit 1 }
       { key = $0; gsub(/[ \t"]/, "", key); gsub(q, "", key) }
       key ~ /^model:/ { found = 1; exit }
       END { exit !found }' "$1"
}
t71_engines=(awk)
if python3 -c 'import yaml' >/dev/null 2>&1; then
  t71_engines=(yaml awk)
else
  skip "T71 no YAML parser — skill pins checked by the awk fallback only"
fi
t71_has_model() { "t71_has_model_${t71_engines[0]}" "$1"; }
t71_pinned=""
for f in $(skill_files); do t71_has_model "$f" && t71_pinned="$t71_pinned $f"; done
[ -z "$t71_pinned" ] && ok "T71 no skill frontmatter pins the main agent's model" \
                     || bad "T71 skill model pin" "pinned:$t71_pinned"
# Every spelling that parses to a `model` key must be caught; body prose must not.
t71_dir="$(mktemp -d)"
CLEANUP_PATHS+=("$t71_dir")
t71_cases=(
  'plain|pin|model: sonnet'
  'spaced|pin|model : sonnet'
  'double-quoted|pin|"model": sonnet'
  "single-quoted|pin|'model': sonnet"
  'body-prose|clean|'
)
for t71_engine in "${t71_engines[@]}"; do
  for t71_case in "${t71_cases[@]}"; do
    IFS='|' read -r t71_label t71_want t71_line <<<"$t71_case"
    t71_file="$t71_dir/$t71_label.md"
    if [ -n "$t71_line" ]; then
      printf -- '---\nname: x\n%s\ndescription: y\n---\nbody\n' "$t71_line" > "$t71_file"
    else
      printf -- '---\nname: x\ndescription: y\n---\nmodel: sonnet\n' > "$t71_file"
    fi
    if "t71_has_model_$t71_engine" "$t71_file"; then t71_got=pin; else t71_got=clean; fi
    [ "$t71_got" = "$t71_want" ] && ok "T71 replay ($t71_engine): $t71_label frontmatter reads as $t71_want" \
                                 || bad "T71 replay ($t71_engine): $t71_label" "got $t71_got, want $t71_want"
  done
done

# ---------------------------------------------------------------- T79
# The plugin's SessionStart hook puts the routing contract into every session
# on both hosts. Claude Code reads only hookSpecificOutput.additionalContext
# and Copilot CLI only the top-level additionalContext, so routing.json holds
# the same text under both; keeping it in a file keeps JSON off the command
# line, where Windows argv quoting into PowerShell strips double quotes. The
# check runs the configured commands themselves, from a root with a space in
# its path, from a working directory outside it: `command` under bash, and
# `powershell` under pwsh when available (FC_STRICT fails a missing pwsh).
t79_check() { # $1 = plugin root, $2 = pwsh path or empty; prints issues
  python3 - "$1" "$2" <<'PY'
import json, os, pathlib, subprocess, sys
root, pwsh = pathlib.Path(sys.argv[1]), sys.argv[2]
errs = []
def load(p):
    try:
        return json.loads((root / p).read_text())
    except Exception:
        errs.append(f"{p}:unreadable"); return {}
hooks, routing = load("hooks/hooks.json"), load("hooks/routing.json")
events = hooks.get("hooks") or {}
if list(events) != ["SessionStart"]: errs.append("events-not-only-SessionStart")
groups = events.get("SessionStart") or [{}]
if len(groups) != 1 or "matcher" in groups[0]: errs.append("one-group-without-matcher")
entries = groups[0].get("hooks") or [{}]
entry = entries[0]
if len(entries) != 1 or entry.get("type") != "command": errs.append("one-command-hook")
hso = routing.get("hookSpecificOutput") or {}
text = hso.get("additionalContext", "")
if set(routing) != {"additionalContext", "hookSpecificOutput"}: errs.append("routing-keys")
if hso != {"hookEventName": "SessionStart", "additionalContext": text}: errs.append("hook-specific-output-shape")
if routing.get("additionalContext") != text: errs.append("host-texts-differ")
if not text.isascii() or not 0 < len(text) <= 900: errs.append("text-not-ascii-or-over-900")
# The contract's clauses: what triggers routing, re-routing grown scope, the
# delivery and review pointers, and leaving non-code questions alone.
for need in ("build, fix, change, refactor, implement, add, or extend code", "invoke /fc-build-or-fix before editing",
             "grows mid-way", "route the new scope through /fc-build-or-fix", "/fc-ship", "/fc-review", "change no code"):
    if need not in text: errs.append(f"text-missing:{need}")
if "| One discoverable fact |" in text: errs.append("text-duplicates-classifier")
def run(argv, var):
    env = dict(os.environ); env.pop("CLAUDE_PLUGIN_ROOT", None); env.pop("COPILOT_PLUGIN_ROOT", None)
    env[var] = str(root)
    try:
        out = subprocess.run(argv, env=env, cwd="/", capture_output=True, text=True, timeout=60).stdout
        return json.loads(out) == routing
    except Exception:
        return False
if not run(["bash", "-c", entry.get("command", "")], "CLAUDE_PLUGIN_ROOT"): errs.append("bash-command-output")
if pwsh and not run([pwsh, "-NoProfile", "-Command", entry.get("powershell", "")], "COPILOT_PLUGIN_ROOT"):
    errs.append("powershell-command-output")
print(" ".join(errs))
PY
}
t79_mutate() { # $1 = plugin root, $2 = mutation
  python3 - "$1" "$2" <<'PY'
import json, pathlib, sys
root, m = pathlib.Path(sys.argv[1]), sys.argv[2]
hp, rp = root / "hooks/hooks.json", root / "hooks/routing.json"
h, r = json.loads(hp.read_text()), json.loads(rp.read_text())
e = h["hooks"]["SessionStart"][0]["hooks"][0]
if m == "texts-differ": r["additionalContext"] += " x"
elif m == "single-quoted-root": e["command"] = e["command"].replace('"', "'")
elif m == "unquoted-root": e["command"] = e["command"].replace('"', "")
elif m == "no-literal-path": e["powershell"] = e["powershell"].replace("-LiteralPath", "-Path")
elif m == "matcher": h["hooks"]["SessionStart"][0]["matcher"] = "startup"
elif m == "over-cap": r["additionalContext"] = r["hookSpecificOutput"]["additionalContext"] = "/fc-build-or-fix /fc-ship /fc-review " + "x" * 900
elif m == "no-ship": r["additionalContext"] = r["hookSpecificOutput"]["additionalContext"] = r["additionalContext"].replace("/fc-ship", "shipping")
elif m == "event-name": r["hookSpecificOutput"]["hookEventName"] = "UserPromptSubmit"
elif m in ("no-trigger", "no-reroute", "no-exemption"):
    cut = {"no-trigger": "When a request asks to build, fix, change, refactor, implement, add, or extend code, ",
           "no-reroute": "If a task grows mid-way, such as a new repository, a refactor, or a release, pause and route the new scope through /fc-build-or-fix instead of continuing inline. ",
           "no-exemption": " Questions that change no code need none of this."}[m]
    assert cut in r["additionalContext"], m
    r["additionalContext"] = r["hookSpecificOutput"]["additionalContext"] = r["additionalContext"].replace(cut, "")
hp.write_text(json.dumps(h)); rp.write_text(json.dumps(r))
PY
}
if ! command -v python3 >/dev/null 2>&1; then
  skip "T79 session routing hook (python3 unavailable)"
else
  t79_dir=$(mktemp -d); CLEANUP_PATHS+=("$t79_dir")
  t79_root="$t79_dir/plugin [root]"
  mkdir -p "$t79_root"
  cp -R hooks "$t79_root/" 2>/dev/null
  t79_out=$(t79_check "$t79_root" "${PWSH_BIN:-}")
  [ -z "$t79_out" ] && ok "T79 SessionStart hook prints the routing contract for both hosts (bash${PWSH_BIN:+ and pwsh})" \
                    || bad "T79 session routing hook" "issues:${t79_out:-python-failed}"
  [ -n "${PWSH_BIN:-}" ] || skip "T79 PowerShell hook command (pwsh unavailable; set PWSH)"
  # A mutation counts only against a clean baseline; otherwise every mutation
  # "fails" for the baseline's reason and the check proves nothing.
  [ -z "$t79_out" ] && for t79_m in texts-differ single-quoted-root matcher over-cap no-ship event-name no-trigger no-reroute no-exemption unquoted-root ${PWSH_BIN:+no-literal-path}; do
    rm -rf "$t79_root/hooks"; cp -R hooks "$t79_root/"
    t79_mutate "$t79_root" "$t79_m"
    [ -n "$(t79_check "$t79_root" "${PWSH_BIN:-}")" ] && ok "T79 mutation caught: $t79_m" \
                                                       || bad "T79 mutation survived" "$t79_m"
  done
fi

echo
if [ "$SKIP" -gt 0 ]; then
  echo "== ${PASS} passed, ${FAIL} failed, ${SKIP} SKIPPED (coverage incomplete) =="
else
  echo "== ${PASS} passed, ${FAIL} failed =="
fi
[ "$FAIL" -eq 0 ]