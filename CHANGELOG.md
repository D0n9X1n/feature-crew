# Changelog

All notable changes to Feature-Crew. Format follows [Keep a Changelog](https://keepachangelog.com/); versioning is [semver](https://semver.org/) with three numbers.

## [5.0.0] — 2026-07-25

Breaking: every skill and agent gained an `fc-` prefix, and `AGENTS.md` was removed.

### Added

- **Six intent-scoped skills**, each named for what the user is missing: `/fc-research` (facts), `/fc-grill-me` (decisions), `/fc-brainstorm` (an approach), `/fc-build-or-fix` (the code), `/fc-review` (an artifact), `/fc-second-opinion` (a decision).
- **`tests/framework_test.sh`** — 26 assertions covering caps, model policy, installer parity, and gate language. Four are mutation tests that replay attacks reviewers used, each proven non-vacuous in both directions.
- **CI** — `test.yml` gates PRs; `release.yml` publishes a GitHub Release on `v*` tag push with notes spanning the previous tag to the new one.
- **Description contract** on every skill: what it does, when to use it, and when to use a sibling instead.
- **Plan cross-audit** in the Complex flow (step 6). The rule named `plan` as a must-audit artifact while the flow never audited it — present since v3.

### Changed

- **Model policy** is native Claude Code naming: operate roles inherit the session model, review roles carry `model: sonnet` in installed frontmatter. The audit rule now requires detecting an operate/review family collision and recording the gate **unsatisfied** rather than met.
- **Progressive disclosure** — `fc-build-or-fix/SKILL.md` dropped 287 → 128 lines; the Complex track and meta-work cap moved to `reference/`, loaded only when used.
- **Standard track costs one dispatch.** The spec cross-audit is conditional on the escalation list, and the single QA pass is a combined spec+code review where a spec gap blocks.
- **Hard gates 7 → 6.** Verification-evidence and tests-pass-before-commit were one gate stated twice. The user override now separates approvals the user owns from gates that exist to stop an agent claiming done falsely.
- **Agent sources are `fc-`prefixed**, so the installer's filename→name mapping table is gone — the subagent name is the source basename.
- **Orchestration cap** counts `agents/fc-pm.md` plus *every* `SKILL.md`. It previously named two files, so new skills could add unbounded orchestration text while the cap still read green.
- **`AGENTS.md` merged into `CLAUDE.md`.** This repo targets Claude Code only; two instruction files meant two places to drift.

### Fixed

- **Data loss.** Legacy-skill cleanup did an unconditional `rm -rf` of `~/.claude/skills/research/` and `~/.claude/skills/build-or-fix/`. Both are plausible personal skill names, so an install destroyed hand-written work with no prompt and no backup. Deletion now requires a matching `name:` **and** a Feature-Crew provenance marker.
- **UTF-8 corruption on Windows.** `install.ps1` used bare `Get-Content`/`Set-Content`, which default to the system ANSI code page on PowerShell 5.1. All six agent bodies contain non-ASCII; on a CJK code page every one was silently mangled while the install reported success.
- **Invalid agent YAML.** Generated frontmatter had an unquoted `description:` containing `": "`, which a plain YAML scalar may not — and the `model:` line the review policy depends on sits inside that block.
- **`--dry-run` claimed deletions it did not perform.**
- **Two tests certified nothing.** T15 probed with a dot-prefixed directory the installer's glob never enumerates; T10 checked only that tokens appeared somewhere in each installer, so a gutted `install.ps1` passed.

### Removed

- `AGENTS.md` — see `CLAUDE.md`.
- The `audit-pair: degraded (same-vendor)` telemetry field. When a second family is unreachable the rule is now *run fewer reviewers*, not fake diversity.

### Upgrading

```bash
git pull origin main && ./install.sh --force
```

Installed agent names are unchanged. The installer removes the legacy unprefixed skill directories, but only when it can prove it shipped them.

[5.0.0]: https://github.com/D0n9X1n/feature-crew/compare/v4.0...v5.0.0
