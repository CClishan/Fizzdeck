# Rehearsal: FizzDeck v0.7.4 Landing (Atlas Editorial + Stageshow + ZH/EN)

- **Version Sync**: All DMG download links (`FizzDeck-0.7.4-arm64.dmg`), Release notes links, hero CTA, and FAQ updater copy synced to `v0.7.4`.

- **Hero 硬件帧与滚动缩放**:
  - 静态正视 2x Retina 合成图 [hero-studio-display.png](file:///Users/a003/dsh-workspace/repo-dashboard/src/assets/hero-studio-display.png)（`2400×1610`，内嵌 `1462×881` 屏幕区）：左侧对齐 Mac Studio、居中独立铝合金 L 支架、冷白影棚打光，外框背景统一融合至 `#F5F5F5`，零矩形接缝；屏幕内含 ` FizzDeck  File  Edit  View  Window` 菜单栏与真实无损亮色工作台。
  - 滚动缩放曲线（[Landing.jsx](file:///Users/a003/dsh-workspace/repo-dashboard/src/landing/Landing.jsx) `.hero-zoom-inner`）：`overflow: clip` 锐角画廊容器（`#F5F5F5`）内随 `scrollY` 从 `y = 0` 的 `scale(0.77)` 经 `rAF` 阻尼插值放大至 `y = 475px` 的 `scale(1.0)`（`transform: none`），回滚可平滑还原；移动端 `≤640px` 从 `scale(0.90)` 平滑至 `1.0`；兼容 `prefers-reduced-motion: reduce`。
- **Look & Theme**: 纯画廊白 `#FFFFFF` + `#F5F5F5` 画廊舞台灰，唯一品牌点缀色 `#6438FF`（对齐原生 `FizzTheme.accent`），无暗黑模式切换。
- **3-Column Stageshow Feature Tiles** ([FeatureStages.jsx](file:///Users/a003/dsh-workspace/repo-dashboard/src/landing/stages/FeatureStages.jsx)):
  1. **Workbench & AI ledger**: 提交热力图点阵 + AI 费用环（`~$10.1` · DeepSeek / Codex / Claude / AGY），悬停触发日期气泡。
  2. **In-place Git loop**: `GitService.swift` 语义增删 Diff + 暂存勾选 + `Commit & Push` 状态翻转（`推送中…` → `已推送 · main`）。
  3. **Services & port guard**: `:4770` 端口占用二次确认释放（`SIGTERM`）与固定脚本列表，悬停触发激活绿灯态。
- **Verification**:
  - `npm run build`：Vite 8.3.8 构建通过（253ms），产出 [public/landing.html](file:///Users/a003/dsh-workspace/repo-dashboard/public/landing.html) 与 `hero-studio-display-BD0DcJO0.png`；中英文 `v0.7.4` CTA、FAQ、静态 meta 与下载链接已进入构建产物。
  - 浏览器实机验收（`http://127.0.0.1:4173/landing.html`，`1440×900` 桌面端 & `390×844` 移动端）：
    - 滚动放大实测：`y = 0` → `scale(0.77)`、`y = 240` → `scale(0.8803)`、`y = 500` → `transform: none`（`1.0`），上滚平滑还原至 `scale(0.77)`。
    - `y = 0` 顶部 `EN` 语言切换正常触发，#F5F5F5 无矩形接缝，0 console error / warning，0 failed requests，移动端 0px 横向溢出。
- **Not checked**: Safari / Firefox 实机浏览、真机触屏滑动、`prefers-reduced-motion` 系统开关切换实拍。
