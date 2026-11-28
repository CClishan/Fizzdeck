# FizzDeck

**给 Vibe Coder 的本地优先 macOS 项目工作台。**

用 AI 写项目，最怕三件事：上次做到哪忘了、改坏了回不去、原本能跑的环境又跑不起来。FizzDeck 把散落在本机的项目、AI 对话和运行环境收进一个原生窗口，用大白话帮你接着做。

线上主页：[koroo.top/fizzdeck](https://koroo.top/fizzdeck)

下载：[最新公开版](https://github.com/CClishan/Fizzdeck/releases/latest)，Apple Silicon、macOS 26+。

不需要账号，不上传遥测，也没有 FizzDeck 托管后端。项目元数据、会话索引和设置都留在本机。

[English](README.md)

**当前公开版：[v0.9.3（Build 26）](https://github.com/CClishan/Fizzdeck/releases/tag/v0.9.3)。** 界面可切换简体中文与 English；从菜单栏继续对话、复制接力卡，在标记过期前一键固定。项目库可自动生成光栅封面，单项目也能导出匿名光栅或 ASCII 战报。[发行说明与校验值](docs/releases/v0.9.3.md)。

下载按钮指向最新公开 DMG。默认临时签名包没有 Apple Team ID，不能依赖系统「快捷指令」执行动作；在 FizzDeck 内仍可打开项目、复制接力卡和查看体检。详见[签名与验收](docs/SYSTEM_INTEGRATION.md)。

## 先解决三个问题

### 记得住

- **人话模式默认开启**：把 Commit、Stash、Pull 等 Git 术语换成「存个版本」「先把改动收起来」「拿回云端的新内容」；熟悉 Git 后可切回专业术语。
- **跨项目「对话」时间线**：按天串起 Codex、Claude 等 AI 会话，直接看到每次想做什么、改了哪些文件、是否报错结束、花了多少。
- **中文可用的本地搜索**：SQLite FTS5 覆盖跨项目对话，1–2 个字会用短词回退；搜索框和 `⌘K` 都能直达对应对话节点。
- **纯剪贴板的「接力卡」**：把项目状态和最近对话整理成 Markdown，复制给任意 Agent 接手；不写项目文件，复制前统一脱敏。
- **跨 Agent 复盘**：看近 7、30、90 天或全部已索引历史，对比对话、AI 干活时长、估算费用和 Tokens；按项目看趋势、活跃天数和连续活跃，逐条查看日志支持的轮数和测试结果。可复制 Markdown，或复制默认隐藏项目名的浅色／暗色 PNG。AI 润色每次单独确认，只发送汇总数字。

### 回得去

- **AI 对话前自动留标记**：用临时 Git 对象记下当时的工作区，不移动分支、不写提交记录，也不会出现在 `git log` 里。
- **看改了什么，随时还原**：对比对话前后的差异，按文件恢复或整体回到对话前；对话后新建的文件默认只列出、不自动删除。
- **内联「存个版本」**：改完直接存成真正的 Git 版本，提交信息可按规则生成，也可用可选 AI 润色。
- **推送前密钥拦截**：检查 `.env` 是否被忽略，以及已跟踪文件里是否出现常见密钥格式；发现风险先拦下，再用大白话解释。

### 跑得起

- **侧栏「体检 Doctor」**：关注项目会自动盯运行状态、依赖、端口、密钥和版本保护；每个问题都尽量给一个能点的下一步。
- **闲置项目整理**：识别依赖、缓存和构建产物占用的空间，默认移到系统废纸篓，需要时还能放回或重新生成。
- **本机环境与 Git 身份**：内联检查 Node、Git、Agent CLI 状态；Git 用户名或邮箱没配，也能在应用里补上。
- **运行页先体检**：进入「运行」页先看阻碍启动的问题；缺依赖、端口冲突、`.env` 缺失等都能就地处理。
- **日志报错求助**：把报错解释成大白话，或生成可直接粘贴给 Agent 的求助 prompt，不必自己读懂整段堆栈。

### 可选 AI 总结（默认关闭）

- 支持 **Agent CLI（免 Key）**、**OpenAI 兼容 API（Key 存 macOS 钥匙串）**和**本地模型（Ollama / LM Studio）**。
- 只发送项目名、文件名、变动计数和脱敏后的一句话意图，不发送完整对话或源码。
- 用 Agent CLI 总结时会隔离工作目录，避免 FizzDeck 自己产生的会话污染项目列表。
- 超时、未登录或断网时静默回退到规则摘要，不影响基础功能。

## 详情页只有 4 个页签

| 页签 | 用来做什么 |
|---|---|
| **进度** | 「做到哪了」、按天对话时间线、对话标记、改动文件与还原入口；可切换查看全部原始会话。 |
| **运行** | 体检问题、运行/停止服务、脚本与测试、实时日志；报错可解释或复制求助 prompt。 |
| **版本** | 当前分支、改动、Diff、暂存、内联「存个版本」、推送与分支操作；进阶 Git 操作收在同页。 |
| **项目信息** | 项目简介、备注、技术栈、占用空间、清理入口，以及 README / AGENTS / HANDOFF 等精简文档列表与预览。 |

## 安装

### 默认安装包：ad-hoc 签名

仓库默认打包使用 ad-hoc 签名，没有 Apple 公证。首次打开需要手动放行：

1. 从同一个 GitHub Release 下载 DMG 和同名 `.sha256` 文件。在下载目录运行 `shasum -a 256 -c FizzDeck-0.9.3-arm64.dmg.sha256`，确认输出 `OK`。
2. 打开 DMG，把 FizzDeck 拖进「应用程序」，尝试打开一次。
3. 如果 macOS 提示无法验证，且你信任本次下载，可在「系统设置 → 隐私与安全性」中为 FizzDeck 选择「仍要打开」。

### 自己打 Developer ID + 公证包

签名身份和公证凭据都从环境变量或命令行注入，仓库不包含任何证书、Apple ID 或 App 专用密码。

```sh
export DEVELOPER_ID_APP="Developer ID Application: <你的名称> (<TEAMID>)"
export NOTARY_PROFILE="<notarytool 凭据配置名>"
./macos/script/package_dmg.sh --notarize
```

也可以把签名身份作为参数传入：

```sh
./macos/script/package_dmg.sh \
  --sign-identity "$DEVELOPER_ID_APP" \
  --notarize
```

`--notarize` 会使用 `xcrun notarytool submit --keychain-profile "$NOTARY_PROFILE" --wait` 提交 DMG，成功后执行 `stapler staple`、`stapler validate` 和 `spctl` 校验。完整参数与凭据配置方式见 [macos/README.md](macos/README.md)。

## 快速开始

### 构建原生版

首次在这台机器构建时，先接受 Xcode 许可：

```sh
sudo xcodebuild -license accept
```

构建、启动并检查进程：

```sh
./macos/script/build_and_run.sh --verify
```

默认版本为 `0.9.3`、Build `26`，也可以在构建时覆盖：

```sh
VERSION=0.9.3 BUILD_NUM=26 ./macos/script/build_and_run.sh --build-only
```

产物在 `macos/dist/FizzDeck.app`。用 Xcode 调试时直接打开 `macos/Package.swift`。

运行测试：

```sh
swift test --package-path macos
```

### 打包 DMG

```sh
./macos/script/package_dmg.sh
```

默认输出 `macos/dist/FizzDeck-0.9.3-arm64.dmg`，同时生成同名的 `FizzDeck-0.9.3-arm64.dmg.sha256`。校验文件是标准 `shasum -a 256` 格式，供应用内更新与 GitHub Release 使用。

### 本地网页版

FizzDeck 仍保留轻量网页版，和原生版共用 `~/.repodeck`：

```sh
npm install
node start.mjs
```

浏览器会打开 `http://127.0.0.1:4770`。修改 `src/` 后重新构建：

```sh
npm run build
```

停止服务：

```sh
./stop.sh
```

## 本机数据与隐私

FizzDeck 不上传项目数据，也不连接 FizzDeck 托管服务。由 FizzDeck 启动的开发命令仍可能自行访问网络。

共享数据目录继续使用 `~/.repodeck`，兼容已有安装：

后续开发版会对关注项目的已配置上游做 24 小时限频检查；仅联系 Git 托管方，不推送、不改工作树。项目脚本仍由用户点击运行。

```text
~/.repodeck/
├── roots.json          # 受管目录与展示别名
├── state.json          # 星标、标签、分组、备注与界面状态
├── scan-cache.json     # 扫描缓存
├── marks.json          # AI 对话前的标记
├── session-search.sqlite # 跨项目对话 FTS5 索引
├── summaries/          # 可选 AI 总结缓存
└── logs/               # 开发服务日志
```

原生版刻意不开启 App Sandbox，因为它需要访问用户自选的项目目录并执行项目脚本。请只加入可信目录，运行命令前先确认项目来源。

## 项目结构

```text
macos/                  SwiftUI 原生应用、资源、脚本与测试
server.mjs              网页版扫描、Git、进程控制与 HTTP 接口
src/                    网页版源码
src/landing/            官网落地页源码
public/                 前端构建产物，由 server.mjs 托管
start.mjs               网页版启动器
stop.sh                 网页版停止脚本
```

## 当前边界

- 原生版面向 Apple Silicon，要求 macOS 26+；公开安装包默认使用 ad-hoc 签名，除非发布时明确提供 Developer ID 公证版。
- 「对话标记」依赖 Git 对象，默认保留约 14 天；可固定的标记会保留更久，非 Git 项目只能记录纯标记。
- 还原会覆盖或删除你勾选的已跟踪改动；对话后新建的文件默认保留，删除需要单独确认。
- 可选 AI 总结默认关闭，失败时只影响润色结果，不阻塞规则摘要和日常操作。
- 网页版是轻量补充，不承担菜单栏、系统通知、默认终端选择和 Developer ID 公证等原生系统能力。

## 状态

FizzDeck 是源码优先的个人工具。原生版是主入口，网页版和双语官网保留为补充入口。

许可：[LICENSE](LICENSE)。可免费下载、构建和在本机使用；第三方素材保留各自许可。

随包素材许可：[Obel Mono（SIL OFL 1.1）](macos/Resources/Fonts/OFL.txt) · [Kubai 图标（MIT）](macos/Resources/Icons/LICENSE)。
