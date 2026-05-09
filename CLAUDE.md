See [`AGENTS.md`](./AGENTS.md) for the full agent instructions — same content used by GitHub Copilot, Cursor, and any other AI assistant.

This file exists so Claude Code auto-loads the framework. The `.claude/skills/build-or-fix/SKILL.md` skill triggers on every build/fix/change request, and you can also invoke it explicitly with `/skill build-or-fix`.

Quick reference (full details in `AGENTS.md` and `.claude/skills/build-or-fix/SKILL.md`):

1. On every build/fix/change request → propose a track (Trivial / Standard / Complex) and confirm.
2. Read `.claude/skills/build-or-fix/SKILL.md` for the chosen track.
3. Honor every hard gate; cross-family model audit is mandatory on hard gates (preferred `claude-opus-4.7-xhigh` ⇆ `gpt-5.5`; fallback to same-vendor cross-family flagged as degraded).
4. Dispatch role agents from `agents/`.
5. TDD, verify-before-claim, root-cause-first, no-guessing, YAGNI.
