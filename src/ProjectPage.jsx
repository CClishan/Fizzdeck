import React, { useEffect, useState } from 'react';
import {
  Activity, AlertTriangle, Check, ChevronDown, Copy, ExternalLink, FileText, FolderGit2,
  FolderOpen, GitBranch, GitCommitHorizontal, HardDrive, Play, RefreshCw, ShieldCheck,
  Square, Star, TerminalSquare, Trash2, X,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Card, CardPanel } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Frame, FramePanel, FrameTitle } from '@/components/ui/frame';
import { Alert, AlertTitle, AlertDescription, AlertAction } from '@/components/ui/alert';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent } from '@/components/ui/empty';
import { Separator } from '@/components/ui/separator';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsList, TabsTab, TabsPanel } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Breadcrumb, BreadcrumbItem, BreadcrumbLink, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator } from '@/components/ui/breadcrumb';
import { Collapsible, CollapsibleTrigger, CollapsiblePanel } from '@/components/ui/collapsible';
import { Progress, ProgressTrack, ProgressIndicator } from '@/components/ui/progress';
import { Spinner } from '@/components/ui/spinner';

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

const STACK_STYLE = {
  framework: 'border-primary/25 bg-primary/10 text-primary',
  language: 'border-border bg-muted text-muted-foreground',
  infra: 'border-warning/35 bg-warning/10 text-warning',
  feature: 'border-border bg-secondary text-secondary-foreground',
};

function StackGroups({ groups, max = 99 }) {
  let left = max;
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      {(groups || []).map((g) => {
        const items = g.items.slice(0, Math.max(0, left));
        left -= items.length;
        if (!items.length) return null;
        return (
          <span key={g.key} className="inline-flex items-center gap-1">
            <span className="text-[10.5px] tracking-wide text-muted-foreground/70 uppercase">{g.label}</span>
            {items.map((it) => (
              <span key={it} className={cn('rounded-[5px] border px-1.5 py-0.5 text-xs leading-none', STACK_STYLE[g.key])}>{it}</span>
            ))}
          </span>
        );
      })}
    </div>
  );
}

const statusDot = (status) => (status === 'passed' ? 'text-success' : status === 'failed' ? 'text-destructive' : 'text-muted-foreground');

/* ---------------- 概览 ---------------- */
function OverviewTab({ p, running, busy, testRun, onLaunch, onStop }) {
  const maxB = Math.max(...p.size.breakdown.map((b) => b.bytes), 1);
  return (
    <div className="grid gap-3 lg:grid-cols-[1.2fr_1fr]">
      <div className="flex flex-col gap-3">
        <Frame>
          <FramePanel className="p-0">
            <div className="flex items-center justify-between px-4 pt-3.5 pb-2">
              <FrameTitle>运行状态</FrameTitle>
              <div className="flex gap-1.5">
                {p.run?.previewUrl && (running
                  ? <Button size="xs" variant="outline" onClick={() => window.open(p.run.previewUrl, '_blank')}><Play />打开页面</Button>
                  : <Button size="xs" onClick={() => onLaunch(p)} disabled={busy === 'launch'}>{busy === 'launch' ? <Spinner className="size-3.5" /> : <Play />}启动</Button>)}
                {running && <Button size="xs" variant="ghost" onClick={() => onStop(p)}><Square />停止</Button>}
              </div>
            </div>
            <dl className="grid grid-cols-[84px_1fr] gap-x-3 gap-y-2 px-4 pb-4 text-xs">
              <dt className="text-muted-foreground">启动命令</dt><dd className="truncate font-mono text-xs">{p.run ? `${p.run.command} · :${p.run.port}` : '无 dev 脚本'}</dd>
              <dt className="text-muted-foreground">本地服务</dt><dd>{running ? <span className="text-success">运行中</span> : p.run?.previewUrl ? '未运行' : '无预览'}</dd>
              <dt className="text-muted-foreground">未提交</dt><dd className={cn(p.dirtyCount && 'text-warning')}>{p.dirtyCount ? `${p.dirtyCount} 个文件` : '干净'}</dd>
              <dt className="text-muted-foreground">最近提交</dt><dd className="truncate">{p.lastCommit ? `${p.lastCommit.hash} · ${p.lastCommit.subject}` : '—'}</dd>
              <dt className="text-muted-foreground">测试</dt>
              <dd className={cn(statusDot(testRun?.status))}>
                {!p.test ? '无测试命令' : testRun?.status === 'running' ? '运行中…' : testRun?.status === 'passed' ? `通过 · ${(testRun.durationMs / 1000).toFixed(1)}s` : testRun?.status === 'failed' ? '失败' : '未运行'}
              </dd>
            </dl>
          </FramePanel>
        </Frame>

        <Frame>
          <FramePanel className="p-0">
            <div className="flex items-center justify-between px-4 pt-3.5 pb-2">
              <FrameTitle>体积构成</FrameTitle>
              <span className="text-xs text-muted-foreground">总计 {fmt(p.size.totalBytes)}</span>
            </div>
            <div className="flex flex-col gap-1.5 px-4 pb-4">
              {p.size.breakdown.map((b) => (
                <div key={b.label} className="grid grid-cols-[110px_1fr_64px] items-center gap-2 text-xs">
                  <span className="truncate font-mono text-xs text-muted-foreground">{b.label}</span>
                  <Progress value={(b.bytes / maxB) * 100} className="h-1.5">
                    <ProgressTrack className="h-1.5 overflow-hidden rounded-full bg-foreground/10">
                      <ProgressIndicator className="h-full rounded-full bg-primary/80" />
                    </ProgressTrack>
                  </Progress>
                  <span className="text-right tabular text-muted-foreground">{fmt(b.bytes)}</span>
                </div>
              ))}
            </div>
          </FramePanel>
        </Frame>
      </div>

      <div className="flex flex-col gap-3">
        <Frame>
          <FramePanel className="p-0">
            <div className="flex items-center justify-between px-4 pt-3.5 pb-2">
              <FrameTitle>AI 会话</FrameTitle>
              <span className="text-xs text-muted-foreground">{p.tool?.sessionCount || 0} 个</span>
            </div>
            <div className="flex flex-col gap-2 px-4 pb-4">
              {(p.tool?.byTool || []).length ? p.tool.byTool.map((t) => (
                <div key={t.tool} className="rounded-lg border border-border bg-muted/40 p-2.5">
                  <div className="mb-1 flex items-center gap-2 text-xs text-muted-foreground">
                    <Badge variant="outline">{t.tool === 'codex' ? 'Codex' : 'Claude Code'}</Badge>
                    <span>{t.sessionCount} 个会话</span>
                    <span className="ml-auto">{ago(t.lastSessionAt)}</span>
                  </div>
                  <p className="mb-2 line-clamp-3 text-xs leading-relaxed">{t.lastUserMessage || '（无可读用户消息）'}</p>
                  <Button size="xs" variant="outline" onClick={() => navigator.clipboard.writeText(t.tool === 'codex' ? `cd ${p.path} && codex resume ${t.lastSessionId}` : `cd ${p.path} && claude --resume ${t.lastSessionId}`)}>
                    <Copy />恢复会话
                  </Button>
                </div>
              )) : (
                <Empty className="border-0 p-4">
                  <EmptyHeader>
                    <EmptyMedia variant="icon"><TerminalSquare /></EmptyMedia>
                    <EmptyTitle>没有会话记录</EmptyTitle>
                    <EmptyDescription>未找到该目录的 Codex / Claude 会话</EmptyDescription>
                  </EmptyHeader>
                </Empty>
              )}
            </div>
          </FramePanel>
        </Frame>
      </div>
    </div>
  );
}

/* ---------------- 改动 ---------------- */
function ChangesTab({ p, detail, onFetch, onCheckout, onCopy }) {
  const git = detail?.git;
  if (!git) {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon"><GitBranch /></EmptyMedia>
          <EmptyTitle>不是 Git 仓库</EmptyTitle>
          <EmptyDescription>该项目没有 .git，无法查看分支与改动</EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }
  const shown = git.files.slice(0, 60);
  return (
    <div className="flex flex-col gap-3">
      {git.files.length === 0 ? (
        <Alert variant="success">
          <Check />
          <AlertTitle>工作区干净</AlertTitle>
          <AlertDescription>当前分支没有未提交改动</AlertDescription>
        </Alert>
      ) : (
        <Alert variant="warning">
          <AlertTriangle />
          <AlertTitle>已跟踪改动 {p.changes?.tracked || 0} 处 · 未跟踪文件 {p.changes?.untracked || 0} 个</AlertTitle>
          <AlertDescription>{git.ahead || git.behind ? `相对远程 ahead ${git.ahead} / behind ${git.behind}` : '两类分开统计：已跟踪是改动过但已纳入版本控制的文件，未跟踪是尚未 git add 的新文件'}</AlertDescription>
          <AlertAction>
            <Button size="xs" variant="outline" onClick={() => onCopy(`cd ${p.path} && git status`)}><Copy />复制命令</Button>
          </AlertAction>
        </Alert>
      )}

      <div className="grid gap-3 lg:grid-cols-[1.3fr_1fr]">
        <Frame>
          <FramePanel className="p-0">
            <div className="flex items-center justify-between px-4 pt-3.5 pb-2">
              <FrameTitle>改动文件</FrameTitle>
              <span className="text-xs text-muted-foreground">{shown.length} / {git.files.length}</span>
            </div>
            <div className="max-h-[420px] overflow-y-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-14">状态</TableHead>
                    <TableHead>路径</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {shown.map((f) => (
                    <TableRow key={f.path}>
                      <TableCell>
                        <Badge variant={f.untracked ? 'outline' : 'secondary'} className="font-mono text-xs">{f.code}</Badge>
                      </TableCell>
                      <TableCell className="max-w-[420px] truncate font-mono text-xs text-muted-foreground" title={f.path}>{f.path}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </FramePanel>
        </Frame>

        <Frame>
          <FramePanel className="p-0">
            <div className="flex items-center justify-between px-4 pt-3.5 pb-2">
              <FrameTitle>分支</FrameTitle>
              <Button size="xs" variant="ghost" onClick={() => onFetch(p)}><RefreshCw />同步远程</Button>
            </div>
            <div className="flex flex-col gap-1 px-2 pb-3">
              {git.branches.map((b) => (
                <div key={b.name} className={cn('flex items-center gap-2 rounded-md px-2 py-1.5', b.name === p.branch && 'bg-accent/60')}>
                  <GitBranch className={cn('size-3.5 shrink-0', b.name === p.branch ? 'text-primary' : 'text-muted-foreground/60')} />
                  <span className="min-w-0 flex-1 truncate font-mono text-xs">{b.name}</span>
                  <span className="shrink-0 text-xs text-muted-foreground">{ago(b.date)}</span>
                  {b.name !== p.branch && (
                    <Button size="xs" variant="ghost" onClick={() => onCheckout(p, b.name)}>切换</Button>
                  )}
                </div>
              ))}
            </div>
          </FramePanel>
        </Frame>
      </div>
    </div>
  );
}

/* ---------------- 文档 ---------------- */
function DocsTab({ p, detail, onCopy }) {
  const docs = detail?.docs || [];
  const [open, setOpen] = useState(docs[0]?.file || null);
  const [content, setContent] = useState({});
  const load = async (file) => {
    if (content[file]) return;
    const r = await fetch(`/api/doc?path=${encodeURIComponent(p.path)}&file=${encodeURIComponent(file)}`).then((x) => x.json()).catch(() => null);
    if (r?.ok) setContent((c) => ({ ...c, [file]: r.text }));
  };
  useEffect(() => { if (open) load(open); }, [open, p.path]);
  if (!docs.length) {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon"><FileText /></EmptyMedia>
          <EmptyTitle>没有文档</EmptyTitle>
          <EmptyDescription>未找到 README / PRODUCT / HANDOFF 等说明文件</EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }
  return (
    <div className="flex flex-col gap-2">
      {docs.map((d) => (
        <Collapsible key={d.file} open={open === d.file} onOpenChange={(v) => setOpen(v ? d.file : null)}>
          <Card>
            <FramePanel className="p-0">
              <CollapsibleTrigger className="flex w-full items-center gap-2 px-4 py-2.5 text-left">
                <FileText className="size-3.5 text-muted-foreground" />
                <span className="text-xs font-medium">{d.title}</span>
                <span className="font-mono text-xs text-muted-foreground">{d.file}</span>
                <span className="ml-auto text-xs text-muted-foreground">{d.lines} 行 · {fmt(d.bytes)} · {ago(d.mtime)}</span>
                <ChevronDown className={cn('size-3.5 text-muted-foreground transition-transform', open === d.file && 'rotate-180')} />
              </CollapsibleTrigger>
              <CollapsiblePanel>
                <div className="border-t border-border px-4 py-3">
                  <div className="mb-2 flex gap-1.5">
                    <Button size="xs" variant="ghost" onClick={() => onCopy(content[d.file] || '')}><Copy />复制全文</Button>
                    <Button size="xs" variant="ghost" onClick={() => window.open(`file://${p.path}/${d.file}`, '_blank')}><ExternalLink />外部打开</Button>
                  </div>
                  {content[d.file]
                    ? <pre className="max-h-[420px] overflow-auto rounded-lg border border-border bg-muted/40 p-3 font-mono text-xs leading-relaxed whitespace-pre-wrap">{content[d.file]}</pre>
                    : <Skeleton className="h-24 w-full" />}
                </div>
              </CollapsiblePanel>
            </FramePanel>
          </Card>
        </Collapsible>
      ))}
    </div>
  );
}

/* ---------------- 测试 ---------------- */
function TestsTab({ p, testRun, onTest }) {
  return (
    <div className="flex flex-col gap-3">
      <Frame>
        <FramePanel className="p-0">
          <div className="flex items-center justify-between px-4 pt-3.5 pb-2">
            <FrameTitle>提交测试</FrameTitle>
            <div className="flex items-center gap-2">
              {testRun?.status && testRun.status !== 'idle' && (
                <Badge variant={testRun.status === 'passed' ? 'default' : testRun.status === 'failed' ? 'destructive' : 'secondary'}>
                  {testRun.status === 'running' ? '运行中' : testRun.status === 'passed' ? '通过' : '失败'}
                  {testRun.durationMs ? ` · ${(testRun.durationMs / 1000).toFixed(1)}s` : ''}
                </Badge>
              )}
              <Button size="xs" onClick={() => onTest(p)} disabled={!p.test || testRun?.status === 'running'}>
                {testRun?.status === 'running' ? <Spinner className="size-3.5" /> : <ShieldCheck />}
                {testRun?.status === 'running' ? '测试中' : '跑测试'}
              </Button>
            </div>
          </div>
          <div className="flex items-center gap-2 px-4 pb-3">
            <span className="text-xs text-muted-foreground">命令</span>
            <code className="rounded border border-border bg-muted px-1.5 py-0.5 font-mono text-xs">{p.test ? p.test.command : '未识别'}</code>
            {p.test && <span className="text-xs text-muted-foreground">来自 {p.test.label}</span>}
          </div>
          {testRun?.output ? (
            <pre className={cn('mx-4 mb-4 max-h-[460px] overflow-auto rounded-lg border bg-muted/40 p-3 font-mono text-xs leading-relaxed whitespace-pre-wrap',
              testRun.status === 'failed' ? 'border-destructive/30 bg-destructive/5' : 'border-border')}>
              {testRun.output}
            </pre>
          ) : (
            <div className="mx-4 mb-4">
              <Empty className="border-0 p-6">
                <EmptyHeader>
                  <EmptyMedia variant="icon"><ShieldCheck /></EmptyMedia>
                  <EmptyTitle>{p.test ? '还没跑过测试' : '没有测试命令'}</EmptyTitle>
                  <EmptyDescription>{p.test ? '点右上「跑测试」在本地执行并回显输出' : '该项目没有 test / check / typecheck 脚本'}</EmptyDescription>
                </EmptyHeader>
              </Empty>
            </div>
          )}
        </FramePanel>
      </Frame>
    </div>
  );
}

/* ---------------- 管理 ---------------- */
function ManageTab({ p, detail, onMeta, onStar, onRemove, onReveal, onCopy }) {
  const [note, setNote] = useState(p.note || '');
  const [confirmName, setConfirmName] = useState('');
  const [removeOpen, setRemoveOpen] = useState(false);
  useEffect(() => { setNote(p.note || ''); setConfirmName(''); setRemoveOpen(false); }, [p.path]);
  const colors = ['red', 'amber', 'green', 'blue', 'violet'];
  return (
    <div className="flex flex-col gap-3">
      <div className="grid gap-3 lg:grid-cols-2">
        <Frame>
          <FramePanel className="flex flex-col gap-3 p-4">
            <FrameTitle>标记与备注</FrameTitle>
            <div className="flex items-center gap-2">
              {colors.map((c) => (
                <button key={c} onClick={() => onMeta(p, { color: p.color === c ? null : c })} title={c}
                  className={cn('size-5 rounded-full ring-offset-2 ring-offset-card transition-shadow', p.color === c && 'ring-2 ring-foreground/40')}
                  style={{ background: `var(--tag-${c})` }} />
              ))}
              <Separator orientation="vertical" className="mx-1 h-4" />
              <Button size="xs" variant="ghost" onClick={() => onStar(p)}>
                <Star className={cn('size-3.5', p.starred && 'fill-warning text-warning')} />{p.starred ? '取消星标' : '星标'}
              </Button>
            </div>
            <textarea value={note} onChange={(e) => setNote(e.target.value)} onBlur={() => onMeta(p, { note })}
              placeholder="备注…" rows={3}
              className="w-full resize-none rounded-lg border border-input bg-background px-2.5 py-2 text-xs outline-none focus-visible:ring-2 focus-visible:ring-ring/40" />
          </FramePanel>
        </Frame>

        <Frame>
          <FramePanel className="flex flex-col gap-2 p-4">
            <FrameTitle>路径与定位</FrameTitle>
            <button onClick={() => onCopy(`cd ${p.path}`)} className="flex items-center gap-1.5 rounded-md border border-border bg-muted/60 px-2 py-1.5 text-left font-mono text-xs text-muted-foreground hover:bg-accent">
              <FolderOpen className="size-3.5 shrink-0" /><span className="truncate">{p.path}</span><Copy className="ml-auto size-3 shrink-0 opacity-60" />
            </button>
            <div className="flex flex-wrap gap-1.5">
              <Button size="xs" variant="outline" onClick={onReveal}><FolderGit2 />定位文件夹</Button>
              <Button size="xs" variant="ghost" onClick={() => onCopy(`cd ${p.path} && ${p.run?.command || 'ls'}`)}><TerminalSquare />复制启动命令</Button>
            </div>
            {detail?.git?.remote && (
              <a href={detail.git.remote.replace(/\.git$/, '').replace(/^git@github\.com:/, 'https://github.com/')} target="_blank" rel="noreferrer"
                className="flex items-center gap-1.5 text-xs text-primary hover:underline">
                <ExternalLink className="size-3" />{detail.git.remote}
              </a>
            )}
          </FramePanel>
        </Frame>
      </div>

      <Frame>
        <FramePanel className="flex flex-col gap-3 p-4">
          <FrameTitle>移除项目</FrameTitle>
          <div className="flex flex-wrap items-center gap-1.5">
            <Button size="xs" variant="outline" onClick={() => onRemove(p, 'unmanage')}><X />从看板移除（保留文件）</Button>
            {!removeOpen && <Button size="xs" variant="destructive-outline" onClick={() => setRemoveOpen(true)}><Trash2 />整项目移除</Button>}
          </div>
          {removeOpen && (
            <div className="flex flex-col gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3">
              <div className="text-xs text-muted-foreground">
                输入目录名 <span className="font-mono font-semibold text-foreground">{p.name}</span> 以启用删除。永久删除会先备份到 <span className="font-mono">~/.repodeck/trash</span>。
              </div>
              <input value={confirmName} onChange={(e) => setConfirmName(e.target.value)} placeholder={p.name}
                className="h-8 rounded-lg border border-input bg-background px-2.5 font-mono text-xs outline-none focus-visible:ring-2 focus-visible:ring-ring/40" />
              <div className="flex flex-wrap gap-1.5">
                <Button size="xs" variant="destructive-outline" disabled={confirmName.trim() !== p.name} onClick={() => onRemove(p, 'delete-trash', confirmName)}>
                  <Trash2 />移到废纸篓
                </Button>
                <Button size="xs" variant="destructive" disabled={confirmName.trim() !== p.name} onClick={() => onRemove(p, 'delete-permanent', confirmName)}>
                  <Trash2 />永久删除
                </Button>
                <Button size="xs" variant="ghost" onClick={() => { setRemoveOpen(false); setConfirmName(''); }}>取消</Button>
              </div>
            </div>
          )}
        </FramePanel>
      </Frame>
    </div>
  );
}

/* ---------------- 子页面 ---------------- */
export function ProjectPage({ p, running, busy, testRun, onBack, onLaunch, onStop, onCopy, onReveal, onMeta, onStar, onRemove, onTest }) {
  const [detail, setDetail] = useState(null);
  const [tab, setTab] = useState('overview');

  const loadDetail = async () => {
    const r = await fetch(`/api/project?path=${encodeURIComponent(p.path)}`).then((x) => x.json()).catch(() => null);
    if (r?.ok) setDetail(r);
  };
  useEffect(() => { setDetail(null); loadDetail(); }, [p.path]);

  const onFetch = async (proj) => {
    await fetch('/api/git', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ path: proj.path, action: 'fetch' }) });
    loadDetail();
  };
  const onCheckout = async (proj, branch) => {
    if (!confirm(`切换到分支 ${branch}？`)) return;
    const r = await fetch('/api/git', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ path: proj.path, action: 'checkout', branch }) }).then((x) => x.json());
    if (!r.ok) alert(r.message);
    loadDetail();
  };

  const tabs = [
    ['overview', '概览', Activity],
    ['changes', `改动${detail?.git?.changedCount ? ` ${detail.git.changedCount}` : ''}`, GitBranch],
    ['commits', `提交 ${detail?.commits?.length || ''}`, GitCommitHorizontal],
    ['docs', `文档 ${detail?.docs?.length || ''}`, FileText],
    ['tests', '测试', ShieldCheck],
    ['manage', '管理', HardDrive],
  ];

  return (
    <div className="fade-in flex flex-col gap-3">
      <Breadcrumb>
        <BreadcrumbList>
          <BreadcrumbItem><BreadcrumbLink onClick={onBack} className="cursor-pointer">项目墙</BreadcrumbLink></BreadcrumbItem>
          <BreadcrumbSeparator />
          <BreadcrumbItem><BreadcrumbPage>{p.displayName}</BreadcrumbPage></BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>

      <Frame>
        <FramePanel className="flex flex-col gap-3 p-5">
          <div className="flex items-start gap-3">
            <span className={cn('mt-2 size-2.5 shrink-0 rounded-full', p.color ? `bg-[var(--tag-${p.color})]` : 'bg-muted-foreground/25')} />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <h1 className="truncate text-[19px] font-semibold tracking-tight">{p.displayName}</h1>
                {p.starred && <Star className="size-4 shrink-0 fill-warning text-warning" />}
                {running && <Badge className="bg-success/15 text-success">运行中</Badge>}
                {detail?.git?.remote && <Badge variant="outline" className="font-mono text-xs">git</Badge>}
              </div>
              {p.intro?.text ? (
                <p className="mt-1.5 max-w-[86ch] text-[13px] leading-relaxed text-muted-foreground">
                  {p.intro.text}
                  {p.intro.source && <span className="ml-1.5 text-xs opacity-60">— {p.intro.source}</span>}
                </p>
              ) : (
                <p className="mt-1.5 text-xs text-muted-foreground/70">未找到项目介绍（放一个 PRODUCT.md 或 README.md 即可）</p>
              )}
            </div>
            <Button size="icon-sm" variant="ghost" className="shrink-0" onClick={onBack}><X /></Button>
          </div>
          <div className="flex flex-wrap items-center gap-1.5">
            <button onClick={() => onCopy(`cd ${p.path}`)} className="inline-flex max-w-full items-center gap-1.5 rounded-md border border-border bg-muted/60 px-2 py-1 font-mono text-xs text-muted-foreground hover:bg-accent">
              <FolderOpen className="size-3.5" />{shortPath(p.path)}<Copy className="size-3 opacity-60" />
            </button>
            <Button size="xs" variant="ghost" onClick={onReveal}><FolderGit2 />定位文件夹</Button>
            {p.run?.previewUrl && (running
              ? <Button size="xs" variant="outline" onClick={() => window.open(p.run.previewUrl, '_blank')}><Play />打开页面</Button>
              : <Button size="xs" onClick={() => onLaunch(p)} disabled={busy === 'launch'}>{busy === 'launch' ? <Spinner className="size-3.5" /> : <Play />}启动</Button>)}
            {running && <Button size="xs" variant="ghost" onClick={() => onStop(p)}><Square />停止</Button>}
          </div>
          <StackGroups groups={p.stack.groups} />
        </FramePanel>
      </Frame>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          {tabs.map(([v, label, Icon]) => (
            <TabsTab key={v} value={v}><Icon className="size-3.5" />{label}</TabsTab>
          ))}
        </TabsList>
        <TabsPanel value="overview"><OverviewTab p={p} running={running} busy={busy} testRun={testRun} onLaunch={onLaunch} onStop={onStop} /></TabsPanel>
        <TabsPanel value="changes"><ChangesTab p={p} detail={detail} onFetch={onFetch} onCheckout={onCheckout} onCopy={onCopy} /></TabsPanel>
        <TabsPanel value="commits">
          {detail ? (
            <Frame>
              <FramePanel className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-20">提交</TableHead>
                      <TableHead>说明</TableHead>
                      <TableHead className="w-28">作者</TableHead>
                      <TableHead className="w-32 text-right">时间</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {detail.commits.map((c) => (
                      <TableRow key={c.full}>
                        <TableCell className="font-mono text-xs text-muted-foreground">{c.hash}</TableCell>
                        <TableCell className="max-w-[520px]">
                          <div className="flex items-center gap-1.5">
                            <span className="truncate">{c.subject}</span>
                            {c.refs && <Badge variant="outline" className="shrink-0 font-mono text-xs">{c.refs}</Badge>}
                          </div>
                        </TableCell>
                        <TableCell className="truncate text-xs text-muted-foreground">{c.author}</TableCell>
                        <TableCell className="text-right text-xs text-muted-foreground">{ago(c.date)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </FramePanel>
            </Frame>
          ) : <Skeleton className="h-40 w-full" />}
        </TabsPanel>
        <TabsPanel value="docs"><DocsTab p={p} detail={detail} onCopy={onCopy} /></TabsPanel>
        <TabsPanel value="tests"><TestsTab p={p} testRun={testRun} onTest={onTest} /></TabsPanel>
        <TabsPanel value="manage"><ManageTab p={p} detail={detail} onMeta={onMeta} onStar={onStar} onRemove={onRemove} onReveal={onReveal} onCopy={onCopy} /></TabsPanel>
      </Tabs>
    </div>
  );
}
