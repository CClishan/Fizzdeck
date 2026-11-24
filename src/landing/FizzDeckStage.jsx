import React from 'react';
import {
  ChevronDown,
  FileText,
  FolderGit2,
  HardDrive,
  Play,
  RefreshCw,
  Search,
  Server,
  Square,
  Star,
  TerminalSquare,
} from 'lucide-react';
import { Row, Spinner, Stage, Window } from '../stageshow/kit/index.ts';
import fizzDeckLogo from '../assets/fizzdeck-logo.png';
import './fizzdeck-stage.css';

const INITIAL = {
  selected: true,
  starting: false,
  running: false,
  logs: 0,
};

const POSTER = {
  selected: true,
  starting: false,
  running: true,
  logs: 4,
};

async function script(a) {
  await a.wait(900);
  await a.move('launch');
  await a.wait(420);
  await a.click();
  a.mark('starting');
  await a.set({ starting: true, logs: 1 });
  await a.wait(520);
  await a.set({ logs: 2 });
  await a.wait(520);
  await a.set({ logs: 3 });
  await a.wait(480);
  await a.set({ logs: 4 });
  await a.wait(520);
  a.mark('running');
  await a.set({ starting: false, running: true });
  await a.wait(500);
  await a.move('rest');
  await a.wait(500);
  a.mark('payoff');
  await a.wait(1800);
  await a.move('launch');
  await a.wait(420);
  a.mark('stop');
  await a.click();
  await a.set({ running: false, starting: false });
  await a.wait(700);
  await a.set({ logs: 0 });
  await a.wait(700);
  await a.move('rest');
  await a.wait(500);
}

const PROJECTS = [
  {
    name: 'stillframe',
    path: '~/video-tem',
    stack: 'TanStack Start',
    session: 'Codex · 2 分钟前',
    changes: '3 处改动',
    starred: true,
    focal: true,
  },
  {
    name: 'FizzDeck',
    path: '~/dsh-workspace/repo-dashboard',
    stack: 'React + Vite',
    session: 'Claude · 14 分钟前',
    changes: '工作区干净',
  },
  {
    name: 'TapinChina',
    path: '/Volumes/back/TapinChina',
    stack: 'TanStack Start',
    session: 'Codex · 1 小时前',
    changes: '6 处改动',
  },
  {
    name: 'koroo Studio',
    path: '~/Documents/ChatGPT/koroo',
    stack: 'Next.js',
    session: 'Claude · 昨天',
    changes: '工作区干净',
  },
  {
    name: 'pixloading',
    path: '~/pixloading',
    stack: 'Next.js',
    session: 'Codex · 昨天',
    changes: '工作区干净',
  },
  {
    name: 'agents',
    path: '~/agents',
    stack: 'TypeScript',
    session: 'Claude · 3 天前',
    changes: '2 处改动',
  },
];

function Sidebar() {
  return (
    <div className="fzs-side">
      <div className="fzs-brand">
        <img src={fizzDeckLogo} alt="" />
        <span>FizzDeck</span>
        <b>12</b>
      </div>

      <div className="fzs-side-search">
        <Search size={12} strokeWidth={1.8} />
        <span>搜索项目或路径</span>
        <kbd>⌘K</kbd>
      </div>

      <div className="fzs-side-actions">
        <span><FolderGit2 size={12} />添加</span>
        <span><RefreshCw size={12} />重扫</span>
      </div>

      <div className="fzs-side-nav">
        <span data-active><FolderGit2 size={13} />总览</span>
        <span><FileText size={13} />项目墙</span>
      </div>

      <div className="fzs-side-group">产品站</div>
      <SideProject name="stillframe" color="orange" active starred dirty />
      <SideProject name="TapinChina" color="green" dirty />
      <SideProject name="A2O LITE" color="blue" />

      <div className="fzs-side-group">工作区</div>
      <SideProject name="repo-dashboard" color="violet" />
      <SideProject name="koroo Studio" color="amber" />

      <div className="fzs-side-group">其他</div>
      <SideProject name="pixloading" color="blue" />
      <SideProject name="noplan 官网" color="amber" />
      <SideProject name="Cardfun" color="green" />

      <div className="fzs-side-foot">
        <span className="fzs-online-dot" />
        本机 · 无需账号
        <span>6.8 GB</span>
      </div>
    </div>
  );
}

function SideProject({ name, color, active, starred, dirty }) {
  return (
    <div className="fzs-side-project" data-active={active || undefined}>
      <i data-color={color} />
      <span>{name}</span>
      {starred && <Star size={10} fill="currentColor" strokeWidth={1.5} />}
      {dirty && <b />}
    </div>
  );
}

function Metric({ icon: Icon, value, label, note }) {
  return (
    <div className="fzs-metric">
      <div className="fzs-metric-top">
        <Icon size={12} strokeWidth={1.8} />
        <span>{label}</span>
      </div>
      <div className="fzs-metric-value">
        <strong>{value}</strong>
        <small>{note}</small>
      </div>
    </div>
  );
}

function LaunchButton({ starting, running }) {
  return (
    <button
      type="button"
      className="fzs-launch"
      data-cursor="hand"
      data-state={running ? 'running' : starting ? 'starting' : 'idle'}
      tabIndex={-1}
    >
      <span className="fzs-launch-hit" data-target="launch" data-cursor="hand" />
      <span className="fzs-launch-mark">
        <span data-icon="play"><Play size={11} fill="currentColor" strokeWidth={1.4} /></span>
        <span data-icon="spinner"><Spinner size={11} /></span>
        <span data-icon="stop"><Square size={9} fill="currentColor" strokeWidth={1.2} /></span>
      </span>
      <span className="fzs-launch-label">
        <span data-on={!starting && !running || undefined}>启动服务</span>
        <span data-on={starting || undefined}>正在启动</span>
        <span data-on={running || undefined}>停止服务</span>
      </span>
    </button>
  );
}

function ProjectRow({ project, state }) {
  const focal = project.focal;
  const selected = focal && state.selected;
  return (
    <Row
      className="fzs-project"
      pad={10}
      selected={selected}
      lead={
        <span className="fzs-folder" data-focal={focal || undefined}>
          <FolderGit2 size={15} strokeWidth={1.6} />
        </span>
      }
      title={
        <span className="fzs-project-name">
          {project.name}
          {project.starred && <Star size={10} fill="currentColor" strokeWidth={1.5} />}
        </span>
      }
      subtitle={
        <span className="fzs-project-meta">
          <span>{project.path}</span>
          <i>·</i>
          <span>{project.stack}</span>
          <i>·</i>
          <span>{project.session}</span>
        </span>
      }
      meta={<span className="fzs-change-count" data-clean={project.changes === '工作区干净' || undefined}>{project.changes}</span>}
    >
      <span className="fzs-row-actions">
        {focal
          ? <LaunchButton starting={state.starting} running={state.running} />
          : <ChevronDown className="fzs-row-more" size={13} aria-hidden="true" />}
      </span>
    </Row>
  );
}

function DevServer({ logs, running, starting }) {
  return (
    <div className="fzs-terminal">
      <div className="fzs-terminal-head">
        <span className="fzs-terminal-title">
          <TerminalSquare size={12} strokeWidth={1.7} />
          dev server
        </span>
        <span className="fzs-terminal-state" data-state={running ? 'running' : starting ? 'starting' : 'idle'}>
          <i />
          <span data-on={!starting && !running || undefined}>未运行</span>
          <span data-on={starting || undefined}>启动中</span>
          <span data-on={running || undefined}>运行中</span>
        </span>
      </div>
      <div className="fzs-log-grid">
        <span className="fzs-log-line" data-in={logs >= 1 || undefined}>
          <b>❯</b> npm run dev
        </span>
        <span className="fzs-log-line" data-in={logs >= 2 || undefined}>
          <em>▲</em> VITE v8.3.4
        </span>
        <span className="fzs-log-line" data-in={logs >= 3 || undefined}>
          <i>➜&nbsp; Local:</i> <span className="fzs-url">http://localhost:4317</span>
        </span>
        <span className="fzs-log-line fzs-log-ready" data-in={logs >= 4 || undefined}>
          <i>✓</i> Ready in 428 ms
        </span>
      </div>
    </div>
  );
}

export function FizzDeckStage() {
  return (
    <Stage
      className="fzs"
      width={1060}
      height={570}
      compact={{ below: 900, width: 358, height: 350 }}
      initial={INITIAL}
      poster={POSTER}
      script={script}
      fidelity="realistic"
      greys="warm"
      accent="#d95f36"
      cursor={{ at: 'rest', idle: false }}
    >
      {(state, _rect, layout) => {
        const compact = layout === 'compact';
        return (
          <>
            <Window
              className="fzs-window"
              title="所有项目"
              sidebar={compact ? undefined : <Sidebar />}
              sidebarWidth={180}
              aria-hidden="true"
              lead={<span className="fzs-headcount">12 个项目 · 3 个正在运行</span>}
              toolbar={
                <>
                  <button type="button" className="fzs-toolbar-button" tabIndex={-1}>
                    <RefreshCw size={11} strokeWidth={1.8} />
                    扫描文件夹
                  </button>
                  <span className="fzs-toolbar-local">
                    <i />
                    本机
                  </span>
                </>
              }
            >
              <div className="fzs-main">
                <div className="fzs-metrics">
                  <Metric icon={FolderGit2} value="12" label="项目" note="2 个新增" />
                  <Metric icon={Server} value="3" label="服务" note="全部本机" />
                  <Metric icon={TerminalSquare} value="4" label="AI 会话" note="Codex · Claude" />
                  <Metric icon={HardDrive} value="6.8 GB" label="可回收" note="依赖与缓存" />
                </div>

                <div className="fzs-list-head">
                  <span>项目</span>
                  <span>工作区</span>
                </div>

                <div className="fzs-projects">
                  {PROJECTS.map((project) => (
                    <div className="fzs-project-wrap" key={project.name}>
                      <ProjectRow project={project} state={state} />
                      {project.focal && <DevServer logs={state.logs} running={state.running} starting={state.starting} />}
                    </div>
                  ))}
                </div>
              </div>
            </Window>
        <span className="fzs-rest" data-target="rest" />
          </>
        );
      }}
    </Stage>
  );
}
