export const REPO_URL = 'https://github.com/CClishan/Fizzdeck';
export const RELEASES_URL = `${REPO_URL}/releases`;
export const DMG_URL = `${RELEASES_URL}/latest`;

export const COPY = {
  zh: {
    meta: {
      title: 'FizzDeck — AI 写的项目，记得住、回得去、跑得起',
      description:
        'FizzDeck 是给 Vibe Coder 的本地优先 macOS 工作台：记得住每次 AI 对话，改坏了回得去，项目跑不起来时先做体检。无需账号，数据留在本机。',
    },
    nav: {
      views: '核心切面',
      features: '能力',
      shortcut: '快捷键',
      faq: '常见问题',
      download: '下载公开版',
      langSwitch: 'EN',
      langAria: 'Switch to English',
    },
    hero: {
      lead: 'AI 写的项目，记得住、回得去、跑得起。',
      rest: '原生 macOS 工作台，用人话看懂每次对话，改坏了也能退回。',
      primaryCta: '下载 macOS 公开版',
      secondaryCta: 'GitHub 源码',
      note: 'v0.8.0（Build 16）· Apple Silicon · macOS 26+ · 截图来自 v0.7.5（Build 13）',
      stageCaption: 'FizzDeck v0.7.5 · 工作台实机截图',
      heroAlt: 'Studio Display 样机中的 FizzDeck v0.7.5 工作台：关注项目、本周活动和待处理事项，显示器旁是 Mac Studio',
    },
    showcase: {
      lead: '先让 AI 项目不再失控。',
      rest: '记得住上次做到哪，回得去改坏之前，跑得起本机环境。',
      hint: '原生应用实机截图',
      tiles: [
        {
          id: 'workbench',
          alt: '项目进度页的对话时间线与四个项目页签',
          lead: '记得住。',
          rest: '跨项目对话时间线、中文搜索和 ⌘K 直达，上次让 AI 做了什么不用翻终端。',
        },
        {
          id: 'git',
          alt: '版本页中的当前分支、待暂存文件和版本记录',
          lead: '回得去。',
          rest: '每次对话前悄悄留个标记；看 Diff、按文件还原，再把这次改动存成真正的版本。',
        },
        {
          id: 'services',
          alt: 'Doctor 的依赖问题与本机运行环境',
          lead: '跑得起。',
          rest: '体检盯依赖、端口、密钥和版本保护；跑不起来时先给能点的一步，而不是一串报错。',
        },
      ],
    },
    grid: {
      lead: '从对话到运行，围着小白重排。',
      rest: '三件小事都留在本机，不需要先学会 Git。',
      items: [
        {
          icon: 'folder',
          lead: '本地优先。',
          rest: '项目、会话索引和设置留在 ~/.repodeck；不登录，不上传源码。',
        },
        {
          icon: 'sparkles',
          lead: '人话模式，默认开启。',
          rest: 'Commit、Stash、Pull 换成大白话；熟悉 Git 后再切专业术语。',
        },
        {
          icon: 'activity',
          lead: '本周回顾。',
          rest: '按项目看近 14 或 30 天的费用和提交趋势；每周回顾可复制为 Markdown，也可选择仅用数字统计润色。',
        },
        {
          icon: 'terminal',
          lead: '中文搜索 + ⌘K。',
          rest: '本地 FTS5 覆盖跨项目对话，短词也有回退；搜到哪条就直达哪个节点。',
        },
        {
          icon: 'shield',
          lead: '纯剪贴板接力卡。',
          rest: '把项目状态和最近对话整理成 Markdown，复制给任意 Agent；不写项目文件，发送前脱敏。',
        },
        {
          icon: 'git-commit',
          lead: '对话前隐形标记。',
          rest: '只写 Git 对象，不碰分支、工作区和提交记录，git log 里看不到。',
        },
        {
          icon: 'git-branch',
          lead: '看改了什么，也能退回。',
          rest: '比较对话前后差异，按文件还原；对话后新建的文件默认保留，不替你做删除决定。',
        },
        {
          icon: 'play',
          lead: '存个版本 + 密钥拦截。',
          rest: '在项目里直接存版本；推送前检查 .env 和已跟踪文件里的密钥，先拦住再解释。',
        },
        {
          icon: 'hard-drive',
          lead: 'Doctor 体检。',
          rest: '依赖或环境文件变化时重新体检；工作台也会提醒关注仓库有新的云端改动。',
        },
        {
          icon: 'menubar',
          lead: '运行页先体检。',
          rest: '看清哪个进程占着开发端口。自己点「试跑一下」才会构建、检查类型或运行测试，日志里随时可停。',
        },
        {
          icon: 'layers',
          lead: '本机环境与 Git 身份。',
          rest: 'Node、Git、Agent CLI 状态和 Git 用户名邮箱内联检查，新机第一次也能照做。',
        },
        {
          icon: 'sparkles',
          badge: 'v0.7',
          lead: '可选 AI 总结。',
          rest: '默认关闭；支持免 Key 的 Agent CLI、钥匙串里的 OpenAI 兼容 API 或本地模型，失败静默回退规则版。',
        },
      ],
    },
    shortcut: {
      lead: '⌘K 现在也能找对话。',
      rest: '项目、分支、命令和跨项目会话一起搜，中文短词也能命中。',
      boundary: '本地 FTS5 索引 · 仅监听 127.0.0.1 · 零遥测无账号',
    },
    faq: {
      title: '常见问题。',
      subtitle: '关于人话模式、对话标记、运行体检与安装签名的直接回答。',
      items: [
        {
          q: 'FizzDeck 会上传我的代码或 AI 对话记录吗？',
          aLead: '不会。FizzDeck 没有后端服务，也不需要登录账号。',
          aRest: '所有项目元数据、会话索引与脚本偏好都保存在你本机的 ~/.repodeck 目录；Web UI 模式也只监听 127.0.0.1 并校验本地来源。',
        },
        {
          q: '打开下载的 DMG 时提示「无法验证开发者」怎么办？',
          aLead: '当前公开的默认安装包采用临时（ad-hoc）签名；除非发布说明明确写了 Developer ID 公证版，否则都会被 Gatekeeper 拦一次。',
          aRest: '先用同一 Release 的 .sha256 核对下载，再将 App 拖入「应用程序」并打开一次。若你信任来源，可在「系统设置 → 隐私与安全性」中为 FizzDeck 选择「仍要打开」。本版没有团队签名，系统快捷指令可能无法执行；可在应用内打开项目、复制接力卡和查看体检。',
        },
        {
          q: '人话模式到底是什么？会改变功能吗？',
          aLead: '只换文案，不换能力。默认把人话放在主位置，把 Commit、Stash、Pull 等专业术语收在悬停提示里。',
          aRest: '熟悉 Git 后可以在「设置 → 界面术语」切回专业模式；两种模式共用同一套 4 个页签和操作。',
        },
        {
          q: '「对话前标记」会污染 Git 分支或提交记录吗？',
          aLead: '不会。它把当前工作区写成临时 Git 对象，不改分支、不动暂存区，也不出现在 git log 里。',
          aRest: '默认保留约 14 天，重要节点可以固定；还原前会再打一个标记，对话后新建的文件默认只列出、不自动删除。',
        },
        {
          q: '「体检 Doctor」会扫描所有项目并频繁跑命令吗？',
          aLead: '不会。关注项目做轻量的静态与本地命令检查；闲置项目只在打开体检页时整理，不会无差别运行项目。',
          aRest: '缺依赖、端口冲突、.env 风险和版本保护都有就地动作；闲置空间默认移到废纸篓，而不是直接永久删除。',
        },
        {
          q: '可选 AI 总结会读取或上传我的完整对话吗？',
          aLead: '默认关闭；开启后也只发送项目名、文件名、变动计数和脱敏后的一句话意图，不发送源码或完整对话。',
          aRest: '可使用本机已登录的 Agent CLI（免 Key）、存进 macOS 钥匙串的 OpenAI 兼容 API，或本地模型；失败会静默回退到规则摘要。',
        },
        {
          q: 'FizzDeck 收费吗？如何升级到新版本？',
          aLead: '可以免费下载并在本机自行构建使用。再分发前请查阅相应版本的许可条款；第三方素材保留各自许可。',
          aRest: '你可以在应用内「设置 → 关于」检查更新、下载 DMG、校验 SHA-256 并安全替换重启，也可以直接前往 GitHub Releases 下载最新 arm64 DMG。',
        },
      ],
    },
    footer: {
      madeForMac: '专为 Mac 打造',
      copyright: '© 2026 FizzDeck · Source on GitHub',
      colProduct: '产品',
      colInfo: '信息',
      linksProduct: [
        { label: '下载最新公开版', href: DMG_URL, external: true },
        { label: 'Release 更新日志', href: RELEASES_URL, external: true },
        { label: '从源码构建', href: `${REPO_URL}#quick-start`, external: true },
      ],
      linksInfo: [
        { label: 'GitHub 仓库', href: REPO_URL, external: true },
        { label: '反馈问题', href: `${REPO_URL}/issues`, external: true },
        { label: '常见问题', href: '#faq', external: false },
      ],
    },
    stages: {
      workbench: {
        title: '提交热力图',
        commitsUnit: '次',
        streak: '连续 4 天',
        calloutDate: '11月26日',
        calloutCount: '14 次',
        costTitle: '本周',
        costLabel: '费用构成',
        legend: [
          { name: 'DeepSeek', pct: '48%' },
          { name: 'Codex', pct: '29%' },
          { name: 'Claude', pct: '15%' },
          { name: 'AGY', pct: '8%' },
        ],
      },
      git: {
        branch: 'main',
        file: 'GitService.swift',
        hunk: '@@ -84,6 +84,9 @@ commitAndPush',
        addLine: '+  return GitResult(committed: true)',
        delLine: '-  throw GitError.pushFailed(out)',
        stagedLabel: '已暂存 3 个文件',
        commitPlaceholder: 'feat: keep local commit on push failure',
        btnIdle: 'Commit & Push',
        btnPushing: '推送中…',
        btnDone: '已推送 · main',
      },
      services: {
        panelTitle: '开发服务',
        conflictPill: '端口冲突',
        conflictDetail: ':4770 正被 node (PID 4821) 占用',
        btnStopStart: '释放并启动',
        btnStopping: '发送 SIGTERM…',
        btnRunning: '运行中 · :4770',
        scriptDev: 'npm run dev',
        scriptTest: 'make test',
        pinned: '已固定',
        readyState: '监听本机',
        idleState: '空闲',
      },
    },
  },
  en: {
    meta: {
      title: 'FizzDeck — AI-built projects that remember, rewind, and run',
      description:
        'FizzDeck is a local-first macOS workbench for vibe coders: remember every AI conversation, rewind changes, and get projects running again. No account, data stays on your Mac.',
    },
    nav: {
      views: 'Views',
      features: 'Features',
      shortcut: 'Shortcut',
      faq: 'FAQ',
      download: 'Download release',
      langSwitch: '中文',
      langAria: '切换为中文',
    },
    hero: {
      lead: 'AI-built projects that remember, rewind, and run.',
      rest: 'A native Mac workbench in plain language—pick up where you left off and undo what broke.',
      primaryCta: 'Download the Mac release',
      secondaryCta: 'View on GitHub',
      note: 'v0.8.0 (Build 16) · Apple Silicon · macOS 26+ · Screenshots from v0.7.5 (Build 13)',
      stageCaption: 'FizzDeck v0.7.5 · Native workbench',
      heroAlt: 'FizzDeck v0.7.5 on a Studio Display beside a Mac Studio, showing focused projects, weekly activity and items that need attention',
    },
    showcase: {
      lead: 'Stop losing control of AI projects.',
      rest: 'Remember where you left off, rewind what broke, and get the local environment running again.',
      hint: 'Hover any tile to preview the interaction',
      tiles: [
        {
          id: 'workbench',
          alt: 'Progress tab showing conversations and the four project tabs',
          lead: 'Remember.',
          rest: 'A cross-project conversation timeline, Chinese search, and ⌘K keep the last AI request in reach.',
        },
        {
          id: 'git',
          alt: 'Version tab showing the current branch and changed files',
          lead: 'Rewind.',
          rest: 'A quiet mark before each conversation; inspect changes, restore files, then save a real version.',
        },
        {
          id: 'services',
          alt: 'Doctor listing missing dependencies and the local environment',
          lead: 'Run.',
          rest: 'Doctor watches dependencies, ports, secrets, and version protection before errors pile up.',
        },
      ],
    },
    grid: {
      lead: 'Rebuilt around the conversation, not Git jargon.',
      rest: 'Three essentials stay local—no Git degree required.',
      items: [
        {
          icon: 'folder',
          lead: 'Local first.',
          rest: 'Projects, session indexes, and settings stay in ~/.repodeck. No login, no source upload.',
        },
        {
          icon: 'sparkles',
          lead: 'Plain language, on by default.',
          rest: 'Commit, Stash, and Pull become everyday words; switch back to professional Git terms anytime.',
        },
        {
          icon: 'activity',
          lead: 'Weekly recap.',
          rest: 'See 14 or 30 days of estimated costs and commits per project. Copy your weekly recap as Markdown, or opt in to polish it using totals alone.',
        },
        {
          icon: 'terminal',
          lead: 'Chinese search + ⌘K.',
          rest: 'A local FTS5 index covers conversations across projects, with short-query fallback and direct jumps.',
        },
        {
          icon: 'shield',
          lead: 'Clipboard-only handoff.',
          rest: 'Turn project state and recent conversations into Markdown for any agent—no project writes, secrets redacted.',
        },
        {
          icon: 'git-commit',
          lead: 'Invisible pre-conversation mark.',
          rest: 'Temporary Git objects only—no branch move, worktree change, or commit entry in git log.',
        },
        {
          icon: 'git-branch',
          lead: 'See changes, then rewind.',
          rest: 'Compare before and after, restore selected files; files created after the conversation stay by default.',
        },
        {
          icon: 'play',
          lead: 'Save a version + secret guard.',
          rest: 'Commit in place; before push, check .env and tracked files for secret patterns and explain the risk.',
        },
        {
          icon: 'hard-drive',
          lead: 'Doctor.',
          rest: 'Doctor rechecks a project when dependencies or environment files change. The workbench shows when a focused repository has new remote commits.',
        },
        {
          icon: 'menubar',
          lead: 'Run-tab preflight.',
          rest: 'See which process holds a development port. Builds, type checks, and tests run only when you start a trial; watch the log or stop it there.',
        },
        {
          icon: 'layers',
          lead: 'Local environment + Git identity.',
          rest: 'Check Node, Git, agent CLI status, and Git name/email inline—first-day setup included.',
        },
        {
          icon: 'sparkles',
          badge: 'v0.7',
          lead: 'Optional AI summaries.',
          rest: 'Off by default. Use a no-key Agent CLI, OpenAI-compatible API in Keychain, or a local model; failures fall back to rules.',
        },
      ],
    },
    shortcut: {
      lead: '⌘K now finds conversations too.',
      rest: 'Search projects, branches, actions, and sessions across projects—even short Chinese queries.',
      boundary: 'Local FTS5 index · 127.0.0.1 only · Zero telemetry',
    },
    faq: {
      title: 'Questions? Answers.',
      subtitle: 'Direct answers on plain language, conversation marks, run checks, and signing.',
      items: [
        {
          q: 'Does FizzDeck ever upload my code or AI transcripts?',
          aLead: 'Never. FizzDeck has no backend, no accounts, and zero telemetry.',
          aRest: 'All project metadata, session indexes, and script preferences stay inside ~/.repodeck on your Mac. The companion Web UI binds strictly to 127.0.0.1.',
        },
        {
          q: 'Why does macOS ask about an unidentified developer on first launch?',
          aLead: 'Public builds use ad-hoc signing by default; unless release notes explicitly name a Developer ID notarized build, Gatekeeper will ask once.',
          aRest: 'Verify the download against the .sha256 file from the same release, drag FizzDeck to Applications and try opening it. If you trust the download, choose Open Anyway for FizzDeck in System Settings → Privacy & Security. This build has no team signature, so system Shortcuts may not run. Opening projects, copying handoffs and viewing health reports work inside the app.',
        },
        {
          q: 'What does plain-language mode change?',
          aLead: 'Only the copy, not the capabilities. Everyday wording leads, while Git terms remain in hover hints.',
          aRest: 'Switch back to professional terminology in Settings once Git becomes familiar; both modes share the same four tabs and actions.',
        },
        {
          q: 'Do conversation marks pollute Git branches or commit history?',
          aLead: 'No. A mark writes temporary Git objects without moving branches, touching the index, or adding anything to git log.',
          aRest: 'Marks usually last about 14 days and can be pinned; restoring creates another mark first, and files created after the conversation are kept by default.',
        },
        {
          q: 'Does Doctor scan every project and constantly run commands?',
          aLead: 'No. Focused projects get light static and local-command checks; idle projects are only organized from the Doctor page.',
          aRest: 'Dependencies, port conflicts, .env risk, and version protection have in-place actions; reclaimable space goes to Trash by default.',
        },
        {
          q: 'Does optional AI summary read or upload my full conversations?',
          aLead: 'It is off by default. When enabled, it sends only project names, file names, change counts, and a redacted one-line intent—not source code or full transcripts.',
          aRest: 'Use a locally logged-in Agent CLI, an OpenAI-compatible API key in macOS Keychain, or a local model. Failures fall back silently to rule-based summaries.',
        },
        {
          q: 'Is FizzDeck free? How do updates work?',
          aLead: 'Download, build and use FizzDeck locally for free. Check the license for the version you plan to redistribute; third-party assets retain their own terms.',
          aRest: 'Check for updates inside Settings → About to download the DMG, verify SHA-256 automatically, replace atomically, and relaunch—or grab arm64 builds from GitHub Releases.',
        },
      ],
    },
    footer: {
      madeForMac: 'Made for Mac',
      copyright: '© 2026 FizzDeck · Source on GitHub',
      colProduct: 'Product',
      colInfo: 'Information',
      linksProduct: [
        { label: 'Download the latest release', href: DMG_URL, external: true },
        { label: 'Release Notes', href: RELEASES_URL, external: true },
        { label: 'Build from Source', href: `${REPO_URL}#quick-start`, external: true },
      ],
      linksInfo: [
        { label: 'GitHub', href: REPO_URL, external: true },
        { label: 'Issues', href: `${REPO_URL}/issues`, external: true },
        { label: 'FAQ', href: '#faq', external: false },
      ],
    },
    stages: {
      workbench: {
        title: 'Commit Heatmap',
        commitsUnit: 'commits',
        streak: '4d streak',
        calloutDate: 'Nov 26',
        calloutCount: '14 commits',
        costTitle: 'This week',
        costLabel: 'Cost Mix',
        legend: [
          { name: 'DeepSeek', pct: '48%' },
          { name: 'Codex', pct: '29%' },
          { name: 'Claude', pct: '15%' },
          { name: 'AGY', pct: '8%' },
        ],
      },
      git: {
        branch: 'main',
        file: 'GitService.swift',
        hunk: '@@ -84,6 +84,9 @@ commitAndPush',
        addLine: '+  return GitResult(committed: true)',
        delLine: '-  throw GitError.pushFailed(out)',
        stagedLabel: '3 staged files',
        commitPlaceholder: 'feat: keep local commit on push failure',
        btnIdle: 'Commit & Push',
        btnPushing: 'Pushing…',
        btnDone: 'Pushed · main',
      },
      services: {
        panelTitle: 'Services',
        conflictPill: 'Port conflict',
        conflictDetail: ':4770 in use by node (PID 4821)',
        btnStopStart: 'Stop & Start',
        btnStopping: 'Sending SIGTERM…',
        btnRunning: 'Running · :4770',
        scriptDev: 'npm run dev',
        scriptTest: 'make test',
        pinned: 'Pinned',
        readyState: 'Listening',
        idleState: 'Idle',
      },
    },
  },
};
