---
name: fc-clean
description: Removes a finished goal's leftovers — temp files, merged worktrees and branches, stale remote-tracking refs, task-made stashes, and task-owned processes — and keeps anything uncertain. Use when a Feature-Crew flow's goal is achieved and its outcome archived, or when the user asks to clean up. Do NOT use for an unfinished goal, for undoing or reverting changes (use /fc-build-or-fix), or for diagnosing a failure (use /fc-debug).
---

# fc-clean

Runs once, at the end of a goal: it removes only what a receipt proves this task created and no longer needs, with no backups, and asks once about everything else.

## Goal gate

Never clean while the goal is unfinished. An active `/goal` or Copilot autopilot objective not yet shown met is unfinished; so is a goal that ended without being achieved, so ask instead. Archive first: the outcome is committed, pushed, and merged as authorized, and reported to the user with its evidence. In Copilot autopilot, clean before `task_complete`.

## Receipts

A receipt names what a task created: the absolute path and inode of a `mktemp -d` root, a worktree path, a branch and its OID, a stash OID, a harness task id, or a PID with its start time and command. Flows record receipts in the checkpoint or their returned result; nested skills return them and never clean. Names alone never prove ownership.

## Remove

Check status, worktrees, sessions, and locks. Remove automatically only what a receipt covers, plus stale references, and re-check each receipt right before removing its item.
- **Worktree:** `git worktree remove`, never `--force`, only when it is unlocked, no session's working directory, its HEAD is in the base or among its merged PR's commits, and `git status --porcelain --ignored --untracked-files=all` lists nothing beyond its receipts.
- **Branch:** only when no worktree has it checked out and its head is in the base or among its merged PR's commits, via `git update-ref -d refs/heads/<branch> <oid>` so a moved branch is kept.
- **Stale references:** `git worktree prune` and `git fetch --prune --no-prune-tags <remote> '+refs/heads/*:refs/remotes/<remote>/*'`, which keep locked worktrees and local tags.
- **Stash:** only by its recorded OID, once its content has landed.
- **Temp root:** only at its recorded path and inode; never empty, `/`, home, or a repository root, never through a link, never by glob.
- **Process:** through the harness's task controls, or by a PID whose start time and command still match its receipt.
- **Checkpoint:** `$(git rev-parse --git-path fc-checkpoint.md)`, last.

## Keep, ask once, report

Keep dirty or unmerged work, stashes without a receipt, and anything uncertain, and list in one question everything kept that may be removable. In an autonomous session (*Think first* in `/fc-build-or-fix`), keep them and report instead of asking. Return to the updated base and report the final status and anything kept.
