#!/usr/bin/env bash
# Tests the wiki publisher offline, the publish workflow's contract, the
# CLAUDE.md wiki rule, and the links between wiki pages. Adapted from
# SonicTerm's scripts/test-wiki-publish.sh; Feature-Crew's wiki is English-only,
# so the bilingual checker is not ported.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
publisher="$root/scripts/publish-wiki.sh"
workflow="$root/.github/workflows/publish-wiki.yml"
guidance="$root/CLAUDE.md"
wiki="$root/wiki"

fail() {
  printf 'wiki publish test: %s\n' "$1" >&2
  exit 1
}

[[ -x "$publisher" ]] || fail "publisher is missing or not executable"
[[ -f "$workflow" ]] || fail "workflow is missing"

# Fixture commits must not depend on the caller's Git configuration or step output.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GITHUB_OUTPUT

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
source_dir="$tmp/source"
wiki_repo="$tmp/wiki"
mkdir -p "$source_dir"
git init -q -b master "$wiki_repo"
git -C "$wiki_repo" config user.name test
git -C "$wiki_repo" config user.email test@example.invalid
printf '# stale\n' > "$wiki_repo/Stale.md"
printf '# old\n' > "$wiki_repo/Keep.md"
mkdir "$wiki_repo/nested"
echo '# nested page' > "$wiki_repo/nested/Deep.md"
git -C "$wiki_repo" add --all
git -C "$wiki_repo" commit -q -m seed

printf '# home\n' > "$source_dir/Home.md"
printf '# current\n' > "$source_dir/Keep.md"
printf 'not a wiki page\n' > "$source_dir/ignored.txt"
mkdir "$source_dir/nested"
echo '# nested source' > "$source_dir/nested/Child.md"

first_output="$tmp/first-output"
GITHUB_OUTPUT="$first_output" "$publisher" "$source_dir" "$wiki_repo" 0123456789abcdef > /dev/null
[[ "$(<"$first_output")" == "changed=true" ]] || fail "changed publish did not request a push"
[[ -d "$wiki_repo/.git" ]] || fail "publisher removed Git metadata"
[[ "$(git -C "$wiki_repo" branch --show-current)" == "master" ]] || fail "publisher changed branch"
[[ -f "$wiki_repo/Home.md" ]] || fail "publisher omitted a new page"
[[ "$(<"$wiki_repo/Keep.md")" == "# current" ]] || fail "publisher did not update a page"
[[ ! -e "$wiki_repo/Stale.md" ]] || fail "publisher retained a deleted page"
[[ ! -e "$wiki_repo/ignored.txt" ]] || fail "publisher copied a non-Markdown file"
# Only top-level pages are in scope: nested Markdown is never copied or deleted.
[[ -f "$wiki_repo/nested/Deep.md" && "$(<"$wiki_repo/nested/Deep.md")" == "# nested page" ]] || fail "publisher touched a nested destination page"
[[ ! -e "$wiki_repo/Child.md" && ! -e "$wiki_repo/nested/Child.md" ]] || fail "publisher copied a nested source page"
[[ "$(git -C "$wiki_repo" rev-list --count HEAD)" == "2" ]] || fail "first publish did not create one commit"
[[ "$(git -C "$wiki_repo" log -1 --pretty=%s)" == "Publish wiki from 0123456" ]] || fail "commit does not identify source SHA"

no_change_output="$tmp/no-change-output"
GITHUB_OUTPUT="$no_change_output" "$publisher" "$source_dir" "$wiki_repo" 0123456789abcdef > /dev/null
[[ "$(<"$no_change_output")" == "changed=false" ]] || fail "unchanged publish requested a push"
[[ "$(git -C "$wiki_repo" rev-list --count HEAD)" == "2" ]] || fail "unchanged publish created a commit"

rm "$source_dir/Keep.md"
printf '# renamed\n' > "$source_dir/Renamed.md"
"$publisher" "$source_dir" "$wiki_repo" fedcba9876543210 > /dev/null
[[ ! -e "$wiki_repo/Keep.md" ]] || fail "rename retained the old page"
[[ -f "$wiki_repo/Renamed.md" ]] || fail "rename omitted the new page"
[[ "$(git -C "$wiki_repo" rev-list --count HEAD)" == "3" ]] || fail "rename did not create one commit"

# Invalid inputs must fail before anything touches the destination. A pending
# page makes any publish that slips through visible in the snapshot.
printf '# pending\n' > "$source_dir/Pending.md"
snapshot() {
  ls -A "$1"
  cat "$1"/*.md 2> /dev/null || true
  if [[ -d "$1/.git" ]]; then
    git -C "$1" rev-parse HEAD
    git -C "$1" branch --show-current
    git -C "$1" status --porcelain
  fi
}
expect_rejected() {
  local label="$1" dest="$2" before
  shift 2
  before="$(snapshot "$dest")"
  if "$publisher" "$@" > /dev/null 2>&1; then
    fail "publisher accepted $label"
  fi
  [[ "$(snapshot "$dest")" == "$before" ]] || fail "publisher changed the destination for $label"
}
mkdir "$tmp/no-pages" "$tmp/plain"
printf 'notes\n' > "$tmp/no-pages/notes.txt"
printf '# keep\n' > "$tmp/plain/Keep.md"
expect_rejected "a missing argument" "$wiki_repo" "$source_dir" "$wiki_repo"
expect_rejected "a missing source" "$wiki_repo" "$tmp/missing" "$wiki_repo" 0123456789abcdef
expect_rejected "a source without pages" "$wiki_repo" "$tmp/no-pages" "$wiki_repo" 0123456789abcdef
expect_rejected "a destination that is not a Git worktree" "$tmp/plain" "$source_dir" "$tmp/plain" 0123456789abcdef
git -C "$wiki_repo" switch -q -c other
expect_rejected "a destination not on master" "$wiki_repo" "$source_dir" "$wiki_repo" 0123456789abcdef
git -C "$wiki_repo" switch -q master

# Workflow structure: triggers, permission scopes, the job guard, serialization.
structure="$(python3 - "$workflow" 2>&1 <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("PyYAML is required to check the workflow structure")
    sys.exit(1)
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
on = wf.get("on", wf.get(True)) or {}  # YAML 1.1 reads the key `on` as true
push = on.get("push") or {}
jobs = wf.get("jobs") or {}
job = jobs.get("publish") or {}
concurrency = wf.get("concurrency") or {}
checks = [
    (set(on) == {"push", "workflow_dispatch"}, "workflow must run on pushes and manual runs only"),
    (push.get("branches") == ["main"], "workflow must run on pushes to main"),
    (not {"paths", "paths-ignore"} & set(push), "workflow filters main pushes instead of publishing after every merge"),
    (wf.get("permissions") == {"contents": "read"}, "workflow default permissions must be contents: read"),
    (list(jobs) == ["publish"], "workflow must have exactly one job, publish"),
    (job.get("permissions") == {"contents": "write"}, "only the publish job may write contents"),
    (job.get("if") == "github.ref == 'refs/heads/main'", "publish job must run only on main"),
    (concurrency.get("group") == "publish-wiki" and concurrency.get("cancel-in-progress") is False,
     "publish runs must be serialized without cancellation"),
]
for passed, message in checks:
    if not passed:
        print(message)
        sys.exit(1)
PY
)" || fail "$structure"

# Workflow steps: publish main as it is now, with only the job's short-lived token.
for required in \
  'ref: main' \
  'persist-credentials: false' \
  'secrets.GITHUB_TOKEN' \
  "x-access-token:\${GH_TOKEN}" \
  'scripts/publish-wiki.sh wiki wiki-repo "$(git rev-parse HEAD)"' \
  "if: steps.mirror.outputs.changed == 'true'" \
  'HEAD:master'; do
  grep -Fq -- "$required" "$workflow" || fail "workflow is missing: $required"
done
if grep -E '^[[:space:]-]*uses:' "$workflow" | grep -Evq 'uses: [^@[:space:]]+@[0-9a-f]{40}([[:space:]]|$)'; then
  fail "workflow uses an action not pinned to a full commit SHA"
fi
if grep -o 'secrets\.[A-Za-z0-9_]*' "$workflow" | grep -vqx 'secrets.GITHUB_TOKEN'; then
  fail "workflow introduces a credential other than the job's GITHUB_TOKEN"
fi

grep -Fq 'only source of truth' "$guidance" || fail "guidance no longer makes wiki/ canonical"
grep -Fq 'Never edit the GitHub wiki directly' "$guidance" || fail "guidance permits divergent browser edits"
grep -Fq 'overwritten on the next publish' "$guidance" || fail "guidance omits one-way mirror behavior"
grep -Fq 'updates `wiki/` in the same PR' "$guidance" || fail "guidance lets documented behavior drift from the wiki"
grep -Fq 'confirm the `Publish wiki` run' "$guidance" || fail "guidance omits the post-merge publish check"

[[ -f "$wiki/Home.md" ]] || fail "wiki has no Home page"
shopt -s nullglob
pages=("$wiki"/*.md)
for page in "${pages[@]}"; do
  name="$(basename "$page" .md)"
  [[ "$(head -n 1 "$page")" == '# '* ]] || fail "$name does not start with a title"
  # Links outside fenced blocks and inline code must name an existing page.
  links="$(awk '/^[[:space:]]*```/ { fence = !fence; next } !fence' "$page" \
    | sed 's/`[^`]*`//g' | grep -oE '[]][(][^)]*[)]' | sed 's/^](//; s/)$//' || true)"
  while IFS= read -r target; do
    case "$target" in
      '' | http://* | https://* | mailto:* | '#'*) continue ;;
    esac
    target="${target%%#*}"
    [[ "$target" =~ ^[A-Za-z0-9-]+$ ]] || fail "$name links to '$target'; link wiki pages by page name"
    [[ -f "$wiki/$target.md" ]] || fail "$name links to a missing page: $target"
  done <<< "$links"
done
for page in "${pages[@]}"; do
  name="$(basename "$page" .md)"
  [[ "$name" == Home ]] || grep -Fq "]($name)" "$wiki/Home.md" || fail "Home does not link to $name"
done

printf 'wiki publish test: ok\n'
