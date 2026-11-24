# FizzDeck 交接文档

- 更新时间：2026-11-24
- 仓库：`/Users/a003/dsh-workspace/repo-dashboard`
- 当前分支：`codex/p1-palette-remote`（PR #1，等待合并）
- 基线 HEAD：`00c678b Record FizzDeck landing deployment`
- 状态：P0 完成，P1 进行中；命令面板、远程仓库动作、Git 错误文案已完成；原生 app 可本地构建和 ad-hoc 运行；landing 主入口为 `https://koroo.top/fizzdeck`，旧 `https://fizzdeck.pages.dev` 保留可用。

## 新对话开场提示

把下面这段直接粘贴到新对话：

```text
继续 FizzDeck 原生 macOS 项目，仓库在 /Users/a003/dsh-workspace/repo-dashboard。

先读 HANDOFF.md、AGENTS.md 和 macos/README.md，再执行 git status / git diff。当前 P0 已完成，P1 进行中；命令面板、远程仓库动作和 Git 错误文案已完成。下一步优先补菜单栏/通知直测，或从 HANDOFF.md 的“待增加能力”选择任务，先汇报改动文件和验收方式，再动手。

不要自动提交、推送、签名或部署，等我明确确认。不要回滚网页版、landing、stageshow 的已发布内容；需要改时先确认范围。

界面要求：纯 SwiftUI、浅色 Liquid Glass，不做整套暗色和吉祥物；UI 不加多余标签，让布局自己解释。
```

## 移交摘要

| 项目 | 当前状态 |
|---|---|
| 原生 app | P0 完成，P1 7/9；`swift build` 通过；ad-hoc 签名可本地运行 |
| 原生分发 | 未做 Developer ID 签名、公证、安装包和自动更新 |
| Web UI | 保留在 `src/` + `server.mjs`，不是当前主入口 |
| Landing | `https://koroo.top/fizzdeck` 已上线；旧 `https://fizzdeck.pages.dev` 仍返回 200 |
| 仓库 | `main` 与 `origin/main` 一致；本轮 P1 改动已提交到 `codex/p1-palette-remote`，PR #1 等待合并 |
| 验证基线 | Swift build、GitSync 本地 6 项、CUA 远程动作；ESLint、TypeScript、34 页生产构建、1440/390/320 浏览器验收、reduced motion 通过 |
| 任务进度 | P0 5/5；P1 7/9；P2 0/5；发布与交付 0/3；质量与性能 0/4 |

## 项目是什么

FizzDeck 是一个本地优先的 macOS 项目管理器。原生版是主入口，纯 SwiftUI，不需要 Node.js；网页版保留在 `src/` 和 `server.mjs`，两者共用 `~/.repodeck` 本地状态。

用户已确认的方向：

- 原生 macOS 是主推版本，网页版是快速方案。
- 左侧导航保持清爽，信息尽量少。
- 不使用大面积深色主题，不做吉祥物。
- 默认中文、结论先行、短句。
- 生产代码禁止 Mock。
- 未经明确确认，不提交、不推送、不签名、不部署。

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
- 编辑器：自动检测 Cursor、VS Code、Zed、Xcode；Xcode 只对存在 `.xcworkspace`、`.xcodeproj` 或 `Package.swift` 的项目显示。
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
- 排序、颜色、AI 工具收进一个“筛选”菜单；活动筛选以可移除 chip 显示在控件下方，菜单图标在有筛选时使用强调色。
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
- CUA 实测：选择紫色颜色后出现“紫 ×”chip 和“清除”，项目数变为 0；清除后恢复 23 个项目。
- CUA 实测：卡片墙、极简列表、横向画廊三种布局切换正常。
- CUA 实测：项目头部只剩星标、打开方式、更多三个控件；打开方式包含 Finder、Terminal、复制路径，星标可切换并恢复。
- CUA 实测：辅助功能树中“打开方式”只出现一次，不再拆成 folder 和 chevron 两个控件。
- CUA 实测：概览“预览端口 4317”和“运行与测试”面板保留端口状态；项目头部不再显示 localhost。
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
- 编辑器打开未实操：当前扫描项目没有顶层 Xcode 工程目标，机器也未安装 Cursor / VS Code / Zed。
- 失败测试、清理命令实际执行仍依赖用户确认，原生版不自动删除。

## 发布记录

- FizzDeck 提交：`00c678b Record FizzDeck landing deployment`
- FizzDeck 推送：`origin/main`，`4133ff2..00c678b`
- 本轮 P1 PR：`https://github.com/CClishan/Fizzdeck/pull/1`（未合并）
- Landing 主入口：`https://koroo.top/fizzdeck`
- koroo 路由提交：`f4a1b4f feat: mount FizzDeck landing at /fizzdeck`
- koroo 当前 `main`：`cff192b`（motion/article 收尾提交）
- 旧入口：`https://fizzdeck.pages.dev/` 仍返回 200；未做 301 重定向
- 线上验收：`/fizzdeck` 返回 200，canonical 为 `https://koroo.top/fizzdeck`；1440/390/320px 无横向溢出，视图切换、复制命令、返回链接和 reduced motion 正常。
- 原生 app 仍为本地 ad-hoc 构建，`codesign --verify --deep --strict` 通过；未做 Developer ID 签名、公证或分发。

## 工作区现状（重要）

- 交接前 `git status --short` 为空，`main` 与 `origin/main` 一致。
- P0 / P1 第一批代码、landing、README 和 HANDOFF 已提交；本轮新增命令面板、远程仓库、Git 错误文案和文档，提交在 `codex/p1-palette-remote`，PR #1 等待合并。
- `macos/dist/FizzDeck.app` 是本机 ad-hoc 构建产物，不是发行包；不要把它当作可分发版本。
- koroo 仓库的 motion/article 改动已在 `cff192b` 提交；本交接不再依赖未提交改动。
- 不要回滚 `server.mjs`、`vite.config.js`、`public/`、`landing.html`、`src/landing/`、`src/stageshow/` 的已发布内容；需要修改时单独开任务。

## 待增加能力（移交清单）

### 发布与交付

- [ ] 原生分发：补 Developer ID 签名、公证、版本号、DMG/ZIP 和更新策略。相关文件：`macos/script/build_and_run.sh`、`macos/Package.swift`、两份 README。验收：`codesign --verify --deep --strict`、`spctl --assess`、公证成功，并在干净 Mac 上安装运行。
- [ ] 旧域名收敛：把 `https://fizzdeck.pages.dev` 301 到 `https://koroo.top/fizzdeck`，保留 Cloudflare Pages 项目作为回滚。验收：旧路径 301、canonical/OG 不重复、静态资源不丢。
- [ ] 文档同步：发布新版本时同步 README、`macos/README.md`、HANDOFF 的 live link、版本号和限制说明。

### P1（下一阶段优先）

- [x] 命令面板增强：最近项目、最近动作、模糊匹配、置顶命令，以及“打开远程仓库 / 复制远端地址”。相关文件：`CommandPaletteView.swift`、`RepositoryStore.swift`、`GitService.swift`。验收：`⌘K` 可搜项目、分支、远端 URL 和动作；无远端时明确不可用；上下键、回车、Esc 不回归。
- [x] 远程仓库动作：从项目读取 `origin`，支持浏览器打开和复制 URL，不发起网络写操作。相关文件：`GitService.swift`、`ProjectDetailView.swift`。验收：有/无 origin、SSH/HTTPS 两种 URL 都正确。
- [ ] Git 真实错误路径（本地可模拟部分已完成）：已补 timeout 和常见错误文案；待真实 GitHub 凭据失效、SSH 密钥失效和真实网络中断直测。相关文件：`GitSyncService.swift`、`GitTabView.swift`、`AttentionQueueView.swift`。验收：命令不挂起，`GIT_TERMINAL_PROMPT=0` 生效，错误就地回显，工作区不变。
- [ ] 菜单栏与通知直测：`MenuBarExtra` 数字、60 秒静默到期、通知点击回到项目。相关文件：`MenuBarView.swift`、`LocalNotifications.swift`、`FizzDeckApp.swift`。验收：系统菜单栏可读、到期刷新、banner/click 路径有记录。

### P2（产品能力）

- [ ] 原生删除项目：对齐网页版的备份、移入废纸篓、浅路径保护、目录名确认和测试运行时拦截。相关文件：`RepositoryStore.swift`、`ProjectDetailView.swift`、新增删除服务。验收：不自动永久删除；失败不改变目录；备份可恢复。
- [ ] 批量操作：批量重扫、批量复制清理命令、按组筛选。相关文件：`HomeDashboardView.swift`、`SidebarView.swift`、`AttentionQueueView.swift`。验收：选择态清晰、部分失败可回显、无误触破坏性操作。
- [ ] 编辑器覆盖：JetBrains 系列、Antigravity、嵌套 Xcode 工程。相关文件：`SystemActions.swift`、`Models.swift`。验收：安装/未安装、工程/普通目录分别显示正确。
- [ ] 测试基线：新增 Swift test target，覆盖 `ProjectAttentionQueue` 排序和 `GitService` ahead/behind 解析。相关文件：`macos/Package.swift`、`macos/Tests/`。验收：`swift test` 可独立运行。
- [ ] AI 会话管理：会话列表、恢复、结束、按项目过滤；仍只读本地元数据。相关文件：Services 与 Views 下的会话相关实现。验收：Codex/Claude 两类会话、无会话空态、复制命令正确。

### 质量与性能

- [ ] 长列表 60fps：项目多、日志长、任务运行时用 Instruments 量；只动必要属性，避免重排、闪烁和溢出。
- [ ] 可访问性：VoiceOver 顺序、减少动态效果、键盘全路径；补充 `accessibilityReduceMotion` 覆盖。
- [ ] 大目录扫描：首次扫描的 `du` 开销、缓存命中、取消/重扫；给出耗时基线。
- [ ] 真实项目回归：至少用一个脏工作区、一个无 upstream、一个多服务项目跑完整流程。

### 建议接手顺序

1. 先跑基线：`swift build --package-path macos`、`./macos/script/build_and_run.sh --verify`。
2. 命令面板和远程仓库动作已完成；下一步补真实凭据失效/网络中断和菜单栏/通知直测，降低日常使用噪声。
3. 再评估 Git 错误路径是否还缺真实环境覆盖；缺则补测，不缺则进入 P2。
4. 最后做原生删除、批量操作和 Developer ID 分发，避免在未稳定的交互上扩大破坏面。

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
./macos/script/build_and_run.sh --verify
./macos/script/build_and_run.sh --sign-local
./macos/script/build_and_run.sh --logs
```

用 Xcode 调试时打开 `macos/Package.swift`。产物在 `macos/dist/FizzDeck.app`。
