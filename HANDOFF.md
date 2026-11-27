# FizzDeck 交接文档

更新：2026-11-27。原生产品仓库 `CClishan/Fizzdeck`，官网仓库 `CClishan/koroo-blog`。请先区分本地构建、官网部署和 GitHub Latest。

| 项目 | 当前状态 |
|---|---|
| 公开安装包 | [v0.8.0 / Build 16](https://github.com/CClishan/Fizzdeck/releases/tag/v0.8.0) 已设为 [Latest](https://github.com/CClishan/Fizzdeck/releases/latest)，非草稿、非预发布。[PR #3](https://github.com/CClishan/Fizzdeck/pull/3) 合并提交 [`3b6a846`](https://github.com/CClishan/Fizzdeck/commit/3b6a8464ee96b7531ffce3b720c0673d5b36e053) 即 tag 对应源码；[GitHub Actions](https://github.com/CClishan/Fizzdeck/actions/runs/46005894773) 生成并校验 DMG 和旁置 SHA-256。 |
| v0.8.0 / Build 16 | 公开 `FizzDeck-0.8.0-arm64.dmg` 为 **6,726,887 字节**，SHA-256 `4f9334184d0596a8fbc20a46e7ab074bd9f40562007900111801079fe8cf58cf`。草稿时只读挂载实读 `0.8.0 / 16`、`com.a003.fizzdeck`、arm64、macOS 26.0、三个动作元数据，严格签名校验通过；公开后匿名重新下载两个资产，字节与草稿一致。签名为 ad-hoc，无 Team ID、未公证。本机带 Finder 排布的候选 SHA `bda4dc4de6d764d57498fed2aa86d648b174e1c0a196c866a07401990283b0db` 不适用于公开包。[发行说明](docs/releases/v0.8.0.md)。 |
| v0.7.5 / Build 13 | 从原有未提交功能冻结独立源码，在其上升级版本：`macos/dist/FizzDeck-0.7.5-Build13-native-source.tar.gz`。源码归档 SHA-256 `414db0f4a29602463b68aa7a6443a020a6d1b79c2e8fee9915a00d83e646ed5c`。独立 `swift test` **264 项通过**。安装包 `macos/dist/FizzDeck-0.7.5-arm64.dmg`，SHA-256 `5378cbc78c863d019961e04c517ee5108af629430431f81d7afeb6bd59fbf844`，挂载后实读 `0.7.5 / 13`，`codesign --verify --deep --strict`、DMG 和旁置 SHA 校验均通过。未公证。 |
| 阶段版本 | v0.7.6 的体检、v0.7.7 的趋势与保护、v0.8.0 的系统集成均随 Build 16 分发。独立 Build 13 安装包、校验和源码仍在 `macos/dist/candidates/v0.7.5-build13/`；不要用 Build 16 源码重建 Build 13。 |
| 官网 | [koroo.top/fizzdeck](https://koroo.top/fizzdeck) 已上线 v0.8.0 文案，保留 Studio Display 与 Mac Studio 样机及 Build 13 实机图。官网[提交 `896e08d`](https://github.com/CClishan/koroo-blog/commit/896e08dc6baf1f9bb3f75413281f3a037c4506a7)。[Vercel 生产部署](https://vercel.com/cclishans-projects/koroo-me/FbbZUt86AY2eEqFo4YtzgLrRZrnA)成功。公网页面 SHA-256 `1a8d7743fedc671474481a3cadf21c0a953c76274e1f290a1c01df8f01ac86a0`，HTML 与 9 个依赖均与发布产物逐字节一致。 |
| 本机开发签名 | 已用有效的 Apple Development 身份签好 `macos/dist/development-signed/FizzDeck.app`（`0.8.0 / 16`，原产品 Bundle ID）。严格签名校验通过；同构建的隔离副本在系统「快捷指令」中跑通了全部三项。 |
| 外部验收 | 已实际用 Git 和 `gh` 推送源码、触发 CI 并发布。当前只有 Apple Development 测试身份，缺 Developer ID Application 与 `NOTARY_PROFILE`。v0.5.3 和 v0.7.4 的原地升级及状态保留、完整 VoiceOver 朗读尚未实测。 |

**官网样机：** 原 Studio Display 与 Mac Studio 中展示真实 Build 13 工作台；其余三张为进度、版本和体检。此前已在 390px / 1440px 核对贴图、中英文和下载；WebP 边缘是 `#f6f6f6`，与展台背景同色。Build 16 文案沿用这组图片并标明截图来源。[本地预览](http://127.0.0.1:52020/landing.html)；其下载入口与公网均使用 `releases/latest`。已在 Latest 更新后部署新版文案。坐标见[官网验收](src/landing/REHEARSAL.md)。

本次发布准备再次用 Chrome 在 1440px / 390px 各点击切换中英文，核对下载地址、版本、截图来源和屏幕贴图位置，四种组合均无横向溢出。官网导出仍为 HTML + 9 个依赖，8 个依赖与线上相同；部署只需替换 HTML 并新增带内容哈希的文案脚本。对应补丁在 `output/release-v0.8.0/koroo-fizzdeck-0.8.0.patch`，浏览器记录在 `output/playwright/fizzdeck-v0.8.0/`。不要将 Swift 编译和测试的临时目录混入 Tailwind 的网页构建目录；本次网页产物从独立、无编译缓存的源码目录生成。

## 真机与回归

- 合并提交第一次 CI 的提示条测试在固定等待 260 毫秒后过早断言，原提交重跑通过。后续测试改为观察队列实际变动，再验证只移除目标提示；不改发布 App 的行为。

- macOS 26 托管 CI 中，旧的结束会话测试以 `yes` 充当 CLI；该版本的 `yes` 会改写参数，`ps` 看到的 `resume` 与会话 ID 不再是两个参数。测试改用同名可执行文件 `cat` 阻塞读取名为 `resume` 的 FIFO，每次生成独立会话 ID，并核对测试子进程的 PID 后才测试停止。保留应用的精确匹配规则。

最后一笔 Swift 改动后，使用 `-strict-concurrency=complete` 复测：**296 项，295 通过、1 项图形压测默认跳过、0 失败、0 编译警告**；该压测另行在解锁桌面通过。用同一份源码重建开发 App，实读 `0.8.0 / 16`，包含快捷指令元数据。Build 13 的 264 项属于单独源码快照。两个 workflow 通过 actionlint v1.7.12，所有 Shell 脚本通过语法检查，干净 `npm ci` + `npm run build` 通过。[PR CI](https://github.com/CClishan/Fizzdeck/actions/runs/46004663046)、[合并提交 CI](https://github.com/CClishan/Fizzdeck/actions/runs/46005782077) 与 [tag 工作流](https://github.com/CClishan/Fizzdeck/actions/runs/46005894773) 均通过。打包与压测日志在 `output/roadmap-qa-2026-11-27/`，键盘、快捷指令、最终构建与公网校验在 `output/integration-qa-2026-11-27/`，均不入 Git。

- L0 按产品设计跟踪前 8 个关注项目的根目录输入，文件变化仅重检该项目。L1 首扫后覆盖全部关注 Git 项目，串行、单项目 24 小时一次；应用重新激活会补排已到期项。HTTPS 与非交互 SSH 的支持边界见 [云端体检](docs/QUIET_FETCH.md)。L2 只有点击才运行，日志和停止状态跨页共享。端口释放重新核对身份，只发一次 `SIGTERM`；工作台、菜单与命令面板的旧入口不再按端口批量终止进程。
- L1 启动回归全程停留在工作台：10 个手动关注项目均完成检查，实测并发峰值为 1。跨进程复测用真实目录和符号链接：跨午夜不重置，第 86,399 秒仍限流，第 86,400 秒放行。刚挂载的 FSEvents 流可能补送旧 `HEAD` / `index` 事件；现在先核对文件状态，回放旧事件不会触发多余刷新。

- Build 13 独立 bundle + 临时 home：逐个点进「进度 / 运行 / 版本 / 项目信息」，确认选中状态；体检显示 fixture 的缺依赖问题；本周回顾显示 3 个项目并提供复制 Markdown；`⌘K` 搜索获焦。临时项目生成的四张真实截图已用于官网。桌面 1440px、手机 390px，切中英文、图片加载、下载目标、横向溢出与 JS 错误均检查通过。
- 键盘（开发版）：系统「键盘导航」关闭时，旧版本页反复 Tab 仍只会选中提交框。修复后，在有改动的隔离项目中，Tab 依次到文件 Diff、暂存按钮、页签，Shift-Tab 可返回；实际用方向键展开/收起 Diff，空格暂存、回车取消暂存，Git 暂存区恢复为空。干净项目可在输入框和原生分段页签间双向循环。左右方向键切换四页，辅助功能树的选中项与内容一致。`⌘1/2/3` 切换工作台/项目库/体检，`⌘K` 搜索打开项目、Esc 返回均已实测。最终签名构建在进度与版本页的辅助功能树中都只出现一次「项目页签」，版本选中值为 1。VoiceOver 实际朗读、其他页面与弹窗的完整焦点链待验。
- 深链：系统进程投递 `fizzdeck://open` 与 `fizzdeck://handoff`，应用日志确认进入 `run` 和打开接力卡；未受管路径未产生路由。快捷指令：ad-hoc 包可被检索，但运行体检时报 `LinkDaemon.ProcessRegistry.Errors 0`，日志为 `Unable to get teamId`。换 Apple Development 签名后，系统编辑器成功打开指定项目、返回两个项目各自的体检状态，并返回接力卡。返回的 251 字节 Markdown 与剪贴板完全一致。试后还原剪贴板和原有 20 条快捷指令。证据：`output/shortcut-signing-2026-11-27/results.json`。
- 签名排查：开发证书未过期，匹配的私钥也在，但 `codesign` 找不到连接证书与 Apple Root CA 的 WWDR G3。只把系统已验证的 G3 公共中间证书加入登录钥匙串后，Apple Development 即成为有效身份；未更改信任设置。开发签名的[复测步骤](docs/SYSTEM_INTEGRATION.md)不使用公证凭据。临时流程用 `shortcuts run --output-path` 时没有写出文件，因此复制动作的验收取系统编辑器的实际返回文本，与剪贴板逐字节比对。
- 进度图在隔离原生窗口从 14 天（约 $0.20 / 1 次提交）切到 30 天（约 $4.95 / 2 次提交）。周报取消同意无请求，同意后本地测试端点仅收到数字汇总；失败回退。首次基线需保留带 BOM 的 `.gitignore` 首条规则；实测 Git GC 后还原仍可用、暂存区字节不变。
- 压测：1,000 项目 / 10,000 会话，FTS P95 **0.96 ms**；真实表格 **60.1 FPS**，测试进程峰值 **118.8 MiB**。测量方法及样本边界见[复测说明](docs/SYSTEM_INTEGRATION.md)。
- 官网构建从 `public/.vite/manifest.json` 递归导出 landing 依赖，不会把伴生工作台或本机数据推到公开网站。仅需 `npm run build` + `node script/export_landing.mjs /path/to/koroo-blog`。此前截图版首屏 62,644 字节；已部署样机版首屏两张 WebP 共 116,414 字节（旧样机 PNG 为 1,184,186 字节），其余三张延迟加载。伴生 Web UI 保留既有六页签和已有操作，未改为只读。
- 本地构建曾在快捷指令元数据提取失败时提前移走 `macos/dist/FizzDeck.app`；已补回完整 Build 13，并改成先在临时目录组装成功再替换。验收新版使用 `FIZZDECK_DIST_DIR` 指向专用目录，不要退出用户其他副本或写入 `/Applications`。真实 `~/.repodeck/roots.json`、`state.json` 和已安装 App 的 mtime 前后相同。
- ad-hoc 和开发签名验收用的 QA 进程均已退出，临时安装副本已从 LaunchServices 注销并移除。真实 `roots.json`、`state.json` 与已安装 v0.5.3 的修改时间均未变。隔离项目保留一处未暂存的 README 改动，供后续 VoiceOver 走查。

## 继续工作

本次发版已完成。后续需在旧版实机验证两条更新路径并核对项目、星标和设置；补完整键盘与 VoiceOver 朗读。取得 Developer ID Application 和公证凭据后，再从对应源码制作公证分发版。公开 DMG 校验记录留在 `output/release-v0.8.0/public-verification.json`。

## 网页版对齐 macOS（2026-11-26，本地未提交）

### 视觉

- 建立与原生一致的浅色 / 低饱和炭黑 / 跟随系统三态外观，统一页面、侧栏、卡片、描边、选中填充和玻璃控件 Token；外观保存到浏览器并在刷新后保持。
- 侧栏改为 236px 悬浮卡片与 58px 图标栏双态，星标、分组、运行中状态、磁盘余量和设置入口保持；折叠状态刷新后保持。
- 工作台对齐原生总览：顶部 KPI、继续工作、待处理队列与分类过滤、本周活动时间线、提交热力图、费用构成、运行与健康；待处理项可直达项目页签。
- 项目页对齐紧凑 Header、六页签、项目封面/介绍/技术栈、四项微柱 KPI、服务、日志、最近活动和备注；项目库提供卡片/表格、筛选、闲置折叠、批量工具条；可清理页按项目汇总目录与复制命令。
- 弹窗统一为 macOS 风格：添加项目（根目录、手动路径、系统选文件夹、1–4 层扫描、候选批量加入、移除根目录但保留文件）、命令面板、设置、Toast；移除多余说明和视觉噪声。
- 已验证修复：添加项目根目录文字重叠、详情四项指标被压成 3+1、表格选择态全部行同时选中、命令面板 420px 高度截断、日志 ANSI 控制字符、`favicon.ico` 404、单面板活动区占满整行。

### 能力

- 状态每 20 秒刷新，页面重新可见时立即刷新；端口运行状态每次读取重新探测，避免旧缓存。
- 项目启动/停止轮询、测试运行/轮询、AI 会话继续/结束、星标/分组/重扫/Finder/移除项目、批量星标/分组/同步远程/复制清理命令。
- 命令面板支持项目名、路径、分支、技术栈、分组和动作搜索；`⌘K`、`⌘1/2/3/0`、`⌘R`、`⌃⌘S`、`⌘,` 快捷键。
- 详情页支持 Git 状态/远程/分支/拉取、文档读取、会话过滤与恢复命令、dev/test 日志、测试输出、清理目录；项目封面自动发现并通过 `/api/artwork` 展示。
- 主要文件：`src/App.jsx`、`src/index.css`、`src/components/{Sidebar,Fizz,Dialogs}.jsx`、`src/views/`、`src/lib/`、`server.mjs`、`index.html`、`public/`。

### 本轮验证

- `node --check server.mjs`：通过；`npm run build`：Vite 8.3.8 构建通过，产物写入 `public/`。
- Playwright CLI：`1320×900` 与 `720×700`；浏览器控制台 0 error / 0 warning；`720px` 下 `scrollWidth == clientWidth`，无横向溢出。
- 外观：设置中切换 `浅色 / 暗色 / 跟随系统` 均即时生效；`light`、`dark` 刷新后保持；`system` 在媒体模拟 light/dark 时正确切换；侧栏 `236 ↔ 58` 且刷新后保持。
- 命令面板：输入 `pixloading` 得到单条项目结果，`Enter` 打开项目详情。
- 详情：四项指标同一 `top=408` 一排展示；日志读取到真实 dev 日志，ANSI `ESC` 计数为 `0`。
- 添加项目：扫描 `/Users/a003/dsh-workspace` 发现 1 个 `repo-dashboard`，正确标记「已在看板」，未执行加入或移除。
- 项目库：表格 16 行；选择模式点击首行后只有该行复选框选中，批量工具条显示「已选 1」；可清理页显示 10 个项目、35 个目录、7.11 GB。
- 截图：`/tmp/fizz-qa/workbench-light-final.png`、`workbench-dark-final.png`、`detail-light-final.png`、`detail-dark-final.png`、`add-scan-dark-final.png`、`cleanup-dark-final.png`、`settings-light-final.png`、`palette-search-final.png`、`table-one-selected-final.png`、`workbench-720-dark-final.png`。

### 边界

- 本地验证服务：`http://127.0.0.1:4770`；旧验证服务 `4780` 与用户自己的 `5173` 未改动。
- 未执行真实启动/停止、测试运行、会话继续/结束、星标/分组/同步远程/删除、实际加入根目录或系统文件夹选择器；只验证了对应 UI、扫描与只读状态。
- 未验证低于 720px 的布局；网页不承担 macOS 菜单栏、系统通知、登录时启动、默认终端/编辑器选择和 Developer ID/公证等系统级能力。
- 本轮未 commit、未 push、未部署，也未改动已发布 landing。

## 已发布改造（`v0.3.0`，2026-11-25/26）

### Round 2 · Batch C4：双主题矢量 Logo 与浅色纯色背景（2026-11-26）

- `FizzAsset` 新增 `logo(for:)`：浅色加载 `FizzDeck_logo_light.svg`，暗色加载 `FizzDeck_logo_dark.svg`；`Bundle.main` → `Resources/` → `macos/Resources/` 三路查找，静态缓存，SVG 缺失时回退旧 `FizzDeck_logo.png`。
- 两份原始 SVG 从 `fizzdeck_{light,dark}.svg` 更名为 `FizzDeck_logo_{light,dark}.svg`，并移除自带的白色/黑色整块 `<rect>` 底板，改为真正透明底；`FizzLogo` 用 `scaledToFit()` 直接渲染，不再加 `logoPlate`、白底或描边，18/32/64pt 均无裁切。
- `FizzBackground` 浅色只渲染 `FizzTheme.page`（`#F8F8F7`），不再叠加 `warmGlow` / `coolGlow` 的 `RadialGradient`；暗色保持两处 `0.06` 微光。新增静态 `glowOpacity(for:)` 便于断言。
- `build_and_run.sh` 同时复制浅/暗 SVG 到 `$APP_RESOURCES/`，保留 PNG 兜底。
- 验证：`swift test --package-path macos` 142/142 通过（新增 SVG 双主题加载与浅色无光晕断言）；`swift build --package-path macos --build-path /tmp/fizzdeck-c4-build -Xswiftc -strict-concurrency=complete` 干净构建 0 warning / 0 error；`git diff --check` 通过。
- 隔离 GUI 验收：独立 bundle `com.a003.fizzdeck.c4audit` + 临时 `CFFIXED_USER_HOME`，路径 `/tmp/fizzdeck-c4-audit-o28LNa`，截图前缀 `/tmp/fizzdeck-c4-`。浅色首页与详情页背景为均匀纯色，无粉/紫渐变；浅/暗关于页分别为透明黑线/白线 Logo，无底板方块；浅/暗 `AddProjectsSheet` 的 18pt Logo 清晰、无裁切。验收后已退出 audit app、注销 LaunchServices 注册，无残留进程或 5199 监听。
- 隔离边界：真实 `~/.repodeck` 与 `/Applications/FizzDeck.app` mtime 未变；截图与临时 bundle 未纳入版本控制。C4 只做本地提交，未 push、未提 PR、未发版、未签名/公证/部署。

### Round 2 · Batch C3：P2 微瑕收口与本地分支提交（2026-11-26）

- `CommandPaletteView`：新增 `Support/CommandPaletteLayout.swift`，把行高 43、分区标题 28、列表内边距 12 与最大高度 420 固化为同一套常量；可见高度只落在完整行末尾，空间不足时不渲染末尾孤立的分区标题。默认场景下「命令」分组要么至少露出 1–2 条，要么整组隐藏；新增 3 例布局单测。
- `Formatting.bytes`：小于 1000 字节统一输出 `N B`，与 `WorkbenchMetrics.splitBytes` 对齐；首页 `82 B` 与详情 KPI 不再混用 `82 bytes`。新增 2 例格式单测。
- `FizzLogo`：浅色与暗色都使用圆角 App Icon 底板；暗色为 `white 0.95` + 黑色 10% 描边，浅色为 `white 0.99` + `FizzTheme.stroke` 细描边，「关于」页双态对称且黑线清晰。
- 验证：`swift test --package-path macos` 140/140 通过；`swift build --package-path macos --build-path /tmp/fizzdeck-c3-clean-build -Xswiftc -strict-concurrency=complete` 干净构建 0 warning / 0 error；`git diff --check` 通过。
- 隔离 GUI 验收：独立 bundle `com.a003.fizzdeck.c3audit` + 临时 `CFFIXED_USER_HOME`，路径 `/tmp/fizzdeck-c3-audit-zFibD9`，截图前缀 `/tmp/fizzdeck-c3-`。暗色 `⌘K` 在 420pt 上限处停在项目行末尾，「命令」标题不再孤立出现；浅/暗关于页 Logo 底板对称；暗色详情页真实启动 `npm run dev` 后显示绿色「1 运行中」，「预览」「停止」对比度正常；首页 fixture 显示 `82 B`。验收后已停止 dev 服务（5199 释放）并退出 audit app。
- 隔离边界：真实 `~/.repodeck` 与 `/Applications/FizzDeck.app` mtime 未变；未执行 commit 前的构建产物、临时 fixture 或截图未纳入版本控制。C3 只做本地分支提交，未 push、未提 PR、未发版、未签名/公证/部署。

### Round 2 · Batch C2：C1 审核收口与玻璃可读性精修（2026-11-26）

- C1 漏网清零：`OverviewTabView` 的 `WorkbenchMetricCard` 15、`AppSettingsView` 的 `SettingsCard` 14、`AttentionQueueView` 16 全部改为 `FizzRadius.card` / `FizzRadius.panel`；`AddProjectsSheet`「只添加当前文件夹」、`AppSettingsView`「前往下载」、`ProjectRemovalSheet`「取消」补齐 `.buttonStyle(.glass)`。
- `ProjectLogsPanel`：新增 `Support/ProjectLogSourcePolicy.swift`，用 `ProjectLogContext` + `resolve(current:previous:selected:)` 纯逻辑记录上一项目路径与 `testRun.startedAt`；只有同一项目产生新的测试运行才自动切 `.test`，切项目时重置并按 `testActive` / 可用日志归一化。日志文本的 10pt 内边距与 `log-bottom` 锚点分离，末行不再被日志视口底部裁切。
- 批量选择：复选框移入 `ProjectFolderCard` 头部右侧并替换端口徽章，删除 `.overlay(.topTrailing)`，不再遮挡；`batchBar` 的「完成」使用 `.glassProminent` + `.tint(FizzTheme.accent)` + `.controlSize(.regular)`，其余按钮逐个 `.glass`。GUI 验收发现外层 `.buttonStyle(.glass)` 会吞掉内层 prominent 样式，已改为逐个按钮设置，聚焦窗口下「完成」呈真实紫色。
- 玻璃可读性：`AddProjectsSheet` 用近实底 `elevatedFill`（暗 0.97 / 浅 0.94）+ 低透明玻璃 tint + 1pt 描边，遮罩加深到暗 0.55 / 浅 0.32；关闭 `×` 移到顶部统一栏右侧。`CommandPaletteView` 同样改为近实底（暗 0.97 / 浅 0.92）+ 加深遮罩，分区标题顶部间距 7→12、结果高度补偿 27→32，暗色下不再透出底层 KPI 白字。
- 暗色细节：`FizzLogo` 在暗色下增加浅色圆角底板与 1pt 黑描边，「关于」页图标清晰；`serviceButton` 明确 `.primary` 前景与 11pt medium，暗色下不再像禁用；`ProjectLogsPanel` 的 `dev / test` 从分段 Picker 改为与 Sessions/ProjectDetail 一致的紧凑胶囊切换器（`elevatedFill` 高亮 + glass 外壳）。
- 文案与语义：详情页 `Services → 服务`、`Logs → 日志`、`N running → N 运行中`，命令标识 `dev / test` 保留；`PortStatusBadge` 的 `.stopped` 改为中性 `.secondary`，橙色只留给未提交改动与待处理告警；项目详情工具栏返回图标 `xmark → chevron.left`，文案「返回总览」。
- 测试：新增 `ProjectLogSourcePolicyTests` 6 例（切项目不误切 test、新 test run 切 test、已有 test run 保持选择、初始来源、不可用回退）；`FizzDesignSystemTests` 增加 `PortStatusBadge` 色调/文案断言。`swift test --package-path macos` 135/135 通过；`swift build --package-path macos --build-path /tmp/fizzdeck-c2-clean-build -Xswiftc -strict-concurrency=complete` 干净构建 0 warning / 0 error；`git diff --check` 通过；`rg` 核查无 `.menuStyle(.borderlessButton)`、无 `.buttonStyle(.bordered/.borderedProminent)`、无数字 `cornerRadius:`、无数字 `.fizzCard(radius:)`，裸 `.shadow(` 仅 `FizzAdaptiveShadowModifier` 内部 1 处。
- 隔离 GUI 验收：独立 bundle `com.a003.fizzdeck.c2audit` + 临时 `CFFIXED_USER_HOME`，截图前缀 `/tmp/fizzdeck-c2-`；覆盖浅/暗首页、暗色批量选择（复选框不遮挡）、浅/暗详情与 `npm run test` 日志末行、浅/暗 `⌘K`、浅/暗 `AddProjectsSheet`、暗色关于页（Logo 可见）、浅色 settings `.glassProminent` 紫色、`port = 0` fixture 仅显示「启动/运行」无「预览」、临时 fixture 永久删除确认红色 destructive 按钮（已取消，未删除）。焦点态截图使用 `osascript activate` + `screencapture -l <windowId>` 获取，避免后台截图把 `.glassProminent` 拍成灰色。
- 窄窗：系统辅助权限拒绝 AX 设置窗口尺寸，CUA 拖拽也未改变尺寸；用临时 audit build 加 `.windowResizability(.contentSize)` + 1000pt 内容宽完成 1000pt 直测，Header/侧栏无裁切，截图后源码已恢复 `defaultSize(1320, 860)` 并重新构建。
- 隔离边界：真实 `~/.repodeck` 未写入，`roots.json`（Nov 25 11:35）、`scan-cache.json`（Nov 26 10:54）、`state.json` 的 mtime 未变；`/Applications/FizzDeck.app` 未触碰，真实 FizzDeck 未启动。一次误用 LaunchServices 启动曾在隔离 profile 中读到真实 roots，已重建隔离 `roots.json`/`scan-cache.json` 并清除 audit domain 的 recentProjects，未修改真实文件。
- 未直测：VoiceOver 顺序、纯键盘全路径、真实终端启动与菜单栏/通知 banner。C2 当轮未提交；后续已在 C3 统一本地分组提交，仍未 push/发版。

### Round 2 · Batch C1：设计 Token + 原生 Liquid Glass 控件层（2026-11-26）

- `FizzTheme.swift` 新增 `FizzRadius`：`frame` / `panel` 16、`card` 14、`inset` 10、`control` 8、`micro` 4；新增 `FizzSpacing`：`page` 24、`section` 20、`panel` 16、`grid` 12、`row` 8；新增 `FizzElevation`（`.subtle` / `.raised` / `.floating`）与 `fizzAdaptiveShadow(...)`。浅色保留克制柔和阴影；暗色收紧圆角半径与位移，主要用 `cardFill` / `elevatedFill` / `recessedFill` 明度差和 1pt `FizzTheme.stroke` 建立纵深。`fizzCard` 默认圆角改为 `FizzRadius.panel`。
- 圆角与阴影收敛：清理 `7 / 9 / 15 / 17 / 28` 等散落数值，统一到 Token；`AddProjectsSheet` 外框 28 → `FizzRadius.frame`（16），内部选中行 7 → `control`。全站硬编码 `.shadow(color: .black...)` 替换为 `fizzAdaptiveShadow(.subtle/.raised/.floating)`；当前源码只剩 `FizzAdaptiveShadowModifier` 内部的一次 `.shadow(`。
- 原生玻璃控件层：项目详情顶栏 6 个页签包进 `GlassEffectContainer(spacing: 2)` + `.glassEffect(.regular.interactive(), in: Capsule())`，保留 `.help(...)` 与 `accessibilityAddTraits(.isSelected)`；`⌘K` 面板外壳改为 `.glassEffect(.regular.tint(FizzTheme.elevatedFill.opacity(0.65)), in: RoundedRectangle(cornerRadius: FizzRadius.frame, style: .continuous))`，移除 `.thickMaterial` 与黑阴影；`CleanupTabView` 和 `SessionsTabView` 中只包裹哑光数据卡片的 `GlassEffectContainer` 已删除，Sessions 工具筛选等真正玻璃控件组保留。
- 按钮层级：全站 `.buttonStyle(.bordered)` → `.glass`，`.borderedProminent` → `.glassProminent` + `.tint(FizzTheme.accent)`；永久删除确认保留 `role: .destructive` + `.tint(.red)`。菜单按钮继续统一 `.menuStyle(.button)` + `.buttonStyle(.plain)` / `.glass`，无 `.menuStyle(.borderlessButton)`。
- UI-3/UI-4 收口：`WorkbenchMetrics.splitBytes` 在四舍五入达到 1000 且仍有更大单位时进位（`999_960 → 1 MB`、`999_999_999 → 1 GB`），`OverviewWorkbenchTests` 新增边界断言；`ProjectServicesPanel.devRow` 的「预览」仅在 `run.port > 0` 时出现；新的 `testRun.startedAt` 变化且测试日志存在/运行中时，`ProjectLogsPanel` 自动把 `source` 切到 `.test`，面板首次因测试运行出现时也默认 `.test`。
- 测试：新增 `FizzDesignSystemTests`（圆角/间距 Token、浅/暗阴影收敛断言）；C1 当轮 `swift test --package-path macos` 128/128 通过（C2 后总计 135 例）；`swift build --package-path macos --build-path <tmp> -Xswiftc -strict-concurrency=complete` 干净构建 0 warning / 0 error；`git diff --check` 通过；`rg` 核查无 `.menuStyle(.borderlessButton)`、无 `.buttonStyle(.bordered/.borderedProminent)`、无数字 `cornerRadius`、视图层无裸 `.shadow(`（仅保留 `FizzAdaptiveShadowModifier` 内部实现）。
- 隔离 GUI 验收：独立 bundle `com.a003.fizzdeck.c1audit` + 临时 `CFFIXED_USER_HOME`，fixture 项目真实执行 `npm run test`（3 passed），Logs 自动从 `dev` 切到 `test` 并显示输出；浅/暗截图统一前缀 `/tmp/fizzdeck-c1-`，含 home、home-batch、palette、detail、detail-test、settings、sheet 的 light/dark（home-batch 仅暗色）。真实 `~/.repodeck` 与 `/Applications/FizzDeck.app` 进程未触碰，验收后临时进程已退出、5199 端口无监听。
- 未直测：dev 启动/预览按钮的 `port = 0` 异常场景、永久删除红色确认弹窗、VoiceOver 顺序与低于 1000pt 最小窗口。C1 当轮未提交；C2/C3 已补测并统一本地提交。

### UI-1：语义化浅/暗双主题 Token 与外观设置（2026-11-26）

- `FizzTheme` 的 page / sidebar / card / 描边 / 选中填充全部改为 `Color(nsColor: NSColor(name: nil) { … })` 动态语义 Token：浅色保持原 Liquid Glass 层级，暗色使用低饱和炭黑（page `#111315`、sidebar `#16181A`、card `#1B1D20`、recessed `#131517`、elevated `#25282C`）；新增 `recessedFill`、`elevatedFill`。`FizzBackground` 在暗色下把 warmGlow/coolGlow 透明度降到 0.06。
- 新增 `AppAppearance`（system / light / dark）与 `AppearancePreferences`，UserDefaults key 为 `fizzdeck.appearance`，默认跟随系统；`FizzDeckApp` 与设置窗口用 `@AppStorage` 同步 `.preferredColorScheme`，AppDelegate 启动时应用 `NSApp.appearance`，不再写死 aqua / light。
- 设置通用页新增「外观」选择器，切换后立即作用于主窗口与设置窗口。
- 清理首页视图模式胶囊、会话工具胶囊、⌘K 面板、筛选 chip 和项目页 tab hover 的浅色硬编码；保留模态半透明遮罩与主题色按钮上的白字。
- 同步 README、README.zh-CN、macos/README 的双主题描述，移除“固定浅色”旧说明。
- 验证：`swift test --package-path macos` 105/105；`swift build --package-path macos -Xswiftc -strict-concurrency=complete` 0 warning；`git diff --check` 通过。当轮未做真实窗口截图，浅/暗双态截图已在 UI-2 验收中补齐。

### UI-2：双态悬浮圆角侧栏与项目品牌微图标（2026-11-26）

- UI-1 收口：`AddProjectsSheet` 的 `.regular.tint` 由 `.white.opacity(0.22)` 改为 `FizzTheme.elevatedFill.opacity(0.22)`，暗色模式弹窗不再泛白。
- 新增 `macos/Sources/FizzDeck/Views/ProjectBadgeIcon.swift`：`ProjectBadgeKind.resolve(stacks:kind:)` 为纯数据映射，优先级 Next.js → Nuxt → Svelte → Astro → Vue → React → Vite，再到 Swift → Flutter → Unity/Godot/Unreal → Go → Rust → Python → Docker → Cloudflare，最后按 `ProjectKind` 回退（macApp / flutter / game / cli / miniProgram / web / other）。徽章混用 SF Symbol 与单字母，颜色走系统语义色，暗色下自动提亮。
- `ProjectBadgeIcon(project:size:framed:)`：`framed == true` 用 `elevatedFill` 圆角底板 + 1px `stroke`，供星标瓷砖、折叠态置顶卡和后续项目 Header 使用；`framed == false` 为无底框轻量图标，供侧栏行、折叠态普通项目与首页卡片使用。
- `HomeDashboardView` 删除 `FolderBadge`，首页卡片与批量选择工具条统一改为 `ProjectBadgeIcon(framed: false)`。
- `SidebarView` 重写为悬浮圆角卡片：外留 9pt、radius 16、`FizzTheme.sidebar` 填充 + `FizzTheme.stroke` 描边；展开 236pt / 折叠 58pt，`@AppStorage("fizzdeck.sidebarCollapsed")` 持久化，切换动画走 `FizzMotion.resolved(reduceMotion, FizzMotion.standard)`。
- 展开态三段式：内凹搜索框（放大镜 + 「搜索」+ 等宽 ⌘K，触发 `store.toggleCommandPalette()`）；总览/有改动/可清理三行指标（运行中数量绿色、脏项目数等宽、可回收空间 `Format.bytes`）；星标 3 列瓷砖（右上 5pt 运行绿点）；下方「正在运行」按 `:port` 展示，再按工作区分组（标题行 `+` 调 `store.addRoot()`），行内只有品牌图标 + 名称；底部磁盘余量 + SettingsLink。
- 折叠态：圆角搜索按钮、总览/有改动/可清理三个图标按钮（状态绿点 + `.help` + `accessibilityLabel`）、星标 36×36 图标卡、普通项目无底框小图标、底部设置齿轮。右键菜单、tooltip、`accessibilityLabel` 与 selected trait 全部保留。
- `ContentView` 移除 `NavigationSplitView`，改为 `FizzBackground` + `HStack(悬浮侧栏, 详情)`；工具栏在红黄绿旁新增 `sidebar.left` 折叠按钮（含 tooltip / accessibilityLabel）；`FizzDeckApp` 用 `CommandGroup(replacing: .sidebar)` 提供“显示/隐藏侧栏”（⌘⌃S）。⌘K、⌘0、⌘R、⌘⇧T、⌘, 与 `WindowFrameGuard` 行为不变。
- 新增 `ProjectBadgeIconTests` 9 例：框架优先级、Vite 单栈、SwiftUI/macApp、Flutter、游戏引擎、语言、基础设施、CLI/kind 回退、每个 kind 都有字形。
- 验证：`swift test --package-path macos` 114/114；`swift build --package-path macos -Xswiftc -strict-concurrency=complete` 干净构建 0 warning；`git diff --check` 通过；`rg` 无 `.menuStyle(.borderlessButton)`、无 `FolderBadge`、无新增纯白/纯黑背景（仅保留模态遮罩与主题色按钮白字）。
- 隔离 GUI 验收：独立 bundle `com.a003.fizzdeck.ui2audit` + 临时 `CFFIXED_USER_HOME`，浅色/暗色 × 展开/折叠四套截图确认悬浮卡片、236/58 双态、星标瓷砖、`:5199` 运行行、品牌图标与暗色对比度正常；未触碰真实 `~/.repodeck` 与用户正在运行的 FizzDeck。
- 未直测：右键菜单各项真实点击、纯键盘全路径、VoiceOver 顺序；低于 1000pt 最小窗口下的折叠态未单独截图。

### UI-3：紧凑自适应项目 Header 与封面缩略图（2026-11-26）

- `ProjectHero` 移除 300pt 全幅封面、`0.88` 黑色渐变叠底与 `fallbackArtwork`，改为 `.fizzCard(radius: 18)` 紧凑 Header：42pt `ProjectBadgeIcon(framed: true)` + 20pt 项目名（运行绿点）+ 11pt 等宽路径复制 + 分组 / 分支 / 改动 / 最近 AI 工具 / test 标签；右侧独立列放 `ProjectHeroActions` 与 `SessionContinueButton(.prominent)`，窄窗口只压缩标题，不裁切按钮。外层 `24pt` 横向、`8pt` 顶部留白，内边距 17pt，高度由内容决定（未写死）。
- `SessionContinueButton.prominentControls` 反馈条由黑底白字改为 `FizzTheme.elevatedFill` + `FizzTheme.stroke` 1pt + `.primary`，前置橙色警告图标；“复制命令”“自动化设置”按钮保留。
- 方案 A：`OverviewTabView.projectSummaryPanel` 在 `project.artwork != nil` 时展示 176×99（16:9）、圆角 10 的封面缩略图，占位底 `FizzTheme.recessedFill` + `FizzTheme.stroke`；`.task(id: path)` 在 `Task.detached(priority: .utility)` 读取 `Data`，回主线程解码 `NSImage`（避免 NSImage 跨 actor），读取前后检查取消；无封面时完全不渲染、不占位，点击调用 `SystemActions.open`。

### UI-4：总览工作台：微柱 KPI + Services + 内嵌 Logs（2026-11-26）

- 新增 `Support/OverviewWorkbench.swift` 纯函数：7 天窗口按日对齐、`SessionRecord` 按日聚合、微柱归一化与峰值强调、清理项占比、字节数值/单位拆分、日志尾部读取（最多 16 KB、UTF-8 边界修剪、最后 40 行）。
- 顶部 KPI 改为自适应网格（最小 205pt）：本周提交（大数字 `次` + 近 7 日提交柱 + branch 底注）、磁盘占用（拆分数值与 KB/MB/GB 单位 + 清理项占比柱 + 可清理大小/目录数）、AI 会话（会话数 + 近 7 日会话柱 + 完整 `aiDetail`）、最近活动；移除独立 `weeklyPanel` 与旧 `WeeklyBars`，预览端口收敛到 Services。
- 新增 `Views/ProjectServicesPanel.swift`：`Services` 面板展示 dev/test 两行真实命令与状态；dev 运行态绿点、`:port`、预览/停止，未运行启动；test 显示运行中/通过/失败 + 耗时与运行/停止；启动/停止中用 mini `ProgressView` 并禁用对应动作；底部单行反馈来自 `actions.messages` / `testMessages`。
- `ProjectDetailView` 的总览页不再挂 `ProjectActionDock`（仅测试页且存在 test 命令时保留），避免浮条与 Services 重复并遮挡 Logs。
- 新增内嵌 `Logs` 面板：dev/test 日志存在或运行中时展示；双日志提供 dev/test 切换、折叠、打开完整日志；视口 `recessedFill` + `stroke` + radius 10，11pt 等宽、210pt 高、支持文本选择并自动滚到底部。运行中（或启动/停止中）每 1.2 秒异步刷新，折叠/切项目/切页/销毁自动取消；test 有内存输出时优先读内存。
- 保留备注编辑、200 字计数、最近活动时间线；顺序为 项目摘要 → KPI → Services → Logs → 备注 → 最近活动。
- 新增 `OverviewWorkbenchTests` 10 例：7 天日期对齐、会话按日聚合、全 0/单峰归一化、峰值强调、清理柱补齐、字节拆分、日志缺失/空文件/40 行截断/16 KB 截断/多字节 UTF-8 边界。
- 验证：`swift test --package-path macos` 124/124；`swift build --package-path macos -Xswiftc -strict-concurrency=complete` 干净构建 0 warning；`git diff --check` 通过；`rg` 无 `.menuStyle(.borderlessButton)`、无新增硬编码浅/暗背景。
- 隔离 GUI 验收：独立 bundle `com.a003.fizzdeck.ui3audit` + 独立 home，真实启动 5199 静态服务、真实执行 `npm run test`（通过 0.2–0.5s）；浅/暗截图保存在 `/tmp/fizzdeck-ui3-light-atlas.png`、`/tmp/fizzdeck-ui3-dark-atlas.png`、`/tmp/fizzdeck-ui3-dark-services-test.png`、`/tmp/fizzdeck-ui3-light-rust.png`，覆盖有/无封面、Services 运行态、test 通过、Logs 展开/折叠与来源切换；未触碰真实 `~/.repodeck` 与用户正在运行的 FizzDeck。
- 未直测：1000pt 极限宽度逐像素、VoiceOver 顺序、超长日志持续滚动帧率、test 失败态截图。

### 阶段 4：质量与性能收口（2026-11-26）

- 修复首页批量选择清理：`HomeDashboardView` 重新监听 `visibleProjects.map(\.path)`，应用分组/颜色/工具筛选后不会残留不可见项目的选择；切换首页分类仍会清空选择。
- 修复 Git 监听精确性：`WorkspaceWatcher` 现在检查 FSEvents 事件路径，只接受当前项目 `.git/HEAD` 与 `.git/index`；`.git/config`、`packed-refs` 等不触发 `refreshGit`。新增真实 FSEvents 测试：写 `config` 不触发，写 `index` 仍触发。
- 修复 FSEvents context 生命周期：删除回调里多余的 `release()`，避免 `stop()`/切换项目时对 sink 过度释放导致崩溃；8 例监听测试全部通过。
- 修复扫描取消：`ProjectDiscovery.discoverStreaming` 的 `Task.detached` 现在通过 `withTaskCancellationHandler` 传递取消，取消后约 28ms 返回，不再在后台继续遍历。
- 性能基线（本机 macOS 27.2，Apple Silicon，debug 测试构建）：50 个项目扫描冷启动 `18.2–18.5ms`、`scan-cache.json` 热读 `1.1–1.2ms`；50 个项目会话索引冷启动 `21.8–22.9ms`、热启动 `2.1–2.2ms`、单文件失效刷新 `2.7–2.9ms`；150 个项目 × 20 轮排序 `8.0–8.4ms`；扫描取消响应 `25–30ms`。数据由 `PerformanceBaselineTests` 输出，未使用 Instruments。
- 可访问性：`FirstRunScanView` 的扫描目录行补充标签/勾选值/提示，扫描状态使用组合描述，“一键开始扫描”为默认动作，“取消扫描/返回重选目录”绑定 Esc；`ScanReportView` 的筛选 chip 补选中状态，候选行和复选框补标签/值/提示；`SessionContinueButton` 与 `SessionsTabView` 的继续/菜单/复制/结束按钮补标签和提示。
- 长列表检查：`HomeDashboardView`、`SessionsTabView`、`ScanReportView` 的 `body` 内没有 `FileManager` I/O；首页筛选/排序为纯内存计算，150 项基线仍在 60fps 预算内。
- 验证：`swift test --package-path macos` 96/96；`swift build --package-path macos --build-path /tmp/fizzdeck-clean-build` 与干净 test 构建均 0 warning；额外以 `-Xswiftc -strict-concurrency=complete` 构建源码和测试，均 0 warning；`git diff --check` 通过；`rg` 无 `.menuStyle(.borderlessButton)`、无调试 `print`、无新增个人路径。
- 隔离 GUI 验收：独立 bundle `com.a003.fizzdeck.stage4` + 临时 `CFFIXED_USER_HOME` 启动 8 秒，未触碰真实 `~/.repodeck` 和用户正在运行的 `FizzDeck.app`；`scan-cache.json` / `session-cache.json` 正常生成并命中会话 fixture，无错误日志，退出后无残留进程。菜单栏截图显示 `(!) 2`，与两个脏项目的首页待处理队列一致。
- 未直测：真实 Terminal 自动化权限弹窗、已有 tab 聚焦与 `-1743` 降级；菜单栏 60 秒静默到期（等待期间屏幕锁定，无法继续截取）；通知 banner 点击回跳；VoiceOver 顺序与 Instruments 长列表帧率；Gemini / Cursor / Trae / Windsurf 真实本机样本。

### P1-A：终端适配层与继续偏好（2026-11-26）

- 新增 `TerminalLauncher.swift`：`terminal` / `iterm2` / `ghostty` / `warp` 四种终端，按 Bundle ID + 应用路径检测已安装项，偏好写入 `UserDefaults`，未安装时回退 Terminal。
- Terminal 复用按 TTY 精确聚焦和 `-1743` 降级；iTerm2 按 TTY 聚焦 session，启动时优先新建 tab；Ghostty 用 AppleScript `new window with configuration` 打开项目目录并执行启动脚本；Warp 只打开项目目录。
- Ghostty / Warp 运行中不假装支持标签定位，统一降级为激活应用 + 提示。Warp 没有命令执行接口，继续时返回可复制的恢复命令。
- 设置页新增“默认终端”“Codex 默认继续方式（自动 / 优先 CLI / 优先 Codex Desktop）”“自动化权限”三项；自动化状态记录最近一次 AppleScript 结果，不冒充实时 TCC 状态。
- `SystemActions.openTerminal` 与 `SessionResumeService` 统一走 `TerminalLauncher`；启动脚本写入 `~/.repodeck/launchers`，创建前清理超过 24 小时且匹配 `resume-*.command` 的旧脚本。
- 移除 `SessionContinueButton` 和 `AttentionQueueView` 中已废弃的 `.menuStyle(.borderlessButton)`。
- 验证：`swift test --package-path macos` 77/77、`swift build --package-path macos`、`git diff --check` 通过。新增 11 例覆盖四种终端脚本/URL 生成与转义、终端检测回退、24 小时清理和偏好读写。
- 本机检测到 Terminal 与 Ghostty；生成的 Terminal 启动/聚焦、Ghostty 启动 AppleScript 均通过 `osacompile` 语法检查。iTerm2 未安装，只验证了脚本生成与转义；未实际点击“继续”以免触发自动化权限弹窗和真实进程。

### P2-B：轻量后台文件监听（2026-11-26）

- 新增 `WorkspaceWatcher.swift`：会话根目录（`~/.codex/sessions`、`~/.claude/projects`、`~/.grok/sessions`、`~/.gemini/tmp`）使用 FSEvents 递归监听；当前项目 `.git` 目录单独监听。监听只触发 `SessionIndex.build()` 增量刷新或 `store.refreshGit(for:)`，不触发 `du`、Git 全量扫描或项目重排。
- 防抖 2 秒；`WorkspaceDebouncer` 合并短时间内的 sessions/git 事件，只回调一次。事件里不改 `recent`、不重排 `projects`，首页卡片不会因监听跳动。
- `ProjectDetailView` 进入时把当前项目路径交给 watcher，离开时清除；切换项目只重建 `.git` 监听，不碰其他项目源码树。
- 前后台：`didResignActive` 暂停所有流，`didBecomeActive` 重建并合并执行一次增量刷新；后台启动的进程在首次激活前保持监听，避免“从未激活 → 永远暂停”。新增 15 秒轻量检查，仅用 `stat` 处理首次出现的新会话目录。
- 资源释放：`stop()` 取消防抖、计时器、观察者并释放 FSEvents 流；FSEvents context 使用配对 retain/release，回调只保留弱引用，流释放后不会访问已释放 watcher。
- 验证：新增 7 例监听单测（防抖合并、取消、生命周期、`.git/HEAD` 变更、会话目录写入、git 路径匹配）；`swift test` 90/90、`swift build`、`git diff --check` 通过。隔离 `CFFIXED_USER_HOME` + `LSEnvironment` 前台启动验收：新增 Gemini 会话文件后 6 秒内 `session-cache.json` 自动包含 `watch-gemini`，无需手动重扫。

### P2-A：Gemini CLI 与 IDE 工作区会话适配（2026-11-26）

- `SessionIndex.swift` 新增 Gemini 读取：按官方 `~/.gemini/tmp/<projectSlug>/chats/*.jsonl` 结构解析首条 metadata（`sessionId` / `startTime` / `directories`），cwd 优先取 `~/.gemini/projects.json` 的绝对路径映射，回退 `.project_root`；最近用户消息跳过 `<...>` 上下文和 `/` 斜杠命令；`tokens.input/output/cached/thoughts/total` 与 `model` 进入现有用量展示，因价目表无 Gemini 价格，费用保持 `nil`。
- Gemini 恢复命令为 `gemini --resume <sessionId>`；CLI 可用时走 `TerminalLauncher`，不可用时提示安装并保留 `cd '<cwd>' && gemini --resume <id>` 复制兜底；进程匹配支持 `--resume <id>`、`-r <id>`、`--resume=<id>`，不把 `--session-id` 当恢复。
- IDE 工作区摘要：只读读取 `~/Library/Application Support/{Cursor,Trae,Windsurf}/User/workspaceStorage/*/workspace.json`，生成 `kind = workspaceSummary` 的会话记录；`state.vscdb` 以 `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX` + `sqlite3_busy_timeout(120ms)` 打开，仅查 `ItemTable` 已知键，损坏、被占用或 schema 变化时静默降级为工作区标题，不崩溃、不阻塞扫描。
- IDE 记录不生成 `resumeCommand`；`SessionContinueButton` 的菜单新增“在 Cursor / Trae / Windsurf 中打开项目”，复用 `SystemActions.open(_:in:)`，只对本机已安装且项目有该工具痕迹的 IDE 显示；只有 IDE 痕迹、没有可恢复 CLI 会话时按钮显示“打开 <IDE>”。
- `ProjectEditor` 新增 Trae / Windsurf 的 bundle ID 与 `/Applications` 回退路径；`SessionsTabView` 的筛选从固定枚举改为按当前项目实际出现的工具动态渲染，切换项目重置为“全部”。
- `session-cache.json` 版本升到 3；Gemini chat 与 IDE 工作区都按 `mtime + fileSize` 增量缓存，IDE 缓存键为 `ide:<tool>:<workspaceHash>`，最多扫描每个 IDE 300 个工作区。轻量 cwd 索引只读 `workspace.json`，不碰 SQLite。
- 验证：新增 3 例 Gemini/IDE fixture（含真实 SQLite `ItemTable` 与损坏数据库降级）、1 例 Gemini 进程匹配、1 例 Gemini 工具证据、2 例 IDE 编辑器元数据；`swift test` 84/84、`swift build`、`git diff --check` 通过。隔离 `CFFIXED_USER_HOME` 启动验收生成了 Gemini 会话与 Cursor 工作区记录，应用运行 10 秒无崩溃。
- 本机未安装标准 Gemini CLI，也没有 Cursor / Trae / Windsurf 的 workspaceStorage；Gemini schema 来自官方仓库格式，IDE 结构来自 VS Code 系真实目录格式，均未在本机真实样本上直测。

### P0-A：首次启动发现、快扫/补全与缓存

- 移除个人目录、项目名和端口硬编码；`roots.json` 缺失时进入首次扫描，不再自动写入个人路径。
- 新增范围勾选、流式发现、权限拒绝恢复、工具/类型 chip 与分组选择；扫描取消不写 `roots.json`。
- 新增确定性项目类型识别（网页、macOS、小程序、Flutter、游戏、CLI、其他）和工具证据识别（Codex、Claude、Grok、Cursor、Trae、Windsurf、Gemini CLI）。
- 首屏读取 `scan-cache.json`，随后依次补全 Git、会话和目录体积；`du` 并发受限，并复用 `CleanupScanner` 已算体积。
- 新增 `session-cache.json`，按 `mtime` / `fileSize` 增量解析会话。

### P0-B：一键回到现场

- 新增运行中会话检测、TTY/cwd 匹配、Terminal 聚焦和“继续”按钮；多选时隐藏。
- 未运行时按工具能力路由到一次性 `.command` 启动脚本或桌面端 URL；失败时保留 `cd '<cwd>' && <cmd>` 复制兜底。
- 结束会话仍只终止明确带 `session.id` 的 CLI 进程，不碰 `codex app-server`。

### 会话用量与 Grok

- 新增 `PricingCatalog`，只对已知模型估算费用；未知模型只显示 token，不编造价格。
- 解析 Codex `token_count` / `turn_context.model`、Claude `message.usage` / `cost-state`、Grok `updates.jsonl` 的 `_meta.totalTokens`。
- 会话页新增 token/费用/模型展示；总览新增“最近活动”时间线。
- Grok 支持 `grok -r <id>` 恢复、CLI 进程匹配和 `~/.grok/sessions` 读取；Grok 桌面端不支持直达。

### 验证与限制

- 隔离 GUI 验收：用 `CFFIXED_USER_HOME` 指向临时目录，启动独立 bundle `com.a003.fizzdeck.acceptance`，未触碰真实 `~/.repodeck`，也未关闭用户正在运行的 `FizzDeck.app`。
- 首启默认只勾选 `~/Projects`；主目录、桌面/文稿/下载和外置卷默认不选。扫描报告正确显示 Codex/Grok 工具、网页/Mac 应用类型和项目多选。
- 加入 2 个临时项目后，缓存重开直接进入总览；“跳过，稍后添加”进入空状态并写入 `onboarding.json`（`skipped: true`）；空状态可重新打开扫描视图。
- Codex 会话显示 1.6K tokens、`~<$0.01` 估算和 `gpt-5.1`；Grok 显示 2.3K tokens、未知模型不显示价格；过滤、复制恢复命令、运行中徽章、结束会话和 10 秒进程轮询均已实测。
- 验收中发现并修复：Grok 会话目录未被工具索引识别；结束会话后“仍在退出”提示不会随进程消失而清除；小于 1 KB 的目录显示为 `0 KB`。
- `swift test --package-path macos`：66/66 通过。
- `swift build --package-path macos -c release`：通过。
- `git diff --check`：通过。
- 未点击真实 Terminal 启动（会触发 macOS 自动化权限弹窗）；真实 Grok 桌面端不支持直达；未提交、未发版。

## 项目是什么

FizzDeck 是一个本地优先的 macOS 项目管理器。原生版是主入口，纯 SwiftUI，不需要 Node.js；网页版保留在 `src/` 和 `server.mjs`，两者共用 `~/.repodeck` 本地状态。

用户已确认的方向：

- 原生 macOS 是主推版本，网页版是快速方案。
- 左侧导航保持清爽，信息尽量少。
- 支持浅色与低饱和炭黑暗色双模式，不做吉祥物。
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
- 覆盖会话排序分组、cwd 规范化、恢复命令和跨分块反向扫描；已补充分组、删除、Git 错误路径、通知路由、项目发现、Grok/Gemini/IDE 会话、进程匹配、工具索引、token 费用、终端脚本、后台监听、50 项目扫描/会话缓存、取消响应、项目品牌徽章映射、7 天 KPI/会话聚合、字节拆分与日志尾部安全读取测试、设计 Token、浅/暗阴影收敛、日志来源决策与端口徽章语义、命令面板高度、小于 1 KB 字节格式、双主题 SVG 加载与浅色背景光晕，当前共 142 例。

相关文件：

- `macos/Package.swift`
- `macos/Tests/FizzDeckTests/ProjectAttentionQueueTests.swift`
- `macos/Tests/FizzDeckTests/GitServiceTests.swift`
- `macos/Tests/FizzDeckTests/ProjectEditorTests.swift`
- `macos/Tests/FizzDeckTests/SessionIndexTests.swift`

### 4. AI 会话管理

- 会话页展示当前项目匹配到的全部会话，按修改时间倒序、同一时间按稳定 ID 排序。
- 会话过滤改为按当前项目实际出现的工具动态生成“全部 / Codex / Claude / Grok / Gemini / IDE”原生玻璃分段；无匹配时显示对应空态，切换项目会重置过滤。
- 每行显示工具、相对时间、最后一条用户需求、token/费用（可用时）和可复制的 `codex resume` / `claude --resume` / `grok -r` / `gemini --resume` 命令；IDE 工作区摘要不显示恢复命令，只提供“在 IDE 中打开项目”。
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

- v0.7.4：`https://github.com/CClishan/Fizzdeck/releases/tag/v0.7.4`（Latest）
- v0.7.4 安装包：`FizzDeck-0.7.4-arm64.dmg`，5,982,222 bytes，Apple Silicon，ad-hoc 签名，未公证；asset ID `799518355`
- v0.7.4 校验文件：`FizzDeck-0.7.4-arm64.dmg.sha256`，91 bytes；asset ID `799518339`
- v0.7.4 SHA-256：`bf91a21fefc4524b59af1c437e687a5251d1aef08cc487142825c61f5b077931`
- v0.7.4 校验：`swift test` 252/252、`swift build` 0 warning、`codesign --verify --deep --strict`、`hdiutil verify` 通过
- v0.7.4 发布提交：`fbbc21f Release FizzDeck 0.7.4 with vibe-coder workflows`；tag object `6127b3e`
- v0.7.4 线上验收：`releases/latest` 指向 v0.7.4；重新下载 DMG 的 GitHub digest 与 `.sha256` 一致，`hdiutil verify` 通过
- v0.3.0：`https://github.com/CClishan/Fizzdeck/releases/tag/v0.3.0`（Release ID `459028876`，DMG asset ID `794574637`，Latest）
- v0.3.0 安装包：`FizzDeck-0.3.0-arm64.dmg`，3,143,502 bytes，Apple Silicon，ad-hoc 签名，未公证
- v0.3.0 SHA-256：`6db40472c6cbf16844d11af1ec1a5af564a854560eab66f68f8156b6567d7eb6`
- v0.3.0 源码提交：`d9610c9 Merge pull request #2 from CClishan/feat/macos-ui2-and-sessions` + `4f1cea6 Release FizzDeck 0.3.0`
- v0.3.0 校验：`codesign --verify --deep --strict`、`hdiutil verify`、`swift test`（142/142）与 GitHub Release digest 一致性校验全部通过；`koroo.top/fizzdeck` landing 本次未改
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

- 当前发布分支是 `main`；`v0.7.4` 已推送并发布为 GitHub Latest。
- `~/.repodeck` 的 `roots.json`、`state.json` 未因打包或 GUI 验收改动。
- 当前运行中或本机安装目录 `/Applications/FizzDeck.app` 未在本次发版中被改动，仍可能为旧版本。
- 最新可分发包是 `macos/dist/FizzDeck-0.7.4-arm64.dmg`；`.app` 已按 ad-hoc 方式签名并通过校验（本机钥匙串无 Developer ID 证书，未公证）。
- `src/landing/i18n.js` 与静态官网已指向 `v0.7.4`；`releases/latest` 已指向 v0.7.4，外部部署仍需单独执行。
- 不要回滚 `server.mjs`、`vite.config.js`、`public/`、`landing.html`、`src/landing/`、`src/stageshow/` 的已发布内容；需要修改时单独开任务。

## 待增加能力（移交清单）

### 发布与交付

- [x] `v0.7.4` GitHub Release：`main` 与 tag 已推送，DMG 与 `.sha256` 已上传，`releases/latest` 与下载哈希已复核。
- [ ] 应用内更新：分别从 `v0.5.3` 和 `v0.7.3` 实机更新到 `v0.7.4`，核对版本、Build、SHA-256、项目状态与重启行为。
- [ ] 正式签名与公证：提供 Developer ID 与 `NOTARY_PROFILE` 后运行 `./macos/script/package_dmg.sh --notarize`，并在干净 Mac 上安装验收。
- [ ] 旧域名收敛：把 `https://fizzdeck.pages.dev` 301 到 `https://koroo.top/fizzdeck`，保留 Cloudflare Pages 项目作为回滚。验收：旧路径 301、canonical/OG 不重复、静态资源不丢。
- [x] 文档同步：README、`README.zh-CN.md`、`macos/README.md`、官网与发布 Checklist 已对齐 `v0.7.4`。

### P1（收尾）

- [x] 命令面板增强：最近项目、最近动作、模糊匹配、置顶命令，以及“打开远程仓库 / 复制远端地址”。相关文件：`CommandPaletteView.swift`、`RepositoryStore.swift`、`GitService.swift`。验收：`⌘K` 可搜项目、分支、远端 URL 和动作；无远端时明确不可用；上下键、回车、Esc 不回归。
- [x] 远程仓库动作：从项目读取 `origin`，支持浏览器打开和复制 URL，不发起网络写操作。相关文件：`GitService.swift`、`ProjectDetailView.swift`。验收：有/无 origin、SSH/HTTPS 两种 URL 都正确。
- [ ] Git 真实错误路径（本地可模拟部分已完成）：已用本地 HTTP 401、SSH 公钥拒绝和关闭端口覆盖凭据/网络失败，7 个测试通过；真实 GitHub 凭据失效尚未在用户仓库触发。相关文件：`GitSyncService.swift`、`GitTabView.swift`、`AttentionQueueView.swift`。验收：命令不挂起，`GIT_TERMINAL_PROMPT=0` 生效，错误就地回显，工作区不变。
- [ ] 菜单栏与通知直测：全屏截图确认菜单栏显示待处理数字 `23`，与首页队列一致；通知点击回项目的路由代码和解析测试已完成，真实 banner 点击与 60 秒静默到期尚未直测。相关文件：`MenuBarView.swift`、`LocalNotifications.swift`、`FizzDeckApp.swift`、`AppRouting.swift`。验收：系统菜单栏可读、到期刷新、banner/click 路径有记录。

### P2（产品能力）

- [x] 原生删除项目：对齐网页版的备份、移入废纸篓、浅路径保护、目录名确认和测试运行时拦截。相关文件：`RepositoryStore.swift`、`ProjectDetailView.swift`、`ProjectRemovalService.swift`。验收：不自动永久删除；失败不改变目录；备份可恢复；6 例单测和确认框已验收。
- [x] 批量操作：批量重扫、批量复制清理命令、按组筛选。相关文件：`HomeDashboardView.swift`、`RepositoryStore.swift`、`RepositoryScanner.swift`。验收：选择态清晰、部分失败可回显、无误触破坏性操作；目录存在性预检和数量回显已实现。
- [x] 编辑器覆盖：JetBrains 系列、Antigravity、嵌套 Xcode 工程。相关文件：`SystemActions.swift`、`CommandPaletteView.swift`、`Components.swift`。验收：安装/未安装、工程/普通目录分别显示正确；本机已验证 Xcode 与 Antigravity，JetBrains 映射待安装后直测。
- [x] 测试基线：新增 Swift test target，覆盖 `ProjectAttentionQueue` 排序和 `GitService` ahead/behind 解析。相关文件：`macos/Package.swift`、`macos/Tests/`。验收：`swift test` 可独立运行，当前 142 例通过。
- [x] AI 会话管理：会话列表、按工具过滤、恢复命令和精确 CLI 进程结束已完成；Desktop app-server 永不终止。相关文件：`SessionIndex.swift`、`SessionProcessService.swift`、`SessionsTabView.swift`。验收：Codex/Claude/Grok 会话、无会话空态、复制命令正确；结束只在明确匹配时出现。

### 质量与性能

- [ ] 长列表 60fps：150 项排序/筛选基线已记录，I/O 已排除；真实滚动帧率仍需 Instruments 实测。
- [ ] 可访问性：标签、提示、选中状态、默认/取消快捷键和减少动态效果已补代码；VoiceOver 顺序和纯键盘全路径仍未直测。
- [x] 大目录扫描：50 个项目扫描冷启动 `18.2–18.5ms`、缓存热读 `1.1–1.2ms`、单文件会话缓存失效 `2.7–2.9ms`、取消响应 `25–30ms`；数据来自 `PerformanceBaselineTests`，未用 Instruments。
- [x] 真实项目回归：用 `repo-dashboard` 脏工作区、`video-tem` 无 upstream、`shipany-template-two` 268 项改动核对了改动列表、概览与测试底栏；只读，没有同步或删除。

### 建议接手顺序

1. 先跑基线：`swift build --package-path macos`、`swift test --package-path macos`。`./macos/script/build_and_run.sh --verify` 会先杀掉同名 app；用户正在用 FizzDeck 时改用独立 bundle + `CFFIXED_USER_HOME` 验收。
2. 首启/缓存/Grok/token/进程结束已验收；下一步补真实 Terminal 启动（会触发自动化权限）、真实凭据失效/网络中断和菜单栏/通知直测。
3. P2 已完成；删除只可用临时目录验证，不要对真实项目点击确认。
4. `v0.2.3` 已发布；下一版再做 Developer ID 签名、公证和自动更新，旧域名 301 仍需单独确认。

### 不做

- 不做高饱和暗色主题；暗色只用低饱和炭黑层级，支持浅色与暗色双模式。
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
