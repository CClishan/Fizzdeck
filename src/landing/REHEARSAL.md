# FizzDeck 官网 · v0.9.3 / Build 26

中文页保留 v0.9.0 / Build 23 的四张实拍；英文页使用 v0.9.3 / Build 26 的四张英文原生窗口实拍。切换语言时连同图片、替代文字、图注和元数据一起切换。本版版本号与中文图片来源分别标注。下载仍指向 `releases/latest`。

- 原图：1320 × 860pt 的独立 macOS 前台窗口。工作台缩至 1600 × 1042，详情和 Doctor 缩至 1056 × 688；使用源图 ICC 转 sRGB，以 `#f6f6f6` 衬透明圆角。Doctor 的可见区域只含隔离样例项目。位置沿用下方 Build 23 样机坐标。
- 构建：独立目录仅复制网页输入，不包含 `macos/`、`output/` 或 Swift 缓存。`npm run build` 后用 `script/export_landing.mjs` 向本地空站点导出 HTML + 13 项资源。**英文首屏两图 127,946 字节，中文 114,922 字节**；中文首图不会被英文入口提前请求，其余三图按需加载。
- Chrome 158 在 1440 × 900、390 × 844 各验中英文。20 组主副句均两行，无横向溢出或控制台错误。每个语言的四张图按实际响应体与对应源 WebP 核对 SHA-256；切换及刷新后再验地址与图组。[验收 JSON](../../output/release-v0.9.3/web-final/verification.json) · [原图映射](../../output/release-v0.9.3/native/web-photos.json) · [审核索引](../../output/release-v0.9.3/REVIEW.md)。

## v0.9.0 / Build 23 历史记录

四张亮色图都取自本版 1320 × 860pt 的原生 macOS 窗口，使用隔离项目。工作台、进度、版本、体检的源图与 WebP 一一对应；体检使用较长的样例项目列表，未把本机监听进程拍进官网。下载仍指向 GitHub `releases/latest`。本地候选不改变公开官网或下载。

用只含网页输入的独立目录执行 `npm ci` 和 `npm run build`；不要把 `output/`、`macos/` 或 Swift 缓存带进 Tailwind 的扫描范围。运行 `node script/export_landing.mjs <独立的官网候选目录>`，只导出 `landing.html` 和 9 个资源。此目录需要有官网的 `app/fizzdeck/route.ts`。发布后再验证公网实际返回的字节。

- Studio Display 机身 53,770 字节，工作台 WebP 61,152 字节；首屏共 **114,922 字节**，两张图各请求一次。窗口贴在原 2400 × 1610 样机的 `(622, 280, 1156, 753)`。其余三张按需加载。
- Chrome 158 在 1440 × 900、390 × 844 的中英文四个组合下，按实际字形位置统计 hero、showcase、grid、shortcut、FAQ。**20 组主副句全部正好两行**，无裁切、横向溢出或控制台错误，灰色标题最低对比度 4.95:1。放大网页后允许自然换行。
- 核对四张图实际传输字节与源文件 SHA-256、下载链接、切换语言后刷新、键盘跳到正文、FAQ 展开和无 JS 下载。真实项目数据、伴生 Web 工作台和 QA 素材不进官网导出包。

本机[浏览器记录及八张截图](../../output/release-v0.9.0/REVIEW.md)、[窗口原图与 WebP 对照](../../output/release-v0.9.0/native/web-photos.json)。可运行 `bash output/release-v0.9.0/web-work/verify.sh` 在新的独立目录复验；该工作脚本及审阅资料由 Git 忽略。
