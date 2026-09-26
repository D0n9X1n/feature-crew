---
name: fc-debug
description: Diagnoses an unexplained failure before anyone attempts a fix — reproduces it, tests one hypothesis at a time within three experiments, and returns the root cause, evidence, and a regression-test recipe to the calling flow. Use when a test, build, command, or behavior fails and the cause is not yet proven. Do NOT use for a failure whose cause is already known or for making the fix (use /fc-build-or-fix), or for reviewing an artifact (use /fc-review).
---

# fc-debug

Diagnosis only: find why it fails; the calling flow owns any fix.

## Record

Record the caller and resume point. Record expected vs. actual behavior. Record the environment.

## Investigate

Reproduce the failure first. Trace the failing boundary against known-good behavior. Test one falsifiable hypothesis at a time. Run at most three experiments.

## Boundaries

Leave tracked files as found (scratch reproductions, or a scratch copy for instrumentation). Never mask a failure. Never commit. Never delegate. Never invoke another skill. Never claim "fixed".

## Report

Return command/output evidence. State the root cause and your confidence in it. Cite `file:line` references. List rejected hypotheses. Give a regression-test recipe that the calling flow writes as its failing test.

## Blocked

No reproduction, no access, or experiments exhausted: return BLOCKED with the evidence. The caller pauses.

## After the diagnosis

A diagnosis does not reset the caller's three-fix counter. Invoked directly, fc-debug offers `/fc-build-or-fix` instead of launching it.
