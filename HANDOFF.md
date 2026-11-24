# FizzDeck 交接文档

更新时间：2026-11-24  
仓库：`/Users/a003/dsh-workspace/repo-dashboard`  
当前分支：`main`  
当前 HEAD：`4133ff2 Ship native dashboard and public landing page`  
状态：P0 / P1 已提交并推送到 `origin/main`；landing 已部署到 `https://fizzdeck.pages.dev`

## 新对话开场提示

把下面这段直接粘贴到新对话：

```text
继续 FizzDeck 原生 macOS 项目，仓库在 /Users/a003/dsh-workspace/repo-dashboard。

先读 HANDOFF.md、AGENTS.md 和 macos/README.md，再执行 git status / git diff，确认当前 P0 改动。不要触碰工作区里与网页版、landing、stageshow 相关的改动（server.mjs、vite.config.js、public/、landing.html、src/landing/、src/stageshow/），它们不属于本任务。

不要自动提交、推送、签名或部署，等我明确确认。下一步按 HANDOFF.md 的 P1 清单推进：先汇报你选的任务、要改的文件和验收方式，再动手。

界面要求：纯 SwiftUI、浅色 Liquid Glass，不做整套暗色和吉祥物；UI 不加多余标签，让布局自己解释。
```

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
- Git 同步的成功路径只在本地临时 remote 上验证；未验证真实 GitHub 凭据失效、无 upstream、网络中断等错误文案。
- 本地 remote 执行过快，“运行中”进度态没有被稳定截图；按钮禁用逻辑复用同一 `runningAction` 状态。
- 菜单栏待处理数字与菜单点击未直接验证；`MenuBarExtra` 标签的 60 秒静默到期刷新没有等待实际到期。
- 本地通知已验证授权与通知中心落库；banner 视觉、声音和点击跳转未逐项截图验证。
- 稍后提醒没有实际等待 1 小时到期；到期重算依赖每 60 秒时间刷新。
- “全部恢复”未单独触发；逐条恢复已验证。
- 编辑器打开未实操：当前扫描项目没有顶层 Xcode 工程目标，机器也未安装 Cursor / VS Code / Zed。
- 失败测试、清理命令实际执行仍依赖用户确认，原生版不自动删除。

## 发布记录

- 提交：`4133ff2 Ship native dashboard and public landing page`
- 推送：`origin/main`，`b38b6d3..4133ff2`
- Cloudflare Pages 项目：`fizzdeck`
- 生产地址：`https://fizzdeck.pages.dev/`
- 本次部署：`780ed1fd.fizzdeck.pages.dev`（生产域名已验证，部署域名在当前代理下 TLS 握手失败）
- 线上验收：`/` 返回 200，landing 的 JS、CSS、logo 资源均返回 200；滚动到 CTA 后文案、命令和 GitHub 按钮正常显示。
- 原生 app 仍为本地 ad-hoc 构建，未做 Developer ID 签名、公证或分发。

## 工作区现状（重要）

本任务产生的改动：

- `README.md`
- `README.zh-CN.md`
- `macos/README.md`
- `macos/Sources/FizzDeck/App/FizzDeckApp.swift`
- `macos/Sources/FizzDeck/Models/Models.swift`
- `macos/Sources/FizzDeck/Models/ProjectAttention.swift`（新增）
- `macos/Sources/FizzDeck/Services/GitService.swift`
- `macos/Sources/FizzDeck/Services/GitSyncService.swift`（新增）
- `macos/Sources/FizzDeck/Services/RepositoryScanner.swift`
- `macos/Sources/FizzDeck/Services/RootStore.swift`
- `macos/Sources/FizzDeck/Stores/RepositoryStore.swift`
- `macos/Sources/FizzDeck/Support/SystemActions.swift`
- `macos/Sources/FizzDeck/Support/LocalNotifications.swift`（新增）
- `macos/Sources/FizzDeck/Support/WindowFrameGuard.swift`（新增）
- `macos/Sources/FizzDeck/Views/AttentionQueueView.swift`（新增）
- `macos/Sources/FizzDeck/Views/CleanupTabView.swift`
- `macos/Sources/FizzDeck/Views/CommandPaletteView.swift`（新增）
- `macos/Sources/FizzDeck/Views/Components.swift`
- `macos/Sources/FizzDeck/Views/ContentView.swift`
- `macos/Sources/FizzDeck/Views/GitTabView.swift`
- `macos/Sources/FizzDeck/Views/HomeDashboardView.swift`
- `macos/Sources/FizzDeck/Views/MenuBarView.swift`（新增）
- `macos/Sources/FizzDeck/Views/OverviewTabView.swift`
- `macos/Sources/FizzDeck/Views/ProjectDetailView.swift`
- `macos/Sources/FizzDeck/Views/SidebarView.swift`
- `src/landing/`
- `src/stageshow/`
- `landing.html`
- `public/`（Vite 构建产物）

**不属于本任务、不要回滚或提交的改动：**

- 用户已明确授权把网页版和 landing 一起提交部署；`server.mjs`、`vite.config.js`、`public/`、`landing.html`、`src/landing/`、`src/stageshow/` 现在属于同一发布批次。

P1 验证期间继续检测到 `src/landing/FizzDeckStage.jsx`、`src/landing/fizzdeck-stage.css` 和根目录 `stage-test.html` 有并行更新；本任务未写入、未回滚。

## 下一步任务

### 待确认

- [x] 提交并推送 P0 / P1。
- [x] 部署 landing 到 Cloudflare Pages。
- [ ] 如需公开分发原生 app，补 Developer ID 签名、公证和版本号。

### P1（建议按顺序）

- [x] 队列条目直接操作：在待处理行内提供“推送 / 拉取 / 运行测试 / 复制清理命令”，不必先进入项目页。
- [x] 队列忽略/稍后：允许对单个项目的某类提醒静音或延后，避免长期噪声。
- [x] Git 快捷同步：fetch、pull、push 带脏工作区保护、确认和结果回显。
- [x] 菜单栏常驻：菜单栏显示待处理数量，快速打开总览/最近项目；开发服务就绪或测试失败时发本地通知。
- [x] 信息架构收敛：首页筛选合并，项目头部动作收敛，端口状态回到概览，动效统一并尊重减少动态效果。
- [ ] 命令面板增强：最近项目、最近动作、模糊匹配、置顶命令，以及“打开远程仓库 / 复制远端地址”。

### P2

- [ ] 原生删除项目：对齐网页版的备份、路径保护和目录名确认。
- [ ] 批量操作：批量重新扫描、批量复制清理命令、按组筛选。
- [ ] 编辑器覆盖扩展：JetBrains 系列、Antigravity；支持识别嵌套的 Xcode 工程。
- [ ] 为 `ProjectAttentionQueue` 排序和 Git ahead/behind 解析补最小单元测试；当前 `Package.swift` 没有 test target。
- [ ] AI 会话管理：会话列表、恢复、结束和按项目过滤。

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
- `GitService.summary` 多跑一次 `git rev-list --count --left-right @{upstream}...HEAD`；无 upstream 时返回 0/0。
- 首页队列只在总览、无搜索、无筛选时显示。
- 队列的 `ProjectAttentionKind.priority` 是唯一排序来源，新增类型时改这里。
- 窗口可见性校正只在窗口不可达时触发，不会强行覆盖用户正常摆放。

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
