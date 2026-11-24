import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import fizzDeckLogo from './assets/fizzdeck-logo.png';
import {
  Activity, Box, ChevronLeft, ChevronRight, Copy, FileQuestion, FolderGit2, FolderOpen, GitBranch, ShieldCheck,
  HardDrive, LayoutGrid, List, Play, Plus, RefreshCw, Search, Sparkles, Square, Star,
  TerminalSquare, Trash2, X,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Card, CardPanel } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Frame, FramePanel, FrameTitle } from '@/components/ui/frame';
import { Meter } from '@/components/ui/meter';
import { ProjectPage } from './ProjectPage.jsx';

/* ---------------- 基础工具 ---------------- */
const fmt = (b) => {
  if (!b) return '0';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0, v = b;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return `${v >= 100 ? v.toFixed(0) : v.toFixed(v >= 10 ? 1 : 2)} ${u[i]}`;
};
const ago = (iso) => {
  if (!iso) return '无记录';
  const d = (Date.now() - new Date(iso).getTime()) / 1000;
  if (!isFinite(d)) return '—';
  if (d < 60) return '刚刚';
  if (d < 3600) return `${Math.floor(d / 60)} 分钟前`;
  if (d < 86400) return `${Math.floor(d / 3600)} 小时前`;
  if (d < 86400 * 30) return `${Math.floor(d / 86400)} 天前`;
  if (d < 86400 * 365) return `${Math.floor(d / 86400 / 30)} 个月前`;
  return `${(d / 86400 / 365).toFixed(1)} 年前`;
};
const shortPath = (p) => (p || '').replace(/^\/(?:Users|home)\/[^/]+/, '~');

/* ---------------- 请求与状态 ---------------- */
const Ctx = createContext(null);
const useApp = () => useContext(Ctx);

async function req(url, body) {
  const r = await fetch(url, body ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) } : undefined);
  const j = await r.json().catch(() => ({ ok: false, message: '响应解析失败' }));
  if (!r.ok || j.ok === false) throw new Error(j.message || '请求失败');
  return j;
}

const STACK_STYLE = {
  framework: 'border-primary/25 bg-primary/10 text-primary',
  language: 'border-border bg-muted text-muted-foreground',
  infra: 'border-warning/35 bg-warning/10 text-warning',
  feature: 'border-border bg-secondary text-secondary-foreground',
};

function StackGroups({ groups, max = 99, dense = false }) {
  let left = max;
  return (
    <div className={cn('flex flex-wrap items-center gap-1.5', dense && 'gap-1')}>
      {(groups || []).map((g) => {
        const items = g.items.slice(0, Math.max(0, left));
        left -= items.length;
        if (!items.length) return null;
        return (
          <span key={g.key} className="inline-flex items-center gap-1">
            <span className="text-[10.5px] uppercase tracking-wide text-muted-foreground/70">{g.label}</span>
            {items.map((it) => (
              <span key={it} className={cn('rounded-[5px] border px-1.5 py-0.5 text-xs leading-none', STACK_STYLE[g.key])}>{it}</span>
            ))}
          </span>
        );
      })}
    </div>
  );
}

function Toast() {
  const { toasts } = useApp();
  return (
    <div className="pointer-events-none fixed bottom-5 left-1/2 z-50 flex -translate-x-1/2 flex-col items-center gap-2">
      {toasts.map((t) => (
        <div key={t.id} className={cn('fade-in rounded-full px-4 py-2 text-xs shadow-lg', t.bad ? 'bg-destructive text-white' : 'bg-foreground text-background')}>{t.text}</div>
      ))}
    </div>
  );
}

/* ---------------- 侧栏 ---------------- */
function Sidebar({ projects, view, setView, selected, onSelect, filter, setFilter, query, setQuery, orphans, onAdd, onOrphans, aiStatus }) {
  const groups = useMemo(() => {
    const m = new Map();
    for (const p of projects) {
      const k = p.group || '其他';
      if (!m.has(k)) m.set(k, []);
      m.get(k).push(p);
    }
    return [...m.entries()];
  }, [projects]);

  const chips = [
    ['all', '全部', projects.length],
    ['starred', '星标', projects.filter((p) => p.starred).length],
    ['dirty', '有改动', projects.filter((p) => p.dirtyCount).length],
    ['session', '有会话', projects.filter((p) => p.tool?.lastSessionAt).length],
  ];

  return (
    <aside className="flex h-full w-[244px] shrink-0 flex-col border-r border-border bg-card/40">
      <div className="flex items-center gap-2.5 px-4 pt-4 pb-3">
        <img src={fizzDeckLogo} alt="" className="size-7 object-contain" />
        <div className="text-sm font-semibold tracking-tight">FizzDeck</div>
        <div className="ml-auto text-xs tabular text-muted-foreground">{projects.length} 个项目</div>
      </div>

      <div className="px-3 pb-2">
        <div className="relative">
          <Search className="pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2 text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="搜索项目 / 路径 / 技术栈"
            className="h-8 w-full rounded-lg border border-input bg-background pr-2 pl-7 text-xs outline-none placeholder:text-muted-foreground/70 focus-visible:ring-2 focus-visible:ring-ring/40"
          />
        </div>
      </div>

      <div className="flex gap-1.5 px-3 pb-2">
        <Button size="xs" variant="outline" className="flex-1" onClick={onAdd}><Plus />添加</Button>
        <Button size="xs" variant="outline" className="flex-1" onClick={onOrphans}><Sparkles />清理</Button>
      </div>

      <div className="flex flex-wrap gap-1.5 px-3 pb-2">
        {chips.map(([k, label, n]) => (
          <button
            key={k}
            onClick={() => setFilter(k)}
            className={cn(
              'rounded-full border px-2.5 py-1 text-xs transition-colors',
              filter === k ? 'border-primary bg-primary text-primary-foreground' : 'border-border bg-card text-muted-foreground hover:bg-accent',
            )}
          >
            {label}<span className="ml-1 tabular opacity-70">{n}</span>
          </button>
        ))}
      </div>

      <nav className="min-h-0 flex-1 overflow-y-auto px-2 pb-3">
        <button
          onClick={() => { setView('dashboard'); onSelect(null); }}
          className={cn('flex w-full items-center gap-2 rounded-lg px-2.5 py-2 text-left text-xs', view === 'dashboard' ? 'bg-accent text-accent-foreground' : 'text-foreground hover:bg-accent/60')}
        >
          <LayoutGrid className="size-3.5 text-muted-foreground" />总览
        </button>
        <button
          onClick={() => { setView('wall'); onSelect(null); }}
          className={cn('mb-1 flex w-full items-center gap-2 rounded-lg px-2.5 py-2 text-left text-xs', view === 'wall' ? 'bg-accent text-accent-foreground' : 'text-foreground hover:bg-accent/60')}
        >
          <FolderGit2 className="size-3.5 text-muted-foreground" />项目墙
        </button>
        {groups.map(([g, ps]) => (
          <div key={g}>
            <div className="px-2.5 pt-3 pb-1 text-[10.5px] font-medium tracking-wider text-muted-foreground/70 uppercase">{g}</div>
            {ps.map((p) => (
              <button
                key={p.path}
                onClick={() => onSelect(p)}
                className={cn('group flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-left text-xs', selected === p.path ? 'bg-accent text-accent-foreground' : 'hover:bg-accent/50')}
              >
                <span className={cn('size-1.5 shrink-0 rounded-full', p.color ? `bg-[var(--tag-${p.color})]` : 'bg-muted-foreground/30')} />
                <span className="truncate">{p.displayName}</span>
                {p.starred && <Star className="size-3 fill-warning text-warning" />}
                {p.dirtyCount > 0 && <span className="ml-auto size-1.5 shrink-0 rounded-full bg-warning" />}
              </button>
            ))}
          </div>
        ))}
      </nav>

      <div className="flex items-center gap-3 border-t border-border px-4 py-2.5 text-xs text-muted-foreground">
        <span className="inline-flex items-center gap-1.5"><span className={cn('size-1.5 rounded-full', aiStatus?.codex === 'running' ? 'bg-success' : aiStatus?.codex === 'recent' ? 'bg-warning' : 'bg-muted-foreground/40')} />Codex</span>
        <span className="inline-flex items-center gap-1.5"><span className={cn('size-1.5 rounded-full', aiStatus?.claude === 'running' ? 'bg-success' : aiStatus?.claude === 'recent' ? 'bg-warning' : 'bg-muted-foreground/40')} />Claude</span>
        <span className="ml-auto tabular">{orphans ? fmt(orphans.totalBytes) : '—'}</span>
      </div>
    </aside>
  );
}

/* ---------------- KPI ---------------- */
function Kpi({ label, value, unit, hint, tone, spark, icon: Icon }) {
  const pts = spark && spark.length > 1 ? spark : null;
  const max = pts ? Math.max(...pts, 1) : 1;
  const path = pts
    ? pts.map((v, i, a) => `${(i / (a.length - 1)) * 100},${28 - (v / max) * 24}`).join(' ')
    : null;
  return (
    <Card>
      <CardPanel className="flex flex-col gap-2 p-4">
        <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
          {Icon && <Icon className="size-3.5" />}{label}
        </div>
        <div className="flex items-end justify-between gap-2">
          <div className="flex items-baseline gap-1">
            <span className="text-[24px] leading-none font-semibold tracking-tight tabular">{value}</span>
            {unit && <span className="text-xs text-muted-foreground">{unit}</span>}
          </div>
          {pts && (
            <svg viewBox="0 0 100 30" preserveAspectRatio="none" className={cn('h-7 w-20 shrink-0', tone || 'text-primary')}>
              <polyline points={path} fill="none" stroke="currentColor" strokeWidth="1.6" vectorEffect="non-scaling-stroke" strokeLinejoin="round" strokeLinecap="round" opacity="0.85" />
            </svg>
          )}
        </div>
        {hint && <div className="truncate text-xs text-muted-foreground">{hint}</div>}
      </CardPanel>
    </Card>
  );
}

function StackedBars({ series, colors, height = 150 }) {
  const max = Math.max(...series.map((d) => d.values.reduce((a, b) => a + b, 0)), 1);
  return (
    <div className="flex items-end justify-around gap-2 px-2" style={{ height }}>
      {series.map((d) => {
        const total = d.values.reduce((a, b) => a + b, 0);
        const h = total ? Math.max(4, (total / max) * (height - 22)) : 2;
        return (
          <div key={d.label} className="flex w-full max-w-[56px] flex-1 flex-col items-center justify-end gap-1.5" style={{ height }}>
            <div className="flex w-full flex-col-reverse justify-start gap-px overflow-hidden rounded-t-[4px]" style={{ height: h }} title={`${d.label} · ${total} 次`}>
              {d.values.map((v, i) => (
                v > 0 ? <span key={i} className={cn('w-full', colors[i])} style={{ height: `${(v / total) * 100}%` }} /> : null
              ))}
            </div>
            <span className="text-[10.5px] leading-none text-muted-foreground">{d.label}</span>
          </div>
        );
      })}
    </div>
  );
}

const stackCount = (projects) => {
  const m = new Map();
  for (const p of projects) for (const g of p.stack.groups) {
    if (g.key === 'feature') continue;
    for (const it of g.items) m.set(it, (m.get(it) || 0) + 1);
  }
  return [...m.entries()].sort((a, b) => b[1] - a[1]).slice(0, 7);
};

/* ---------------- 首页看板 ---------------- */
function Dashboard({ projects, orphans, onSelect, runningCount, scannedAt }) {
  const [metric, setMetric] = useState('size');

  const stats = useMemo(() => {
    const total = projects.reduce((s, p) => s + p.size.totalBytes, 0);
    const reclaim = projects.reduce((s, p) => s + p.cleandoc.reusableBytes, 0);
    const tracked = projects.reduce((s, p) => s + (p.changes?.tracked || 0), 0);
    const untracked = projects.reduce((s, p) => s + (p.changes?.untracked || 0), 0);
    const dirtyProjects = projects.filter((p) => p.changes?.total > 0).length;
    const recent = [...projects].filter((p) => p.recent).sort((a, b) => (b.recent > a.recent ? 1 : -1));
    const sessions = projects.reduce((s, p) => s + (p.tool?.sessionCount || 0), 0);
    return { total, reclaim, tracked, untracked, dirtyProjects, recent, sessions };
  }, [projects]);

  // 按天聚合近 7 天的提交活动
  const activity = useMemo(() => {
    const days = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date(Date.now() - i * 86400000);
      days.push({ key: d.toISOString().slice(0, 10), label: `${d.getMonth() + 1}/${d.getDate()}`, values: [0, 0, 0] });
    }
    const idx = new Map(days.map((d) => [d.key, d]));
    for (const p of projects) {
      const i = p.group === '产品站' ? 0 : p.group === '官网' ? 1 : 2;
      for (const [day, n] of Object.entries(p.weekly || {})) {
        const bucket = idx.get(day);
        if (bucket) bucket.values[i] += n;
      }
    }
    const sum = days.reduce((a, d) => a + d.values.reduce((x, y) => x + y, 0), 0);
    return { days: days.map((d) => ({ ...d, title: d.values.join(' / ') })), sum };
  }, [projects]);

  const maxSize = Math.max(...projects.map((p) => p.size.totalBytes), 1);
  const top = [...projects].sort((a, b) => {
    if (metric === 'reclaim') return b.cleandoc.reusableBytes - a.cleandoc.reusableBytes;
    if (metric === 'changes') return (b.changes?.total || 0) - (a.changes?.total || 0);
    return b.size.totalBytes - a.size.totalBytes;
  }).slice(0, 6);

  const metricValue = (p) => (metric === 'reclaim' ? p.cleandoc.reusableBytes : metric === 'changes' ? (p.changes?.total || 0) : p.size.totalBytes);
  const maxMetric = Math.max(...top.map(metricValue), 1);

  return (
    <div className="flex flex-col gap-3">
      <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">
        <Kpi label="项目总数" value={projects.length} unit="个" hint={`${runningCount} 个服务运行中 · ${stats.sessions} 个 AI 会话`} icon={FolderGit2} />
        <Kpi label="占用空间" value={fmt(stats.total)} hint={`可回收 ${fmt(stats.reclaim)}`} icon={HardDrive} tone="text-primary"
          spark={projects.slice(0, 8).map((p) => p.size.totalBytes)} />
        <Kpi label="已跟踪改动" value={stats.tracked} unit="处" hint={`${stats.dirtyProjects} 个项目有变动`} icon={GitBranch} tone="text-warning"
          spark={projects.map((p) => p.changes?.tracked || 0)} />
        <Kpi label="未跟踪文件" value={stats.untracked} unit="个" hint="新增未纳入版本控制" icon={FileQuestion} tone="text-muted-foreground"
          spark={projects.map((p) => p.changes?.untracked || 0)} />
      </div>

      <div className="grid gap-3 xl:grid-cols-[1.45fr_1fr]">
        <Frame>
          <FramePanel className="p-0">
            <div className="flex items-center justify-between px-4 pt-3.5 pb-1">
              <FrameTitle>最近 7 天提交活动</FrameTitle>
              <div className="flex items-center gap-3 text-xs text-muted-foreground">
                <span className="inline-flex items-center gap-1"><span className="size-2 rounded-[2px] bg-chart-1" />产品站</span>
                <span className="inline-flex items-center gap-1"><span className="size-2 rounded-[2px] bg-chart-3" />官网</span>
                <span className="inline-flex items-center gap-1"><span className="size-2 rounded-[2px] bg-chart-4" />其他</span>
              </div>
            </div>
            <div className="px-4 pb-1 text-xs text-muted-foreground">按提交日期归档 · 近 7 天共 {activity.sum} 次提交</div>
            <div className="px-3 pt-3 pb-4">
              {activity.sum === 0
                ? <div className="grid h-40 place-items-center text-xs text-muted-foreground">近 7 天没有提交</div>
                : <StackedBars series={activity.days} colors={['bg-chart-1', 'bg-chart-3', 'bg-chart-4']} />}
            </div>
          </FramePanel>
        </Frame>

        <Frame>
          <FramePanel className="p-0">
            <div className="flex items-center justify-between px-4 pt-3.5 pb-2">
              <FrameTitle>项目排行</FrameTitle>
              <div className="flex rounded-md border border-border bg-muted p-0.5">
                {[['size', '体积'], ['reclaim', '可回收'], ['changes', '改动']].map(([k, label]) => (
                  <button key={k} onClick={() => setMetric(k)}
                    className={cn('rounded px-2 py-0.5 text-xs', metric === k ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground')}>{label}</button>
                ))}
              </div>
            </div>
            <div className="flex flex-col gap-2 px-4 pb-4">
              {top.map((p, i) => (
                <button key={p.path} onClick={() => onSelect(p.path)} className="group text-left">
                  <div className="mb-1 flex items-center gap-2 text-xs">
                    <span className="w-3 text-muted-foreground/60 tabular">{i + 1}</span>
                    <span className="truncate">{p.displayName}</span>
                    <span className="ml-auto shrink-0 tabular text-muted-foreground">{metric === 'changes' ? `${metricValue(p)} 个` : fmt(metricValue(p))}</span>
                  </div>
                  <div className="ml-5 h-1.5 overflow-hidden rounded-full bg-foreground/8">
                    <div className={cn('h-full rounded-full transition-all group-hover:brightness-110', ['bg-chart-1', 'bg-chart-2', 'bg-chart-3', 'bg-chart-4', 'bg-chart-5', 'bg-muted-foreground/50'][i % 6])}
                      style={{ width: `${Math.max(2, (metricValue(p) / maxMetric) * 100)}%` }} />
                  </div>
                </button>
              ))}
            </div>
          </FramePanel>
        </Frame>
      </div>

      <div className="grid gap-3 xl:grid-cols-[1fr_1fr]">
        <Frame>
          <FramePanel className="p-0">
            <div className="px-4 pt-3.5 pb-2"><FrameTitle>最近活动</FrameTitle></div>
            <div className="divide-y divide-border">
              {stats.recent.slice(0, 5).map((p) => (
                <button key={p.path} onClick={() => onSelect(p.path)} className="flex w-full items-center gap-2.5 px-4 py-2 text-left hover:bg-accent/50">
                  <span className={cn('size-1.5 shrink-0 rounded-full', p.color ? `bg-[var(--tag-${p.color})]` : 'bg-muted-foreground/30')} />
                  <span className="w-[110px] shrink-0 truncate text-xs font-medium">{p.displayName}</span>
                  <span className="min-w-0 flex-1 truncate text-xs text-muted-foreground">{p.lastCommit?.subject || p.tool?.lastUserMessage || '无提交记录'}</span>
                  <span className="shrink-0 text-xs tabular text-muted-foreground">{ago(p.recent)}</span>
                </button>
              ))}
            </div>
          </FramePanel>
        </Frame>

        <Frame>
          <FramePanel className="p-0">
            <div className="px-4 pt-3.5 pb-2"><FrameTitle>技术栈分布</FrameTitle></div>
            <div className="flex flex-col gap-2 px-4 pb-4">
              {stackCount(projects).map(([name, n]) => (
                <div key={name} className="flex items-center gap-2 text-xs">
                  <span className="w-[130px] shrink-0 truncate">{name}</span>
                  <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-foreground/8">
                    <div className="h-full rounded-full bg-primary/70" style={{ width: `${(n / projects.length) * 100}%` }} />
                  </div>
                  <span className="w-6 shrink-0 text-right tabular text-muted-foreground">{n}</span>
                </div>
              ))}
            </div>
          </FramePanel>
        </Frame>
      </div>

      <Frame>
        <FramePanel className="p-0">
          <div className="flex items-center justify-between px-4 pt-3.5 pb-2">
            <FrameTitle>台账</FrameTitle>
            <span className="text-xs text-muted-foreground">扫描于 {scannedAt ? new Date(scannedAt).toLocaleTimeString('zh-CN', { hour12: false }) : '—'}</span>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-y border-border bg-muted/40 text-left text-xs text-muted-foreground">
                  <th className="px-4 py-1.5 font-normal">项目</th>
                  <th className="px-2 py-1.5 font-normal">技术栈</th>
                  <th className="px-2 py-1.5 text-right font-normal">体积</th>
                  <th className="px-2 py-1.5 text-right font-normal">可回收</th>
                  <th className="px-2 py-1.5 text-right font-normal">已跟踪</th>
                  <th className="px-2 py-1.5 text-right font-normal">未跟踪</th>
                  <th className="px-4 py-1.5 text-right font-normal">最近</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {projects.map((p) => (
                  <tr key={p.path} onClick={() => onSelect(p.path)} className="cursor-pointer hover:bg-accent/50">
                    <td className="px-4 py-1.5 whitespace-nowrap">
                      <div className="flex items-center gap-1.5">
                        <span className={cn('size-1.5 rounded-full', p.color ? `bg-[var(--tag-${p.color})]` : 'bg-muted-foreground/25')} />
                        {p.displayName}
                      </div>
                    </td>
                    <td className="px-2 py-1.5"><StackGroups groups={p.stack.groups} max={3} dense /></td>
                    <td className="px-2 py-1.5 text-right tabular">{fmt(p.size.totalBytes)}</td>
                    <td className="px-2 py-1.5 text-right tabular text-muted-foreground">{p.cleandoc.reusableBytes ? fmt(p.cleandoc.reusableBytes) : '—'}</td>
                    <td className={cn('px-2 py-1.5 text-right tabular', p.changes?.tracked ? 'text-warning' : 'text-muted-foreground/50')}>{p.changes?.tracked || '—'}</td>
                    <td className={cn('px-2 py-1.5 text-right tabular', p.changes?.untracked ? 'text-muted-foreground' : 'text-muted-foreground/50')}>{p.changes?.untracked || '—'}</td>
                    <td className="px-4 py-1.5 text-right whitespace-nowrap text-muted-foreground">{ago(p.recent)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </FramePanel>
      </Frame>
    </div>
  );
}

/* ---------------- 项目卡片 ---------------- */
function ProjectCard({ p, running, busy, onLaunch, onStop, onOpen, onStar, onCopy }) {
  const maxSize = Math.max(p.size.totalBytes, 1);
  return (
    <Card className="group cursor-pointer transition-shadow hover:shadow-md" onClick={() => onOpen(p)}>
      <CardPanel className="flex flex-col gap-2.5 p-3.5">
        <div className="flex items-start gap-2">
          <span className={cn('mt-1.5 size-2 shrink-0 rounded-full', p.color ? `bg-[var(--tag-${p.color})]` : 'bg-muted-foreground/25')} />
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-1.5 text-[13px] font-semibold tracking-tight">
              <span className="truncate">{p.displayName}</span>
              {p.starred && <Star className="size-3 shrink-0 fill-warning text-warning" />}
            </div>
            <div className="truncate font-mono text-xs text-muted-foreground">{shortPath(p.path)}</div>
          </div>
          <button
            onClick={(e) => { e.stopPropagation(); onStar(p); }}
            className="rounded p-1 text-muted-foreground opacity-0 transition group-hover:opacity-100 hover:text-warning"
          >
            <Star className={cn('size-3.5', p.starred && 'fill-warning text-warning')} />
          </button>
        </div>

        <StackGroups groups={p.stack.groups} max={5} dense />

        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <span className="tabular">总 {fmt(p.size.totalBytes)}</span>
          {p.size.breakdown[0] && <span className="truncate">· {p.size.breakdown[0].label} {fmt(p.size.breakdown[0].bytes)}</span>}
          <span className="ml-auto shrink-0">{p.tool?.lastSessionAt ? `${p.tool.lastTool} ${ago(p.tool.lastSessionAt)}` : ''}</span>
        </div>

        <div className="h-1 overflow-hidden rounded-full bg-muted">
          <div className="h-full rounded-full bg-primary/70" style={{ width: `${Math.max(3, (p.size.totalBytes / maxSize) * 100)}%` }} />
        </div>

        <div className="flex items-center gap-2 text-xs">
          <span className="min-w-0 flex-1 truncate text-muted-foreground">{p.lastCommit?.subject || (p.branch ? '无提交' : '未纳入 Git')}</span>
          {p.dirtyCount > 0 && <span className="shrink-0 rounded bg-warning/15 px-1.5 py-0.5 text-xs text-warning">{p.dirtyCount}</span>}
          <span className="shrink-0 text-muted-foreground/80">{ago(p.recent)}</span>
        </div>

        <div className="mt-auto flex items-center gap-1.5 pt-1" onClick={(e) => e.stopPropagation()}>
          {p.run?.previewUrl && (running
            ? <Button size="xs" variant="outline" onClick={() => window.open(p.run.previewUrl, '_blank')}><Play />打开</Button>
            : <Button size="xs" onClick={() => onLaunch(p)} disabled={busy === 'launch'}>{busy === 'launch' ? <RefreshCw className="animate-spin" /> : <Play />}{busy === 'launch' ? '启动中' : '启动'}</Button>)}
          {running && <Button size="xs" variant="ghost" onClick={() => onStop(p)}><Square />停止</Button>}
          <Button size="xs" variant="ghost" onClick={() => onCopy(p)}><TerminalSquare />终端</Button>
          {p.tool?.lastSessionAt && <Button size="xs" variant="ghost" onClick={() => onCopy(p, true)}><Copy />会话</Button>}
        </div>
      </CardPanel>
    </Card>
  );
}

/* ---------------- 清理建议 ---------------- */
function OrphansView({ orphans, projects, onCopy }) {
  if (!orphans) return <div className="p-10 text-center text-xs text-muted-foreground">读取中…</div>;
  const items = projects.flatMap((p) => p.cleandoc.items.map((i) => ({ p, i }))).sort((a, b) => b.i.bytes - a.i.bytes);
  return (
    <div className="flex flex-col gap-3">
      <div className="grid grid-cols-3 gap-3">
        <Kpi label="AI 会话历史" value={fmt(orphans.totalBytes)} hint="Codex + Claude Code" icon={Activity} />
        <Kpi label="项目内可回收" value={fmt(items.reduce((s, x) => s + x.i.bytes, 0))} hint={`${items.length} 个目录`} icon={HardDrive} tone="text-primary" />
        <Kpi label="最占空间" value={items[0] ? fmt(items[0].i.bytes) : '—'} hint={items[0] ? `${items[0].p.displayName} / ${items[0].i.label}` : ''} icon={Box} />
      </div>
      <Frame>
        <FramePanel className="p-0">
          <div className="flex items-center justify-between px-4 pt-3.5 pb-2">
            <FrameTitle>各项目可清理目录</FrameTitle>
            <span className="text-xs text-muted-foreground">依赖与构建产物可直接删，归档类先确认</span>
          </div>
          <div className="divide-y divide-border">
            {items.slice(0, 30).map(({ p, i }) => (
              <div key={p.path + i.label} className="flex items-center gap-3 px-4 py-2 text-xs">
                <span className="w-[120px] shrink-0 truncate font-medium">{p.displayName}</span>
                <span className="min-w-0 flex-1 truncate font-mono text-xs text-muted-foreground">{shortPath(i.path)}</span>
                <span className="w-[92px] shrink-0 truncate text-right text-muted-foreground">{i.reason}</span>
                <span className="w-16 shrink-0 text-right tabular">{fmt(i.bytes)}</span>
                <Button size="xs" variant="ghost" onClick={() => onCopy(`rm -rf ${i.path}`)}><Copy /></Button>
              </div>
            ))}
          </div>
        </FramePanel>
      </Frame>
      {orphans.groups.map((g) => (
        <Frame key={g.site}>
          <FramePanel className="p-0">
            <div className="flex items-center justify-between px-4 pt-3.5 pb-2">
              <FrameTitle>{g.site}</FrameTitle>
              <span className="text-xs tabular text-muted-foreground">{fmt(g.totalBytes)}</span>
            </div>
            <div className="px-4 pb-3 text-xs text-muted-foreground">{g.note}</div>
            <div className="divide-y divide-border">
              {g.items.map((it) => (
                <div key={it.path} className="flex items-center gap-3 px-4 py-1.5 text-xs">
                  <span className="min-w-0 flex-1 truncate font-mono text-xs text-muted-foreground">{shortPath(it.path)}</span>
                  <span className="tabular">{fmt(it.bytes)}</span>
                  <span className="w-16 text-right text-muted-foreground">{ago(it.mtime)}</span>
                </div>
              ))}
            </div>
            <div className="px-4 py-2.5"><Button size="xs" variant="outline" onClick={() => onCopy(g.pruneCommand)}><Copy />复制清理命令</Button></div>
          </FramePanel>
        </Frame>
      ))}
    </div>
  );
}

/* ---------------- 添加项目 ---------------- */
function AddModal({ onClose, onAdded }) {
  const [dir, setDir] = useState('');
  const [depth, setDepth] = useState(2);
  const [found, setFound] = useState(null);
  const [loading, setLoading] = useState(false);
  const scan = async (d = dir, dp = depth) => {
    setLoading(true);
    try {
      const r = await req('/api/folders', { dir: d, depth: dp });
      setFound(r.found);
    } catch { setFound([]); } finally { setLoading(false); }
  };
  useEffect(() => { scan(); }, []);
  const pick = async () => {
    try { const r = await req('/api/pick-folder', {}); if (r.dir) { setDir(r.dir); scan(r.dir, depth); } } catch {}
  };
  const add = async (f) => {
    await req('/api/roots', { add: f.path });
    setFound((cur) => cur.map((x) => (x.path === f.path ? { ...x, added: true } : x)));
    onAdded();
  };
  return (
    <div className="fixed inset-0 z-40 grid place-items-center bg-black/30 p-6" onClick={onClose}>
      <div className="fade-in flex max-h-[86vh] w-[min(760px,96vw)] flex-col overflow-hidden rounded-xl border border-border bg-card shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <header className="flex items-center gap-2 border-b border-border px-4 py-3">
          <FolderOpen className="size-4 text-muted-foreground" />
          <div className="text-sm font-semibold">扫描本地文件夹</div>
          <Button size="icon-sm" variant="ghost" className="ml-auto" onClick={onClose}><X /></Button>
        </header>
        <div className="border-b border-border px-4 py-3">
          <div className="flex gap-2">
            <input
              value={dir}
              onChange={(e) => setDir(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && scan()}
              placeholder="~"
              className="h-8 flex-1 rounded-lg border border-input bg-background px-2.5 font-mono text-xs outline-none focus-visible:ring-2 focus-visible:ring-ring/40"
            />
            <Button size="sm" variant="outline" onClick={pick}>选择…</Button>
            <Button size="sm" onClick={() => scan()}>扫描</Button>
          </div>
          <div className="mt-2 flex items-center gap-1.5">
            {[1, 2, 3].map((d) => (
              <button
                key={d}
                onClick={() => { setDepth(d); scan(dir, d); }}
                className={cn('rounded-full border px-2.5 py-0.5 text-xs', depth === d ? 'border-primary bg-primary text-primary-foreground' : 'border-border text-muted-foreground')}
              >{d} 层</button>
            ))}
            <span className="ml-2 text-xs text-muted-foreground">识别 .git / package.json / pom.xml / go.mod 等</span>
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto">
          {loading && <div className="p-8 text-center text-xs text-muted-foreground">扫描中…</div>}
          {!loading && found?.length === 0 && <div className="p-8 text-center text-xs text-muted-foreground">没找到工程目录，试试加大层级</div>}
          {!loading && found?.map((f) => (
            <div key={f.path} className="flex items-center gap-3 border-b border-border px-4 py-2.5 last:border-0">
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-1.5 text-xs font-medium">
                  {f.name}
                  <Badge variant={f.hasGit ? 'default' : 'outline'} className="text-xs">{f.hasGit ? 'git' : '无 git'}</Badge>
                </div>
                <div className="truncate font-mono text-xs text-muted-foreground">{f.path}</div>
                <div className="truncate text-xs text-muted-foreground/80">{f.lastCommit ? f.lastCommit.split('\n')[2] : ''}</div>
              </div>
              {f.added ? <Badge variant="outline" className="shrink-0">已在看板</Badge> : <Button size="xs" onClick={() => add(f)}><Plus />添加</Button>}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ---------------- 主应用 ---------------- */
export function App() {
  const [state, setState] = useState(null);
  const [orphans, setOrphans] = useState(null);
  const [view, setViewRaw] = useState(localStorage.getItem('rd.view') || 'dashboard');
  const [filter, setFilter] = useState('all');
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState(null);
  const [toasts, setToasts] = useState([]);
  const [busy, setBusy] = useState({});
  const [adding, setAdding] = useState(false);
  const [testRuns, setTestRuns] = useState({});

  const setView = (v) => { setViewRaw(v); localStorage.setItem('rd.view', v); };
  const toast = useCallback((text, bad) => {
    const id = Math.random();
    setToasts((t) => [...t, { id, text, bad }]);
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 3200);
  }, []);
  const copy = useCallback((text) => navigator.clipboard.writeText(text).then(() => toast('已复制')).catch(() => toast('复制失败', true)), [toast]);

  const load = useCallback(async () => {
    try { const s = await req('/api/state'); setState(s); return s; } catch { toast('服务未连接', true); }
  }, [toast]);

  const rescan = useCallback(async () => {
    try {
      const s = await req('/api/rescan');
      setState(s);
      toast(`扫描完成 ${s.scan.durationMs}ms`);
      fetch('/api/orphans').then((r) => r.json()).then(setOrphans).catch(() => {});
    } catch (e) { toast(e.message, true); }
  }, [toast]);

  useEffect(() => {
    load();
    fetch('/api/orphans').then((r) => r.json()).then(setOrphans).catch(() => {});
    const dark = window.matchMedia('(prefers-color-scheme: dark)');
    const apply = () => document.documentElement.classList.toggle('dark', dark.matches);
    apply();
    dark.addEventListener('change', apply);
    const t = setInterval(load, 20000);
    return () => { clearInterval(t); dark.removeEventListener('change', apply); };
  }, [load]);

  const projects = state?.projects || [];
  const runningCount = projects.filter((p) => state?.portStatus?.[p.path] === 'running').length;
  const selectedP = projects.find((p) => p.path === selected) || null;

  const filtered = useMemo(() => projects.filter((p) => {
    if (filter === 'starred' && !p.starred) return false;
    if (filter === 'dirty' && !p.dirtyCount) return false;
    if (filter === 'session' && !p.tool?.lastSessionAt) return false;
    if (query) {
      const hay = [p.displayName, p.name, p.path, ...p.stack.languages, ...p.stack.frameworks, ...p.stack.tags, p.note].join(' ').toLowerCase();
      if (!hay.includes(query.toLowerCase())) return false;
    }
    return true;
  }), [projects, filter, query]);

  const doLaunch = async (p) => {
    setBusy((b) => ({ ...b, [p.path]: 'launch' }));
    try {
      const r = await req('/api/action', { path: p.path, action: 'launch' });
      toast(r.message);
      const t0 = Date.now();
      const tick = async () => {
        const s = await req('/api/state').catch(() => null);
        if (s) {
          setState((cur) => (cur ? { ...cur, portStatus: s.portStatus } : s));
          if (s.portStatus?.[p.path] === 'running') {
            setBusy((b) => ({ ...b, [p.path]: null }));
            toast(`${p.displayName} 已就绪`);
            window.open(p.run.previewUrl, '_blank');
            return;
          }
        }
        if (Date.now() - t0 > 60000) {
          setBusy((b) => ({ ...b, [p.path]: null }));
          toast(`${p.displayName} 60 秒内未就绪，看 ~/.repodeck/logs`, true);
          return;
        }
        setTimeout(tick, 1500);
      };
      setTimeout(tick, 1500);
    } catch (e) { toast(e.message, true); setBusy((b) => ({ ...b, [p.path]: null })); }
  };
  const doStop = async (p) => {
    try { const r = await req('/api/action', { path: p.path, action: 'stop' }); toast(r.message); setTimeout(load, 800); } catch (e) { toast(e.message, true); }
  };
  const doCopy = (p, session) => {
    if (session) {
      const t = p.tool?.byTool?.[0];
      if (!t) return copy(`cd ${p.path}`);
      return copy(t.tool === 'codex' ? `cd ${p.path} && codex resume ${t.lastSessionId}` : `cd ${p.path} && claude --resume ${t.lastSessionId}`);
    }
    copy(p.run ? `cd ${p.path} && ${p.run.command}` : `cd ${p.path}`);
  };
  const doStar = async (p) => {
    try {
      await req('/api/star', { path: p.path, starred: !p.starred });
      setState((s) => ({ ...s, projects: s.projects.map((x) => (x.path === p.path ? { ...x, starred: !x.starred } : x)) }));
    } catch (e) { toast(e.message, true); }
  };
  const doMeta = async (p, patch) => {
    try {
      await req('/api/meta', { path: p.path, ...patch });
      setState((s) => ({ ...s, projects: s.projects.map((x) => (x.path === p.path ? { ...x, ...patch } : x)) }));
    } catch (e) { toast(e.message, true); }
  };
  const doReveal = async (p) => {
    try { const r = await req('/api/action', { path: p.path, action: 'reveal' }); toast(r.message); } catch (e) { toast(e.message, true); }
  };
  const pollTest = async (p) => {
    const r = await req(`/api/test-run?path=${encodeURIComponent(p.path)}`).catch(() => null);
    if (!r) return;
    setTestRuns((m) => ({ ...m, [p.path]: r }));
    if (r.status === 'running') setTimeout(() => pollTest(p), 1500);
    else if (r.status === 'passed') toast(`${p.displayName} 测试通过`);
    else if (r.status === 'failed') toast(`${p.displayName} 测试失败`, true);
  };
  const doTest = async (p) => {
    try {
      setTestRuns((m) => ({ ...m, [p.path]: { status: 'running', output: '启动中…' } }));
      const r = await req('/api/test', { path: p.path });
      toast(`开始 ${r.run.command}`);
      setTimeout(() => pollTest(p), 1200);
    } catch (e) { toast(e.message, true); setTestRuns((m) => ({ ...m, [p.path]: { status: 'idle' } })); }
  };
  const doRemove = async (p, mode, confirmName) => {
    if (mode === 'unmanage' && !confirm(`不再看管 ${p.displayName}？\n只从列表移除，不删文件。`)) return;
    try {
      const r = await req('/api/remove', { path: p.path, mode, confirm: confirmName });
      toast(r.message);
      if (mode !== 'unmanage' || r.ok) setSelected(null);
      await rescan();
    } catch (e) { toast(e.message, true); }
  };

  const activeView = selectedP ? 'project' : view;
  const viewTitle = activeView === 'dashboard' ? '总览' : activeView === 'wall' ? '项目墙' : activeView === 'project' ? '项目详情' : '清理建议';

  return (
    <Ctx.Provider value={{ toasts }}>
      <div className="flex h-screen overflow-hidden">
        <Sidebar
          projects={projects} view={view} setView={(v) => { setView(v); setSelected(null); }}
          selected={selected} onSelect={(p) => setSelected(p ? p.path : null)} filter={filter} setFilter={setFilter}
          query={query} setQuery={setQuery} orphans={orphans} onAdd={() => setAdding(true)}
          onOrphans={() => { setView('orphans'); setSelected(null); }} aiStatus={state?.aiStatus}
        />
        <main className="flex min-h-0 min-w-0 flex-1 flex-col">
          <header className="flex items-center gap-3 border-b border-border px-5 py-3">
            <div>
              <h1 className="text-sm font-semibold tracking-tight">{viewTitle}</h1>
              <div className="text-xs text-muted-foreground">
                {state
                  ? `${projects.length} 个 · ${fmt(projects.reduce((s, p) => s + p.size.totalBytes, 0))} · 可回收 ${fmt(projects.reduce((s, p) => s + p.cleandoc.reusableBytes, 0))} · 扫描于 ${new Date(state.scannedAt).toLocaleTimeString('zh-CN', { hour12: false })}`
                  : '连接中…'}
              </div>
            </div>
            <div className="ml-auto flex items-center gap-1.5">
              <div className={cn('flex rounded-lg border border-border bg-card p-0.5', activeView === 'project' && 'hidden')}>
                {[['dashboard', '总览', Activity], ['wall', '项目墙', LayoutGrid], ['list', '列表', List]].map(([v, label, Icon]) => (
                  <button
                    key={v}
                    onClick={() => { setView(v); setSelected(null); }}
                    className={cn('inline-flex items-center gap-1 rounded-md px-2.5 py-1 text-xs', activeView === v ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:text-foreground')}
                  >
                    <Icon className="size-3.5" />{label}
                  </button>
                ))}
              </div>
              <Button size="sm" variant="outline" onClick={rescan}><RefreshCw />重新扫描</Button>
            </div>
          </header>

          <div className="min-h-0 flex-1 overflow-y-auto p-4">
            {!state && <div className="p-16 text-center text-xs text-muted-foreground">正在读取本地项目…</div>}
            {state && activeView === 'project' && selectedP && (
              <ProjectPage
                p={selectedP} running={state.portStatus?.[selectedP.path] === 'running'} busy={busy[selectedP.path]}
                onBack={() => setSelected(null)} onLaunch={doLaunch} onStop={doStop} onCopy={copy}
                onReveal={() => doReveal(selectedP)} onMeta={doMeta} onStar={doStar} onRemove={doRemove}
                onTest={doTest} testRun={testRuns[selectedP.path]}
              />
            )}
            {state && activeView === 'dashboard' && (
              <Dashboard projects={filtered} orphans={orphans} onSelect={setSelected} runningCount={runningCount} scannedAt={state.scannedAt} />
            )}
            {state && activeView === 'wall' && (
              filtered.length ? (
                <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
                  {filtered.map((p) => (
                    <ProjectCard
                      key={p.path} p={p} running={state.portStatus?.[p.path] === 'running'} busy={busy[p.path]}
                      onLaunch={doLaunch} onStop={doStop} onOpen={(x) => setSelected(x.path)} onStar={doStar} onCopy={doCopy}
                    />
                  ))}
                </div>
              ) : <div className="p-16 text-center text-xs text-muted-foreground">没有匹配的项目</div>
            )}
            {state && activeView === 'list' && (
              <Frame>
                <FramePanel className="p-0">
                  <div className="divide-y divide-border">
                    {filtered.map((p) => (
                      <button key={p.path} onClick={() => setSelected(p.path)} className="flex w-full items-center gap-3 px-4 py-2 text-left text-xs hover:bg-accent/50">
                        <span className={cn('size-1.5 shrink-0 rounded-full', p.color ? `bg-[var(--tag-${p.color})]` : 'bg-muted-foreground/30')} />
                        <span className="w-[140px] shrink-0 truncate font-medium">{p.displayName}</span>
                        <span className="min-w-0 flex-1 truncate font-mono text-xs text-muted-foreground">{shortPath(p.path)}</span>
                        <span className="w-[300px] shrink-0 truncate"><StackGroups groups={p.stack.groups} max={4} dense /></span>
                        <span className="w-16 shrink-0 text-right tabular">{fmt(p.size.totalBytes)}</span>
                        <span className="w-16 shrink-0 text-right tabular text-muted-foreground">{p.cleandoc.reusableBytes ? fmt(p.cleandoc.reusableBytes) : '—'}</span>
                        <span className="w-16 shrink-0 text-right text-muted-foreground">{ago(p.recent)}</span>
                        <ChevronRight className="size-3.5 shrink-0 text-muted-foreground/60" />
                      </button>
                    ))}
                  </div>
                </FramePanel>
              </Frame>
            )}
            {state && activeView === 'orphans' && <OrphansView orphans={orphans} projects={projects} onCopy={copy} />}
          </div>
        </main>

        {adding && <AddModal onClose={() => setAdding(false)} onAdded={rescan} />}
        <Toast />
      </div>
    </Ctx.Provider>
  );
}
