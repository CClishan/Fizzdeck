# FizzDeck v0.8.0 官网与 Build 13 实机贴图

首屏沿用原版 Studio Display 与 Mac Studio 样机。机身图为原 PNG 的 WebP 副本（53,770 字节）；屏幕使用独立的 Build 13 工作台实机图（62,644 字节），两图共 116,414 字节。窗口贴在 2400 × 1610 底图的 `(622, 280, 1156, 753)`，随底图等比缩放；更换同宽高比截图时无需重做样机。底图 WebP 边缘是 `#f6f6f6`，与首屏背景同色。

下方三张仍是「进度」「版本」「体检」的原生截图，按需加载。所有原生截图来自独立 bundle、临时 home 和三个隔离项目，不发布用户的项目、日志或路径。

- 中英文区分产品版本（v0.8.0 / Build 16）和截图来源（v0.7.5 / Build 13）。下载与发版记录分别指向 `releases/latest` 和 `releases`。等 GitHub 的公开下载切换到 Build 16 再部署对应官网文案。
- `npm run build` 构建独立的 `public/landing.html`；线上站点入口为 `koroo.top/fizzdeck`。实际发布与 CDN 核验见根目录 `HANDOFF.md`。
