import React, { useMemo, useState } from 'react';
import {
  Activity, AlertCircle, Archive, ChevronDown, ChevronUp, CircleCheck, Clock, Cpu,
  GitBranch, HardDrive, Play, Server, Sparkles,
} from 'lucide-react';
import { BadgeIcon, Panel, StatCard, ToolBadge } from '@/components/Fizz.jsx';
import { fmtBytes, fmtCost, fmtTokens, relativeTime, todayTitle } from '@/lib/format.js';
import {
  ATTENTION_META, attentionItems, commitHeatmap, continueItems, costBreakdown,
  healthAlerts, weeklyKpi, weeklyTimeline,
} from '@/lib/dashboard.js';
import { groupTone, toolTitle } from '@/lib/tool.js';

function Heatmap({ projects, onOpenLibrary }) {
  const [weeks, setWeeks] = useState(() => Number(localStorage.getItem('fizzdeck.web.heatmap') || 26));
  const [hovered, setHovered] = useState(null);
  const data = useMemo(() => commitHeatmap(projects, weeks), [projects, weeks]);
  const cellSize = weeks === 26 ? 8.5 : 5.2;
  const gap = weeks === 26 ? 4 : 2.2;
  const colors = ['var(--fizz-hairline)', '#f4d57a', '#e6ae32', '#ce8510', '#9f5d06'];

  return (
    <Panel
      title="提交热力图"
      icon={GitBranch}
      action={(
        <div className="fizz-seg">
          {[26, 52].map((value) => (
            <button
              type="button"
              key={value}
              className={weeks === value ? 'is-active' : ''}
              onClick={() => {
                setWeeks(value);
                localStorage.setItem('fizzdeck.web.heatmap', String(value));
              }}
            >
              {value === 26 ? '26 周' : '12 月'}
            </button>
          ))}
        </div>
      )}
    >
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 10 }}>
        <strong style={{ fontSize: 22, fontVariantNumeric: 'tabular-nums' }}>{data.totalCommits}</strong>
        <span className="fizz-muted" style={{ fontSize: 11 }}>次 · 连续 {data.currentStreak} 天</span>
      </div>
      <div className="fizz-heatmap-wrap">
        {data.columns.map((column, columnIndex) => (
          <div className="fizz-heatmap-col" key={columnIndex} style={{ gap: `${gap}px` }}>
            {column.map((cell) => (
              <button
                type="button"
                key={cell.key}
                className={`fizz-heatmap-cell${cell.isFuture ? ' is-empty' : ''}${cell.level ? ` level-${cell.level}` : ''}`}
                style={{ width: `${cellSize}px`, height: `${cellSize}px` }}
                title={cell.isFuture ? '' : `${cell.date.getMonth() + 1} 月 ${cell.date.getDate()} 日 · ${cell.count} 次`}
                onMouseEnter={() => setHovered(cell)}
                onMouseLeave={() => setHovered(null)}
                onClick={() => {
                  if (cell.count > 0) onOpenLibrary({ commitDayKey: cell.key });
                }}
              />
            ))}
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 8 }}>
        <div className="fizz-panel-sub fizz-truncate" style={{ flex: 1 }}>
          {hovered
            ? `${hovered.date.getMonth() + 1} 月 ${hovered.date.getDate()} 日 · ${hovered.count} 次${hovered.projects.length ? ` · ${hovered.projects.slice(0, 3).map((item) => `${item.name} ${item.count}`).join('、')}` : ''}`
            : `最长连续 ${data.longestStreak} 天 · 点击有提交的日期筛选项目`}
        </div>
        <div className="fizz-heatmap-legend">
          {colors.map((color) => <i key={color} style={{ background: color }} />)}
        </div>
      </div>
    </Panel>
  );
}

function CostCard({ projects, kpi }) {
  const [mode, setMode] = useState('tool');
  const segments = useMemo(() => costBreakdown(projects, mode), [projects, mode]);
  const hasData = segments.length > 0 && (kpi.weeklyCostUSD != null || kpi.weeklyTokens > 0);
  if (!hasData) return null;
  let cursor = 0;
  const stops = [];
  for (let index = 0; index < segments.length; index += 1) {
    const segment = segments[index];
    const start = cursor;
    const end = Math.min(1, cursor + Math.max(0.005, segment.fraction - (segments.length > 1 ? 0.008 : 0)));
    const color = colorFor(segment.tone, index);
    stops.push(`${color} ${start * 100}%`, `${color} ${end * 100}%`);
    if (end < 1) stops.push(`var(--fizz-card) ${end * 100}%`, `var(--fizz-card) ${Math.min(1, cursor + segment.fraction) * 100}%`);
    cursor += segment.fraction;
  }
  const center = kpi.weeklyCostUSD != null
    ? fmtCost(kpi.weeklyCostUSD, kpi.costIsEstimate)
    : fmtTokens(kpi.weeklyTokens);
  return (
    <Panel
      title={kpi.weeklyCostUSD != null ? '费用构成' : '用量构成'}
      icon={Sparkles}
      action={(
        <div className="fizz-seg">
          <button type="button" className={mode === 'tool' ? 'is-active' : ''} onClick={() => setMode('tool')}>按工具</button>
          <button type="button" className={mode === 'project' ? 'is-active' : ''} onClick={() => setMode('project')}>按项目</button>
        </div>
      )}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 18 }}>
        <div className="fizz-donut" style={{ background: `conic-gradient(${stops.join(',')})` }}>
          <div className="fizz-donut-center">
            <strong>{center}</strong>
            <span>{kpi.weeklyCostUSD != null ? (kpi.costIsEstimate ? '本周估' : '本周') : 'tokens'}</span>
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 7, minWidth: 0, flex: 1 }}>
          {segments.map((segment, index) => (
            <div className="fizz-legend-row" key={segment.id}>
              <i style={{ background: colorFor(segment.tone, index) }} />
              <span className="label">{segment.label}</span>
              <span className="value">{segment.cost > 0 ? fmtCost(segment.cost) : fmtTokens(segment.tokens)}</span>
              <span className="pct">{Math.round(segment.fraction * 100)}%</span>
            </div>
          ))}
        </div>
      </div>
    </Panel>
  );
}

function colorFor(tone, index) {
  if (tone === 'secondary') return 'var(--fizz-tertiary)';
  return `var(--fizz-${tone})`;
}

function ContinueSection({ items, onOpenProject, onResume }) {
  if (!items.length) return null;
  return (
    <section>
      <div className="fizz-panel-head" style={{ marginBottom: 10 }}>
        <Play size={13} style={{ color: 'var(--fizz-accent)' }} />
        <div className="fizz-panel-title">继续工作</div>
        <span className="fizz-panel-sub">{items.length}</span>
      </div>
      <div className="fizz-grid fizz-auto-grid">
        {items.map((item) => (
          <div className="fizz-continue-card" key={item.id}>
            <div className="fizz-continue-head">
              <BadgeIcon project={item.project} size={24} />
              <button
                type="button"
                onClick={() => onOpenProject(item.project.path)}
                style={{ border: 0, background: 'transparent', padding: 0, minWidth: 0, flex: 1, textAlign: 'left' }}
              >
                <strong className="fizz-truncate" style={{ display: 'block', fontSize: 13, fontWeight: 600 }}>{item.project.displayName}</strong>
              </button>
              <ToolBadge tool={item.session.tool} />
            </div>
            <div className="fizz-continue-summary fizz-line-2">{item.summary}</div>
            <div className="fizz-continue-foot">
              <span className="fizz-panel-sub">{relativeTime(item.modified)}</span>
              <span className="fizz-spacer" />
              <button type="button" className="fizz-btn small" onClick={() => onResume(item.project, item.session)}>
                <Play size={11} />继续
              </button>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function AttentionPanel({ items, onOpenProject }) {
  const [expanded, setExpanded] = useState(false);
  const [kind, setKind] = useState(null);
  if (!items.length) return null;
  const kindCounts = Object.keys(ATTENTION_META)
    .map((key) => ({ key, count: items.filter((item) => item.kind === key).length }))
    .filter((entry) => entry.count > 0);
  const filtered = kind ? items.filter((item) => item.kind === kind) : items;
  const visible = expanded ? filtered : filtered.slice(0, 4);
  const projectCount = new Set(items.map((item) => item.project.path)).size;
  return (
    <section className="fizz-card" style={{ overflow: 'hidden' }}>
      <div className="fizz-panel-head" style={{ padding: '12px 14px 8px', marginBottom: 0 }}>
        <AlertCircle size={13} style={{ color: 'var(--fizz-accent)' }} />
        <div className="fizz-panel-title">待处理</div>
        <span className="fizz-panel-sub">{projectCount} 个项目</span>
        <span className="fizz-spacer" />
        <span className="fizz-panel-sub">{items.length} 项</span>
      </div>
      <div className="fizz-divider" style={{ margin: '0 14px', opacity: 0.55 }} />
      {kindCounts.length > 1 ? (
        <>
          <div style={{ display: 'flex', gap: 6, padding: '8px 14px', overflowX: 'auto' }}>
            <button type="button" className={`fizz-filter-chip${!kind ? ' is-active' : ''}`} onClick={() => setKind(null)}>全部 {items.length}</button>
            {kindCounts.map((entry) => (
              <button
                type="button"
                key={entry.key}
                className={`fizz-filter-chip${kind === entry.key ? ' is-active' : ''}`}
                onClick={() => setKind(entry.key)}
              >
                {ATTENTION_META[entry.key].label} {entry.count}
              </button>
            ))}
          </div>
          <div className="fizz-divider" style={{ margin: '0 14px', opacity: 0.45 }} />
        </>
      ) : null}
      <div>
        {visible.map((item, index) => (
          <React.Fragment key={item.id}>
            <button
              type="button"
              className="fizz-attention-row"
              style={{ width: '100%' }}
              onClick={() => onOpenProject(item.project.path, ATTENTION_META[item.kind].tab)}
            >
              <span className="fizz-attention-icon">
                {item.kind === 'cleanup' ? <Archive size={13} /> : item.kind === 'testFailed' ? <AlertCircle size={13} /> : <GitBranch size={13} />}
              </span>
              <span className="fizz-attention-copy">
                <strong>{item.project.displayName} · {item.title}</strong>
                <span>{item.detail}</span>
              </span>
              <span className="fizz-panel-sub" style={{ flex: '0 0 auto' }}>{relativeTime(item.project.recent)}</span>
            </button>
            {index < visible.length - 1 ? <div className="fizz-divider" style={{ marginLeft: 50, opacity: 0.38 }} /> : null}
          </React.Fragment>
        ))}
      </div>
      {filtered.length > 4 ? (
        <button
          type="button"
          onClick={() => setExpanded(!expanded)}
          style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5, width: '100%', height: 29, border: 0, borderTop: '1px solid var(--fizz-hairline)', background: 'transparent', color: 'var(--fizz-secondary)', fontSize: 11 }}
        >
          {expanded ? '收起' : `还有 ${filtered.length - 4} 项`}
          {expanded ? <ChevronUp size={10} /> : <ChevronDown size={10} />}
        </button>
      ) : null}
    </section>
  );
}

function TimelinePanel({ projects, onOpenProject }) {
  const columns = useMemo(() => weeklyTimeline(projects), [projects]);
  if (!columns.some((column) => column.blocks.length)) return null;
  return (
    <Panel
      title="本周活动时间线"
      icon={Clock}
      action={(
        <div style={{ display: 'flex', gap: 10, color: 'var(--fizz-secondary)', fontSize: 10 }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}><i className="fizz-dot green" />提交</span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}><i className="fizz-dot accent" />会话</span>
        </div>
      )}
    >
      <div className="fizz-timeline">
        {columns.map((column) => {
          const visible = column.blocks.slice(0, 4);
          return (
            <div className="fizz-timeline-day" key={column.key}>
              <div className={`fizz-timeline-head${column.isToday ? ' is-today' : ''}`}>
                <span>{column.weekdayLabel}</span>
                <b>{column.dayNumber}</b>
              </div>
              <div className="fizz-timeline-box">
                {visible.map((block) => (
                  <button
                    type="button"
                    key={block.id}
                    className={`fizz-timeline-pill${block.kind === 'session' ? ' session' : ''}`}
                    title={`${block.projectName} · ${block.detail}`}
                    onClick={() => onOpenProject(block.projectPath)}
                  >
                    {block.projectName}
                  </button>
                ))}
                {column.blocks.length > visible.length ? (
                  <span className="fizz-timeline-overflow">+{column.blocks.length - visible.length}</span>
                ) : null}
              </div>
            </div>
          );
        })}
      </div>
    </Panel>
  );
}

function StatusPanel({ projects, disk, onOpenProject, onOpenCleanup, onOpenLibrary }) {
  const running = projects.filter((project) => project.portState === 'running');
  const alerts = healthAlerts(projects, disk);
  return (
    <Panel title="运行与健康" icon={Server}>
      {running.length ? (
        <div style={{ marginBottom: alerts.length ? 10 : 0 }}>
          {running.map((project) => (
            <button
              type="button"
              key={project.path}
              onClick={() => onOpenProject(project.path)}
              style={{ display: 'flex', alignItems: 'center', gap: 8, width: '100%', height: 30, padding: '0 2px', border: 0, background: 'transparent', textAlign: 'left' }}
            >
              <span className="fizz-dot green" />
              <span className="fizz-truncate" style={{ flex: 1, fontSize: 11.5 }}>{project.displayName}</span>
              <span className="fizz-mono fizz-tertiary">:{project.run?.port}</span>
              <span className="fizz-chip tone-green compact">运行中</span>
            </button>
          ))}
        </div>
      ) : null}
      {alerts.map((alert) => (
        <button
          type="button"
          key={alert.id}
          onClick={() => {
            if (alert.projectPath) onOpenProject(alert.projectPath);
            else if (alert.id === 'high-cleanup') onOpenCleanup();
            else onOpenLibrary();
          }}
          style={{ display: 'flex', alignItems: 'center', gap: 8, width: '100%', padding: '7px 2px', border: 0, borderTop: running.length ? '1px solid var(--fizz-hairline)' : 0, background: 'transparent', textAlign: 'left' }}
        >
          <AlertCircle size={12} style={{ color: 'var(--fizz-orange)', flex: '0 0 auto' }} />
          <span style={{ minWidth: 0, flex: 1 }}>
            <strong style={{ display: 'block', fontSize: 11.5, fontWeight: 500 }}>{alert.title}</strong>
            <span className="fizz-panel-sub">{alert.detail}</span>
          </span>
        </button>
      ))}
      {!running.length && !alerts.length ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '10px 0', color: 'var(--fizz-secondary)', fontSize: 11.5 }}>
          <CircleCheck size={13} style={{ color: 'var(--fizz-green)' }} />
          没有运行中的服务或健康提醒
        </div>
      ) : null}
    </Panel>
  );
}

function AllClear({ projects, onOpenProject }) {
  const recent = [...projects]
    .sort((a, b) => String(b.recent || '').localeCompare(String(a.recent || '')))
    .slice(0, 4);
  return (
    <section className="fizz-card" style={{ padding: 16 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <CircleCheck size={15} style={{ color: 'var(--fizz-green)' }} />
        <div>
          <strong style={{ display: 'block', fontSize: 13.5, fontWeight: 600 }}>一切就绪</strong>
          <span className="fizz-panel-sub">没有待处理项、陈旧改动或运行中的服务</span>
        </div>
      </div>
      {recent.length ? (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 12 }}>
          {recent.map((project) => (
            <button
              type="button"
              key={project.path}
              className="fizz-chip"
              style={{ height: 28, padding: '0 10px', gap: 6 }}
              onClick={() => onOpenProject(project.path)}
            >
              <BadgeIcon project={project} size={18} />
              {project.displayName}
            </button>
          ))}
        </div>
      ) : null}
    </section>
  );
}

export function Workbench({ projects, disk, testRuns, onOpenProject, onResume, onOpenLibrary, onOpenCleanup }) {
  const attention = useMemo(() => attentionItems(projects, testRuns), [projects, testRuns]);
  const continueList = useMemo(() => continueItems(projects), [projects]);
  const kpi = useMemo(() => weeklyKpi(projects), [projects]);
  const running = projects.filter((project) => project.portState === 'running').length;
  const alerts = healthAlerts(projects, disk);
  const allClear = !attention.length && !continueList.length && !running && !alerts.length && projects.length > 0;
  const cost = fmtCost(kpi.weeklyCostUSD, kpi.costIsEstimate);
  const subtitle = [
    attention.length ? `${attention.length} 项待处理` : '暂无待处理',
    running ? `${running} 个运行中` : null,
  ].filter(Boolean).join(' · ');

  return (
    <div className="fizz-page-scroll">
      <div className="fizz-page-inner">
        <div className="fizz-page-head">
          <div>
            <h1>{todayTitle()}</h1>
            <div className="fizz-page-sub">{subtitle}</div>
          </div>
          <div className="fizz-head-actions">
            <div className="fizz-head-kpis">
              <div className="fizz-kpi-number">
                <strong>{kpi.weeklyCommits}</strong>
                <span>本周提交</span>
              </div>
              <div className="fizz-kpi-number">
                <strong>{kpi.weeklySessions}</strong>
                <span>AI 会话</span>
              </div>
              <div className="fizz-kpi-number" title={[
                kpi.monthlyCostUSD != null ? `近 30 天 ${fmtCost(kpi.monthlyCostUSD)}` : null,
                kpi.delta != null ? `较上周 ${kpi.delta >= 0 ? '↑' : '↓'} ${Math.abs(kpi.delta).toFixed(0)}%` : null,
              ].filter(Boolean).join(' · ')}>
                <strong>{cost || fmtTokens(kpi.weeklyTokens)}</strong>
                <span>{cost ? (kpi.costIsEstimate ? '本周费用(估)' : '本周费用') : '本周 tokens'}</span>
              </div>
            </div>
          </div>
        </div>

        <div className="fizz-workbench">
          <div className="fizz-stack" style={{ gap: 12 }}>
            {allClear ? <AllClear projects={projects} onOpenProject={onOpenProject} /> : null}
            <ContinueSection items={continueList} onOpenProject={onOpenProject} onResume={onResume} />
            <AttentionPanel items={attention} onOpenProject={onOpenProject} />
            <TimelinePanel projects={projects} onOpenProject={onOpenProject} />
            {!attention.length && !continueList.length && projects.length === 0 ? (
              <Panel title="还没有项目"><div className="fizz-panel-sub">从左侧「添加项目目录」开始。</div></Panel>
            ) : null}
          </div>
          <div className="fizz-stack" style={{ gap: 12 }}>
            <Heatmap projects={projects} onOpenLibrary={onOpenLibrary} />
            <CostCard projects={projects} kpi={kpi} />
            <StatusPanel
              projects={projects}
              disk={disk}
              onOpenProject={onOpenProject}
              onOpenCleanup={onOpenCleanup}
              onOpenLibrary={() => onOpenLibrary({})}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
