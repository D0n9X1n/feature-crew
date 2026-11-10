# Smallest change

Loaded through [run-discipline.md](run-discipline.md) before writing production code, and pasted into every developer task. Adapted from [Ponytail](https://github.com/DietrichGebert/ponytail) (MIT). It governs production code only; tests follow TDD and are never shrunk to save lines.

## Ladder

Take the first option that fully works:

1. Does it need to exist? Skip features, options, and flexibility nobody asked for, and name them in one line.
2. Already in this codebase? Reuse the helper, component, or pattern the way the surrounding code does.
3. The standard library or a platform feature, unless the project has its own.
4. An installed dependency. Never add a dependency for a few lines.
5. One line a reader gets at a glance.
6. Otherwise, the minimum code that works.

## Complete, not lazy

Be lazy about the solution, never about the change: reach every caller, test, fixture, config, and export the change touches. For a bug fix, grep every caller of the function first, then fix the root cause once in the shared code. No abstraction, wrapper, option, config, or "for later" code nobody asked for. Deletion beats addition. Code you move or merge keeps its error handling and validation. Between options of equal size, take the one that is correct on edge cases.

## Never cut

validation at trust boundaries, error handling that prevents data loss, security, accessibility, the failing test and its edge cases, and anything the user asked for.

## Shortcuts

A deliberate shortcut with a known limit carries a code comment: `shortcut: <the limit>, <when to upgrade>`. Name it in the report; reviews treat it as a decision, and `/fc-review` can list every marker.
