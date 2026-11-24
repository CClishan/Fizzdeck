# FizzDeck

**本地优先的 macOS 项目看板。** 扫描指定目录、识别工程、查看 Git 与磁盘状态、恢复 AI 编程会话，并从一个界面启动开发服务。

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
| 项目发现 | 扫描受管目录中的 `.git`、`package.json`、`pom.xml`、`go.mod` 等工程标记，跳过 `node_modules`、`Library`、`dist`、`build` 等生成目录。 |
| 总览首页 | 原生总览支持收藏、有改动、正在运行、可折叠项目组，以及卡片、列表、画廊三种布局。 |
| 待处理队列 | 首页汇总测试失败、落后远端、未推送提交、未提交文件与可回收空间，按紧急程度排序；行内可直接推送、fast-forward 拉取、重跑测试或复制清理命令；右键行可稍后或忽略该项目的此类提醒，标题栏可恢复。 |
| 菜单栏 | 常驻显示待处理数量，可快速打开总览或最近项目；开发服务就绪或测试失败时发送本地通知。 |
| 快速打开 | `⌘K` 搜索项目、分支与动作，键盘即可执行项目命令和全局操作。 |
| 项目快捷动作 | 在 Finder、Terminal 或已安装的编辑器中打开项目（Cursor、VS Code、Zed；有工程目标时支持 Xcode），也可复制路径。`⌘⇧T` 在当前项目中打开 Terminal。 |
| AI 会话 | 读取本机 Codex 与 Claude Code 会话信息，匹配到项目后复制 `codex resume` / `claude --resume` 命令。 |
| Git | 展示当前分支、领先/落后远端状态、未提交文件与最近提交；支持切换分支，以及带确认的 fetch、fast-forward 拉取与推送，结果就地回显，脏工作区有保护。 |
| 开发服务 | 识别常见 dev 脚本与端口，启动/停止项目进程，等待端口就绪并打开浏览器。 |
| 磁盘占用 | 拆解项目体积与可清理空间，覆盖依赖、构建缓存、构建产物、临时文件和 AI 会话历史。 |
| 清理建议 | 只生成并复制清理命令，不自动执行破坏性操作。 |
| 文档 | 自动发现并阅读 `README`、`PRODUCT`、`HANDOFF`、`AGENTS` 等文档。 |
| 测试 | 识别 `test`、`check`、`typecheck`、`mvn test`、`go test`，后台执行并回显输出与耗时。 |
| 项目组织 | 星标、颜色标签、备注、展示别名与分组技术栈标记。 |
| 安全移除 | 网页版支持仅移出看板、移到废纸篓、永久删除，包含备份与目录名确认。 |

## 本地数据与隐私

FizzDeck 不上传项目数据，也不连接 FizzDeck 托管服务。由 FizzDeck 启动的开发命令仍可能自行访问网络。

共享数据目录是 `~/.repodeck`，沿用旧路径以兼容已有安装。

```text
~/.repodeck/
├── roots.json        # 受管目录与展示别名
├── state.json        # 星标、标签、备注与界面状态
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

- 原生版要求 macOS 26+，目前从源码构建，未签名、未公证。
- 原生版专注浏览与日常项目操作；破坏性删除目前仍在网页版完成。
- 原生界面固定浅色，不做暗色主题。
- 暂不提供后台文件监听。
- 本地通知需要系统授权。`--sign-local` 的 ad-hoc 签名足以在本地注册通知中心；正式分发仍需要 Developer ID 签名与公证。
- AI 会话目前支持 Codex 与 Claude Code。
- 端口识别是启发式的；特殊开发环境可在 `server.mjs` 中补充映射。
- 首次扫描需要统计目录体积，大目录通常耗时数秒；之后读取缓存，重新扫描时再更新。

## 状态

FizzDeck 是自用的源码优先 macOS 工具。原生版与网页版共用数据目录，切换客户端不需要导出或迁移。
