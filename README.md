# Feature-Crew

**v5.2.1** · A need-based agent-team framework for **Claude Code**. Describe what you need naturally; Feature-Crew looks up facts, resolves decisions and approaches, then runs code through right-sized TDD and hard gates. Full documentation lives in the [wiki](https://github.com/D0n9X1n/feature-crew/wiki) ([简体中文](https://github.com/D0n9X1n/feature-crew/wiki/Home-zh-CN)). MIT licensed.

## Quick start

```bash
./install.sh         # macOS / Linux / Git Bash / WSL
.\install.ps1        # native Windows PowerShell
```

Then describe the change you want in plain words inside Claude Code; Feature-Crew picks the skill and the track. Flags, commands, and updating are in [Usage](https://github.com/D0n9X1n/feature-crew/wiki/Usage).

## Features

- **Need-based routing:** facts are looked up; evidence, decisions, approaches, confidence checks, and unexplained failures each go to one skill that returns to the flow.
- **Right-sized tracks:** Just Do It, Standard, and Complex, each with TDD and hard gates.
- **Cross-family review:** every hard-gate artifact is reviewed by a model from another family, proven from the session record.
- **Two designs before building:** Standard and Complex designs are compared against an independent second design; only a super straightforward Standard design skips it.
- **Verified shipping:** `/fc-ship` watches CI in the background and merges only the verified head.
- **Explained projects:** `/fc-explain` draws evidence-tied Mermaid diagrams.
- **Safe installers:** `install.sh` and `install.ps1` record what they install and remove only their own files.
