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

## v0.8.1 / Build 17 · 2026-11-28

Wave 1 已在本地完成。证据在 `output/wave-081/`：`strict-build.log`、`swift-test.log`、`bundle-version.txt`，以及隔离组件的浅/暗快照和实际布局尺寸。新增 9 项测试均通过。

## v0.8.2 / Build 18 · 2026-11-28

Wave 2 本地实现和复测完成，审核通过。严格并发构建无警告，308 项测试中 307 通过、1 项既有压测默认跳过，`git diff --check` 通过。新增 3 项测试。构建日志、版本号与隔离记录在 `output/wave-082/`；32 张主页面截图及弹窗、全文搜索、批量选择证据在 `output/wave-082/final-qa/`。首次 QA 重连的隔离异常、影响范围和加固后的复测结果见 [HANDOFF.md](HANDOFF.md)。本波未发布。

## v0.8.3 / Build 19 · 2026-11-28

并行工作区闭环与三处视觉微调完成，审核通过。严格并发构建无警告，327 项测试中 326 通过、1 项既有压测默认跳过，新增 19 项均通过。只在无远端的临时仓执行写操作，已核对真实配置、安装包和任务仓 Git 元数据。证据在 `output/wave-083/`：`strict-build.log`、`swift-test.log`、`bundle-version.txt`、`native/qa-observations.txt`、`native/fixture-verification.txt`、`isolation-verification.txt` 与本波 `review.patch`。

## v0.8.4 / Build 20 · 2026-11-28

三种接力卡和 Cursor / OpenCode 本地会话接入完成，已审核并放行下一波。严格并发构建无警告；344 项测试中 343 通过、1 项既有压测默认跳过，新增 17 项均通过。隔离原生验收覆盖接力卡三场景、预览及复制脱敏、双工具时间线与中文搜索、文件反查和增量更新；1,839 个受检路径零变化。证据见 `output/wave-084/` 中的构建与单测日志、`bundle-version.txt`、`native/qa-observations.txt`、`isolation-verification.txt` 与本波 `review.patch`。

## v0.8.5 / Build 21 · 2026-11-28

四周期跨 Agent 复盘、OpenCode 瞬时读失败兜底、横版浅暗 PNG 和官网四张新图已完成。两张匿名 PNG 在分享专项中均实测复制并还原剪贴板；v0.5.3 与 v0.8.0 隔离升级通过。官网候选通过 390px / 1440px 中英文走查，未部署。

键盘修正后严格并发构建 0 警告 / 0 错误，361 项中 360 通过、1 项既有压测跳过。已在 Build 21 实测工作台、侧栏、对话真实搜索、项目库、体检、设置、四个项目页签、Worktree 新建取消与接力卡三场景。[焦点和选中证据](output/wave-085/native/keyboard-qa/keyboard-ax.txt) · [隔离核对](output/wave-085/native/keyboard-qa/isolation-verification.txt)。早两次各观察到六项真实缓存相关路径变化，未归因到写入 PID；最终有进程内防护的复测 1,839 项零变化。一次接力卡预览动作误触复制，系统剪贴板先前内容未能恢复。详见[交接](HANDOFF.md#v085--build-21本地已审核)。

[仅 Wave 5 的补丁](output/wave-085/review.patch)已验贴并获本地审核放行。VoiceOver 实际朗读、未抽查的原生菜单路径、签名版系统快捷指令与公证在线更新链仍待验。

## v0.8.6 / Build 22 · 2026-11-28

Build 21 审核通过后按[完整基线](output/wave-086/baseline-verification.txt)推进。四层色彩预算、工作台两列行动区与全宽周历、按复盘周期统计的费用构成和小基数涨幅守门已落地。最终严格并发构建无诊断，全量 365/365 通过（含真实窗口规模压测，0 跳过）。[构建](output/wave-086/strict-build.log) · [测试](output/wave-086/swift-test-verified.log) · [仅 Wave 6 的补丁与验贴](output/wave-086/review-verification.txt)。

[真机结果](output/wave-086/native/QA.md)：1000pt / 1320pt 浅暗四组打开复盘后都保持原宽；工作台四张、复盘三张可审核，1000pt 暗色复盘还缺原图。最终受控区间 1,839 项零变化；整波快照保留一次六项缓存变化，[两个区间分列](output/wave-086/isolation-verification.txt)。同期其他图标、色值和分享卡改动已从[冻结候选](output/wave-086/build22-source.tar.gz)中分开，并原样保留在共享工作树。公开仍为 v0.8.0 / Build 16，本地候选待审核。

## Wave 087 · 真机视觉验收与补丁 · 2026-11-28

工作树视觉候选沿用 0.8.6 / 22。[独立 App](output/wave-087/preview/FizzDeck.app)和[原图索引](output/wave-087/native/QA.md)已就绪：四张工作台、四张复盘、四份从界面切换后复制的匿名分享 PNG。精修玻璃侧栏次级文字、匿名图例撞色和波峰贴边；另实测长侧栏滚动与预览 App 的直接启动。

[严格构建](output/wave-087/strict-build.log)无警告错误，[368 项全量测试](output/wave-087/swift-test.log)全部通过，无跳过。真实配置、安装包与 Git 等 [1,839 项前后相同](output/wave-087/isolation-verification.txt)，剪贴板按表示核对已还原，临时实例均已退出注销。

[独立补丁](output/wave-087/review.patch)以封存的 Build 22 为底；[完整源码回贴校验](output/wave-087/review-verification.txt)含文件内容、模式及 SHA-256。旧波的[1000pt 暗色复盘](output/wave-086-retake/README.md)由原 Build 22 单独补拍，两个封存件未改。仅本地待审核，未触及伴生 Web 或发布链。

## v0.9.0 / Build 23 · 已发布 · 2026-11-28

四字重字体注册及逐字符混排、四组窄宽浅暗实拍、长名称排版和四张官网实机图均已完成。严格构建无诊断，372/372 全过。独立官网构建和导出后，Chrome 1440 / 390 的中英文四组标题全部两行；首屏 114,922 字节。[审阅清单与原图](output/release-v0.9.0/REVIEW.md)。随后已按确认发布为 [GitHub Latest](https://github.com/CClishan/Fizzdeck/releases/tag/v0.9.0)；[官网提交 `ce5ff35`](https://github.com/CClishan/koroo-blog/commit/ce5ff35e174c25b6b277e79d5c9bb8d9e17d4953) 已上线，HTML 与九个依赖从公网逐字节核对。

## v0.9.1 / Build 24 · 本地审核通过

基于 `main`（`35103ee`）。项目库四组浅暗宽度组合共量了 24 个头图，全部 64pt。全局复盘和单项目战报各导出八张 1280 × 800 原图，另验关闭品牌角标。[实拍、原图与文件清单](output/release-v0.9.1/REVIEW.md) · [发行说明](docs/releases/v0.9.1.md)。

严格并发构建无诊断，381 项全过、无跳过。剪贴板的三种表示逐字节还原；隔离快照仅真实 `.repodeck` 根的时间变化，73 条事件无法归因到写入进程，详见[核对记录](output/release-v0.9.1/isolation-verification.json)。Build 24 未发布，公开版及官网仍为 Build 23。

## v0.9.2 / Build 25 · 本地审核通过

菜单栏遥控器、临期标记按项目提醒与两处中文数字排版均已完成。正式构建零警告错误，395/395 通过。菜单三种复制均脱敏，主窗口始终最小化；进度页固定、工作台按批忽略、重启后新标记继续提醒均在隔离实例实测。发现并修正了状态栏反复重排和旧标记路径别名漏报。[实拍、原文、隔离核对与本轮差异](output/release-v0.9.2/REVIEW.md) · [发行说明](docs/releases/v0.9.2.md)。本轮无发布；Build 25 已审核通过，未单独发布。

## v0.9.3 / Build 26 · 已审核

原生界面语言与 Git 术语模式可独立切换；完成两种窗口宽度的英文走查、中英四页前台实拍、匿名分享 PNG 和官网双语四态验收。干净严格构建无诊断，410 项测试全部通过，无跳过。官网展示图按语言选取，实际响应字节与源 WebP 一致。[审核索引](output/release-v0.9.3/REVIEW.md) · [发行说明](docs/releases/v0.9.3.md)。审核已确认；复盘日期、表头与官网搜索文案随正式版本更新。
