# Feature-Crew Wiki

[English](Home)

一个面向 Claude Code 的按需代理团队框架。用自然的语言描述你的需要；Feature-Crew 会查找事实、解决决定和方案，然后用规模合适的 TDD 和硬性关卡运行代码。

### 入门

- [使用说明](Usage-zh-CN) — 安装、参数、描述需求、命令和更新。

### Feature-Crew 如何工作

- [架构](Architecture-zh-CN) — 构建模块、一次构建请求的路径、硬性关卡和原则，图由 `/fc-explain` 绘制。

### 构建与发布

- [开发与发布](Development-and-Release-zh-CN) — 变更如何进入 `main`、上限与自测、目录结构、发布，以及本 wiki 如何发布。

### 其他资料

- [README](https://github.com/D0n9X1n/feature-crew/blob/main/README.md) — 简介、快速开始和功能。
- [CLAUDE.md](https://github.com/D0n9X1n/feature-crew/blob/main/CLAUDE.md) — 代理在本仓库中遵循的规则。

### 致谢

`/fc-grill-me` 借鉴了 [mattpocock/skills](https://github.com/mattpocock/skills) 中的追问机制。“证据写在消息里”的规则来自 [obra/superpowers](https://github.com/obra/superpowers)。描述契约遵循 [tech-leads-club/agent-skills](https://github.com/tech-leads-club/agent-skills)。Feature-Crew 采用 MIT 许可证。

这些页面位于仓库的 [`wiki/`](https://github.com/D0n9X1n/feature-crew/tree/main/wiki) 文件夹中。CI 在每次推送到 `main` 时把它们镜像到这里，所以请通过拉取请求修改；在 GitHub 上直接做的修改会被覆盖。
