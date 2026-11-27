# 系统集成与发布验收

这些功能包含在 **v0.8.0 / Build 16** 中。`macos/dist/FizzDeck-0.7.5-arm64.dmg` 是单独归档的 Build 13 安装包。

开发工作树可用以下命令组装独立的候选 App（不会启动或覆盖正在运行的副本）：

```sh
FIZZDECK_DIST_DIR="$PWD/macos/dist/development" VERSION=0.8.0 BUILD_NUM=16 ./macos/script/build_and_run.sh --build-only
```

## 深链与快捷指令

深链只接受已加入 FizzDeck 的项目绝对路径。将路径作为 UTF-8 查询参数编码，避免空格、`&` 或 `#` 改变参数含义。`tab` 可选，接受 `progress`、`run`、`version`、`info`。未知动作、重复参数和未受管路径均被拒绝。

```sh
open "$(python3 -c 'import os, urllib.parse; print("fizzdeck://open?" + urllib.parse.urlencode({"path": os.getcwd(), "tab": "run"}, quote_via=urllib.parse.quote))')"
open "$(python3 -c 'import os, urllib.parse; print("fizzdeck://handoff?" + urllib.parse.urlencode({"path": os.getcwd()}, quote_via=urllib.parse.quote))')"
```

`handoff` 打开本地接力卡预览；点击「复制」才更改剪贴板。快捷指令另提供「打开 FizzDeck 项目」「复制项目接力卡」「查询关注项目体检状态」。复制动作无需打开编辑界面，输出脱敏 Markdown；体检优先读已完成的报告，冷启动回退到本地 L0，绝不触发试跑。两种打包脚本都会将 `Metadata.appintents` 写入 App 的 `Contents/Resources` 并校验三个动作。

**真机结果（2026-11-27）：** 同一 Build 16，ad-hoc 包能被操作库检索，但执行时 `linkd` 报 `Unable to get teamId`，系统回执为 `LinkDaemon.ProcessRegistry.Errors 0`。使用 Apple Development 证书签名、严格校验通过后，在独立 bundle 与临时 home 上，通过系统「快捷指令」编辑器分别运行：

| 动作 | 系统实际结果 |
|---|---|
| 查询关注项目体检状态 | `Clean Fixture：体检正常`；`Focus Fixture：项目需要的零件还没装`。 |
| 打开 FizzDeck 项目 | 在系统项目选择器中选 `Focus Fixture`，原生窗口选中同一项目并进入进度页。 |
| 复制项目接力卡 | 选 `Clean Fixture`，编辑器返回该项目的 Markdown。实际返回文本与剪贴板逐字节相等，均为 251 字节。原剪贴板已恢复。 |

本机留存的开发版为 `macos/dist/development-signed/FizzDeck.app`，使用产品 Bundle ID。重新构建时，从 `security find-identity -v -p codesigning` 中选择自己的 Apple Development 身份，将其指纹放入 `FIZZDECK_DEV_IDENTITY`，在仓库根目录运行：

```sh
: "${FIZZDECK_DEV_IDENTITY:?请先选择本机 Apple Development 身份}"
app_dir="$PWD/macos/dist/development-signed"
FIZZDECK_DIST_DIR="$app_dir" VERSION=0.8.0 BUILD_NUM=16 ./macos/script/build_and_run.sh --build-only &&
  codesign --force --timestamp=none --sign "$FIZZDECK_DEV_IDENTITY" "$app_dir/FizzDeck.app" &&
  codesign --verify --deep --strict "$app_dir/FizzDeck.app" &&
  codesign -dv --verbose=4 "$app_dir/FizzDeck.app"
```

核对 `Authority=Apple Development: …` 和 `TeamIdentifier`。本机曾有未过期的证书与私钥，但签名报 `unable to build chain to self-signed root`；补入由系统 Apple Root CA 验证的 WWDR G3 公共中间证书后，签名成功。开发签名用于本机测试，公开公证 DMG 另需 Developer ID Application。

## 键盘与 VoiceOver

在系统「键盘导航」关闭的原有设置下验了两种项目：有改动时，提交说明 → 文件 Diff → 暂存/取消暂存 → 页签可按 Tab 到达；无改动时，提交说明与页签可用 Tab / Shift-Tab 往返。左右方向键切换原生分段页签，选中状态可从辅助功能树读取。工作台、项目库、体检和命令面板的键盘入口也已验过。

最终开发签名构建中，进度和版本页均只暴露一个「项目页签」标题和对应选中值。VoiceOver 声音与光标尚未实测。复验时用隔离项目确认页签只读一次、选中页正确、Diff 文件名与展开值清楚、暂存按钮读出目标文件、关闭命令面板后可继续导航。也要走一次体检页、对话框和菜单，并恢复原设置。

## CI 与打包

PR 与分支 push 在 macOS 26 上构建、运行 Swift 测试、组装 App；Ubuntu 上执行 `npm ci`、Vite 构建和逐文件 `bash -n`。`vX.Y.Z` tag 必须与该提交的打包版本一致，先复用 CI，再构建 arm64 DMG，检验 SHA-256，并把 DMG 与 `.sha256` 上传至 GitHub **草稿** Release。此时不会改变 Latest。CI 跳过 Finder 图标排布；正式本地打包保留排布。

两个 workflow 已在本地通过 actionlint。[PR #3 的托管 CI](https://github.com/CClishan/Fizzdeck/actions/runs/46004663046) 与[同一提交的分支 CI](https://github.com/CClishan/Fizzdeck/actions/runs/46004657337) 均通过了 `native` 和 `web-and-shell`，随后合并到 `3b6a846`。`v0.8.0` 指向该合并提交。参见 [tag 打包记录](https://github.com/CClishan/Fizzdeck/actions/runs/46005894773) 和 [HANDOFF](../HANDOFF.md)。独立 Build 13 仍使用冻结源码。

无签名 Secrets 时生成 ad-hoc 包。使用 Developer ID 时设置全套 GitHub Actions secrets：`DEVELOPER_ID_APP`、`CERTIFICATE_P12_BASE64`、`CERTIFICATE_PASSWORD`、`NOTARY_KEY_BASE64`、`NOTARY_KEY_ID`、`NOTARY_ISSUER_ID`。配置不完整会失败，不会静默降级。凭据只在 GitHub 托管 runner 中处理；签名钥匙串和临时文件在退出时清理。手动公证仍使用本机钥匙串的 `NOTARY_PROFILE`。

## 规模压测

```sh
FIZZDECK_SCALE_TEST=1 swift test --package-path macos --filter PerformanceBaselineTests.testThousandProjectWindowAndTenThousandConversations
```

在解锁的 macOS 桌面运行，需要屏幕录制权限读取测试表格的窗口帧。普通 CI 跳过此项，不会索取权限。1,000 个项目，每项目 10 段会话；40 个能定位唯一会话的查询另测中文短词回退。表格使用正式 `LibraryTableView`；以 ScreenCaptureKit 的 `complete` 帧计数，而非用排序耗时推算帧率。

本次 Mac（Apple Silicon，macOS 27.2.1，60 Hz，debug）：建索引 0.17 s，查询 P50/P95 为 0.63/0.96 ms，中文两字回退 2.12 ms；表格 181 完整帧 / 3.01 s = 60.1 FPS。测试进程 RSS 峰值 118.8 MiB（起始 26.9 MiB，单独建索引后 54.4 MiB）。单台机器、三秒连续滚动，不代表所有页面与机型的长期性能。
