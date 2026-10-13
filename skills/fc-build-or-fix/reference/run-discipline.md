# Run discipline

Loaded by `/fc-build-or-fix` at entry and on resume.

## Feedback
Check every incoming finding, such as QA results or PR comments, against the code and spec before acting on it. Reproduce a runnable failure before fixing it. Reject or defer an unsupported claim with a stated reason.

## Checkpoint
After each task or gate transition, and before a requested handoff or compaction, refresh a checkpoint of at most 25 lines at `$(git rev-parse --git-path fc-checkpoint.md)`, which is git-private and worktree-local. Record worktree and HEAD, approvals, stage, next action, blockers, and evidence and provenance links. On resume, reconcile HEAD, status, and diff against it, and re-verify stale evidence.

## Runtime proof
Changed user-visible behavior needs actual CLI/API execution or rendered interaction, with output or screenshot evidence. Existing end-to-end evidence counts; static or unit tests alone do not. If the runtime is unavailable, do not claim done. Non-behavioral changes state "N/A".
