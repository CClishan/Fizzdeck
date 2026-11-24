# Rehearsal: FizzDeck stage

Gold: `hero-demo` 的单一动作与终端卫星、`static-card` 的安静层级；场景用 kit 重新编排，没有复制示例身份。

Beats: 选中 stillframe → 点击启动 → 四行日志 → 运行中 → payoff 停留 → 停止并淡出日志，约 10 秒循环。

Captured: 1440 / 390 的 payoff still、完整 loop、states、reduced motion；320 / 390 / 1440 的整页与 CTA。

Film: 390 完整采样无 findings，`rehearsal passed`；1440 gate 通过，但 2x 截图让采样出现 47–56ms 间隙，覆盖不完整。1440 独立 jumps 扫描 663 帧完整、无 jump/drift；390 jumps 662 帧完整。

Review: 复核了裁切、层级、循环接缝、日志复位和移动端命令换行；没有阻塞问题。reduced-motion 静帧与 payoff 逐字节一致。

Assumptions: 界面数据是产品示意；演示不读取真实项目状态。

Unresolved: 1440 的 film 覆盖受截图开销影响，不能作为完整运动采样；同一循环的 jumps 扫描已完整通过。

Not checked: Safari / Firefox、真实触屏设备、屏幕阅读器；GitHub 页面内 `#quick-start` / `#readme-ov-file` 锚点的实际滚动。
