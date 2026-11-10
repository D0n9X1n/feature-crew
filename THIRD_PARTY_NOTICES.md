# Third-party notices

Feature-Crew is MIT licensed. Some of its prompt text adapts practices from the projects below. Each adaptation is rewritten in our own words; no upstream file is copied.

## Ponytail

- Source: https://github.com/DietrichGebert/ponytail, Copyright (c) 2026 DietrichGebert, under the [MIT License](https://github.com/DietrichGebert/ponytail/blob/main/LICENSE).
- Used in: `skills/fc-build-or-fix/reference/smallest-change.md`, the lean and scale checks in `agents/fc-qa-code.md` and `skills/fc-review/SKILL.md`, the `shortcut:` marker, and the `evals/` approach.
- Changes: rewritten in our own words, limited to production code, with the failing test added to the never-cut list.

## Impeccable

- Source: https://github.com/pbakaus/impeccable, Copyright 2025 Paul Bakaus, under the [Apache License 2.0](https://github.com/pbakaus/impeccable/blob/main/LICENSE).
- Used in: the brief and critique floor checks in `agents/fc-designer.md`.
- Changes: rewritten in our own words, shortened, and reduced to non-blocking checks, with no numeric thresholds or scoring.
