# 本轮验收索引 · 2026-11-27

| 范围 | 证据 |
|---|---|
| Build 13 | `macos/dist/candidates/v0.7.5-build13/` 同目录有 DMG、SHA-256 和独立原生源码快照；原版与开发工作树分别测试。 |
| Build 16 | [GitHub Release](https://github.com/CClishan/Fizzdeck/releases/tag/v0.8.0) 对应 `3b6a846`；公开 DMG 为 6,726,887 字节，SHA-256 `4f9334184d0596a8fbc20a46e7ab074bd9f40562007900111801079fe8cf58cf`。下载复核见 `output/release-v0.8.0/public-verification.json`。 |
| 原生界面 | `src/assets/native-075-{workbench,progress,version,doctor}.webp` 是隔离项目的真机截图。开发阶段另测了 14/30 天、周报同意/取消及首个基线。 |
| 事件体检与端口 | 见 [云端检查](docs/QUIET_FETCH.md)、SwiftPM 中的 WorkspaceWatcher、QuietGitFetch、PortConflict、ProjectTrial 测试。 |
| 键盘与系统动作 | `output/integration-qa-2026-11-27/keyboard-ax.txt` 为真机键盘记录。`output/shortcut-signing-2026-11-27/results.json` 记录开发签名后的三项成功执行、剪贴板还原及最终页签标题。VoiceOver 朗读待验。 |
| CI 与规模 | [PR 托管检查](https://github.com/CClishan/Fizzdeck/actions/runs/46004663046)与分支检查均通过，macOS 完成编译、测试及 App 组装，Ubuntu 完成网页和 Shell 检查。千项目万会话压测见[集成记录](docs/SYSTEM_INTEGRATION.md)。 |
| 官网 | [公网样机版](https://koroo.top/fizzdeck)已显示 v0.8.0，截图仍标 Build 13；页面与 9 个依赖一致，官网提交 `896e08d`。 |

最终测试数量、发布条件和仍需真机核对的项目以 [HANDOFF](HANDOFF.md) 顶部为准。
