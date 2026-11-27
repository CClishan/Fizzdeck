# FizzDeck 现有能力全量梳理与后续演进路线

> **源码基线**：macOS 原生端 `v0.7.4`（Build `12`，已发布）｜ 线上公开版本 [`v0.7.4`](https://github.com/CClishan/Fizzdeck/releases/tag/v0.7.4)（Build `12`）｜ 官网 [`https://koroo.top/fizzdeck`](https://koroo.top/fizzdeck)
> **工程规模**：macOS 原生源码 **110** 个 Swift 文件（`App` 1 / `Models` 4 / `Stores` 1 / `Services` 38 / `Support` 24 / `Views` 42），**46** 个测试文件；配套本地 Web UI 与双语官网。

---

## 一、产品定位与三端形态

FizzDeck 是一个**面向小白 Vibe Coder 的本地优先 macOS 项目与 AI 会话工作台**。它不接管仓库、不需要登录账号、不上传源码或会话内容，状态与索引留在本机 `~/.repodeck`。

核心不是让用户先学会 Git，而是先解决三件事：

1. **记得住**：上次让 AI 做了什么、改过哪些文件、现在做到哪。
2. **回得去**：AI 改坏了，能看差异、能按文件还原、能真正存一个版本。
3. **跑得起**：依赖、端口、密钥、版本保护和本机环境，在启动前先体检。

| 形态 | 定位 | 运行载体 | 核心特征 |
| :--- | :--- | :--- | :--- |
| **macOS 原生 App** | **主入口** | Swift 6 + 纯 SwiftUI + macOS 26 Liquid Glass（Apple Silicon） | 双态侧栏、菜单栏、通知、应用内更新、4 页签详情、Doctor、可选 AI 总结 |
| **本地 Web UI** | **轻量补充** | Node.js 22+（`127.0.0.1:4770`）+ React 19 | 共用 `~/.repodeck`，浏览器查看项目、清理审计与基础操作 |
| **官网落地页** | **分发门户** | `https://koroo.top/fizzdeck`（中/英双语） | 版本下载、安装说明、能力展示与 FAQ |

---

## 二、现有能力矩阵（`v0.7.4`，已包含 `v0.6.0–v0.7.3`）

### 1. 本地发现、缓存与增量监听

- **首次启动流式发现**（[FirstRunScanView.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Views/FirstRunScanView.swift)、[ProjectDiscovery.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/ProjectDiscovery.swift)）：不预设个人目录，按 1–4 层深度勾选范围，实时列出候选并批量加入。
- **快扫与补全**（[RepositoryScanner.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/RepositoryScanner.swift)、[RepositoryStore.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Stores/RepositoryStore.swift)）：首屏优先读 `scan-cache.json`，随后异步补全 Git、会话和受限并发的 `du` 体积。
- **局部 FSEvents**（[WorkspaceWatcher.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/WorkspaceWatcher.swift)）：监听 AI 会话目录与当前项目的 `.git/HEAD`、`.git/index`，2 秒防抖，不扫描整棵源码树。

### 2. 记得住：人话模式、对话时间线与本地搜索

- **人话模式默认开启**（[FizzCopy.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Support/FizzCopy.swift)、[AppSettingsView.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Views/AppSettingsView.swift)）：Commit / Stash / Pull / 未推送等术语映射成日常表达，专业术语留在悬停提示；可在设置切回专业模式。
- **跨项目「对话」时间线**（[ConversationsWorkspaceView.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Views/ConversationsWorkspaceView.swift)、[ProgressTabView.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Views/ProgressTabView.swift)）：按天串起 Codex、Claude 等 AI 会话，展示首句需求、改动文件、结束状态和费用。
- **中文 FTS5 + 短词回退**（[SessionSearchIndex.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/SessionSearchIndex.swift)）：SQLite FTS5 `trigram` 覆盖跨项目会话；1–2 字用 `LIKE` 回退。搜索框与 `⌘K` 都能跳到对应对话节点。
- **纯剪贴板接力卡**（[HandoffCardBuilder.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/HandoffCardBuilder.swift)、[SecretRedactor.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Support/SecretRedactor.swift)）：把项目状态、最近对话和报错整理成 Markdown，复制前脱敏；不写入项目文件。

### 3. 回得去：对话标记、还原与存版本

- **对话前标记**（[SessionMarkService.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/SessionMarkService.swift)）：新会话开始时写 `marks.json`；默认用临时 index + `commit-tree` 生成不挂分支的隐形版本，不改分支、工作区、暂存区，也不出现在 `git log`。
- **降级与保留**（[SessionMarkService.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/SessionMarkService.swift)）：排除依赖/构建目录、5 MB 单文件和 5,000 文件上限；大仓库或非 Git 项目降级为纯标记，默认保留约 14 天，可固定重要标记。
- **看改了什么 / 还原**（[MarkDiffRestoreSheet.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Views/MarkDiffRestoreSheet.swift)）：对比对话前后差异，按文件还原或整体还原；还原前自动再打标记；对话后新建文件默认只列出、不删除。
- **内联「存个版本」**（[GitTabView.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Views/GitTabView.swift)、[CommitMessageGenerator.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/CommitMessageGenerator.swift)）：把改动存成真实 commit，提交信息可由规则生成，开启 AI 总结后可选润色。
- **推送前密钥守护**（[LightweightProjectCheckService.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/LightweightProjectCheckService.swift)、[DoctorService.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/DoctorService.swift)）：前者检查 `.env` 是否被忽略，后者通过 `git grep` 扫描已跟踪文件中的常见密钥模式；风险会阻断推送并给出人话说明。

### 4. 跑得起：Doctor、闲置整理与启动前体检

- **侧栏「体检 Doctor」**（[DoctorWorkspaceView.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Views/DoctorWorkspaceView.swift)、[DoctorService.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/DoctorService.swift)）：按关注/闲置分层，检查依赖、`.env`、端口占用、密钥风险、版本保护和本机环境。
- **关注策略**（[ProjectFocusPolicy.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Support/ProjectFocusPolicy.swift)）：手动关注 + 7 天自动活跃，默认上限 8 个；状态点与工作台提醒只针对关注项目，避免闲置项目刷屏。
- **闲置整理**：识别 `node_modules`、构建缓存和产物，默认移到系统废纸篓（可恢复或重新生成）；专业模式保留复制清理命令。
- **本机环境与 Git 身份**：内联展示 Node、Git、Agent CLI 状态；缺少 Git `user.name` / `user.email` 时可直接补上。
- **运行页进门体检**（[RunTabView.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Views/RunTabView.swift)）：启动前展示缺依赖、端口冲突、`.env` 等阻断项；依赖安装日志可见、可停止。
- **报错求助**（[LogErrorHelper.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/LogErrorHelper.swift)）：把日志报错解释成人话，或生成可复制给 Agent 的求助 prompt。

### 5. AI 会话、终端回场与可选 AI 总结

- **多工具原生索引**（[SessionIndex.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/SessionIndex.swift)）：Codex、Claude Code、DeepSeek Harness、Antigravity / AGY、Grok、Gemini CLI；Cursor / Trae / Windsurf 只读工作区摘要。
- **多终端回场**（[SessionResumeService.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/SessionResumeService.swift)、[TerminalLauncher.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/TerminalLauncher.swift)）：Terminal、iTerm2、Ghostty、Warp；命令行中显式匹配会话 ID 的 CLI 进程可确认结束，不误杀共享 app-server。
- **可选 AI 总结（默认关闭）**（[SummaryProvider.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/SummaryProvider.swift)、[SummaryEngine.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/SummaryEngine.swift)、[KeychainStore.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Support/KeychainStore.swift)）：Agent CLI（免 Key）、OpenAI 兼容 API（Key 存 macOS 钥匙串）、本地模型（Ollama / LM Studio）。
- **最小输入与防污染**：只发送项目名、文件名、变动计数和脱敏后的一句话意图；Agent CLI 在 `llm-workdir` 隔离执行，FizzDeck 自身会话被过滤并单独计费；失败静默回退规则摘要。

### 6. 项目详情：固定 4 页签

（[ProjectDetailView.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Views/ProjectDetailView.swift)）

| 页签 | 内容 |
| :--- | :--- |
| **进度** | 「做到哪了」、按天对话时间线、对话标记、改动文件与还原入口；可切换查看全部原始会话。 |
| **运行** | 体检问题、服务启动/停止、脚本、测试、实时日志、报错解释与求助 prompt。 |
| **版本** | 分支、改动、Diff、暂存、内联「存个版本」、推送；Stash / 分支 / Worktree 收在同一页的进阶区。 |
| **项目信息** | 项目简介、备注、技术栈、占用空间与清理入口、精简文档列表（点击弹窗预览）。 |

### 7. 项目库、Git、服务与安全边界

- **项目库**：[LibraryView.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Views/LibraryView.swift) 支持卡片/表格、分组与工具筛选、30 天闲置折叠、批量星标/分组/同步/清理、自定义封面。
- **Git**：[GitTabView.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Views/GitTabView.swift) 支持内嵌 Diff、单文件暂存、Stash、切换分支前脏检查、fetch / fast-forward pull / push、Worktree 感知。
- **开发服务**：[RunDetector.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/RunDetector.swift) 读取 npm、Makefile、justfile；启动/停止、测试、端口探测与日志尾部读取。
- **端口冲突**：[PortConflictService.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/PortConflictService.swift) 只读探测 PID，确认后仅发送 `SIGTERM`，排除 FizzDeck 自身与系统关键进程。
- **安全移除**：[ProjectRemovalService.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/ProjectRemovalService.swift) 只接受受管目录，拒绝过浅/受保护路径，运行中的服务或测试不允许删除，永久删除前复制到 `~/.repodeck/trash`。

### 8. 分发、应用内更新与打包

- **应用内下载与原子更新**（[AppUpdateService.swift](file:///Users/a003/dsh-workspace/repo-dashboard/macos/Sources/FizzDeck/Services/AppUpdateService.swift)）：GitHub Releases 检查、DMG 下载、`.sha256` 校验、挂载验证 Bundle ID 与签名、同卷暂存替换、自动重启。
- **版本注入**（[build_and_run.sh](file:///Users/a003/dsh-workspace/repo-dashboard/macos/script/build_and_run.sh)）：默认 `0.7.4` / Build `12`，支持 `VERSION`、`BUILD_NUM` 环境变量覆盖。
- **DMG 打包**（[package_dmg.sh](file:///Users/a003/dsh-workspace/repo-dashboard/macos/script/package_dmg.sh)）：默认 ad-hoc；支持 `--sign-identity` / `DEVELOPER_ID_APP`、Hardened Runtime、DMG 签名、`--notarize` + `NOTARY_PROFILE`、staple 与 `spctl` 校验。
- **校验文件**：打包结束自动生成同名 `.sha256`，格式为 `shasum -a 256` 仅含文件名，供应用内更新和 GitHub Release 上传。

---

## 三、当前真实边界

| 类别 | 现状 | 下一步 |
| :--- | :--- | :--- |
| **公开安装包签名** | 默认 ad-hoc，首次打开仍需 Control-click 放行；Developer ID + 公证流程已在脚本实现，但需要发布时注入凭据 | 用真实 Developer ID 凭据打一次公证包，并在 Release Notes 明确标注 |
| **应用内更新实机验证** | 原子更新、SHA-256、挂载校验和替换回滚均有实现与测试，但 `v0.5.3 / v0.7.3 → v0.7.4` 的真实更新仍需按 Checklist 跑 | 发布前分别从两个旧版本实机验证一次 |
| **对话标记** | 依赖临时 Git 对象，通常保留约 14 天；非 Git 项目只能纯标记 | 可在后续版本增加更明显的过期提示与固定入口 |
| **长期性能与无障碍** | 基础构建、单测与扫描性能基线存在；千级项目长列表、VoiceOver 与纯键盘焦点链未做全面实测 | 纳入正式发布后的稳定性专项目 |
| **Worktree 与 Web UI** | Worktree 偏展示/只读；Web UI 是轻量补充，不承担原生菜单栏、通知和公证分发 | 按实际需求决定是否继续对齐 |

---

## 四、后续演进方向

### 方向 1：把「记得住」做成真正的个人开发记忆

- 已完成：跨项目时间线、中文搜索、接力卡、可选 AI 总结。
- 可继续：周回顾、按文件反查历史对话、项目级成本与改动趋势。

### 方向 2：把「回得去」做得更可控

- 已完成：隐形标记、对话 Diff、按文件/整体还原、内联存版本、推送前密钥拦截。
- 可继续：标记固定与过期提示、还原预览的批量选择、更多非 Git 项目的安全引导。

### 方向 3：把「跑得起」扩成本机开发环境管家

- 已完成：Doctor、关注/闲置分层、依赖/端口/.env/密钥检查、本机环境与 Git 身份。
- 可继续：全局端口拓扑、更多语言版本探测、按项目自定义体检规则。

### 方向 4：分发与系统集成

- 已完成：Developer ID / 公证脚本、版本注入、DMG 签名与 SHA-256。
- 可继续：CI 自动签名/公证、URL Scheme、Shortcuts / AppIntents、主页与更新日志自动发布。

---

## 五、版本节奏

| 版本 | 主题 | 状态 |
| :--- | :--- | :--- |
| `v0.6.0` | 接着做：人话模式、对话时间线、接力卡、4 页签骨架 | 已落地 |
| `v0.7.0` | 回得去：对话标记、Diff/还原、存个版本、可选 AI 总结 | 已落地 |
| `v0.7.1` | 详情页瘦身、项目信息与文档列表合并 | 已落地 |
| `v0.7.2` | 找得回：中文 FTS5、短词回退、⌘K 对话直达 | 已落地 |
| `v0.7.3` | 跑得起：Doctor、闲置整理、运行页体检、报错求助 | 已落地 |
| `v0.7.4` | 正式分发：版本统一、签名/公证脚本、双语新手文档、官网同步 | 已发布（ad-hoc，未公证） |

---

## 六、`v0.7.4` 发布验证清单

### 1. 本地脚本与构建

```sh
bash -n macos/script/build_and_run.sh
bash -n macos/script/package_dmg.sh
swift build --package-path macos --product FizzDeck
```

改过官网时：

```sh
npm run build
```

### 2. DMG 打包与校验

```sh
./macos/script/package_dmg.sh
hdiutil verify macos/dist/FizzDeck-0.7.4-arm64.dmg
mkdir -p /tmp/fizzdeck-verify
hdiutil attach -nobrowse -readonly -mountpoint /tmp/fizzdeck-verify macos/dist/FizzDeck-0.7.4-arm64.dmg
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /tmp/fizzdeck-verify/FizzDeck.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /tmp/fizzdeck-verify/FizzDeck.app/Contents/Info.plist
codesign --verify --deep --strict /tmp/fizzdeck-verify/FizzDeck.app
hdiutil detach /tmp/fizzdeck-verify
cd macos/dist && shasum -a 256 -c FizzDeck-0.7.4-arm64.dmg.sha256
```

期望版本 `0.7.4`、Build `12`；上面的 `codesign --verify --deep --strict` 检查的是 DMG 内实际会被安装的 App。

### 3. `v0.5.3 / v0.7.3 → v0.7.4` 真实应用内更新

1. 在测试 Mac 的 `/Applications` 安装旧版，保留现有 `~/.repodeck` 状态。
2. 将 v0.7.4 的 DMG 与 `.sha256` 发布到测试 Release 或正式 Release。
3. 启动旧版，进入「设置 → 关于 → 检查更新」，确认能发现 `v0.7.4`。
4. 开始下载，确认 DMG 和校验文件都下载成功。
5. 确认应用校验 SHA-256、挂载 DMG、检查 Bundle ID 与签名、原子替换并自动重启。
6. 确认重启后的版本与 Build：

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/FizzDeck.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/FizzDeck.app/Contents/Info.plist
```

7. 检查项目、星标、备注、关注状态和设置是否保留。
8. 再次从 Finder 打开，确认没有空白窗口或重复更新提示。
9. 分别从 `v0.5.3` 和 `v0.7.3` 各跑一次；任一次失败都不能标记为可发布。

### 4. Developer ID + 公证包

```sh
export DEVELOPER_ID_APP="Developer ID Application: <name> (<TEAMID>)"
export NOTARY_PROFILE="<notarytool profile>"
./macos/script/package_dmg.sh --notarize
xcrun stapler validate macos/dist/FizzDeck-0.7.4-arm64.dmg
spctl -a -vvv -t open --context context:primary-signature macos/dist/FizzDeck-0.7.4-arm64.dmg
```

安装后检查：

```sh
spctl -a -vvv -t exec /Applications/FizzDeck.app
codesign --display --verbose=4 /Applications/FizzDeck.app
```

### 5. Release 资产

上传 `FizzDeck-0.7.4-arm64.dmg` 与 `FizzDeck-0.7.4-arm64.dmg.sha256`。发布后再次确认 tag、文件名、校验值、`releases/latest` 指向和下载页版本号一致。
