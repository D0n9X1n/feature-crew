# 使用说明

[English](Usage)

如何安装、运行和更新 Feature-Crew。返回[首页](Home-zh-CN)。

## 安装

```bash
./install.sh         # macOS / Linux / Git Bash / WSL
.\install.ps1        # native Windows PowerShell
```

参数：`--force`、`--dry-run`、`--uninstall`、`--check`、`--verify`、`--prefix DIR`；`install.ps1` 还接受 `-Force`、`-DryRun`、`-Uninstall`、`-Check`、`-Verify`、`-Prefix DIR`。代理安装到 `~/.claude/agents/fc-*.md`；技能安装到 `~/.claude/skills/fc-*/`。

## 描述需求

不需要了解斜杠命令。Feature-Crew 会区分可以直接查到的事实、需要多方来源的证据、由用户决定的事项、尚未解决的方案、对已选定重大决定的对抗性信心检查，以及无法解释的故障。第一种它直接查找，其余的交给相应的技能。一个子技能解决一类问题后返回发起它的流程，该流程继续执行，不会递归调用，也不会对未变化的缺口重复处理。

精确的分类器只在 `.claude/skills/fc-build-or-fix/SKILL.md` 中写一次；本页不重复它。也可以直接使用这些命令：`/fc-research`、`/fc-grill-me`、`/fc-brainstorm`、`/fc-debug`、`/fc-explain`、`/fc-build-or-fix`、`/fc-ship`、`/fc-review`、`/fc-second-opinion` 和 `/fc-update`。

## 更新

运行 `/fc-update`，或 `git pull origin main && ./install.sh --force`。覆盖前，更新流程会报告你修改过的已安装文件。遗留清理和卸载只删除内容能精确证明由 Feature-Crew 安装的文件。每次安装都会在 `~/.claude/feature-crew.sha256` 中记录写入了什么，因此更新流程能分辨你的修改和上游的变化。
