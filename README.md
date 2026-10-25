# Feature-Crew

[![Release](https://img.shields.io/github/v/release/D0n9X1n/feature-crew?sort=semver)](https://github.com/D0n9X1n/feature-crew/releases/latest) [![CI](https://github.com/D0n9X1n/feature-crew/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/D0n9X1n/feature-crew/actions/workflows/test.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE) [![Docs](https://img.shields.io/badge/docs-wiki-blue)](https://github.com/D0n9X1n/feature-crew/wiki) [![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A52.1.251-D97757)](https://code.claude.com/docs) [![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](https://github.com/D0n9X1n/feature-crew/wiki/Usage)

**A need-based agent team for Claude Code.** Describe what you need in plain words; Feature-Crew looks up facts, settles decisions and approaches, then runs the code through right-sized TDD, hard gates, and cross-family review. MIT licensed.

**[Documentation](https://github.com/D0n9X1n/feature-crew/wiki)** · [Usage](https://github.com/D0n9X1n/feature-crew/wiki/Usage) · [Architecture](https://github.com/D0n9X1n/feature-crew/wiki/Architecture) · [简体中文](https://github.com/D0n9X1n/feature-crew/wiki/Home-zh-CN) · [Releases](https://github.com/D0n9X1n/feature-crew/releases)

## Quick start

Requires [Claude Code](https://code.claude.com/docs) 2.1.251 or later, or GitHub Copilot CLI 1.0.97 or later.

```bash
claude plugin marketplace add D0n9X1n/feature-crew
claude plugin install feature-crew@feature-crew
copilot plugin marketplace add D0n9X1n/feature-crew
copilot plugin install feature-crew@feature-crew
```

Then describe the change you want in plain words; Feature-Crew picks the skill and the track. To update later, run `/fc-update`. Coming from an old `./install.sh` install? Run `./install.sh` from a clone to switch to the plugin. Details are in [Usage](https://github.com/D0n9X1n/feature-crew/wiki/Usage).

## Features

- **Need-based routing:** facts are looked up; evidence, decisions, approaches, confidence checks, and unexplained failures each go to one skill that returns to the flow.
- **Right-sized tracks:** Just Do It, Standard, and Complex, each with TDD and hard gates.
- **Cross-family review:** every hard-gate artifact is reviewed by a model from another family, chosen from the two most capable models the agent can use and proven from the session record.
- **Two designs before building:** Standard and Complex designs are compared against an independent second design; only a super straightforward Standard design skips it.
- **Researched designs:** Standard and Complex designs start from a cited industry survey; a better approach that needs a requirement relaxed is shown to you as a trade-off.
- **Verified shipping:** `/fc-ship` watches CI in the background and merges only the verified head.
- **Clean finish:** once the goal is achieved, `/fc-clean` removes only the leftovers the task can prove it created, with no backups, and asks once about the rest.
- **Explained projects:** `/fc-explain` draws evidence-tied Mermaid diagrams.
- **One plugin, two CLIs:** the same `feature-crew` plugin installs in Claude Code and GitHub Copilot CLI; `install.sh` and `install.ps1` migrate an old script install.
