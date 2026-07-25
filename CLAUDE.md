See [`AGENTS.md`](./AGENTS.md) for the full agent instructions.

This file exists so Claude Code auto-loads the framework.

Quick reference:

1. Every request routes to a skill: `/fc-research` (facts) · `/fc-grill-me` (decisions) · `/fc-brainstorm` (approach) · `/fc-build-or-fix` (code) · `/fc-review` (artifact) · `/fc-second-opinion` (claim).
2. On any build/fix/change → propose a track (Trivial / Standard / Complex) and confirm first.
3. Honor every hard gate. The cross-family audit rule is canonical in `.claude/skills/fc-build-or-fix/SKILL.md`.
4. Operate roles use the session model; review roles use `model: sonnet`.
5. TDD, verify-before-claim, root-cause-first, no-guessing, YAGNI.
6. Framework changes are Standard-track max and must keep `tests/framework_test.sh` green.
