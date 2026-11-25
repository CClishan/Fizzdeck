# FizzDeck 交接文档

- 更新时间：2026-11-25
- 仓库：`/Users/a003/dsh-workspace/repo-dashboard`
- 当前分支：`main`（PR #1 已合并；`v0.2.3` 已发布）
- 基线 HEAD：`b36d8b8 Release FizzDeck 0.2.3`
- 状态：P0 完成，P1 功能完成，P2 5/5；原生删除和 AI 会话结束已补齐；2026-11-25 完成页签/底栏收口、项目自动发现、文件夹面板原生 Glass 覆盖层、设置页、IconMCP 图标替换和真实项目回归；上述 UI 改动已随 `v0.2.3` 发布，Release DMG 与 landing 均已上线。

## 新对话开场提示

把下面这段直接粘贴到新对话：

```text
继续 FizzDeck 原生 macOS 项目，仓库在 /Users/a003/dsh-workspace/repo-dashboard。

先读 HANDOFF.md、AGENTS.md 和 macos/README.md，再执行 git status / git diff。当前 main 已完成 P0、P1 功能和 P2 5/5；v0.2.3 已发布，app 从 `https://github.com/CClishan/Fizzdeck/releases/latest` 下载。下一步优先补真实菜单栏/通知直测，或继续质量与性能任务。删除项目只能用临时目录验证，不要对用户真实项目点击确认。

不要在没有明确确认时再发版、签名、公证或部署。不要回滚网页版、landing、stageshow 的已发布内容；需要改时先确认范围。

界面要求：纯 SwiftUI、浅色 Liquid Glass，不做整套暗色和吉祥物；UI 不加多余标签，让布局自己解释。

筛选按钮使用原生 `Menu`，配 `.menuStyle(.button)` + `.buttonStyle(.glass)`；不要改回自定义 HStack 或已废弃的 `.menuStyle(.borderlessButton)`。
```

## 移交摘要

| 项目 | 当前状态 |
|---|---|
| 原生 app | P0 完成，P1 功能完成，P2 5/5；`swift build`、`swift test` 通过（49 例）；AI 会话列表/过滤/恢复/结束 CLI 可用；设置页和 IconMCP 图标已随 `v0.2.3` 发布 |
| 原生分发 | `v0.2.3` arm64 DMG 已发布，ad-hoc 签名；未做 Developer ID、公证和自动更新 |
| Web UI | 保留在 `src/` + `server.mjs`，不是当前主入口 |
| Landing | `https://koroo.top/fizzdeck` 已上线并显示 `v0.2.3` macOS 下载；旧 `https://fizzdeck.pages.dev` 仍返回 200 |
| 仓库 | PR #1 已合并到 `main`；v0.2.3 Release 和 landing 下载入口已发布 |
| 验证基线 | Swift test 49 例、ESLint、TypeScript、35 页生产构建、Vercel 生产部署、线上 CTA 与 DMG SHA-256 一致 |
| 任务进度 | P0 5/5；P1 5/5（功能完成，2 项真实环境直测待补）；P2 5/5；发布与交付 1/3；质量与性能 1/4 |

## 项目是什么

FizzDeck 是一个本地优先的 macOS 项目管理器。原生版是主入口，纯 SwiftUI，不需要 Node.js；网页版保留在 `src/` 和 `server.mjs`，两者共用 `~/.repodeck` 本地状态。

用户已确认的方向：

- 原生 macOS 是主推版本，网页版是快速方案。
- 左侧导航保持清爽，信息尽量少。
- 不使用大面积深色主题，不做吉祥物。
- 默认中文、结论先行、短句。
- 生产代码禁止 Mock。
- 本轮已授权合并、部署和打包；后续版本、Developer ID、公证仍需明确确认。

## 已完成（P0）

### 1. 待处理队列

- 首页总览新增“待处理 N 个项目 / N 项”。
- 汇总五类问题：测试失败、落后远端、未推送提交、未提交文件、可回收空间。
- 排序：测试失败 → 落后远端 → 未推送 → 未提交 → 清理。
- 默认展示 4 项，可展开全部。
- 点击条目直接打开对应项目页签：改动 / 测试 / 清理。
- Git 扫描新增 ahead / behind；读取 `@{upstream}...HEAD`。

相关文件：

- `macos/Sources/FizzDeck/Models/ProjectAttention.swift`
- `macos/Sources/FizzDeck/Views/AttentionQueueView.swift`
- `macos/Sources/FizzDeck/Services/GitService.swift`
- `macos/Sources/FizzDeck/Services/RepositoryScanner.swift`
- `macos/Sources/FizzDeck/Models/Models.swift`
- `macos/Sources/FizzDeck/Views/HomeDashboardView.swift`

### 2. ⌘K 命令面板

- `⌘K` 打开/关闭。
- 搜索项目名、路径、分支、技术栈和动作。
- 项目页显示“快捷操作”：Terminal、Finder、编辑器、启停服务、运行测试、复制 AI resume。
- “命令”区包含：打开总览、重新扫描、添加目录、收藏当前项目。
- 支持上下键、回车、Esc、点击；单条结果自动收紧高度。
- 面板使用更实的玻璃背景，避免下层文字透出干扰。

相关文件：

- `macos/Sources/FizzDeck/Views/CommandPaletteView.swift`
- `macos/Sources/FizzDeck/Views/ContentView.swift`
- `macos/Sources/FizzDeck/Stores/RepositoryStore.swift`
- `macos/Sources/FizzDeck/App/FizzDeckApp.swift`

### 3. Finder / Terminal / 编辑器快捷动作

- 统一 `ProjectQuickActions`，已接入首页卡片右键、列表右键、侧栏右键、详情页头部和概览运行面板。
- Finder：定位并选中项目目录。
- Terminal：在项目目录打开新 Terminal 窗口。
- 编辑器：自动检测 Cursor、VS Code、Zed、Antigravity、JetBrains 系列和 Xcode；Xcode 支持顶层与最多 3 层的嵌套 workspace、project 或 `Package.swift`。
- 复制项目完整路径。
- `⌘⇧T` 在当前项目打开 Terminal。

相关文件：

- `macos/Sources/FizzDeck/Support/SystemActions.swift`
- `macos/Sources/FizzDeck/Views/Components.swift`
- `macos/Sources/FizzDeck/Views/ProjectDetailView.swift`
- `macos/Sources/FizzDeck/Views/OverviewTabView.swift`
- `macos/Sources/FizzDeck/Views/SidebarView.swift`

### 4. 顺手修复

- 页签的辅助功能“已选中”状态会残留：已用 `accessibilityRemoveTraits` 修正。
- 窗口恢复时会沿用屏幕外的旧坐标，导致界面被裁：新增启动时可见性校正。

相关文件：

- `macos/Sources/FizzDeck/Support/WindowFrameGuard.swift`
- `macos/Sources/FizzDeck/Views/ProjectDetailView.swift`

### 5. 文档

- `README.md`
- `README.zh-CN.md`
- `macos/README.md`

## 已完成（P1）

### 1. 队列条目直接操作

- 待处理行按类型显示图标动作：推送提交、拉取远端、运行测试、复制清理命令。
- 点击行本身仍打开对应项目页签；动作按钮不改变导航。
- 推送和拉取都会二次确认；拉取使用 `git pull --ff-only`。
- 拉取前检查 `git status --porcelain -uall`，有未提交文件时直接拦截。
- 动作完成后只刷新当前项目的 Git 摘要；失败结果显示在该行，复制成功显示绿色勾。

相关文件：

- `macos/Sources/FizzDeck/Services/GitSyncService.swift`（新增）
- `macos/Sources/FizzDeck/Views/AttentionQueueView.swift`
- `macos/Sources/FizzDeck/Stores/RepositoryStore.swift`
- `macos/Sources/FizzDeck/Models/Models.swift`
- `macos/Sources/FizzDeck/Views/CleanupTabView.swift`

### 2. 队列忽略 / 稍后

- 行右键可稍后提醒：1 小时后、明天 9:00；也可无限期忽略该项目的此类提醒。
- 规则按项目路径 + 提醒类型保存到共享 `state.json` 的 `attention` 字段，网页版读写元数据时会保留该字段。
- 被静默的提醒从队列和计数中移除；标题栏显示铃铛图标和静默数量。
- 铃铛菜单可逐条恢复或全部恢复。
- 队列每 60 秒刷新一次当前时间，稍后到期后无需重扫项目即可重新出现。

相关文件：

- `macos/Sources/FizzDeck/Models/ProjectAttention.swift`
- `macos/Sources/FizzDeck/Models/Models.swift`
- `macos/Sources/FizzDeck/Services/RootStore.swift`
- `macos/Sources/FizzDeck/Stores/RepositoryStore.swift`
- `macos/Sources/FizzDeck/Views/AttentionQueueView.swift`

### 3. Git 快捷同步

- “改动”页状态面板右上角提供紧凑的 fetch、pull、push 图标组，使用浅色 Liquid Glass，不增加文字标签。
- 三个动作都会先弹确认框；执行期间显示进度并禁用整组按钮。
- pull 使用 `git pull --ff-only`；执行前检查 `git status --porcelain=v1 -uall`，有未提交文件时直接拦截。
- fetch 只更新远端引用，不修改工作区；push 只推送已提交内容。
- 成功和失败结果都在状态面板内回显；成功后刷新项目 Git 摘要、提交列表、分支和文件状态。
- 所有 Git 命令设置 `GIT_TERMINAL_PROMPT=0`，避免凭据提示卡住后台执行。

相关文件：

- `macos/Sources/FizzDeck/Services/GitSyncService.swift`
- `macos/Sources/FizzDeck/Views/GitTabView.swift`
- `macos/Sources/FizzDeck/Views/ProjectDetailView.swift`
- `macos/Sources/FizzDeck/Views/Components.swift`
- `macos/Sources/FizzDeck/Stores/RepositoryStore.swift`

### 4. 菜单栏常驻与本地通知

- 新增 `MenuBarExtra`，菜单栏标签显示待处理项数量；数量跟随扫描、测试结果和静音规则更新，每 60 秒重算一次到期静默。
- 菜单提供打开总览、重新扫描、最近 6 个项目和退出。
- 打开项目时优先恢复已有主窗口，没有窗口时通过 `WindowGroup(id: "main")` 新建；主窗口保留关闭按钮。
- 开发服务从启动到端口就绪时发送“开发服务已就绪”通知；测试进程非用户停止且退出码非 0 时发送“测试失败”通知。
- 主动停止测试不会触发失败通知。
- 前台时通过通知中心 delegate 显示 banner 和声音；首次启动请求通知授权。
- 本地测试用 `./macos/script/build_and_run.sh --sign-local` 生成 ad-hoc 签名；默认 `run` / `--verify` 不签名。用户已授权通知，通知中心已收到“测试失败”和“开发服务已就绪”两条记录。

相关文件：

- `macos/Sources/FizzDeck/App/FizzDeckApp.swift`
- `macos/Sources/FizzDeck/Views/MenuBarView.swift`（新增）
- `macos/Sources/FizzDeck/Support/LocalNotifications.swift`（新增）
- `macos/Sources/FizzDeck/Services/ProjectActions.swift`

### 5. 信息架构收敛（图 2 / 图 3）

- 首页布局切换改为单个浅色玻璃分段控件，选中态用 `matchedGeometryEffect` 跟随，不再出现三组独立菜单。
- 排序、颜色、AI 工具收进一个原生“筛选”菜单；按钮使用 `.menuStyle(.button)` + `.buttonStyle(.glass)`，由系统提供玻璃外观和菜单指示器，活动筛选以可移除 chip 显示在控件下方。
- 项目头部收成“星标 + 打开方式 + 更多”三段玻璃控件；Finder、Terminal、编辑器、复制路径在“打开方式”内。
- localhost / 端口状态从项目头部移除，统一留在概览的“预览端口”卡片和“运行与测试”面板。
- 新增 `FizzMotion` 统一 `quick` / `standard` / `panel` 三档节奏；原生视图统一接入 `accessibilityReduceMotion`，星标切换使用可关闭的 symbol transition。
- 打开方式菜单合并辅助功能子元素，读屏只暴露一个“打开方式”控件。

相关文件：

- `macos/Sources/FizzDeck/Support/FizzTheme.swift`
- `macos/Sources/FizzDeck/Views/HomeDashboardView.swift`
- `macos/Sources/FizzDeck/Views/ProjectDetailView.swift`
- `macos/Sources/FizzDeck/Views/ContentView.swift`
- `macos/Sources/FizzDeck/Views/SidebarView.swift`
- `macos/Sources/FizzDeck/Views/AttentionQueueView.swift`
- `macos/Sources/FizzDeck/Views/CommandPaletteView.swift`

### 6. 命令面板增强

- 空查询显示“最近 / 快捷操作 / 项目 / 命令”；最近项目与最近动作写入 `UserDefaults`，重启后保留。
- 支持多词模糊匹配，覆盖标题、副标题和关键词；连续命中、词首和靠前位置得分更高。
- 置顶命令“打开总览”“重新扫描项目”始终排在命令区前面。
- 后台用最多 4 个并发读取各项目 `origin` 并缓存；`⌘K` 可直接搜 SSH / HTTPS 远程地址。
- 选中项目后显示“在浏览器中打开远程仓库”“复制远程地址”；已确认无 `origin` 时显示禁用的“没有远程仓库”。

相关文件：

- `macos/Sources/FizzDeck/Views/CommandPaletteView.swift`
- `macos/Sources/FizzDeck/Stores/RepositoryStore.swift`

### 7. 远程仓库动作

- 新增 `GitRemote`：识别 `git@host:path`、`ssh://`、`git://` 和 HTTPS 远程，生成浏览器地址时去掉 `.git` 后缀和 HTTPS 内嵌凭据。
- 项目“更多”菜单和“改动”页远程区都能打开浏览器或复制原始 remote；只读 `git config`，不发起网络写操作。
- 无 `origin`、本地路径和空 remote 不生成浏览器地址；复制动作仍保留原始 remote。

相关文件：

- `macos/Sources/FizzDeck/Services/GitService.swift`
- `macos/Sources/FizzDeck/Views/ProjectDetailView.swift`
- `macos/Sources/FizzDeck/Views/GitTabView.swift`

### 8. Git 错误文案

- `ShellOutput` 增加 `timedOut`，超时后不再只显示退出码。
- `GitSyncService` 将常见失败映射为可操作文案：无 upstream、凭据不可用、SSH 密钥不可用、非快进、非 Git 仓库、远端不可达、超时。
- 所有同步命令继续使用 `GIT_TERMINAL_PROMPT=0`，避免后台等待凭据输入。

相关文件：

- `macos/Sources/FizzDeck/Services/Shell.swift`
- `macos/Sources/FizzDeck/Services/GitSyncService.swift`

## 已完成（P2）

### 0. 总览与项目页收口

- 项目概览把“简介”和“技术栈”合并为一张“项目”卡片，删除原独立技术栈与“运行与测试”面板。
- 运行与测试收进底部居中的 Liquid Glass 悬浮操作区，显示运行/测试状态，并提供启动/停止、测试/停止、Terminal、复制命令、预览、日志等动作；所有项目页共用。
- 总览只保留卡片墙和极简列表；删除没有实际差异的横向画廊，旧的 `viewMode=gallery` 会自动回退到卡片墙。
- 总览顶部改为左右两栏：待处理卡片固定约半宽，右侧四项汇总卡片按 2×2 并排；窗口变窄时仍保持并排。
- 原生筛选菜单保持 `Menu` + `.menuStyle(.button)` + `.buttonStyle(.glass)`；移除全局黑色 tint，避免 Liquid Glass 按钮在活动窗口变成黑底。

### 1. 分组筛选与批量操作

- 分组默认按路径关键词自动分类；项目右键/详情“更多”可移动到已有分组、新建分组，或恢复自动分类。自定义分组写入共享 `state.json`，侧栏和筛选菜单自动出现。
- 自定义分组颜色用稳定哈希从固定色板选取，跨启动不变。
- 首页筛选菜单新增分组子菜单，分组数量会叠加当前颜色和 AI 工具条件；活动分组显示为可移除 chip。
- 右上批量选择按钮进入选择模式；卡片和列表都支持选中态、全选、取消全选、清除和退出。
- 批量重扫只读取选中目录并替换对应项目，保留其他项目顺序和状态；所选项目的 remote 缓存会失效。
- 批量复制按项目加注释，一次复制合并后的清理命令；没有可清理项的项目会跳过并回显数量。
- 批量操作不提供删除，不自动执行 `rm`；单点选择、全选和部分无清理项都有独立结果反馈。
- 选中态用项目色描边或底色加勾选图标；辅助功能会暴露“选择 / 取消选择”和已选 traits。

相关文件：

- `macos/Sources/FizzDeck/Services/RepositoryScanner.swift`
- `macos/Sources/FizzDeck/Support/ProjectGrouping.swift`
- `macos/Sources/FizzDeck/Stores/RepositoryStore.swift`
- `macos/Sources/FizzDeck/Views/HomeDashboardView.swift`
- `macos/Sources/FizzDeck/Views/Components.swift`
- `macos/Sources/FizzDeck/Views/SidebarView.swift`

### 2. 编辑器覆盖

- 保留 Cursor、VS Code、Zed 和 Xcode，新增 Antigravity 与 JetBrains 系列：IntelliJ IDEA、WebStorm、PyCharm、GoLand、RustRover、CLion、PhpStorm、RubyMine、DataGrip。
- JetBrains 同时识别 Ultimate / Community 的 bundle ID，并保留 `/Applications` 回退路径；只显示已安装的编辑器。
- Xcode 目标不再只看顶层：优先顶层 workspace / project / `Package.swift`，否则在最多 3 层目录内找嵌套 workspace、project 或 `Package.swift`。
- 嵌套搜索跳过 `node_modules`、`Pods`、`build`、`dist`、`DerivedData`、`vendor`、隐藏目录和符号链接，避免扫描生成目录。

相关文件：

- `macos/Sources/FizzDeck/Support/SystemActions.swift`
- `macos/Sources/FizzDeck/Views/Components.swift`
- `macos/Sources/FizzDeck/Views/CommandPaletteView.swift`

### 3. Swift 测试基线

- 新增 SwiftPM `FizzDeckTests` target，可直接运行 `swift test --package-path macos`。
- 覆盖待处理队列的五类优先级、最近项目 tie-break、1 GB 清理阈值和静默到期判断。
- 覆盖 Git tracking 的 behind/ahead 解析、缺失 upstream、格式异常和 SSH remote 转换。
- 覆盖编辑器嵌套 Xcode 目标：嵌套 workspace、顶层优先、嵌套 Package 回退、生成目录跳过。
- 覆盖会话排序分组、cwd 规范化、恢复命令和跨分块反向扫描；后续补充分组、删除、Git 错误路径、通知路由和项目发现测试，当前共 47 例。

相关文件：

- `macos/Package.swift`
- `macos/Tests/FizzDeckTests/ProjectAttentionQueueTests.swift`
- `macos/Tests/FizzDeckTests/GitServiceTests.swift`
- `macos/Tests/FizzDeckTests/ProjectEditorTests.swift`
- `macos/Tests/FizzDeckTests/SessionIndexTests.swift`

### 4. AI 会话管理

- 会话页展示当前项目匹配到的全部会话，按修改时间倒序、同一时间按稳定 ID 排序。
- 新增“全部 / Codex / Claude”原生玻璃分段过滤；无匹配时显示对应空态，切换项目会重置过滤。
- 每行显示工具、相对时间、最后一条用户需求和可复制的 `codex resume` / `claude --resume` 命令。
- Codex 解析兼容现代 `event_msg/item_completed` 下的 `UserMessage` 和旧式 `payload.role == "user"`；Claude 从文件尾部反向读取。
- 会话文件反向分块扫描最多 8 MiB，单次读取 128 KiB，能处理跨分块的行；不再受原先 256 KiB tail 限制。
- 新增“结束会话”：仅匹配命令行首段（或 `env` / `node` / `bun` / `deno` 启动器之后）明确包含 `codex resume <id>` / `claude --resume <id>` 的独立 CLI 进程，确认后发送 SIGTERM。
- Codex Desktop 的共享 `codex app-server` 不含单个会话 ID，永远不会被结束；找不到独立进程时不显示结束按钮，并提示在对应客户端处理。
- 结束动作会二次确认；完成后回显 PID 结果，并刷新 CLI 进程列表。单元/集成测试覆盖精确匹配、Desktop app-server 排除、伪造 grep 排除和真实 SIGTERM。

相关文件：

- `macos/Sources/FizzDeck/Models/Models.swift`
- `macos/Sources/FizzDeck/Services/SessionIndex.swift`
- `macos/Sources/FizzDeck/Services/FileTools.swift`
- `macos/Sources/FizzDeck/Views/SessionsTabView.swift`
- `macos/Tests/FizzDeckTests/SessionIndexTests.swift`

### 5. 原生删除

- 项目“更多”菜单新增“移入废纸篓…”和“永久删除…”。
- 删除前要求输入目录名；名称不匹配、非受管目录、过浅或受保护路径、开发服务运行中、测试运行中、启停处理中都会拒绝。
- 废纸篓使用 `FileManager.trashItem`；永久删除先复制到 `~/.repodeck/trash/<名称>-<时间>`，成功后删除原目录。
- 删除成功后同步移除 roots、metadata、项目缓存和最近项目记录；失败时原目录保持不变。

相关文件：

- `macos/Sources/FizzDeck/Services/ProjectRemovalService.swift`
- `macos/Sources/FizzDeck/Views/ProjectDetailView.swift`
- `macos/Sources/FizzDeck/Stores/RepositoryStore.swift`
- `macos/Tests/FizzDeckTests/ProjectRemovalTests.swift`

## 2026-11-25 页签选中态与操作栏分流

- 搜索保留独立 `ToolbarItem`，六个页签合并到另一个 `ToolbarItem`；系统渲染为两个胶囊。六个页签分开提交时，选中态会停在第一个页签，内容切换后视觉不跟随。
- 选中页签使用 `FizzTheme.accent` 实心底、白字；辅助功能树显示 `(selected)`。
- 底部操作栏只在「概览 / 测试」出现：概览显示启动服务、Terminal、复制命令、启动日志；测试显示运行测试、测试日志、复制测试；其他页签不显示。
- 底栏保留整条玻璃底衬与阴影；状态为上方纯文字，操作按钮保持独立玻璃胶囊。
- 截图中底部大块遮挡来自内容区预留的 `96pt` 底部 padding，不是玻璃胶囊。移除后内容延伸到操作栏后方，操作栏只占自身内容高度。
- 测试页中间区移除「跑测试 / 日志」按钮，只保留状态和输出；启动与测试消息分开保存，避免串到另一页签。
- 修复 `git status --porcelain` 首字符被吞：原 `Shell.output` 会去掉行首空格，导致 ` HANDOFF.md` 显示成 `ANDOFF.md`；状态读取改用保留前缀空格的专用路径，并加回归测试。
- Git 错误路径新增 7 个本地集成/单元测试：无 upstream、HTTP 401、SSH 公钥拒绝、断开本地端口、脏工作区拉取拦截和超时终止。
- 本地通知写入 `projectPath` / `tab`，点击通知会回到对应项目页签；主窗口关闭时会先恢复主窗口。新增 2 个通知路由解析测试。
- 验证：`swift build`、`swift test`（47 例）、`./macos/script/build_and_run.sh --verify` 通过；CUA 实测概览/测试页底栏动作、玻璃底衬、阴影和内容延伸。
- 真实项目只读回归：`repo-dashboard` 的 `HANDOFF.md` 首字符正确；`video-tem` 无 upstream、16 个改动；`shipany-template-two` 268 个改动、概览与测试底栏分流正确。未执行真实同步。

## 2026-11-25 添加项目自动发现

- 工具栏“文件夹”打开文件夹面板：左侧列出已加入文件夹，点击可直接打开；底部提供“添加文件夹…”和层级控制，右侧显示新父目录的扫描结果。
- “添加文件夹…”从面板内打开系统目录选择器；文件夹扫描层级为 1–10，默认 3，可恢复默认，扫描结果按层级即时刷新。
- 按文件特征发现项目：`.git`、`package.json`、`pnpm-workspace.yaml`、Gradle/Maven、Cargo、Go、Python、Ruby、PHP、Elixir、Swift Package、`*.xcodeproj`、`*.xcworkspace`。
- `CLAUDE.md` / `Claude.md` 大小写不敏感；同时识别 `AGENTS.md`、`SKILL.md`。
- 跳过隐藏目录、`node_modules`、构建产物、缓存、虚拟环境和其他常见生成目录；不跟随符号链接。
- 候选行使用文件夹图标，显示名称、`~` 路径、识别特征和 Git 标记；已在看板的项目显示“已加入”且不可重复勾选。
- 默认只勾选顶层项目；勾选子项目会自动取消父目录，勾选父目录会取消其子项目；“全选”也只保留顶层，避免重复添加重叠目录。
- 无候选时可只添加当前文件夹；最多显示 200 个候选，添加后统一写入 roots 并重新扫描一次。
- 面板不再使用系统 sheet：macOS 的 sheet 窗口背板会压住 `.glassEffect`，`NSGlassEffectView` 也无法跨窗口采样，最终改为主窗口内原生 Glass 覆盖层。
- 面板使用 14% 深色遮罩、28pt 连续圆角、native Liquid Glass 与 22% 白色 tint；点击面板外、关闭按钮或取消可退出，已加入文件夹点击后会打开项目并关闭面板。
- 验证：`ProjectDiscoveryTests` 5 例通过，覆盖嵌套发现、跳过生成/隐藏目录、层级限制、默认选择和父子互斥；全量 47 例通过。
- CUA 用临时父目录验证：左侧已加入列表正确显示、从面板内选择文件夹、发现 4 个候选、`node_modules` 被跳过、父子互斥、实际添加一个子项目后看板从 23 增至 24、左侧计数更新为 24、再次扫描显示“已加入”。测试后已恢复原 `~/.repodeck/roots.json` 并重启应用，当前仍为 23 个项目。
- 玻璃终验：激活窗口截图中可透出后方项目卡片与模糊文字，侧栏、扫描结果、底部操作均保持可读；`swift test` 47 例通过，`./macos/script/build_and_run.sh --verify` 通过。Escape 快捷关闭已挂到 `onExitCommand`，CUA 无法稳定前台聚焦，未单独实测。

相关文件：

- `macos/Sources/FizzDeck/Services/ProjectDiscovery.swift`
- `macos/Sources/FizzDeck/Views/AddProjectsSheet.swift`
- `macos/Sources/FizzDeck/Stores/RepositoryStore.swift`
- `macos/Sources/FizzDeck/Views/ContentView.swift`
- `macos/Tests/FizzDeckTests/ProjectDiscoveryTests.swift`

## 验证记录

已通过：

```sh
swift build --package-path macos
./macos/script/build_and_run.sh --verify
```

P1 行内操作：

- 临时 bare remote 实测：`GitSyncService` 推送成功、fast-forward 拉取成功。
- 脏工作区实测：工作区有未提交文件时，拉取返回 `blocked`，远端新文件未进入工作区。
- CUA 实测：待处理行显示推送/复制清理图标；推送按钮打开确认框；取消后不执行。
- CUA 实测：点击清理复制图标后变为绿色勾；剪贴板内容为多行 `rm -rf '<absolute path>'`。
- CUA 实测：点击行正文仍进入对应项目的“改动”页。

P1 忽略 / 稍后：

- CUA 实测：右键“8 个提交未推送”行，选择“1 小时后”，队列从 24 项变为 23 项，标题栏出现铃铛和 1 项静默。
- 重启应用后该行仍保持隐藏，确认 `state.json` 持久化生效。
- 从铃铛菜单恢复后，队列回到 24 项。
- CUA 实测：“忽略此提醒”同样隐藏该行；`state.json` 中记录 `muted: true`。
- 测试结束后已用测试前快照恢复 `state.json`，当前没有残留静默规则。

P1 Git 快捷同步：

- 临时 bare remote 实测：fetch 只推进 `origin/main`，工作区保持干净且远端文件未落盘。
- 临时 bare remote 实测：pull fast-forward 成功；有未提交文件时返回 `blocked`，HEAD 和工作区都未改变。
- 临时 bare remote 实测：push 后远端 `main` 与本地 HEAD 一致。
- CUA 实测：状态面板右上角三个图标无文字标签，不遮挡指标；fetch、pull、push 均弹出确认框。
- CUA 实测：在用户现有项目上逐一点击三个动作并取消，没有执行任何同步。
- CUA 实测：临时项目 fetch、pull、push 成功，分别回显“已获取远端”“已拉取”“已推送”，提交列表同步刷新。
- CUA 实测：临时项目有未提交文件时执行 pull，回显红色“有 1 个文件未提交，先处理后才能拉取”。
- 测试用临时项目已从 `roots.json` 移除；测试前后 `roots.json` 与 `state.json` 哈希一致。

P1 菜单栏与通知：

- `swift build --package-path macos` 与 `./macos/script/build_and_run.sh --verify` 通过。
- CUA 实测：应用启动后主窗口正常，`WindowGroup(id: "main")` 保留关闭按钮，窗口识别为 `main-AppWindow-1`。
- CUA 实测：临时项目启动 `npm run dev` 后端口 6199 就绪，界面显示“已启动 npm run dev · localhost:6199”。
- CUA 实测：临时项目运行失败测试后显示“失败 · 0.6s”，首页待处理从 25 项变为 26 项。
- 通知授权状态为 `authorized`；通知中心数据库确认收到“测试失败 / project · npm run test”和“开发服务已就绪 / project · localhost:6199”两条记录。
- 临时项目已移除，测试用 node 进程已停止；`roots.json` 与 `state.json` 已恢复到测试前哈希。
- 当前开发产物由 `--sign-local` 做 ad-hoc 签名，`Info.plist` 已绑定 `com.a003.fizzdeck`；该模式只用于本地测试，不参与默认构建。
- CUA 无法读取系统菜单栏中的 `MenuBarExtra` 项，菜单栏图标、数字和菜单点击未直接自动化验证；代码路径和编译通过。

P1 信息架构收敛：

- `swift build --package-path macos` 通过；`./macos/script/build_and_run.sh --sign-local` 本地启动成功。
- CUA 实测：首页只保留布局分段控件和一个“筛选”菜单；排序、颜色、AI 工具均可从该菜单进入。
- CUA 实测：筛选按钮改为原生 `Menu` + `.menuStyle(.button)` + `.buttonStyle(.glass)`，菜单指示器由系统绘制；辅助功能树只暴露一个“筛选”菜单按钮。
- CUA 实测：从原生菜单选择“产品站”后显示 `5 / 23` 个项目并生成活动 chip；点击“清除”恢复 23 个项目。
- CUA 实测：选择紫色颜色后出现“紫 ×”chip 和“清除”，项目数变为 0；清除后恢复 23 个项目。
- CUA 实测：卡片墙、极简列表两种布局切换正常；横向画廊已删除。
- CUA 实测：项目头部只剩星标、打开方式、更多三个控件；打开方式包含 Finder、Terminal、复制路径，星标可切换并恢复。
- CUA 实测：辅助功能树中“打开方式”只出现一次，不再拆成 folder 和 chevron 两个控件。
- CUA 实测：概览“预览端口 4317”保留端口状态；原“运行与测试”面板已移到底部悬浮操作区，项目头部不显示 localhost。
- `npm run build` 通过；本地 `/landing` 返回 200，landing 的 JS、CSS、logo 资源均返回 200。

P1 命令面板 / 远程仓库 / Git 错误：

- `swift build --package-path macos` 通过。
- 本地 Swift 校验：`GitRemote` 15 个输入通过，覆盖 SSH、`ssh://`、`git://`、HTTPS、内嵌凭据剥离、`.git` 去除、自定义 HTTPS 端口、SSH 单段主机别名，以及空值和本地路径拒绝。
- 本地 Swift 校验：模糊匹配 9 个输入通过，覆盖中英文、大小写/变音、URL 片段和无匹配。
- CUA 实测：`⌘K` 空查询显示“最近 / 快捷操作 / 项目 / 命令”；执行“复制远程地址”后剪贴板为 `https://github.com/CClishan/Fizzdeck.git`，重开面板出现“最近 / 复制远程地址”。
- CUA 实测：输入 `CClishan/Fizzdeck` 同时命中项目 repo-dashboard 和远程动作；选中项目显示“打开远程仓库 / 复制远程地址”。
- CUA 实测：项目“更多”菜单和“改动”页远程区均有打开/复制图标；未实际打开浏览器，避免打断当前会话。
- 临时仓库脚本编译实际 `Shell.swift` + `GitSyncService.swift`，6 项通过：push 成功、无 upstream、脏工作区 pull 拦截、非快进 pull、不可达远端 fetch、Shell 超时标记。
- 未实测：无 `origin` 项目的禁用态没有在 CUA 中实际切换确认；代码路径已覆盖。

P2 分组筛选与批量操作：

- `swift build --package-path macos` 与 `git diff --check` 通过。
- CUA 实测：筛选菜单显示 6 个分组及数量；“产品站”筛出 5 / 23 个项目，活动 chip 数量与汇总指标同步，移除 chip 后恢复 23 个。
- CUA 实测：进入批量模式后卡片和列表都有勾选图标和选中描边；选中 2 个项目时批量栏显示“已选 2 个”。
- CUA 实测：批量复制得到 zoopfizz 与 pixloading 两组清理命令，`pbpaste` 内容包含项目注释和绝对路径；未执行任何命令。
- CUA 实测：对 2 个选中项目重扫后回显“已重新扫描 2 个项目”，其他 21 个项目仍在看板中；首页时间和体积汇总刷新。
- CUA 实测：全选从 2 个变为 5 个，再次点击取消全选回到 0 个；“完成”退出后选择状态清空。
- CUA 实测：最终构建中选中卡片在辅助功能树显示 `(selected)`，批量按钮显示“退出批量选择”。
- 批量操作前后 `~/.repodeck/roots.json` 与 `state.json` 的 SHA-256 与操作前快照一致。
- 未实测：所选目录不存在、部分目录在扫描前消失的提示未用真实缺失目录触发；代码会在重扫前过滤非目录并回显数量。

P2 编辑器覆盖：

- `swift build --package-path macos` 通过。
- 单测覆盖嵌套 workspace、顶层目标优先、嵌套 `Package.swift` 回退、`node_modules` 跳过。
- CUA 实测：repo-dashboard 的快捷操作同时出现“用 Xcode 打开”和“用 Antigravity 打开”。
- CUA 实测：项目详情“打开方式 → 在编辑器中打开”列出 Xcode 与 Antigravity；未实际启动编辑器。
- JetBrains 系列当前机器未安装，仅完成 bundle ID / 路径映射与编译验证，未做真机打开。

P2 Swift 测试基线：

- `swift test --package-path macos` 通过，32 例 0 失败。
- `GitServiceTests` 5 例：behind/ahead 顺序、零值、无 upstream、异常格式、SSH remote URL。
- `ProjectAttentionQueueTests` 4 例：五类优先级、最近项目 tie-break、1 GB 阈值、静默到期。
- `ProjectEditorTests` 6 例：嵌套 workspace、顶层目标优先、顶层/嵌套 Package 回退、嵌套 workspace 优先于 Package、生成目录跳过。
- `SessionIndexTests` 4 例：排序分组与稳定 ID、cwd 规范化、恢复命令、跨分块反向扫描。
- `ProjectGroupingTests` 3 例：自动分类、默认分组排序、自定义分组颜色稳定。
- `ProjectRemovalTests` 6 例：非受管、确认名错误、测试运行中、开发服务运行中、过浅路径、永久删除先备份。
- `SessionProcessTests` 4 例：精确 resume 匹配、Desktop app-server 排除、grep 伪匹配排除、真实 CLI 进程 SIGTERM。

P2 AI 会话管理：

- CUA 实测：repo-dashboard 会话页显示 2 个 Codex 会话，最新一条需求为当前对话文本，不再显示“未读取到最后一条用户消息”。
- CUA 实测：切换到 Codex 保留 2 条；切换到 Claude 显示“没有 Claude 会话”；切回“全部”恢复两条。
- CUA 实测：点击“复制恢复命令”后 `pbpaste` 为 `codex resume 01a20cb9-cfa6-7e42-be3a-5f1072992852`。
- 集成测试：临时启动一个名为 `codex` 的独立进程并带 `resume <session-id>`，`SessionProcessService.end` 发送 SIGTERM 后进程退出；Codex Desktop 共享 app-server 不匹配。
- CUA 实测：会话页“会话总数 / 最近会话”卡片和工具过滤保持正常，Desktop 会话不会出现“结束”按钮。
- 未实测：真实 Claude 项目会话列表和恢复命令；本机匹配项目当前只有 Codex 会话，Claude 空态已验证。

P2 总览 / 项目页 / 分类 / 删除：

- `swift build --package-path macos` 通过。
- CUA 实测：总览顶部待处理卡片约半宽，四项汇总卡片在右侧 2×2 并排；窗口变窄后仍保持并排。
- CUA 实测：项目概览“项目”卡片同时显示简介和技术栈；原“运行与测试”面板不再出现。
- CUA 实测：项目页底部悬浮操作区为原生 Liquid Glass，包含状态、启动/停止、测试/停止和更多菜单；移除全局黑色 tint 后按钮为浅色玻璃、深色图标。
- CUA 实测：项目右键“移动到分组”列出默认分组；新建“测试分组”后项目立即移动到新分组，侧栏和详情标签同步；选择“恢复自动分类”后回到“产品站”。
- 分组测试后已用测试前快照恢复 `state.json`，哈希与操作前一致。
- CUA 实测：打开“移入废纸篓…”确认框，输入错误名称时按钮禁用，输入目录名 `video-tem` 后启用；点击取消，`video-tem` 与 `roots.json` / `state.json` 均未变化。
- 未实测：真实执行移入废纸篓或永久删除的 UI 路径；服务层永久删除先备份已由 `ProjectRemovalTests` 覆盖。

CUA 实测：

- 首页队列显示 18 个项目 / 24 项。
- 第一项为未推送提交，符合优先级。
- 点击队列项进入项目“改动”页；展开后点击清理项进入“清理”页。
- `⌘K` 输入 `converter` 回车打开 `Converter-tools`。
- 上下键移动选择、Esc 关闭、单条结果紧凑高度均正常。
- `⌘⇧T` 打开 Terminal，窗口标题为 `Converter-tools — -zsh`。
- Finder 定位并选中 `Converter-tools`。
- 窗口完整落在屏幕可见区域内。

未实测或未覆盖：

- “测试失败”行内操作没有用真实失败项触发；执行逻辑复用测试页的运行按钮。
- 推送和拉取只在临时仓库执行，没有对用户现有项目实际推送或拉取。
- Git 同步成功路径和可模拟错误路径已在临时 remote 验证；真实 GitHub 凭据失效、SSH 密钥失效和真实网络中断仍未在用户仓库触发。
- 本地 remote 执行过快，“运行中”进度态没有被稳定截图；按钮禁用逻辑复用同一 `runningAction` 状态。
- 菜单栏待处理数字与菜单点击未直接验证；`MenuBarExtra` 标签的 60 秒静默到期刷新没有等待实际到期。
- 本地通知已验证授权与通知中心落库；banner 视觉、声音和点击跳转未逐项截图验证。
- 稍后提醒没有实际等待 1 小时到期；到期重算依赖每 60 秒时间刷新。
- “全部恢复”未单独触发；逐条恢复已验证。
- 编辑器未实际启动：Xcode 与 Antigravity 只在菜单中确认，未点击打开；JetBrains 系列、Cursor、VS Code 和 Zed 未安装，未做真机打开。
- 失败测试、清理命令实际执行仍依赖用户确认，原生版不自动删除。

## 本轮 UI 收口（2026-11-24）

- 总览：布局切换、筛选、批量选择实际落在标题行右端，不再单独占一行；布局只保留卡片墙/极简列表，改用原生 `Picker(.segmented)`；筛选使用原生 `Menu` + `.buttonStyle(.glass)`；批量选择使用原生玻璃按钮。
- 项目页：hero 改为全宽 300，新增 `ProjectArtwork` 自动扫描（≥20 KB、≥640×300、宽高比 ≥1.2，优先 og/cover/home/hero）；标题、路径、标签叠在底部暗色渐变上；六个页签改为独立 `ToolbarItem(.principal)`；搜索保持独立图标；项目子页工具栏只保留退出、重扫、搜索。
- 概览：项目简介与技术栈合并为同一张卡片并横向分栏；备注与本周提交同排。
- 底部运行/测试操作区：启动/测试及 7 个操作项全部带名字，统一 66×24，使用原生 `.buttonStyle(.glass)`；状态在左，保留外层胶囊玻璃。
- 踩坑：macOS 26 + `.toolbar(removing: .title)` 下，`ToolbarItemGroup(.confirmationAction)`、`.primaryAction` 和 `ToolbarSpacer(.flexible)` 没有把子视图操作项稳定推到右侧；最终改用内容标题行 `HStack`，不要再盲目试 placement。
- 验证：`swift test --package-path macos` 32/32；`swift build --package-path macos -c release`；CUA 实测卡片墙/极简列表切换、项目页 hero、六页签、底部七项操作区；`git diff --check` 通过。
- 分发：`FizzDeck-0.2.1-arm64.dmg`，Release 二进制，ad-hoc 签名，SHA-256 `5b0b4e2da4636c1e93416cf8317ecf9db55f35ec57f0b89af0a79b53abe14de7`；已上传 GitHub Release，未做 Developer ID/公证。

## 设置与图标收口（2026-11-25）

- 设置入口位于侧栏最下方，另有 `⌘,`；通用页包含登录时启动、通知权限和完整磁盘访问，关于页包含版本、手动检查更新、主页、关注 `@koroo` 和 GitHub。
- 图标来源改为 IconMCP `https://iconmcp.com/mcp`，共 59 个 SVG；统一 outline、16px 基准、stroke 1.3、radius 2，运行时按 template tint 并统一放大约 12%。
- `FizzIcon` 优先加载 bundle 内 `Resources/Icons`，开发态回退仓库路径；未覆盖的动态符号回退到 `.semibold` SF Symbol。构建脚本已复制整个 `Icons` 目录。
- 已移除项目 folder、汇总指标、设置页、命令面板和待处理行的图标色块底板；操作区胶囊、卡片和玻璃容器保持不变。
- 项目总览右上角视图切换改为 `GlassEffectContainer` + `.glassEffect` 的分段胶囊；筛选保留原生 `Menu`，外层显式使用 Liquid Glass。
- 验证：`swift test --package-path macos` 49/49；`swift build --package-path macos -c release` 通过；CUA 检查主界面、设置/关于和命令面板；bundle 内 59 个 SVG 可加载。
- 已发布：`v0.2.3`（build 5），Release DMG、landing 和线上下载验收已完成；签名仍为 ad-hoc，未公证。

## 发布记录

- v0.2.3：`https://github.com/CClishan/Fizzdeck/releases/tag/v0.2.3`（Release ID `457653656`，asset ID `790049637`）
- v0.2.3 安装包：`FizzDeck-0.2.3-arm64.dmg`，2,283,542 bytes，Apple Silicon，ad-hoc 签名，未公证
- v0.2.3 SHA-256：`582377bef15d25527e1660fb13fbd66527d670f0ba8c46f0583015df9e404c9a`
- v0.2.3 源码提交：`b36d8b8 Release FizzDeck 0.2.3`
- v0.2.3 landing 提交：`2a74a0b feat: update FizzDeck download to 0.2.3`
- v0.2.3 线上验收：`https://koroo.top/fizzdeck` 显示“原生版 v0.2.3”；`releases/latest` 302 到 v0.2.3；重新下载的 DMG SHA-256 与 Release asset 一致，`hdiutil verify`、`codesign --verify --deep --strict` 和 app 内版本检查通过；Vercel deployment `AtRZisvNnbLw4AQz7QupdgWuiwDU` 状态 `success`
- v0.2.2：`https://github.com/CClishan/Fizzdeck/releases/tag/v0.2.2`（Release ID `457609467`）
- v0.2.2 安装包：`FizzDeck-0.2.2-arm64.dmg`，2,306,016 bytes，Apple Silicon，ad-hoc 签名，未公证
- v0.2.2 SHA-256：`d3ee8ae51ede416a65cccc450fb0374db4949e54919d520eeebae78144a2e0ee`
- v0.2.2 源码提交：`5446002 Release FizzDeck 0.2.2`
- v0.2.2 landing 提交：`bdd22fe feat: update FizzDeck download to 0.2.2`
- v0.2.2 线上验收：`https://koroo.top/fizzdeck` 显示“原生版 v0.2.2”；`releases/latest` 302 到 v0.2.2；重新下载的 DMG SHA-256 与 Release asset 一致，`hdiutil verify`、`codesign --verify --deep --strict` 和 app 内版本检查通过
- v0.2.1：`https://github.com/CClishan/Fizzdeck/releases/tag/v0.2.1`
- v0.2.1 安装包：`FizzDeck-0.2.1-arm64.dmg`，2,135,011 bytes，Apple Silicon，ad-hoc 签名，未公证
- v0.2.1 SHA-256：`5b0b4e2da4636c1e93416cf8317ecf9db55f35ec57f0b89af0a79b53abe14de7`
- v0.2.1 源码提交：`b2ae507 Polish overview, project hero, and action dock` + `577d7e7 Release FizzDeck 0.2.1`
- v0.2.1 landing 提交：`4c1a938 feat: update FizzDeck download to 0.2.1`
- v0.2.1 线上验收：`https://koroo.top/fizzdeck` 返回 200，显示“原生版 v0.2.1”；`releases/latest` 302 到 v0.2.1；下载文件 SHA-256 与 Release asset 一致，`hdiutil verify` 通过
- FizzDeck PR #1：`https://github.com/CClishan/Fizzdeck/pull/1`，已合并为 `a93c096`
- FizzDeck 推送：`origin/main`，`680f842..a93c096`
- 原生 Release：`https://github.com/CClishan/Fizzdeck/releases/tag/v0.2.0`
- 安装包：`FizzDeck-0.2.0-arm64.dmg`，Apple Silicon，ad-hoc 签名，未公证
- 安装包 SHA-256：`efb77fe2907c4b4adee24f36845e83d5d61b7c2f0f963487a5976901c6a78460`
- 安装包验证：下载后的文件大小 2,120,985 bytes、SHA-256 一致、`hdiutil verify` 通过、`codesign --verify --deep --strict` 通过；`spctl` 因未公证被拒绝
- 本轮会话 / 筛选提交：`55c0a20 Add AI session list and native filter menu`
- 分支 `codex/p1-palette-remote` 起始提交：`732ef39 Add remote repository actions and palette search`
- Landing 主入口：`https://koroo.top/fizzdeck`
- koroo 路由提交：`f4a1b4f feat: mount FizzDeck landing at /fizzdeck`
- koroo 下载入口提交：`089168d feat: add FizzDeck macOS download`
- Vercel 生产部署：deployment `8026894649`，状态 `success`
- 旧入口：`https://fizzdeck.pages.dev/` 仍返回 200；未做 301 重定向
- 线上验收（v0.2.0 历史）：`/fizzdeck` 返回 200；HTML 含“下载 macOS 版”、`releases/latest` 和“原生版 v0.2.0”
- 分发限制：前端仍使用 ad-hoc 签名，未做 Developer ID 签名、公证或自动更新。

## 工作区现状（重要）

- 当前发布分支是 `main`；PR #1 已合并，`v0.2.3` tag 已创建并已推送。
- 本轮发布记录提交后工作区应为空；`~/.repodeck` 的 `roots.json`、`state.json` 未因打包改动。
- 可分发安装包是 `macos/dist/FizzDeck-0.2.3-arm64.dmg`；`macos/dist/FizzDeck.app` 仍只是本机构建产物。
- koroo 下载入口已在 `2a74a0b` 提交并部署到 `https://koroo.top/fizzdeck`。
- 不要回滚 `server.mjs`、`vite.config.js`、`public/`、`landing.html`、`src/landing/`、`src/stageshow/` 的已发布内容；需要修改时单独开任务。

## 待增加能力（移交清单）

### 发布与交付

- [x] 原生安装包：`v0.2.3` arm64 DMG 已发布，landing 已接入下载；校验 SHA-256、镜像和 ad-hoc 签名均通过。
- [ ] 正式签名与公证：补 Developer ID、公证、自动更新和干净 Mac 安装验收。相关文件：`macos/script/build_and_run.sh`、`macos/Package.swift`、两份 README。验收：`spctl --assess` 通过、公证成功，并在干净 Mac 上安装运行。
- [ ] 旧域名收敛：把 `https://fizzdeck.pages.dev` 301 到 `https://koroo.top/fizzdeck`，保留 Cloudflare Pages 项目作为回滚。验收：旧路径 301、canonical/OG 不重复、静态资源不丢。
- [x] 文档同步：README、`macos/README.md`、HANDOFF 已补充 v0.2.3 下载地址、签名限制和发布记录。

### P1（收尾）

- [x] 命令面板增强：最近项目、最近动作、模糊匹配、置顶命令，以及“打开远程仓库 / 复制远端地址”。相关文件：`CommandPaletteView.swift`、`RepositoryStore.swift`、`GitService.swift`。验收：`⌘K` 可搜项目、分支、远端 URL 和动作；无远端时明确不可用；上下键、回车、Esc 不回归。
- [x] 远程仓库动作：从项目读取 `origin`，支持浏览器打开和复制 URL，不发起网络写操作。相关文件：`GitService.swift`、`ProjectDetailView.swift`。验收：有/无 origin、SSH/HTTPS 两种 URL 都正确。
- [ ] Git 真实错误路径（本地可模拟部分已完成）：已用本地 HTTP 401、SSH 公钥拒绝和关闭端口覆盖凭据/网络失败，7 个测试通过；真实 GitHub 凭据失效尚未在用户仓库触发。相关文件：`GitSyncService.swift`、`GitTabView.swift`、`AttentionQueueView.swift`。验收：命令不挂起，`GIT_TERMINAL_PROMPT=0` 生效，错误就地回显，工作区不变。
- [ ] 菜单栏与通知直测：全屏截图确认菜单栏显示待处理数字 `23`，与首页队列一致；通知点击回项目的路由代码和解析测试已完成，真实 banner 点击与 60 秒静默到期尚未直测。相关文件：`MenuBarView.swift`、`LocalNotifications.swift`、`FizzDeckApp.swift`、`AppRouting.swift`。验收：系统菜单栏可读、到期刷新、banner/click 路径有记录。

### P2（产品能力）

- [x] 原生删除项目：对齐网页版的备份、移入废纸篓、浅路径保护、目录名确认和测试运行时拦截。相关文件：`RepositoryStore.swift`、`ProjectDetailView.swift`、`ProjectRemovalService.swift`。验收：不自动永久删除；失败不改变目录；备份可恢复；6 例单测和确认框已验收。
- [x] 批量操作：批量重扫、批量复制清理命令、按组筛选。相关文件：`HomeDashboardView.swift`、`RepositoryStore.swift`、`RepositoryScanner.swift`。验收：选择态清晰、部分失败可回显、无误触破坏性操作；目录存在性预检和数量回显已实现。
- [x] 编辑器覆盖：JetBrains 系列、Antigravity、嵌套 Xcode 工程。相关文件：`SystemActions.swift`、`CommandPaletteView.swift`、`Components.swift`。验收：安装/未安装、工程/普通目录分别显示正确；本机已验证 Xcode 与 Antigravity，JetBrains 映射待安装后直测。
- [x] 测试基线：新增 Swift test target，覆盖 `ProjectAttentionQueue` 排序和 `GitService` ahead/behind 解析。相关文件：`macos/Package.swift`、`macos/Tests/`。验收：`swift test` 可独立运行，49 例通过。
- [x] AI 会话管理：会话列表、按工具过滤、恢复命令和精确 CLI 进程结束已完成；Desktop app-server 永不终止。相关文件：`SessionIndex.swift`、`SessionProcessService.swift`、`SessionsTabView.swift`。验收：Codex/Claude 两类会话、无会话空态、复制命令正确；结束只在明确匹配时出现。

### 质量与性能

- [ ] 长列表 60fps：项目多、日志长、任务运行时用 Instruments 量；只动必要属性，避免重排、闪烁和溢出。
- [ ] 可访问性：VoiceOver 顺序、减少动态效果、键盘全路径；补充 `accessibilityReduceMotion` 覆盖。
- [ ] 大目录扫描：首次扫描的 `du` 开销、缓存命中、取消/重扫；给出耗时基线。
- [x] 真实项目回归：用 `repo-dashboard` 脏工作区、`video-tem` 无 upstream、`shipany-template-two` 268 项改动核对了改动列表、概览与测试底栏；只读，没有同步或删除。

### 建议接手顺序

1. 先跑基线：`swift build --package-path macos`、`swift test --package-path macos`、`./macos/script/build_and_run.sh --verify`。
2. P1 功能已完成；下一步补真实凭据失效/网络中断和菜单栏/通知直测。
3. P2 已完成；删除只可用临时目录验证，不要对真实项目点击确认。
4. `v0.2.3` 已发布；下一版再做 Developer ID 签名、公证和自动更新，旧域名 301 仍需单独确认。

### 不做

- 不做整套暗色主题。
- 不做吉祥物。
- 不在原生版自动执行破坏性删除。
- 不为了“完整”重写网页版已有能力；按日常使用频率补齐。

## 关键实现提示

- 共享状态目录是 `~/.repodeck`，不要改路径，旧安装依赖它。
- 原生版刻意不开启 App Sandbox，需要访问任意用户目录和执行项目脚本。
- `RepositoryStore.requestedTab` 用于从首页跳转到项目页签；`ProjectDetailView` 消费后清空。
- `RepositoryStore.isCommandPalettePresented` 控制覆盖层；菜单和视图共用。
- `RepositoryStore.loadRemotes` 以最多 4 个并发读取 `origin`，缓存缺失结果；项目页和命令面板共用。
- `GitRemote` 只负责把 remote 转成浏览器地址，不改变原始 remote；打开/复制都不发起网络写操作。
- `ShellOutput.timedOut` 是 Git 同步超时文案的依据；新增后台命令时不要只看退出码。
- `GitService.summary` 多跑一次 `git rev-list --count --left-right @{upstream}...HEAD`；无 upstream 时返回 0/0。
- `GitService.trackingCounts` 是 ahead/behind 的唯一解析入口，输出顺序是 behind、ahead；新增调用不要重复解析。
- `ProjectEditor.available` 只返回已安装且能定位打开目标的编辑器；Xcode 嵌套搜索最多 3 层，并跳过生成目录。
- `FizzDeckTests` 直接依赖 executable target；新增可测逻辑保持 internal，不要为了测试改成 public。
- 首页队列只在总览、无搜索、无筛选时显示。
- 队列的 `ProjectAttentionKind.priority` 是唯一排序来源，新增类型时改这里。
- 窗口可见性校正只在窗口不可达时触发，不会强行覆盖用户正常摆放。
- 原生动效统一走 `FizzMotion`，新增动画先复用它，并接 `accessibilityReduceMotion`。
- koroo 的 landing 路由是 `app/fizzdeck/page.tsx`；`fizzdeck.css` 只在 `.fizzdeck-page` 下生效。若 koroo 工作区有其他未完成改动，用干净 `HEAD` 临时副本验证。
- 新增公开路由时同步 `public/llms.txt`，避免机器可读索引与页面入口脱节。

## CUA 验证提示

- 键盘名用 xdotool 风格：`Return`、`Down`、`Up`、`Escape`。
- `pressKey("return")`、`pressKey("down")` 会报 `keyNotFound`；用 `Return` / `Down`。
- 打开命令面板：`await app.pressKey("cmd+k")`。
- 点击 AX 行前先确认 FizzDeck 是前台；可用 `osascript` 设置 `frontmost of process "FizzDeck"`。
- 窗口坐标异常时先看 `CGWindowList`；不要根据截图白边判断应用崩溃。

## 常用命令

```sh
cd /Users/a003/dsh-workspace/repo-dashboard

swift build --package-path macos
swift test --package-path macos
./macos/script/build_and_run.sh --verify
./macos/script/build_and_run.sh --sign-local
./macos/script/build_and_run.sh --logs
```

用 Xcode 调试时打开 `macos/Package.swift`。产物在 `macos/dist/FizzDeck.app`。
