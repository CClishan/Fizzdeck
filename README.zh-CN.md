# FizzDeck

**本地优先的 macOS 项目看板。** 扫描指定目录、识别工程、查看 Git 与磁盘状态、恢复 AI 编程会话，并从一个界面启动开发服务。

线上 landing：[koroo.top/fizzdeck](https://koroo.top/fizzdeck)

下载：[FizzDeck 0.5.0 macOS 版](https://github.com/CClishan/Fizzdeck/releases/latest)，Apple Silicon、macOS 26+，ad-hoc 签名，未公证。

不需要账号，不上传遥测，也没有托管后端。FizzDeck 只读取本机项目元数据，状态保存在本机。

[English](README.md)

## 原生优先

FizzDeck 有两个入口，共用同一份本地状态：

| 界面 | 说明 |
|---|---|
| **macOS 原生版**（`macos/`） | 主入口。纯 SwiftUI，不依赖 Node.js 或 HTTP 服务。 |
| **本地网页版** | 单 Node.js 进程 + React/Vite SPA，适合浏览器操作和带保护机制的删除流程。 |

网页版仍是快速方案；日常浏览、检查和启动项目，优先使用原生版。

## 环境要求

### 原生版

- macOS 26 或更高版本
- Xcode 26 或更高版本，Swift 6 工具链

### 网页版

- 较新的 Node.js（建议 Node.js 22+）

## 快速开始

### 原生 macOS 版

首次在这台机器上构建 Xcode 项目时，先同意许可：

```sh
sudo xcodebuild -license accept
```

构建、启动并检查进程：

```sh
./macos/script/build_and_run.sh --verify
```

运行 Swift 测试基线：

```sh
swift test --package-path macos
```

本地测试通知时，使用 ad-hoc 签名启动：

```sh
./macos/script/build_and_run.sh --sign-local
```

产物位于 `macos/dist/FizzDeck.app`。需要用 Xcode 调试时，直接打开 `macos/Package.swift`。

首次使用时，点击「添加项目目录」选择要管理的文件夹。

### 本地网页版

```sh
npm install
node start.mjs
```

浏览器会打开 `http://127.0.0.1:4770`。服务已运行时重复执行 `start.mjs` 只会打开页面。更换端口：

```sh
PORT=4800 node start.mjs
```

修改 `src/` 后重新构建网页资源：

```sh
npm run build
```

停止服务：

```sh
./stop.sh
```

首次使用时，在侧栏点击「扫描文件夹」发现并添加项目。

## 核心能力

| 模块 | 能力 |
|---|---|
| 项目发现 | 原生文件夹面板列出已加入目录，扫描所选父目录下的嵌套项目，识别 `.git`、`package.json`、`CLAUDE.md`、`AGENTS.md`、Xcode、Gradle、Cargo、Go、Python 等工程标记；跳过生成目录，并避免重复或父子项目重叠添加。 |
| 总览首页 | 原生总览支持收藏、有改动、正在运行、可折叠项目组，以及卡片、列表两种布局；待处理卡片半宽显示，四项汇总卡片并排在右侧。 |
| 项目分组 | 默认按路径关键词自动分类；右键项目可移动到已有分组或新建分组，也可随时恢复自动分类。 |
| 批量操作 | 可按项目分组筛选，在卡片或列表中多选项目，仅重扫所选目录或一次复制合并后的清理命令；批量操作不会删除文件。 |
| 待处理队列 | 首页汇总测试失败、落后远端、未推送提交、未提交文件与可回收空间，按紧急程度排序；行内可直接推送、fast-forward 拉取、重跑测试或复制清理命令；右键行可稍后或忽略该项目的此类提醒，标题栏可恢复。 |
| 菜单栏 | 常驻显示待处理数量，可快速打开总览或最近项目；开发服务就绪或测试失败时发送本地通知。 |
| 快速打开 | `⌘K` 搜索项目、分支、远程地址与动作；最近项优先，支持模糊匹配与置顶命令，键盘即可执行项目命令和全局操作。 |
| 项目快捷动作 | 在 Finder、默认终端（Terminal、iTerm2、Ghostty 或 Warp）或已安装的编辑器中打开项目（Cursor、VS Code、Zed、Antigravity、JetBrains 系列；支持顶层和嵌套 Xcode 工程），也可复制路径。`⌘⇧T` 在当前项目中打开默认终端。 |
| AI 会话 | 列出匹配项目的 Codex 与 Claude Code 会话，支持按工具过滤、查看最后一条需求、复制 `codex resume` / `claude --resume` 命令；确认后可结束精确匹配的 CLI 进程，不会终止 Codex Desktop 的共享 app-server。 |
| Git | 展示当前分支、领先/落后远端状态、未提交文件、最近提交与 `origin` 地址；支持在浏览器打开或复制远程地址、切换分支，以及带确认的 fetch、fast-forward 拉取与推送，结果就地回显，脏工作区有保护。 |
| 开发服务 | 识别常见 dev 脚本与端口；底部 Liquid Glass 悬浮操作区提供运行、测试、日志、预览和复制命令。 |
| 磁盘占用 | 拆解项目体积与可清理空间，覆盖依赖、构建缓存、构建产物、临时文件和 AI 会话历史。 |
| 清理建议 | 只生成并复制清理命令，不自动执行破坏性操作。 |
| 文档 | 自动发现并阅读 `README`、`PRODUCT`、`HANDOFF`、`AGENTS` 等文档。 |
| 测试 | 识别 `test`、`check`、`typecheck`、`mvn test`、`go test`，后台执行并回显输出与耗时。 |
| 项目组织 | 星标、颜色标签、备注、展示别名、分组技术栈标记，以及自动或手动项目分组。 |
| 安全移除 | 原生版和网页版都支持仅移出看板；移到废纸篓或永久删除会先备份到 `~/.repodeck/trash`，拦截过浅路径与运行中的服务/测试，并要求输入目录名。 |

## 本地数据与隐私

FizzDeck 不上传项目数据，也不连接 FizzDeck 托管服务。由 FizzDeck 启动的开发命令仍可能自行访问网络。

共享数据目录是 `~/.repodeck`，沿用旧路径以兼容已有安装。

```text
~/.repodeck/
├── roots.json        # 受管目录与展示别名
├── state.json        # 星标、标签、分组、备注与界面状态
├── roots-cache.json  # 扫描缓存
└── logs/             # 开发服务日志
```

### 网页版安全边界

- 只监听 `127.0.0.1`。
- 拒绝非本机 Origin。
- 启停操作只对受管目录生效。
- 清理命令只复制，不执行。
- 不把源码内容加载进看板。
- 永久删除会拦截过浅路径、测试运行中禁止删除、先备份到 `~/.repodeck/trash`，并要求输入目录名确认。

### 原生版边界

原生版刻意**不开启 App Sandbox**。它需要访问任意的用户自选项目目录，并执行项目脚本。请把它当作本地开发者工具：只加入可信目录，运行命令前先确认项目来源。

删除项目只接受受管目录，拒绝过浅或受保护路径；开发服务或测试运行中会直接拦截，并要求输入目录名。永久删除会先把项目复制到 `~/.repodeck/trash`。

## 项目结构

```text
macos/                  SwiftUI 原生应用
server.mjs              扫描、Git、体积、会话、进程控制与 HTTP 接口
src/                    网页版源码
src/components/ui/      内联 coss UI 组件
public/                 server.mjs 直接托管的 Vite 构建产物
start.mjs               网页版启动器
stop.sh                 网页版停止脚本
scan-clean.mjs          命令行版体积报告
```

## 当前限制

- 原生版要求 macOS 26+ 与 Apple Silicon；已提供 DMG，但使用 ad-hoc 签名，未公证。
- 原生版专注浏览与日常项目操作；支持批量重扫、复制清理命令，以及带备份和确认的删除。
- 原生界面支持浅色与低饱和炭黑暗色双模式，可跟随系统或手动切换。
- 提供轻量后台监听，只增量刷新 Git 与 AI 会话状态，不触发全量重扫。
- 本地通知需要系统授权。`--sign-local` 的 ad-hoc 签名足以在本地注册通知中心；正式分发仍需要 Developer ID 签名与公证。
- AI 会话支持 Codex、Claude Code 与 Grok；只能结束命令行中明确包含当前会话 ID 的 CLI 进程，Codex Desktop 的共享 app-server 需要在客户端内处理。
- 端口识别是启发式的；特殊开发环境可在 `server.mjs` 中补充映射。
- 首次扫描需要统计目录体积，大目录通常耗时数秒；之后读取缓存，重新扫描时再更新。

## 状态

FizzDeck 是自用的源码优先 macOS 工具。原生版与网页版共用数据目录，切换客户端不需要导出或迁移。
