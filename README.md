# Feature-Crew

[![Release](https://img.shields.io/github/v/release/D0n9X1n/feature-crew?sort=semver)](https://github.com/D0n9X1n/feature-crew/releases/latest) [![CI](https://github.com/D0n9X1n/feature-crew/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/D0n9X1n/feature-crew/actions/workflows/test.yml) [![Docs](https://img.shields.io/badge/docs-wiki-blue)](https://github.com/D0n9X1n/feature-crew/wiki) [![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A52.1.251-D97757)](https://code.claude.com/docs) [![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](https://github.com/D0n9X1n/feature-crew/wiki/Usage)

**A need-based agent team for Claude Code.** Describe what you need in plain words; Feature-Crew looks up facts, settles decisions and approaches, then runs the code through right-sized TDD, hard gates, and cross-family review. MIT licensed.

**[Documentation](https://github.com/D0n9X1n/feature-crew/wiki)** · [Usage](https://github.com/D0n9X1n/feature-crew/wiki/Usage) · [Architecture](https://github.com/D0n9X1n/feature-crew/wiki/Architecture) · [简体中文](https://github.com/D0n9X1n/feature-crew/wiki/Home-zh-CN) · [Releases](https://github.com/D0n9X1n/feature-crew/releases)

## Quick start

Requires [Claude Code](https://code.claude.com/docs) 2.1.251 or later.

```bash
git clone https://github.com/D0n9X1n/feature-crew.git
cd feature-crew
./install.sh         # macOS / Linux / Git Bash / WSL
.\install.ps1        # native Windows PowerShell
```

Then describe the change you want in plain words inside Claude Code; Feature-Crew picks the skill and the track. To update later, run `/fc-update` from the clone. Flags and commands are in [Usage](https://github.com/D0n9X1n/feature-crew/wiki/Usage).

## Features

- **Need-based routing:** facts are looked up; evidence, decisions, approaches, confidence checks, and unexplained failures each go to one skill that returns to the flow.
- **Right-sized tracks:** Just Do It, Standard, and Complex, each with TDD and hard gates.
- **Cross-family review:** every hard-gate artifact is reviewed by a model from another family, picked at run time from the two most capable models available and proven from the session record.
- **Two designs before building:** Standard and Complex designs are compared against an independent second design; only a super straightforward Standard design skips it.
- **Verified shipping:** `/fc-ship` watches CI in the background and merges only the verified head.
- **Explained projects:** `/fc-explain` draws evidence-tied Mermaid diagrams.
- **Safe installers:** `install.sh` and `install.ps1` record what they install and remove only their own files.
