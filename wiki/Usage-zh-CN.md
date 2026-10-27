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

也可以在克隆的仓库里运行 `./install.sh`（macOS / Linux / Git Bash / WSL）或 `.\install.ps1`（原生 Windows PowerShell）：它会在 PATH 上找到的每个 CLI 中安装或更新插件，然后从 `~/.claude` 删除旧的脚本安装。旧的 `fc-*` 代理和技能即使被修改过也会删除，因为它们会代替插件里的版本运行；更早的文件只有在哈希证明是 Feature-Crew 写入时才删除。不会经由链接删除任何内容，无论链接的是前缀、`agents` 还是 `skills`；其中旧的 `fc-*` 条目会被报告。旧文件或文件夹无法读取或删除时，运行在任何改动之前以退出码 2 停止。如果系统之后仍拒绝删除或读取（不可变文件、文件锁、运行期间的变化），运行会列出剩下的内容并以退出码 1 结束；处理后再运行一次即可。在 Claude Code 中它只管理用户作用域的安装，项目自己的 Feature-Crew 设置保持不变。参数：`--dry-run`、`--check`、`--uninstall`、`--prefix DIR`、`--source SRC`；`install.ps1` 还接受 `-DryRun`、`-Check`、`-Uninstall`、`-Prefix DIR`、`-Source SRC`。

技能保留原名，例如 `/fc-build-or-fix`。代理注册为 `feature-crew:fc-*`，例如 `feature-crew:fc-qa-code`。

**已知限制。**
- 旧的 `fc-*` 技能文件夹会整个删除；其中在运行期间变得不可读的文件也会随之删除。
- 原生 Windows 无法预先检查权限，因此无法删除的文件只会在运行期间发现（退出码 1）。
- Claude Code 每个市场名称只保留一个来源：如果某个项目从另一个来源声明了 `feature-crew`，切换你的安装来源也会改变项目的来源，`--uninstall` 会移除项目的安装，但项目设置保留。
- 从 Git URL 添加的 Copilot 市场按 Copilot 显示的 `URL:` 标签匹配；这一路径只用桩 CLI 测试过。

## 描述需求

不需要了解斜杠命令。Feature-Crew 会区分可以直接查到的事实、需要多方来源的证据、由用户决定的事项、尚未解决的方案、对已选定重大决定的对抗性信心检查，以及无法解释的故障。第一种它直接查找，其余的交给相应的技能。一个子技能解决一类问题后返回发起它的流程，该流程继续执行，不会递归调用，也不会对未变化的缺口重复处理。

精确的分类器只在 `skills/fc-build-or-fix/SKILL.md` 中写一次；本页不重复它。也可以直接使用这些命令：`/fc-research`、`/fc-grill-me`、`/fc-brainstorm`、`/fc-debug`、`/fc-explain`、`/fc-build-or-fix`、`/fc-ship`、`/fc-clean`、`/fc-review`、`/fc-second-opinion` 和 `/fc-update`。

## 先思考再构建

在构建 Standard 或 Complex 变更之前，Feature-Crew 先用 `/fc-research` 调研问题，用 `/fc-brainstorm` 比较三种方案，再用 `/fc-grill-me` 向你提问：至少一轮，问未决的决定，没有未决问题时用一个问题确认计划。Just Do It 变更（明显、低风险、可撤销）跳过这一步。要为某个变更跳过它，请明确说出来，例如“跳过调研”或“不用问了，直接做”；代理会说明跳过了什么。“开始吧”只批准计划，不跳过任何步骤。测试、跨家族审查和规格检查始终运行。

在 Claude Code 的 `/goal` 或 Copilot CLI 的 autopilot 会话中，或在你说“你全权处理”之后，代理不再向你提问，直到该目标的清理和最终报告完成。调研和头脑风暴照常运行。它用自己的推荐回答自己的问题、代你豁免需要你批准的事项，把每一项记录为它自己的决定，并在最后报告。它不能豁免跨家族审查、Tech Lead 批准、验证、规格符合性或宿主权限。对于无法撤销的操作，它选择安全的做法：保留你说明的需求，不超过大小上限，保留无法证明由自己创建的残留，只有在目标涵盖交付时才合并或发布。仅开启 Claude Code 的 auto 模式不算：Feature-Crew 仍会提问。

## 会话路由

技能只有在模型选择时才会运行，所以代码变更可能跳过 `/fc-build-or-fix`，尤其是一个小请求逐渐扩大成新仓库、重构或发布时。插件的 SessionStart 钩子会把一段简短的路由约定放进会话：在 Claude Code 中是启动、恢复、`/clear` 和压缩时；在 GitHub Copilot CLI 中是会话开始和恢复时。它输出 [routing.json](https://github.com/D0n9X1n/feature-crew/blob/main/hooks/routing.json)：把代码变更指向 `/fc-build-or-fix`，任务中途范围扩大时重新路由，推送、合并、发布和清理用 `/fc-ship`，跳过流程的工作在推送前用 `/fc-review`。需要证据的问题交给 `/fc-research`，方案选择交给 `/fc-brainstorm`，无法解释的故障交给 `/fc-debug`，简单问题直接回答；自主会话按上面的“先思考再构建”处理。这段文字只是指引，不是强制：它让路由更可能发生，但不能保证。要关闭它，用 `claude plugin disable feature-crew@feature-crew` 或 `copilot plugin disable feature-crew@feature-crew` 停用插件。

**已知限制。**
- Copilot CLI 在压缩后没有可用的钩子来源，所以压缩后的 Copilot 会话只依靠技能描述（[copilot-cli#5225](https://github.com/github/copilot-cli/issues/5225)）。Copilot 交互式 `/clear` 后是否会重新注入这段文字尚未测试；只有会话开始和恢复经过验证。
- 原生 Windows 上的 Claude Code 需要 Git for Windows 才能运行这个钩子。没有 Git Bash 时，Claude Code 在 PowerShell 中运行钩子，钩子读不到自己的安装路径；它会失败，但不会阻塞会话。

## 清理

目标达成后，Feature-Crew 以 `/fc-clean` 收尾。只要 `/goal` 或 Copilot autopilot 的目标尚未达成，它就不会运行。它先归档成果：按授权提交、推送、合并，并向你报告。然后只删除任务能证明由自己创建的内容：临时根目录、worktree、已合并的分支、stash、后台进程和过期的远程跟踪引用，不做备份。未提交、未合并、正在使用或来源不明的内容都会保留，并在一个问题里列出。你也可以运行 `/fc-clean` 或说“清理一下”来手动启动它。

## 更新

运行 `/fc-update`。它通过每个 CLI 自己的命令更新插件，报告已安装的版本，并报告 `~/.claude` 中残留的旧脚本安装；用 `./install.sh --dry-run` 然后 `./install.sh` 删除它。之后开启新会话，或在 Claude Code 中运行 `/reload-plugins`。
