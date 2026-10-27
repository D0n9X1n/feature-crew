---
name: fc-ship
description: Finishes a pull request — watches CI asynchronously with a callback to the main agent on failure, merges only a verified head, optionally releases, and always cleans up, with no polling loops. Use when authorized work needs pushing, CI watching, merging, releasing, or post-merge cleanup, including the hand-off from /fc-build-or-fix. Do NOT use for writing, fixing, or diagnosing code (use /fc-build-or-fix or /fc-debug) or for reviewing a PR (use /fc-review).
---

# fc-ship

Ships authorized work: async CI with a callback, a verified merge, an optional release, and mandatory cleanup. No custom polling script.

## 1 — Authorize

Commit, push, PR, merge, and tag/publish are separate authorizations; none implies another. Ask for every missing approval in one question up front, then do only what is approved. In an autonomous session (*Think first* in `/fc-build-or-fix`), ask nothing: the goal or instruction is the approval, and merge or release only when it covers delivery.

## 2 — Watch CI asynchronously

After each push, record the head SHA. The main agent itself — never a subagent, because a background task notifies whoever started it — starts one background watch on the recorded head, `gh pr checks <pr> --watch --fail-fast --required --interval 30`, and keeps working meanwhile. When gh reports no required checks, watch all checks instead: drop `--required` here and when reading states.

## 3 — Read the outcome

When the watch exits, read the actual check states and the PR head; the exit code cannot tell success from cancellation, and the watch follows the latest PR commit. Run `gh pr checks <pr> --required --json name,state,bucket,link` and `gh pr view <pr> --json headRefOid,state,mergeCommit`. Report each outcome: failure (immediately, via `--fail-fast`), success, cancelled, action-required, timed out, no checks, API error, head changed, PR closed or merged. A watcher error or time limit re-arms once, then reports. No loops.

## 4 — Failure

Fetch `gh run view <id> --log-failed`, taking the run id from the failed check link. Return head, run, and log evidence to the calling flow, which routes it to `/fc-debug` and fixes under its own gates; invoked directly, fc-ship routes it itself. Shipping resumes only on a new, verified head.

## 5 — Merge

Right before the irreversible step, re-verify head, gates, and approval. Run `git fetch origin <base>` and require the PR head to contain the current base tip: `git merge-base --is-ancestor origin/<base> <head>`. If the base advanced: rebase and push only the feature branch with `git push --force-with-lease=<branch>:<old-head> origin <branch>` (fc-ship never pushes the base), rerun the full suite and CI on the new head, and compare with `git range-diff origin/<base> <old-head> <head>`. Parts changed by conflict resolution get a cross-family re-review (selector in `/fc-build-or-fix`).

Then run `gh pr merge <pr> --squash --match-head-commit <sha>` with no bypass (`--admin`, `--auto`) and no `--delete-branch`. Confirm the merge through PR metadata (`state` is `MERGED`), fetch the base, and verify the merged tree equals the head tree: `git diff --quiet <head> <merge-commit>`. If it still differs: stop and report; the goal is unfinished, so do not clean up.

## 6 — Release

Release only when approved: tag the verified base commit, push the tag last, watch the release run in the background (`gh run watch <id> --exit-status`), and verify the published body.

## 7 — Clean up

Cleanup is mandatory when shipping ends. Once the goal is achieved, finish with `/fc-clean`; until then, keep the receipts.
