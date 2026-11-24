import React, { useEffect, useRef, useState } from 'react';
import {
  ArrowRight,
  ArrowUpRight,
  Check,
  ChevronRight,
  Copy,
  FileText,
  FolderGit2,
  GitBranch,
  Globe,
  HardDrive,
  LayoutGrid,
  Lock,
  Monitor,
  ScanLine,
  Server,
  ShieldCheck,
  TerminalSquare,
} from 'lucide-react';
import fizzDeckLogo from '../assets/fizzdeck-logo.png';
import { FizzDeckStage } from './FizzDeckStage.jsx';
import './landing.css';

const REPO_URL = 'https://github.com/CClishan/Fizzdeck';
const CLONE = 'git clone https://github.com/CClishan/Fizzdeck.git';

const VIEWS = [
  {
    id: 'projects',
    icon: LayoutGrid,
    name: '项目总览',
    note: '哪些有改动，哪些正在运行',
  },
  {
    id: 'git',
    icon: GitBranch,
    name: 'Git 改动',
    note: '分支、未提交文件和最近提交',
  },
  {
    id: 'sessions',
    icon: TerminalSquare,
    name: 'AI 会话',
    note: '接回 Codex 与 Claude Code',
  },
  {
    id: 'disk',
    icon: HardDrive,
    name: '清理磁盘',
    note: '依赖、缓存和可回收空间',
  },
];

function GitHubMark({ size = 15 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 .7a11.5 11.5 0 0 0-3.6 22.4c.6.1.8-.3.8-.6v-2.2c-3.4.7-4.2-1.4-4.2-1.4-.5-1.4-1.3-1.7-1.3-1.7-1.1-.8.1-.8.1-.8 1.2.1 1.8 1.2 1.8 1.2 1 1.7 2.6 1.2 3.3.9.1-.7.4-1.2.8-1.5-2.7-.3-5.5-1.4-5.5-6.1 0-1.3.5-2.4 1.3-3.3-.1-.3-.6-1.6.1-3.3 0 0 1-.3 3.4 1.3a11.7 11.7 0 0 1 6.2 0c2.3-1.6 3.3-1.3 3.3-1.3.7 1.7.3 3 .1 3.3.9.9 1.3 2 1.3 3.3 0 4.7-2.8 5.8-5.5 6.1.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A11.5 11.5 0 0 0 12 .7Z" />
    </svg>
  );
}

function Command({ value = CLONE, onDark = false }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef(0);

  useEffect(() => () => window.clearTimeout(timer.current), []);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      window.clearTimeout(timer.current);
      timer.current = window.setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  };

  return (
    <span className="command" data-on-dark={onDark || undefined}>
      <code>
        <span className="command-prompt" aria-hidden="true">$&nbsp;</span>
        <CommandValue value={value} />
      </code>
      <button type="button" onClick={copy} aria-label={copied ? '已复制命令' : '复制命令'}>
        {copied ? <Check size={13} /> : <Copy size={13} />}
        {copied ? '已复制' : '复制'}
      </button>
    </span>
  );
}

function CommandValue({ value }) {
  const split = value.lastIndexOf(' ');
  if (split < 0) return value;

  const chunks = value.slice(split + 1).split('/');
  return (
    <>
      {value.slice(0, split + 1)}
      <span className="command-url">
        {chunks.map((chunk, index) => (
          <React.Fragment key={index}>
            {index > 0 && '/'}
            {index > 2 && <wbr />}
            {chunk}
          </React.Fragment>
        ))}
      </span>
    </>
  );
}

function Header() {
  return (
    <header className="site-header">
      <div className="shell header-row">
        <a className="brand" href="#top" aria-label="FizzDeck 首页">
          <img src={fizzDeckLogo} alt="" />
          <span>FizzDeck</span>
          <em>本地项目看板</em>
        </a>
        <nav className="site-nav" aria-label="主导航">
          <a href="#workflow">视图</a>
          <a href="#native">原生版</a>
          <a href="#local">本地优先</a>
        </nav>
        <div className="header-actions">
          <a className="header-quiet" href="#start">从源码开始</a>
          <a className="header-github" href={REPO_URL} target="_blank" rel="noreferrer">
            <GitHubMark />
            GitHub
          </a>
        </div>
      </div>
    </header>
  );
}

function Hero() {
  return (
    <>
      <section className="hero shell">
        <p className="kicker"><span />本地优先 · macOS 项目工作台</p>
        <h1>
          项目、改动和会话，
          <br />
          收进一个<span>本地看板</span>。
        </h1>
        <p className="hero-lead">
          FizzDeck 扫描你选择的文件夹，识别仓库、Git 改动、AI 会话和开发服务。
          不用登录，不上传项目数据，所有状态都留在你的 Mac 上。
        </p>
        <div className="hero-actions">
          <Command />
          <a className="text-link" href="#workflow">
            看看它怎么工作
            <ArrowRight size={14} />
          </a>
        </div>
        <p className="hero-note">macOS 26+ · Node.js 22+ · 从源码本地运行</p>
        <div className="tech-row" aria-label="支持的技术栈">
          <span className="tech-label">适配</span>
          <span className="tech" style={{ '--tone': '#7a7f92' }}>macOS</span>
          <span className="tech" style={{ '--tone': '#e06732' }}>SwiftUI</span>
          <span className="tech" style={{ '--tone': '#5c8f52' }}>Node.js</span>
          <span className="tech" style={{ '--tone': '#5980c2' }}>React</span>
          <span className="tech" style={{ '--tone': '#9270b3' }}>Codex</span>
          <span className="tech" style={{ '--tone': '#a48255' }}>Claude Code</span>
          <span className="tech" style={{ '--tone': '#66707a' }}>Git</span>
        </div>
      </section>

      <section className="hero-stage shell" aria-label="FizzDeck 界面演示">
        <div
          className="stage-figure"
          role="img"
          aria-label="FizzDeck 看板循环演示：在 stillframe 项目上启动本地开发服务，查看日志与状态变化"
        >
          <FizzDeckStage />
        </div>
        <div className="stage-caption">
          <span><i />循环演示 · 启动 stillframe 的本地服务</span>
          <span>产品界面示意 · 数据仅用于演示</span>
        </div>
      </section>
    </>
  );
}

function SectionIntro({ label, title, copy, wide = false }) {
  return (
    <div className="section-intro" data-wide={wide || undefined}>
      <div>
        <p className="section-label">{label}</p>
        <h2>{title}</h2>
      </div>
      <p className="section-copy">{copy}</p>
    </div>
  );
}

function Anatomy() {
  return (
    <section className="section shell" id="what">
      <SectionIntro
        label="本地扫描"
        title={<>项目不用搬家，<br />状态自己找上门。</>}
        copy="你只需要选择文件夹。FizzDeck 从目录结构、package.json、.git 和本地会话索引里读取状态，不复制源代码，也不建立另一份项目库。"
      />

      <div className="anatomy-row">
        <div className="tree-card" data-reveal>
          <div className="tree-head">
            <span><FolderGit2 size={14} />你的磁盘</span>
            <em>只读</em>
          </div>
          <pre className="file-tree">
            <span className="tree-root">/Users/you</span>{'\n'}
            <span className="tree-branch">├─</span> <span className="tree-dir">Projects/</span>{'\n'}
            <span className="tree-branch">│  ├─</span> <span className="tree-dir">stillframe/</span>{'\n'}
            <span className="tree-branch">│  ├─</span> <span className="tree-dir">TapinChina/</span>{'\n'}
            <span className="tree-branch">│  └─</span> <span className="tree-dir">koroo/</span>{'\n'}
            <span className="tree-branch">├─</span> <span className="tree-dir">.repodeck/</span>{'\n'}
            <span className="tree-branch">│  ├─</span> <span className="tree-file">roots.json</span>{'\n'}
            <span className="tree-branch">│  ├─</span> <span className="tree-file">state.json</span>{'\n'}
            <span className="tree-branch">│  └─</span> <span className="tree-file">logs/</span>{'\n'}
            <span className="tree-branch">├─</span> <span className="tree-dir">.codex/sessions/</span>{'\n'}
            <span className="tree-branch">└─</span> <span className="tree-dir">.claude/projects/</span>
          </pre>
          <div className="tree-foot">
            <Lock size={12} />
            不上传项目文件
          </div>
        </div>

        <div className="anatomy-arrow" aria-hidden="true">
          <span>本地读取</span>
          <i />
          <b>→</b>
        </div>

        <div className="discovery-card" data-reveal>
          <div className="discovery-head">
            <span><ScanLine size={14} />扫描结果</span>
            <em>刚刚</em>
          </div>
          <div className="discovery-grid">
            <DiscoveryStat icon={FolderGit2} value="12" label="个项目" note="Git · Node · Go" />
            <DiscoveryStat icon={TerminalSquare} value="4" label="个 AI 会话" note="Codex · Claude" />
            <DiscoveryStat icon={Server} value="3" label="个服务" note="只在 localhost" />
            <DiscoveryStat icon={HardDrive} value="6.8 GB" label="可回收" note="依赖与缓存" />
          </div>
          <div className="discovery-foot">
            <span className="mini-status"><i />3 个正在运行</span>
            <span>扫描耗时 1.2s</span>
          </div>
        </div>
      </div>

      <div className="fact-grid">
        <article data-reveal>
          <span className="fact-index">01</span>
          <h3>原地识别</h3>
          <p>项目留在原来的文件夹。FizzDeck 只记录路径和元数据，不接管你的仓库。</p>
        </article>
        <article data-reveal>
          <span className="fact-index">02</span>
          <h3>会话能接回来</h3>
          <p>匹配 Codex 和 Claude Code 的本地会话，生成恢复命令，不用回忆上次做到哪。</p>
        </article>
        <article data-reveal>
          <span className="fact-index">03</span>
          <h3>两端同一份状态</h3>
          <p>原生 app 和 Web UI 共用 <code>~/.repodeck</code>，切换客户端不需要导入导出。</p>
        </article>
      </div>
    </section>
  );
}

function DiscoveryStat({ icon: Icon, value, label, note }) {
  return (
    <div className="discovery-stat">
      <span className="discovery-icon"><Icon size={15} /></span>
      <div>
        <strong>{value}</strong>
        <span>{label}</span>
      </div>
      <small>{note}</small>
    </div>
  );
}

function ProjectRowMini({ name, meta, state, stateText, tone }) {
  return (
    <div className="surface-project-row">
      <span className="surface-folder" data-tone={tone}><FolderGit2 size={13} /></span>
      <span className="surface-project-copy">
        <b>{name}</b>
        <small>{meta}</small>
      </span>
      <span className="surface-status" data-state={state}>{stateText}</span>
    </div>
  );
}

function OverviewPreview() {
  return (
    <div className="surface-body">
      <div className="surface-head">
        <div>
          <span className="surface-kicker">所有项目</span>
          <div className="surface-title">今天要打开哪一个？</div>
        </div>
        <span className="surface-segmented"><i data-on />总览<i />列表</span>
      </div>
      <div className="surface-stats">
        <div><span>项目</span><strong>12</strong><small>2 个新增</small></div>
        <div><span>有改动</span><strong>4</strong><small>9 个文件</small></div>
        <div><span>运行中</span><strong>3</strong><small>本机端口</small></div>
      </div>
      <div className="surface-projects">
        <ProjectRowMini name="stillframe" meta="~/video-tem · TanStack Start · Codex 2 分钟前" state="running" stateText="运行中" tone="orange" />
        <ProjectRowMini name="TapinChina" meta="/Volumes/back/TapinChina · 6 处改动" state="idle" stateText="未运行" tone="green" />
        <ProjectRowMini name="repo-dashboard" meta="~/dsh-workspace/repo-dashboard · 工作区干净" state="idle" stateText="未运行" tone="violet" />
        <ProjectRowMini name="koroo Studio" meta="~/Documents/ChatGPT/koroo · Claude 昨天" state="done" stateText="已通过" tone="amber" />
      </div>
    </div>
  );
}

function GitPreview() {
  return (
    <div className="surface-body">
      <div className="surface-head">
        <div>
          <span className="surface-kicker">repo-dashboard</span>
          <div className="surface-title">Git 工作区</div>
        </div>
        <span className="branch-pill"><GitBranch size={12} />main</span>
      </div>
      <div className="git-summary">
        <span><i className="dot warn" />3 个文件已修改</span>
        <span>ahead 1</span>
        <span>最近提交 2 分钟前</span>
      </div>
      <div className="git-files">
        <div><b data-kind="M">M</b><code>src/App.jsx</code><span>+18 −4</span></div>
        <div><b data-kind="M">M</b><code>src/index.css</code><span>+32 −9</span></div>
        <div><b data-kind="A">A</b><code>src/landing/</code><span>新目录</span></div>
      </div>
      <div className="git-commit">
        <span className="commit-mark">●</span>
        <div><b>Add local project dashboard</b><small>a41c9e2 · main · L</small></div>
        <button type="button" tabIndex={-1}><Copy size={12} />命令</button>
      </div>
      <div className="surface-footnote"><ShieldCheck size={12} />有未提交改动时，FizzDeck 不会替你切分支。</div>
    </div>
  );
}

function SessionsPreview() {
  return (
    <div className="surface-body">
      <div className="surface-head">
        <div>
          <span className="surface-kicker">本机会话索引</span>
          <div className="surface-title">上次做到哪，这里接着。</div>
        </div>
        <span className="surface-count">4 个会话</span>
      </div>
      <div className="session-cards">
        <div className="session-card">
          <div className="session-top"><span className="tool-badge" data-tool="codex">Codex</span><span>2 分钟前</span></div>
          <p>把落地页主视觉改成可播放的项目看板，保留现有颜色变量。</p>
          <code>codex resume 019c…</code>
        </div>
        <div className="session-card">
          <div className="session-top"><span className="tool-badge" data-tool="claude">Claude</span><span>昨天 23:40</span></div>
          <p>清理分支前先确认未提交改动，不要动用户正在编辑的文件。</p>
          <code>claude --resume 7d02…</code>
        </div>
      </div>
      <div className="surface-footnote"><TerminalSquare size={12} />只读取会话元数据，复制命令后在终端恢复。</div>
    </div>
  );
}

function DiskPreview() {
  return (
    <div className="surface-body">
      <div className="surface-head">
        <div>
          <span className="surface-kicker">可回收空间</span>
          <div className="surface-title disk-total">6.8 GB</div>
        </div>
        <span className="surface-segmented"><i data-on />依赖<i />构建<i />归档</span>
      </div>
      <div className="disk-strip" aria-hidden="true">
        <span data-tone="a" />
        <span data-tone="b" />
        <span data-tone="c" />
        <span data-tone="d" />
      </div>
      <div className="disk-rows">
        <div><span>依赖目录</span><i><b data-tone="a" /></i><strong>3.1 GB</strong></div>
        <div><span>构建缓存</span><i><b data-tone="b" /></i><strong>1.9 GB</strong></div>
        <div><span>历史产物</span><i><b data-tone="c" /></i><strong>1.2 GB</strong></div>
        <div><span>临时文件</span><i><b data-tone="d" /></i><strong>0.6 GB</strong></div>
      </div>
      <div className="surface-footnote"><ShieldCheck size={12} />只生成清理命令；永久删除前先备份到本地。</div>
    </div>
  );
}

function SurfacePreview({ active }) {
  return (
    <div className="surface-panel">
      <div className="surface-topbar">
        <span className="surface-live"><i />LOCAL</span>
        <span className="surface-path">FizzDeck / {VIEWS.find((view) => view.id === active)?.name}</span>
        <span className="surface-window-actions" aria-hidden="true"><i /><i /><i /></span>
      </div>
      <div className="surface-content" key={active}>
        {active === 'projects' && <OverviewPreview />}
        {active === 'git' && <GitPreview />}
        {active === 'sessions' && <SessionsPreview />}
        {active === 'disk' && <DiskPreview />}
      </div>
    </div>
  );
}

function Views() {
  const [active, setActive] = useState('projects');
  return (
    <section className="section shell views" id="workflow">
      <SectionIntro
        label="四个视图"
        title={<>从项目列表，<br />到该做的那一步。</>}
        copy="不用在终端、Finder 和编辑器之间来回找。选中一个项目，改动、会话、服务和可清理空间都在同一页。"
      />
      <div className="views-grid">
        <div className="view-nav" role="tablist" aria-label="FizzDeck 功能视图">
          {VIEWS.map(({ id, icon: Icon, name, note }) => (
            <button
              type="button"
              key={id}
              id={`view-tab-${id}`}
              role="tab"
              aria-selected={active === id}
              aria-controls="surface-panel"
              data-active={active === id || undefined}
              onClick={() => setActive(id)}
            >
              <span className="view-icon"><Icon size={16} /></span>
              <span className="view-copy"><b>{name}</b><small>{note}</small></span>
              <ChevronRight size={15} />
            </button>
          ))}
        </div>
        <div
          className="view-stage"
          id="surface-panel"
          role="tabpanel"
          aria-labelledby={`view-tab-${active}`}
          aria-live="polite"
        >
          <SurfacePreview active={active} />
        </div>
      </div>
    </section>
  );
}

function Native() {
  return (
    <section className="section shell native" id="native">
      <div className="native-copy" data-reveal>
        <p className="section-label">两种形态</p>
        <h2>原生优先，<br />网页补充。</h2>
        <p className="section-copy">
          日常使用打开 SwiftUI 原生 app；需要浏览器或清理项目时，再用本地 Web UI。
          它们不是两个产品，只是同一份本地状态的两个入口。
        </p>
        <ul className="native-list">
          <li><span><Monitor size={16} /></span><div><b>macOS 原生主客户端</b><p>纯 SwiftUI，不需要 Node.js 运行时，启动更快。</p></div></li>
          <li><span><Globe size={16} /></span><div><b>轻量 Web UI</b><p>一个 Node.js 进程，浏览器里完成清理和破坏性操作。</p></div></li>
          <li><span><HardDrive size={16} /></span><div><b>共享 <code>~/.repodeck</code></b><p>星标、标签、备注和扫描缓存保持一致。</p></div></li>
        </ul>
        <a className="text-link" href={`${REPO_URL}#quick-start`} target="_blank" rel="noreferrer">
          查看构建方式
          <ArrowUpRight size={14} />
        </a>
      </div>

      <div className="native-diagram" data-reveal>
        <div className="client-node" data-kind="native">
          <span className="client-icon"><Monitor size={20} /></span>
          <div>
            <b>FizzDeck.app</b>
            <small>SwiftUI · 原生窗口</small>
          </div>
          <span className="client-state"><i />主客户端</span>
        </div>
        <div className="state-bridge">
          <span>共享本地状态</span>
          <code>~/.repodeck</code>
          <i />
        </div>
        <div className="client-node" data-kind="web">
          <span className="client-icon"><Globe size={20} /></span>
          <div>
            <b>FizzDeck Web UI</b>
            <small>Node.js · React</small>
          </div>
          <span className="client-state"><i />浏览器</span>
        </div>
        <div className="native-side-note">
          <TerminalSquare size={15} />
          <code>node start.mjs</code>
          <span>→ 127.0.0.1:4770</span>
        </div>
      </div>
    </section>
  );
}

function BoundaryRow({ icon: Icon, title, body, code }) {
  return (
    <div className="boundary-row">
      <span className="boundary-icon"><Icon size={16} /></span>
      <div>
        <b>{title}</b>
        <p>{body}</p>
      </div>
      {code && <code>{code}</code>}
    </div>
  );
}

function LocalFirst() {
  return (
    <section className="local-first" id="local">
      <div className="shell local-grid">
        <div className="local-copy" data-reveal>
          <p className="section-label">本地边界</p>
          <h2>没有账号，<br />也没有云端副本。</h2>
          <p className="section-copy">
            FizzDeck 不调用自己托管的服务。项目数据、会话索引和扫描缓存都在本机，
            网络请求只来自你主动执行的 Git 或开发命令。
          </p>
          <div className="local-pill">
            <Lock size={14} />
            <span>服务只监听</span>
            <code>127.0.0.1</code>
          </div>
          <p className="local-fine">
            原生 app 不是沙盒应用。它需要访问你主动选择的目录，并运行该目录里的项目脚本。
            只添加你信任的文件夹。
          </p>
        </div>
        <div className="boundary-panel" data-reveal>
          <div className="boundary-head">
            <span><ShieldCheck size={15} />本机安全边界</span>
            <em>server.mjs</em>
          </div>
          <BoundaryRow
            icon={Globe}
            title="只接受本机来源"
            body="监听 127.0.0.1，并拒绝非本地 Origin。"
            code="127.0.0.1"
          />
          <BoundaryRow
            icon={FolderGit2}
            title="动作限定在受管目录"
            body="启动、停止和清理只对已添加的项目生效。"
            code="roots.json"
          />
          <BoundaryRow
            icon={TerminalSquare}
            title="清理只生成命令"
            body="不会自动执行依赖或构建产物删除。"
            code="copy-only"
          />
          <BoundaryRow
            icon={HardDrive}
            title="永久删除先做备份"
            body="需要输入目录名确认，副本留在本地回收目录。"
            code="~/.repodeck/trash"
          />
          <div className="boundary-foot">
            <span className="mini-status"><i />no telemetry</span>
            <span>无需账号</span>
            <span>无托管后端</span>
          </div>
        </div>
      </div>
    </section>
  );
}

function CTA() {
  return (
    <section className="shell cta-section" id="start">
      <div className="cta-card">
        <div className="cta-copy" data-reveal>
          <p className="section-label">从源码开始</p>
          <h2>从一个文件夹开始。</h2>
          <p>
            克隆仓库，构建原生 app 或启动本地 Web UI。
            第一次打开后，选择你要管理的项目文件夹。
          </p>
          <span className="cta-requirements">macOS 26+ · Xcode 26+ · Node.js 22+</span>
        </div>
        <div className="cta-actions" data-reveal>
          <Command onDark />
          <a className="cta-github" href={REPO_URL} target="_blank" rel="noreferrer">
            <GitHubMark size={16} />
            在 GitHub 查看
            <ArrowUpRight size={14} />
          </a>
          <span className="cta-fine">当前需要自行构建，原生 app 尚未签名或公证。</span>
        </div>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="site-footer">
      <div className="shell footer-row">
        <span className="footer-brand"><img src={fizzDeckLogo} alt="" />FizzDeck</span>
        <span>本地优先 · 无遥测 · 无账号</span>
        <nav aria-label="页脚">
          <a href={`${REPO_URL}#readme-ov-file`} target="_blank" rel="noreferrer">文档</a>
          <a href={`${REPO_URL}/issues`} target="_blank" rel="noreferrer">反馈</a>
          <a href={REPO_URL} target="_blank" rel="noreferrer">GitHub</a>
        </nav>
        <span>© 2026 FizzDeck</span>
      </div>
    </footer>
  );
}

export function Landing() {
  useEffect(() => {
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const nodes = [...document.querySelectorAll('[data-reveal]')];
    if (reduced || !('IntersectionObserver' in window)) {
      nodes.forEach((node) => node.setAttribute('data-in', ''));
      return undefined;
    }
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.setAttribute('data-in', '');
        observer.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.08 });
    nodes.forEach((node) => observer.observe(node));
    return () => observer.disconnect();
  }, []);

  return (
    <div id="top" className="landing">
      <a className="skip-link" href="#main">跳到主要内容</a>
      <Header />
      <main id="main">
        <Hero />
        <Anatomy />
        <Views />
        <Native />
        <LocalFirst />
        <CTA />
      </main>
      <Footer />
    </div>
  );
}
