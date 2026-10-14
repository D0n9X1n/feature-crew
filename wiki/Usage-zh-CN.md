# 使用说明

[English](Usage)

如何安装、运行和更新 Feature-Crew。返回[首页](Home-zh-CN)。

## 安装

Feature-Crew 是一个同时用于 Claude Code 和 GitHub Copilot CLI 的插件。可以装在其中一个或两个里：

```bash
claude plugin marketplace add D0n9X1n/feature-crew
claude plugin install feature-crew@feature-crew
copilot plugin marketplace add D0n9X1n/feature-crew
copilot plugin install feature-crew@feature-crew
```

也可以在克隆的仓库里运行 `./install.sh`（macOS / Linux / Git Bash / WSL）或 `.\install.ps1`（原生 Windows PowerShell）：它会在 PATH 上找到的每个 CLI 中安装或更新插件，然后从 `~/.claude` 删除旧的脚本安装。旧的 `fc-*` 代理和技能即使被修改过也会删除，因为它们会代替插件里的版本运行；更早的文件只有在哈希证明是 Feature-Crew 写入时才删除。不会经由链接删除任何内容，无论链接的是前缀、`agents` 还是 `skills`；其中旧的 `fc-*` 条目会被报告。旧文件或文件夹无法读取或删除时，运行在任何改动之前以退出码 2 停止。在 Claude Code 中它只管理用户作用域的安装，项目自己的 Feature-Crew 设置保持不变。参数：`--dry-run`、`--check`、`--uninstall`、`--prefix DIR`、`--source SRC`；`install.ps1` 还接受 `-DryRun`、`-Check`、`-Uninstall`、`-Prefix DIR`、`-Source SRC`。

技能保留原名，例如 `/fc-build-or-fix`。代理注册为 `feature-crew:fc-*`，例如 `feature-crew:fc-qa-code`。

## 描述需求

不需要了解斜杠命令。Feature-Crew 会区分可以直接查到的事实、需要多方来源的证据、由用户决定的事项、尚未解决的方案、对已选定重大决定的对抗性信心检查，以及无法解释的故障。第一种它直接查找，其余的交给相应的技能。一个子技能解决一类问题后返回发起它的流程，该流程继续执行，不会递归调用，也不会对未变化的缺口重复处理。

精确的分类器只在 `skills/fc-build-or-fix/SKILL.md` 中写一次；本页不重复它。也可以直接使用这些命令：`/fc-research`、`/fc-grill-me`、`/fc-brainstorm`、`/fc-debug`、`/fc-explain`、`/fc-build-or-fix`、`/fc-ship`、`/fc-review`、`/fc-second-opinion` 和 `/fc-update`。

## 更新

运行 `/fc-update`。它通过每个 CLI 自己的命令更新插件，报告已安装的版本，并报告 `~/.claude` 中残留的旧脚本安装；用 `./install.sh --dry-run` 然后 `./install.sh` 删除它。之后开启新会话，或在 Claude Code 中运行 `/reload-plugins`。
