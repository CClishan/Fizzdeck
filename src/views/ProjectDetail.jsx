import React, { useEffect, useMemo, useState } from 'react';
import {
  Activity, AlertCircle, Archive, ArrowUpRight, Check, ChevronDown, ChevronLeft,
  CircleCheck, Clipboard, Clock, Code2, Copy, ExternalLink, FileText, FolderOpen,
  GitBranch, Globe, HardDrive, History, MessageCircle, MoreHorizontal, Play, RefreshCw,
  Server, ShieldCheck, Square, Star, Terminal, Trash2, X,
} from 'lucide-react';
import { BadgeIcon, EmptyState, Panel, Spinner, StatCard, ToolBadge, ToolIcon } from '@/components/Fizz.jsx';
import { api } from '@/lib/api.js';
import {
  fmtBytes, fmtCost, fmtTokens, relativeTime, shortPath, shortTime, splitBytes,
  stripAnsi,
} from '@/lib/format.js';
import { groupTone, stackChipTone, toolTitle } from '@/lib/tool.js';

const TABS = [
  { key: 'overview', label: '概览' },
  { key: 'git', label: '改动' },
  { key: 'docs', label: '文档' },
  { key: 'sessions', label: '会话' },
  { key: 'tests', label: '测试' },
  { key: 'cleanup', label: '清理' },
];

const CLEAN_KIND = {
  deps: { icon: PackageIcon, tone: 'green' },
  build: { icon: WrenchIcon, tone: 'orange' },
  tmp: { icon: Clock, tone: 'red' },
  archive: { icon: Archive, tone: 'violet' },
  default: { icon: FolderOpen, tone: 'secondary' },
};

function PackageIcon(props) {
  return <Archive {...props} />;
}

function WrenchIcon(props) {
  return <HardDrive {...props} />;
}

function toneColor(tone, fallback = 'var(--fizz-secondary)') {
  if (!tone || tone === 'secondary') return fallback;
  return `var(--fizz-${tone})`;
}

function normalizeBars(values) {
  const max = Math.max(...values, 1);
  return values.map((value) => Math.max(0.06, value / max));
}

function emphasis(values) {
  let best = 0;
  for (let index = 1; index < values.length; index += 1) {
    if (values[index] > values[best]) best = index;
  }
  return values[best] > 0 ? best : null;
}

function lastSevenDays(project) {
  const values = [];
  for (let offset = 6; offset >= 0; offset -= 1) {
    const date = new Date();
    date.setDate(date.getDate() - offset);
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    values.push(project.activity?.daily?.[key] || project.weekly?.[key] || 0);
  }
  return values;
}

function sessionDayCounts(project) {
  const values = Array.from({ length: 7 }, () => 0);
  const today = new Date();
  for (const session of project.tool?.recentSessions || []) {
    const date = new Date(session.mtime);
    const days = Math.floor((new Date(today.getFullYear(), today.getMonth(), today.getDate()) - new Date(date.getFullYear(), date.getMonth(), date.getDate())) / 86400000);
    if (days >= 0 && days < 7) values[6 - days] += 1;
  }
  return values;
}

function Hero({ project, running, onCopy, onReveal, onStar, onRemove }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [removal, setRemoval] = useState(null);
  const [confirmName, setConfirmName] = useState('');
  const [remote, setRemote] = useState(null);

  useEffect(() => {
    setRemote(null);
    setMenuOpen(false);
  }, [project.path]);

  const openRemote = remote?.replace(/\.git$/, '').replace(/^git@github\.com:/, 'https://github.com/');
  return (
    <>
      <section className="fizz-hero">
        <BadgeIcon project={project} size={42} framed />
        <div className="fizz-hero-main">
          <div className="fizz-hero-title">
            <h1>{project.displayName}</h1>
            {project.starred ? <Star size={13} fill="var(--fizz-gold)" stroke="none" /> : null}
            {running ? <span className="fizz-chip tone-green compact">运行中</span> : null}
          </div>
          <button type="button" className="fizz-hero-path" onClick={() => onCopy(project.path)} title="复制完整路径">
            <span className="fizz-truncate">{shortPath(project.path)}</span>
            <Copy size={9} />
          </button>
          <div className="fizz-hero-tags">
            <span className="fizz-chip" style={{ color: groupTone(project.group).hex, background: `color-mix(in oklab, ${groupTone(project.group).hex} 12%, transparent)` }}>{project.group}</span>
            {project.branch ? <span className="fizz-chip tone-blue">{project.branch}</span> : null}
            {project.dirtyCount ? <span className="fizz-chip tone-orange">{project.dirtyCount} 个改动</span> : null}
            {project.tool?.lastTool ? <span className="fizz-chip tone-violet">{toolTitle(project.tool.lastTool)}</span> : null}
            {project.test ? <span className="fizz-chip tone-green">{project.test.label}</span> : null}
          </div>
        </div>
        <div className="fizz-hero-actions">
          <div className="fizz-glass">
            <button type="button" onClick={() => onStar(project)} title={project.starred ? '取消星标' : '设为星标'}>
              <Star size={13} fill={project.starred ? 'var(--fizz-gold)' : 'none'} color={project.starred ? 'var(--fizz-gold)' : 'currentColor'} />
            </button>
            <button type="button" onClick={() => onReveal(project)} title="在 Finder 中显示">
              <FolderOpen size={13} />
            </button>
            <div style={{ position: 'relative' }}>
              <button type="button" onClick={() => setMenuOpen(!menuOpen)} title="更多">
                <MoreHorizontal size={14} />
              </button>
              {menuOpen ? (
                <>
                  <div
                    style={{ position: 'fixed', inset: 0, zIndex: 20 }}
                    onClick={() => setMenuOpen(false)}
                  />
                  <div className="fizz-card" style={{ position: 'absolute', right: 0, top: 32, zIndex: 21, width: 218, padding: 5, boxShadow: 'var(--fizz-shadow-floating)' }}>
                    <button type="button" className="fizz-palette-row" onClick={() => { onCopy(project.path); setMenuOpen(false); }}>
                      <Copy size={12} />复制路径
                    </button>
                    <button type="button" className="fizz-palette-row" onClick={() => { onReveal(project); setMenuOpen(false); }}>
                      <FolderOpen size={12} />在 Finder 中显示
                    </button>
                    <button type="button" className="fizz-palette-row" onClick={() => { onCopy(`cd '${project.path}'`); setMenuOpen(false); }}>
                      <Terminal size={12} />复制终端命令
                    </button>
                    <div className="fizz-divider" style={{ margin: '4px 6px' }} />
                    <button type="button" className="fizz-palette-row" onClick={() => { setRemoval('unmanage'); setMenuOpen(false); }}>
                      <X size={12} />从看板移除
                    </button>
                    <button type="button" className="fizz-palette-row" style={{ color: 'var(--fizz-red)' }} onClick={() => { setRemoval('delete-trash'); setMenuOpen(false); }}>
                      <Trash2 size={12} />移入废纸篓…
                    </button>
                    <button type="button" className="fizz-palette-row" style={{ color: 'var(--fizz-red)' }} onClick={() => { setRemoval('delete-permanent'); setMenuOpen(false); }}>
                      <Trash2 size={12} />永久删除…
                    </button>
                  </div>
                </>
              ) : null}
            </div>
          </div>
        </div>
      </section>

      {removal ? (
        <div className="fizz-overlay" onClick={() => setRemoval(null)}>
          <div className="fizz-sheet small" onClick={(event) => event.stopPropagation()}>
            <div className="fizz-sheet-head">
              <div className="fizz-sheet-title">{removal === 'unmanage' ? '从看板移除' : removal === 'delete-trash' ? '移入废纸篓' : '永久删除项目'}</div>
              <button type="button" className="fizz-icon-btn plain" onClick={() => setRemoval(null)}><X size={13} /></button>
            </div>
            <div className="fizz-sheet-body" style={{ padding: 14 }}>
              {removal === 'unmanage' ? (
                <p className="fizz-muted" style={{ margin: 0, lineHeight: 1.6 }}>只从看板移除，不删除磁盘文件。</p>
              ) : (
                <>
                  <p className="fizz-muted" style={{ marginTop: 0, lineHeight: 1.6 }}>
                    输入目录名 <strong className="fizz-mono" style={{ color: 'var(--fizz-text)' }}>{project.name}</strong> 以确认。
                    {removal === 'delete-permanent' ? ' 删除前会先备份到 ~/.repodeck/trash。' : ''}
                  </p>
                  <input className="fizz-input mono" value={confirmName} onChange={(event) => setConfirmName(event.target.value)} placeholder={project.name} />
                </>
              )}
            </div>
            <div className="fizz-sheet-foot">
              <span className="fizz-spacer" />
              <button type="button" className="fizz-btn" onClick={() => setRemoval(null)}>取消</button>
              <button
                type="button"
                className={`fizz-btn ${removal === 'unmanage' ? '' : 'danger'}`}
                disabled={removal !== 'unmanage' && confirmName.trim() !== project.name}
                onClick={() => {
                  onRemove(project, removal, confirmName);
                  setRemoval(null);
                  setConfirmName('');
                }}
              >
                {removal === 'unmanage' ? '移除' : removal === 'delete-trash' ? '移到废纸篓' : '永久删除'}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}

function SummaryPanel({ project }) {
  const hasArtwork = Boolean(project.artwork);
  return (
    <Panel title="项目" icon={Code2}>
      <div style={{ display: 'grid', gridTemplateColumns: hasArtwork ? '176px minmax(0, 1fr) minmax(180px, 0.8fr)' : 'minmax(0, 1.2fr) minmax(180px, 0.8fr)', gap: 18, alignItems: 'start' }}>
        {hasArtwork ? (
          <button
            type="button"
            onClick={() => window.open(`/api/artwork?path=${encodeURIComponent(project.path)}`, '_blank')}
            style={{ display: 'block', padding: 0, border: '1px solid var(--fizz-stroke)', borderRadius: 10, overflow: 'hidden', background: 'var(--fizz-recessed)' }}
            title="打开项目截图"
          >
            <img
              src={`/api/artwork?path=${encodeURIComponent(project.path)}`}
              alt=""
              style={{ display: 'block', width: 176, height: 99, objectFit: 'cover' }}
              onError={(event) => { event.currentTarget.parentElement.style.display = 'none'; }}
            />
          </button>
        ) : null}
        <div>
          <div className="fizz-panel-sub" style={{ marginBottom: 5 }}>项目介绍</div>
          <p style={{ margin: 0, color: project.intro?.text ? 'var(--fizz-text)' : 'var(--fizz-tertiary)', fontSize: 12, lineHeight: 1.55 }}>
            {project.intro?.text || '未找到项目介绍（放一个 PRODUCT.md 或 README.md 即可）'}
          </p>
          {project.intro?.source ? <div className="fizz-panel-sub" style={{ marginTop: 6 }}>— {project.intro.source}</div> : null}
        </div>
        <div>
          <div className="fizz-panel-sub" style={{ marginBottom: 6 }}>技术栈</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5 }}>
            {(project.stack?.groups || []).flatMap((group) => group.items.map((item) => (
              <span key={`${group.key}:${item}`} className={`fizz-chip tone-${stackChipTone(group.key)} compact`}>{item}</span>
            )))}
            {!(project.stack?.groups || []).length ? <span className="fizz-panel-sub">未识别到技术栈</span> : null}
          </div>
        </div>
      </div>
    </Panel>
  );
}

function OverviewTab({ project, running, busy, testRun, detail, onLaunch, onStop, onCopy, onMeta, onTest, toast }) {
  const weekValues = lastSevenDays(project);
  const sessionValues = sessionDayCounts(project);
  const cleanupValues = (project.cleandoc.items || []).slice(0, 7).map((item) => item.bytes);
  const sizeParts = splitBytes(project.size.totalBytes);
  const [note, setNote] = useState(project.note || '');
  const [logs, setLogs] = useState({ dev: null, test: null });
  const [logSource, setLogSource] = useState('dev');
  const [logsOpen, setLogsOpen] = useState(true);
  const [serviceMessage, setServiceMessage] = useState('');

  useEffect(() => {
    setNote(project.note || '');
  }, [project.path, project.note]);

  useEffect(() => {
    let cancelled = false;
    let timer = null;
    const load = async () => {
      try {
        const data = await api.logs(project.path);
        if (cancelled) return;
        setLogs({ dev: data.dev, test: data.test });
        if (!data.dev?.exists && data.test?.exists) setLogSource('test');
        if (running || testRun?.status === 'running') timer = setTimeout(load, 1500);
      } catch {}
    };
    load();
    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
  }, [project.path, running, testRun?.status]);

  const activeLog = logs[logSource] || logs.dev || logs.test;
  const hasLogs = Boolean(logs.dev?.exists || logs.test?.exists || running || testRun?.status === 'running');
  const activity = useMemo(() => {
    const entries = [];
    if (project.lastCommit) {
      entries.push({
        id: `commit:${project.lastCommit.hash}`,
        date: project.lastCommit.date,
        title: project.lastCommit.subject,
        detail: `${project.lastCommit.hash} · 提交`,
        icon: GitBranch,
        tone: 'green',
      });
    }
    for (const session of (project.tool?.recentSessions || []).slice(0, 5)) {
      entries.push({
        id: `session:${session.tool}:${session.id}`,
        date: session.mtime,
        title: session.lastUser || `${toolTitle(session.tool)} 会话`,
        detail: toolTitle(session.tool),
        icon: MessageCircle,
        tone: 'violet',
      });
    }
    return entries.sort((a, b) => new Date(b.date) - new Date(a.date)).slice(0, 7);
  }, [project]);

  const aiDetail = (() => {
    const parts = (project.tool?.detected || []).map(toolTitle);
    if (project.tool?.totalTokens) parts.push(`${fmtTokens(project.tool.totalTokens)} tokens`);
    if (project.tool?.totalCostUSD != null) parts.push(fmtCost(project.tool.totalCostUSD, project.tool.costIsEstimate));
    return parts.length ? parts.join(' · ') : '还没有会话';
  })();

  return (
    <div className="fizz-stack" style={{ gap: 20 }}>
      <SummaryPanel project={project} />

      <div className="fizz-grid fizz-auto-grid fizz-metric-grid">
        <StatCard
          title="本周提交"
          icon={GitBranch}
          tint="var(--fizz-green)"
          value={weekValues.reduce((sum, value) => sum + value, 0)}
          unit="次"
          bars={normalizeBars(weekValues)}
          peak={emphasis(weekValues)}
          detail={project.branch || '无 Git 分支'}
        />
        <StatCard
          title="磁盘占用"
          icon={HardDrive}
          tint="var(--fizz-blue)"
          value={sizeParts.value}
          unit={sizeParts.unit}
          bars={normalizeBars(cleanupValues.length ? cleanupValues : Array.from({ length: 7 }, () => 0))}
          peak={cleanupValues.length ? emphasis(cleanupValues) : null}
          detail={project.cleandoc.items.length ? `可清理 ${fmtBytes(project.cleandoc.reusableBytes)} · ${project.cleandoc.items.length} 个目录` : '没有命中清理规则'}
        />
        <StatCard
          title="AI 会话"
          icon={MessageCircle}
          tint="var(--fizz-violet)"
          value={project.tool?.sessionCount || 0}
          unit="会话"
          bars={normalizeBars(sessionValues)}
          peak={emphasis(sessionValues)}
          detail={aiDetail}
        />
        <StatCard
          title="最近活动"
          icon={Clock}
          tint="var(--fizz-blue)"
          value={relativeTime(project.recent)}
          detail={project.lastCommit?.subject || project.tool?.lastUserMessage || '还没有可识别的活动'}
        />
      </div>

      {project.run || project.test ? (
        <Panel title="服务" icon={Server}>
          <div className="fizz-service-row">
            <span className={`fizz-dot ${running ? 'green' : 'secondary'}`} />
            <div className="fizz-service-main">
              <div className="fizz-service-title">
                dev
                {running ? <span className="fizz-chip tone-green compact">运行中</span> : <span className="fizz-chip compact">未运行</span>}
                {running && project.run?.port ? <span className="fizz-mono fizz-tertiary">:{project.run.port}</span> : null}
              </div>
              <div className="fizz-service-command">{project.run ? `${project.run.command}${project.run.port ? ` · :${project.run.port}` : ''}` : '无 dev 脚本'}</div>
            </div>
            <div className="fizz-service-actions">
              {project.run?.previewUrl && running ? (
                <button type="button" className="fizz-btn small" onClick={() => window.open(project.run.previewUrl, '_blank')}>
                  <Play size={10} />预览
                </button>
              ) : null}
              {running ? (
                <button type="button" className="fizz-btn small ghost" onClick={() => onStop(project)}>
                  <Square size={10} />停止
                </button>
              ) : project.run ? (
                <button type="button" className="fizz-btn small" disabled={busy === 'launch'} onClick={() => onLaunch(project)}>
                  {busy === 'launch' ? <Spinner size={11} /> : <Play size={10} />}
                  {busy === 'launch' ? '启动中' : '启动'}
                </button>
              ) : null}
            </div>
          </div>
          {project.test ? (
            <div className="fizz-service-row">
              <span className={`fizz-dot ${testRun?.status === 'passed' ? 'green' : testRun?.status === 'failed' ? 'red' : testRun?.status === 'running' ? 'orange' : 'secondary'}`} />
              <div className="fizz-service-main">
                <div className="fizz-service-title">
                  test
                  <span className={`fizz-chip compact ${testRun?.status === 'passed' ? 'tone-green' : testRun?.status === 'failed' ? 'tone-red' : 'tone-secondary'}`}>
                    {testRun?.status === 'running' ? '运行中' : testRun?.status === 'passed' ? '通过' : testRun?.status === 'failed' ? '失败' : '未运行'}
                  </span>
                  {testRun?.durationMs ? <span className="fizz-panel-sub">{(testRun.durationMs / 1000).toFixed(1)}s</span> : null}
                </div>
                <div className="fizz-service-command">{project.test.command}</div>
              </div>
              <div className="fizz-service-actions">
                <button type="button" className="fizz-btn small" disabled={testRun?.status === 'running'} onClick={() => onTest(project)}>
                  {testRun?.status === 'running' ? <Spinner size={11} /> : <ShieldCheck size={10} />}
                  {testRun?.status === 'running' ? '测试中' : '运行测试'}
                </button>
              </div>
            </div>
          ) : null}
          {serviceMessage ? <div className="fizz-panel-sub" style={{ marginTop: 6 }}>{serviceMessage}</div> : null}
        </Panel>
      ) : null}

      <div className="fizz-activity-layout">
        {hasLogs ? (
          <Panel
            title="日志"
            icon={Terminal}
            action={(
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                {logs.dev?.exists && logs.test?.exists ? (
                  <div className="fizz-seg">
                    <button type="button" className={logSource === 'dev' ? 'is-active' : ''} onClick={() => setLogSource('dev')}>dev</button>
                    <button type="button" className={logSource === 'test' ? 'is-active' : ''} onClick={() => setLogSource('test')}>test</button>
                  </div>
                ) : null}
                <button type="button" className="fizz-icon-btn plain" title="复制日志路径" onClick={() => onCopy(`~/.repodeck/logs/${project.name}.log`)}><Clipboard size={12} /></button>
                <button type="button" className="fizz-icon-btn plain" title={logsOpen ? '收起' : '展开'} onClick={() => setLogsOpen(!logsOpen)}><ChevronDown size={12} style={{ transform: logsOpen ? 'none' : 'rotate(-90deg)' }} /></button>
              </div>
            )}
          >
            {logsOpen ? (
              <pre className="fizz-log">{stripAnsi(activeLog?.text) || (running ? '服务运行中，等待日志…' : '暂无日志')}</pre>
            ) : null}
          </Panel>
        ) : null}

        <Panel title="最近活动" icon={History}>
          {activity.length ? activity.map((entry, index) => {
            const Icon = entry.icon;
            return (
              <div key={entry.id}>
                <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10, padding: '8px 0' }}>
                  <Icon size={12} style={{ color: toneColor(entry.tone), marginTop: 2, flex: '0 0 auto' }} />
                  <div style={{ minWidth: 0, flex: 1 }}>
                    <div style={{ fontSize: 11.5, lineHeight: 1.4 }} className="fizz-line-2">{entry.title}</div>
                    <div className="fizz-panel-sub" style={{ marginTop: 1 }}>{entry.detail}</div>
                  </div>
                  <span className="fizz-panel-sub" style={{ flex: '0 0 auto' }}>{relativeTime(entry.date)}</span>
                </div>
                {index < activity.length - 1 ? <div className="fizz-divider" /> : null}
              </div>
            );
          }) : <div className="fizz-panel-sub">还没有可识别的活动</div>}
        </Panel>
      </div>

      <section className="fizz-card" style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 16px' }}>
        <MessageCircle size={12} className="fizz-muted" />
        <strong style={{ fontSize: 12, fontWeight: 600 }}>备注</strong>
        <input
          className="fizz-input"
          style={{ height: 26, background: 'transparent', borderColor: 'transparent', flex: 1 }}
          maxLength={200}
          value={note}
          onChange={(event) => setNote(event.target.value)}
          onBlur={() => note !== project.note && onMeta(project, { note })}
          onKeyDown={(event) => {
            if (event.key === 'Enter') {
              event.preventDefault();
              onMeta(project, { note });
            }
          }}
          placeholder="给这个项目留一句话"
        />
        <span className="fizz-panel-sub fizz-mono">{note.length}/200</span>
        <button type="button" className="fizz-btn small" onClick={() => onMeta(project, { note })}><Check size={11} />保存</button>
      </section>
    </div>
  );
}

function GitTab({ project, detail, loading, onCopy, onFetch, onCheckout, toast }) {
  if (loading) {
    return <div className="fizz-empty"><Spinner size={20} /></div>;
  }
  const git = detail?.git;
  if (!git) {
    return <EmptyState icon={GitBranch} title="不是 Git 仓库" detail="这个目录没有 .git，仍可在概览里查看体积和文件信息。" />;
  }
  return (
    <div className="fizz-stack" style={{ gap: 20 }}>
      <Panel
        title="状态"
        icon={GitBranch}
        action={(
          <div style={{ display: 'flex', gap: 5 }}>
            <button type="button" className="fizz-btn small" onClick={() => onFetch(project)}><RefreshCw size={10} />同步远程</button>
            <button type="button" className="fizz-btn small ghost" onClick={() => onCopy(`cd '${project.path}' && git status`)}><Copy size={10} /></button>
          </div>
        )}
      >
        <dl className="fizz-kv">
          <dt>当前分支</dt><dd className="fizz-mono">{git.branch || project.branch || '—'}</dd>
          <dt>未提交</dt><dd style={{ color: git.changedCount ? 'var(--fizz-orange)' : undefined }}>{git.changedCount ?? 0} 个改动</dd>
          <dt>领先 / 落后</dt><dd className="fizz-mono">↑ {git.ahead ?? 0}　↓ {git.behind ?? 0}</dd>
          <dt>Stash</dt><dd>{git.stashCount ?? 0}</dd>
          <dt>最近标签</dt><dd className="fizz-mono">{git.lastTag || '—'}</dd>
          <dt>分支数</dt><dd>{git.branches?.length || 0}</dd>
        </dl>
        {git.remote ? (
          <>
            <div className="fizz-divider" style={{ margin: '12px 0' }} />
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span className="fizz-panel-sub">远程</span>
              <span className="fizz-spacer" />
              <button type="button" className="fizz-icon-btn plain" title="复制远程地址" onClick={() => onCopy(git.remote)}><Copy size={11} /></button>
              <a
                href={git.remote.replace(/\.git$/, '').replace(/^git@github\.com:/, 'https://github.com/')}
                target="_blank"
                rel="noreferrer"
                className="fizz-icon-btn plain"
                title="在浏览器中打开远程仓库"
              ><ArrowUpRight size={11} /></a>
            </div>
            <div className="fizz-mono fizz-muted fizz-line-2" style={{ marginTop: 4 }}>{git.remote}</div>
          </>
        ) : null}
      </Panel>

      <Panel title="改动文件" icon={FileText} action={<span className="fizz-panel-sub">{git.files?.length || 0} 个</span>}>
        {git.files?.length ? (
          <div style={{ maxHeight: 320, overflowY: 'auto' }}>
            {git.files.map((file) => (
              <div key={file.path} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '5px 0', borderTop: '1px solid var(--fizz-hairline)' }}>
                <span className={`fizz-chip compact ${file.untracked ? 'tone-orange' : 'tone-blue'}`} style={{ minWidth: 30, justifyContent: 'center', fontFamily: 'var(--font-mono)' }}>{file.code}</span>
                <span className="fizz-mono fizz-muted fizz-truncate" style={{ flex: 1 }}>{file.path}</span>
              </div>
            ))}
          </div>
        ) : <div className="fizz-chip tone-green" style={{ alignSelf: 'flex-start' }}><CircleCheck size={11} />工作区干净</div>}
      </Panel>

      <Panel title="分支" icon={GitBranch} action={<span className="fizz-panel-sub">{git.branches?.length || 0} 个</span>}>
        <div style={{ maxHeight: 280, overflowY: 'auto' }}>
          {git.branches?.map((branch) => (
            <div key={branch.name} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '5px 0', borderTop: '1px solid var(--fizz-hairline)' }}>
              <GitBranch size={12} style={{ color: branch.name === project.branch ? 'var(--fizz-accent)' : 'var(--fizz-tertiary)' }} />
              <span className="fizz-mono" style={{ flex: 1 }}>{branch.name}</span>
              <span className="fizz-panel-sub">{relativeTime(branch.date)}</span>
              {branch.name !== project.branch ? (
                <button
                  type="button"
                  className="fizz-btn small ghost"
                  onClick={() => {
                    if (window.confirm(`切换到分支 ${branch.name}？`)) onCheckout(project, branch.name);
                  }}
                >切换</button>
              ) : null}
            </div>
          ))}
        </div>
      </Panel>

      <Panel title="最近提交" icon={History} action={<span className="fizz-panel-sub">{detail.commits?.length || 0} 次</span>}>
        <div style={{ maxHeight: 420, overflowY: 'auto' }}>
          {(detail.commits || []).map((commit) => (
            <div key={commit.full} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 0', borderTop: '1px solid var(--fizz-hairline)' }}>
              <span className="fizz-mono fizz-tertiary">{commit.hash}</span>
              <span className="fizz-truncate" style={{ flex: 1 }}>{commit.subject}</span>
              <span className="fizz-panel-sub">{commit.author}</span>
              <span className="fizz-panel-sub">{relativeTime(commit.date)}</span>
            </div>
          ))}
        </div>
      </Panel>
    </div>
  );
}

function DocsTab({ project, docs, onCopy, onReveal }) {
  const [selected, setSelected] = useState(docs?.[0]?.file || null);
  const [content, setContent] = useState('');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!docs?.length) {
      setSelected(null);
      return;
    }
    if (!docs.some((doc) => doc.file === selected)) setSelected(docs[0].file);
  }, [docs]);

  useEffect(() => {
    if (!selected) return;
    let cancelled = false;
    setLoading(true);
    api.doc(project.path, selected).then((data) => {
      if (!cancelled) setContent(data.text || '');
    }).catch(() => {
      if (!cancelled) setContent('');
    }).finally(() => {
      if (!cancelled) setLoading(false);
    });
    return () => { cancelled = true; };
  }, [project.path, selected]);

  if (!docs?.length) {
    return <EmptyState icon={FileText} title="没有文档" detail="支持 README、PRODUCT、HANDOFF、AGENTS 等常见文档。" />;
  }
  const doc = docs.find((item) => item.file === selected);
  return (
    <div className="fizz-card" style={{ display: 'grid', gridTemplateColumns: 'minmax(180px, 230px) minmax(0, 1fr)', minHeight: 420, overflow: 'hidden' }}>
      <div style={{ borderRight: '1px solid var(--fizz-hairline)', padding: 8, overflowY: 'auto' }}>
        {docs.map((item) => (
          <button
            type="button"
            key={item.file}
            onClick={() => setSelected(item.file)}
            style={{
              display: 'block', width: '100%', padding: '8px 9px', border: 0, borderRadius: 8,
              background: item.file === selected ? 'var(--fizz-selected)' : 'transparent', textAlign: 'left',
            }}
          >
            <span className="fizz-truncate" style={{ display: 'block', fontSize: 12, fontWeight: 500 }}>{item.title}</span>
            <span className="fizz-panel-sub">{item.file} · {fmtBytes(item.bytes)}</span>
          </button>
        ))}
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '12px 16px', borderBottom: '1px solid var(--fizz-hairline)' }}>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div style={{ fontSize: 13, fontWeight: 600 }}>{doc?.title}</div>
            <div className="fizz-panel-sub">{doc?.file} · {doc?.lines} 行 · {fmtBytes(doc?.bytes)} · {relativeTime(doc?.mtime)}</div>
          </div>
          <button type="button" className="fizz-icon-btn plain" title="复制文件路径" onClick={() => onCopy(`${project.path}/${doc?.file}`)}><Copy size={12} /></button>
          <button type="button" className="fizz-icon-btn plain" title="在 Finder 中显示项目" onClick={() => onReveal(project)}><FolderOpen size={12} /></button>
        </div>
        <div style={{ minHeight: 0, flex: 1, overflowY: 'auto', padding: 18 }}>
          {loading ? <Spinner size={18} /> : (
            <pre style={{ margin: 0, whiteSpace: 'pre-wrap', wordBreak: 'break-word', fontFamily: 'var(--font-sans)', fontSize: 12, lineHeight: 1.65 }}>{content}</pre>
          )}
        </div>
      </div>
    </div>
  );
}

function SessionsTab({ project, onResumeSession, onEndSession, onCopy, toast, version }) {
  const [data, setData] = useState(null);
  const [filter, setFilter] = useState('all');
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true);
    try {
      setData(await api.sessions(project.path));
    } catch {
      setData({ recentSessions: project.tool?.recentSessions || [], sessionCount: project.tool?.sessionCount || 0 });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    setData(null);
    setFilter('all');
    load();
  }, [project.path, version]);

  const sessions = data?.recentSessions || project.tool?.recentSessions || [];
  const tools = [...new Set(sessions.map((session) => session.tool))];
  const visible = filter === 'all' ? sessions : sessions.filter((session) => session.tool === filter);
  const totalTokens = data?.totalTokens ?? project.tool?.totalTokens ?? 0;
  const totalCost = data?.totalCostUSD ?? project.tool?.totalCostUSD;
  const last = sessions[0];

  if (loading && !sessions.length) return <div className="fizz-empty"><Spinner size={20} /></div>;
  if (!sessions.length) {
    return <EmptyState icon={MessageCircle} title="没有匹配的会话" detail="读取 ~/.codex、~/.claude、~/.grok、~/.gemini 与 ~/.dsh，按项目 cwd 精确匹配。" />;
  }

  return (
    <div className="fizz-stack" style={{ gap: 20 }}>
      <div className="fizz-grid fizz-auto-grid fizz-metric-grid">
        <StatCard title="会话总数" icon={MessageCircle} tint="var(--fizz-violet)" value={data?.sessionCount ?? project.tool?.sessionCount ?? sessions.length} unit="个" detail={tools.map(toolTitle).join(' · ')} />
        <StatCard title="最近会话" icon={Clock} tint="var(--fizz-blue)" value={relativeTime(last?.mtime)} detail={last ? toolTitle(last.tool) : '—'} />
        {totalTokens ? <StatCard title="Token 用量" icon={Activity} tint="var(--fizz-orange)" value={fmtTokens(totalTokens)} detail={fmtCost(totalCost, data?.costIsEstimate ?? project.tool?.costIsEstimate) || '未知模型不计价'} /> : null}
      </div>

      <Panel
        title="最近会话"
        icon={History}
        action={(
          <div className="fizz-seg" style={{ maxWidth: '100%', overflowX: 'auto' }}>
            <button type="button" className={filter === 'all' ? 'is-active' : ''} onClick={() => setFilter('all')}>全部</button>
            {tools.map((tool) => (
              <button type="button" key={tool} className={filter === tool ? 'is-active' : ''} onClick={() => setFilter(tool)}>{toolTitle(tool)}</button>
            ))}
          </div>
        )}
      >
        <div>
          {visible.map((session) => {
            const command = session.resumeCommand || (session.tool === 'codex' ? `codex resume ${session.id}` : session.tool === 'claude' ? `claude --resume ${session.id}` : session.tool === 'grok' ? `grok -r ${session.id}` : session.tool === 'gemini' ? `gemini --resume ${session.id}` : null);
            return (
              <div className="fizz-session-row" key={`${session.tool}:${session.id}`}>
                <span className="fizz-session-icon"><ToolIcon tool={session.tool} size={13} /></span>
                <div className="fizz-session-main">
                  <p className="fizz-session-message fizz-line-2">{session.lastUser || `${toolTitle(session.tool)} 会话`}</p>
                  <div className="fizz-session-meta">
                    <ToolBadge tool={session.tool} compact />
                    {session.model ? <span className="fizz-mono">{session.model}</span> : null}
                    {session.usage?.totalTokens ? <span>{fmtTokens(session.usage.totalTokens)} tokens</span> : null}
                    {session.costUSD != null ? <span>{fmtCost(session.costUSD, session.costIsEstimate)}</span> : null}
                    <span className="fizz-tertiary">{relativeTime(session.mtime)}</span>
                    {session.running ? <span className="fizz-chip tone-green compact">运行中</span> : null}
                  </div>
                </div>
                <div className="fizz-session-actions">
                  {command ? (
                    <>
                      <button type="button" className="fizz-btn small" onClick={() => onResumeSession(project, session)}>
                        <Play size={10} />继续
                      </button>
                      <button type="button" className="fizz-icon-btn plain" title="复制恢复命令" onClick={() => onCopy(`cd '${project.path}' && ${command}`)}>
                        <Copy size={11} />
                      </button>
                    </>
                  ) : null}
                  {session.running ? (
                    <button type="button" className="fizz-icon-btn plain" title="结束会话" onClick={() => onEndSession(project, session)}>
                      <X size={12} style={{ color: 'var(--fizz-red)' }} />
                    </button>
                  ) : null}
                </div>
              </div>
            );
          })}
          {!visible.length ? <div className="fizz-panel-sub" style={{ padding: '12px 0' }}>没有这个工具的会话</div> : null}
        </div>
      </Panel>
    </div>
  );
}

function TestsTab({ project, testRun, onTest, onCopy }) {
  return (
    <Panel
      title="提交测试"
      icon={ShieldCheck}
      action={(
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          {testRun?.status && testRun.status !== 'idle' ? (
            <span className={`fizz-chip ${testRun.status === 'passed' ? 'tone-green' : testRun.status === 'failed' ? 'tone-red' : 'tone-orange'}`}>
              {testRun.status === 'running' ? '运行中' : testRun.status === 'passed' ? '通过' : '失败'}
              {testRun.durationMs ? ` · ${(testRun.durationMs / 1000).toFixed(1)}s` : ''}
            </span>
          ) : null}
          <button type="button" className="fizz-btn small" disabled={!project.test || testRun?.status === 'running'} onClick={() => onTest(project)}>
            {testRun?.status === 'running' ? <Spinner size={11} /> : <ShieldCheck size={10} />}
            {testRun?.status === 'running' ? '测试中' : '跑测试'}
          </button>
        </div>
      )}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
        <span className="fizz-panel-sub">命令</span>
        <code className="fizz-chip fizz-mono">{project.test?.command || '未识别'}</code>
        {project.test?.label ? <span className="fizz-panel-sub">来自 {project.test.label}</span> : null}
        {project.test ? <button type="button" className="fizz-icon-btn plain" onClick={() => onCopy(project.test.command)}><Copy size={11} /></button> : null}
      </div>
      {testRun?.output ? (
        <pre className="fizz-log" style={{ maxHeight: 460, borderColor: testRun.status === 'failed' ? 'color-mix(in oklab, var(--fizz-red) 30%, transparent)' : undefined }}>{stripAnsi(testRun.output)}</pre>
      ) : (
        <EmptyState
          icon={ShieldCheck}
          title={project.test ? '还没跑过测试' : '没有测试命令'}
          detail={project.test ? '点右上「跑测试」在本地执行并回显输出' : '该项目没有 test / check / typecheck 脚本'}
        />
      )}
    </Panel>
  );
}

function CleanupTab({ project, onCopy }) {
  const items = project.cleandoc?.items || [];
  return (
    <div className="fizz-stack" style={{ gap: 20 }}>
      <div className="fizz-grid fizz-auto-grid fizz-metric-grid">
        <StatCard title="可回收" icon={Archive} tint="var(--fizz-orange)" value={fmtBytes(project.cleandoc.reusableBytes)} detail="只复制命令，不执行删除" />
        <StatCard title="命中目录" icon={FolderOpen} tint="var(--fizz-red)" value={items.length} unit="个" detail="依赖、缓存、构建产物、归档" />
      </div>
      {items.length ? (
        <Panel title="可清理目录" icon={Archive}>
          {items.map((item) => {
            const meta = CLEAN_KIND[item.kind] || CLEAN_KIND.default;
            const Icon = meta.icon;
            return (
              <div key={item.path} className="fizz-clean-row" style={{ paddingLeft: 0, paddingRight: 0 }}>
                <span className="fizz-clean-icon" style={{ color: toneColor(meta.tone) }}><Icon size={14} /></span>
                <div className="fizz-clean-main">
                  <div className="fizz-clean-title">{item.label}<span>{fmtBytes(item.bytes)}</span></div>
                  <div className="fizz-clean-sub">{item.reason}{item.regen ? ` · ${item.regen}` : ''}</div>
                </div>
                <button type="button" className="fizz-icon-btn plain" title="复制删除命令" onClick={() => onCopy(`rm -rf '${item.path.replace(/'/g, `'\\''`)}'`)}><Copy size={11} /></button>
              </div>
            );
          })}
        </Panel>
      ) : <EmptyState icon={CircleCheck} title="没有可清理项" detail="没有命中 node_modules、构建产物、缓存或归档规则。" />}
      <Panel title="体积构成" icon={HardDrive}>
        {project.size.breakdown.map((row) => {
          const ratio = project.size.totalBytes ? row.bytes / project.size.totalBytes : 0;
          return (
            <div key={row.label} style={{ marginBottom: 10 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 11 }}>
                <span className="fizz-mono fizz-truncate" style={{ flex: 1 }}>{row.label}</span>
                <span className="fizz-panel-sub">{fmtBytes(row.bytes)}</span>
              </div>
              <div style={{ height: 4, marginTop: 4, borderRadius: 999, background: 'var(--fizz-hairline)', overflow: 'hidden' }}>
                <span style={{ display: 'block', height: '100%', width: `${Math.max(2, ratio * 100)}%`, borderRadius: 999, background: 'color-mix(in oklab, var(--fizz-accent) 55%, transparent)' }} />
              </div>
            </div>
          );
        })}
      </Panel>
    </div>
  );
}

export function ProjectDetail({
  project, running, busy, testRun, requestedTab, sessionsVersion, onResumeSession, onEndSession,
  onLaunch, onStop, onCopy, onReveal, onMeta, onStar, onRemove, onTest, toast,
}) {
  const [tab, setTab] = useState(requestedTab || 'overview');
  const [detail, setDetail] = useState(null);
  const [loading, setLoading] = useState(true);

  const loadDetail = async () => {
    setLoading(true);
    try {
      const data = await api.project(project.path);
      if (data.ok) setDetail(data);
    } catch {
      setDetail(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    setDetail(null);
    loadDetail();
  }, [project.path]);

  useEffect(() => {
    if (requestedTab) setTab(requestedTab);
  }, [project.path, requestedTab]);

  const tabs = TABS.map((item) => ({
    ...item,
    count: item.key === 'git' ? detail?.git?.changedCount
      : item.key === 'docs' ? detail?.docs?.length
        : item.key === 'sessions' ? project.tool?.sessionCount
          : item.key === 'cleanup' ? project.cleandoc?.items?.length
            : null,
  }));

  return (
    <div className="fizz-page-scroll">
      <div className="fizz-page-inner">
        <Hero
          project={project}
          running={running}
          onCopy={onCopy}
          onReveal={onReveal}
          onStar={onStar}
          onRemove={onRemove}
        />
        <div className="fizz-tabbar-wrap">
          <div className="fizz-glass">
            {tabs.map((item) => (
              <button
                type="button"
                key={item.key}
                className={tab === item.key ? 'is-active is-accent' : ''}
                onClick={() => setTab(item.key)}
              >
                {item.label}
                {item.count ? <span style={{ opacity: 0.7 }}>{item.count}</span> : null}
              </button>
            ))}
          </div>
        </div>

        <div className="fizz-fade-in" style={{ marginTop: 14 }}>
          {tab === 'overview' ? (
            <OverviewTab
              project={project}
              running={running}
              busy={busy}
              testRun={testRun}
              detail={detail}
              onLaunch={onLaunch}
              onStop={onStop}
              onCopy={onCopy}
              onMeta={onMeta}
              onTest={onTest}
              toast={toast}
            />
          ) : null}
          {tab === 'git' ? (
            <GitTab
              project={project}
              detail={detail}
              loading={loading}
              onCopy={onCopy}
              onFetch={async (target) => {
                try {
                  await api.git(target.path, 'fetch');
                  await loadDetail();
                  toast?.('已同步远程');
                } catch (error) {
                  toast?.(error.message, true);
                }
              }}
              onCheckout={async (target, branch) => {
                try {
                  await api.git(target.path, 'checkout', branch);
                  await loadDetail();
                  toast?.(`已切换到 ${branch}`);
                } catch (error) {
                  toast?.(error.message, true);
                }
              }}
              toast={toast}
            />
          ) : null}
          {tab === 'docs' ? (
            <DocsTab project={project} docs={detail?.docs} onCopy={onCopy} onReveal={onReveal} />
          ) : null}
          {tab === 'sessions' ? (
            <SessionsTab
              project={project}
              onResumeSession={onResumeSession}
              onEndSession={onEndSession}
              onCopy={onCopy}
              toast={toast}
              version={sessionsVersion}
            />
          ) : null}
          {tab === 'tests' ? (
            <TestsTab project={project} testRun={testRun} onTest={onTest} onCopy={onCopy} />
          ) : null}
          {tab === 'cleanup' ? (
            <CleanupTab project={project} onCopy={onCopy} />
          ) : null}
        </div>
      </div>
    </div>
  );
}
