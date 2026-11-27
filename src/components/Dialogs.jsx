import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Archive, ArrowDown, ArrowUp, Check, ChevronRight, Command, Copy, CornerDownLeft,
  Folder, FolderOpen, FolderPlus, House, LayoutGrid, Loader2, MessageCircle, Monitor,
  Moon, Play, Plus, RefreshCw, Search, Settings, ShieldCheck, Square, Star, Sun,
  Terminal, Trash2, X,
} from 'lucide-react';
import { api } from '@/lib/api.js';
import { Spinner } from '@/components/Fizz.jsx';
import { fmtBytes, relativeTime, shortPath } from '@/lib/format.js';
import { toolTitle } from '@/lib/tool.js';

function closeOnEscape(open, onClose) {
  useEffect(() => {
    if (!open) return undefined;
    const handler = (event) => {
      if (event.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [open, onClose]);
}

function baseName(path) {
  return String(path || '').split('/').filter(Boolean).pop() || path;
}

function commitSubject(value) {
  if (!value) return '';
  return String(value).split('\n')[2] || '';
}

function commitDate(value) {
  if (!value) return '';
  return String(value).split('\n')[1] || '';
}

function RootRow({ path, active, disabled, onOpen, onRemove }) {
  return (
    <div className={`fizz-root-row${active ? ' is-active' : ''}`}>
      <button type="button" className="root-main" onClick={onOpen} title={path}>
        <Folder size={15} style={{ color: 'var(--fizz-blue)', flex: '0 0 auto' }} />
        <span className="fizz-root-copy">
          <strong>{baseName(path)}</strong>
          <span>{shortPath(path)}</span>
        </span>
        <ChevronRight size={11} />
      </button>
      <button
        type="button"
        className="fizz-root-remove"
        title="不再看管这个文件夹"
        disabled={disabled}
        onClick={onRemove}
      >
        <X size={11} />
      </button>
    </div>
  );
}

function CandidateRow({ candidate, checked, disabled, onToggle }) {
  const added = candidate.added;
  return (
    <button
      type="button"
      className={`fizz-candidate${checked ? ' is-checked' : ''}${added ? ' is-added' : ''}`}
      disabled={added || disabled}
      onClick={onToggle}
    >
      <span className={`fizz-checkbox${checked || added ? ' is-on' : ''}`}>
        {checked || added ? <Check size={10} strokeWidth={3} /> : null}
      </span>
      <Folder size={16} style={{ color: added ? 'var(--fizz-green)' : 'var(--fizz-blue)', flex: '0 0 auto' }} />
      <span className="candidate-copy">
        <span className="candidate-title">
          <strong>{candidate.name}</strong>
          <span className={`fizz-chip compact ${candidate.hasGit ? 'tone-blue' : 'tone-secondary'}`}>
            {candidate.hasGit ? 'git' : '无 git'}
          </span>
          {candidate.dirtyCount ? <span className="fizz-chip compact tone-orange">{candidate.dirtyCount} 改动</span> : null}
        </span>
        <span className="candidate-path">{shortPath(candidate.path)}</span>
        {commitSubject(candidate.lastCommit) ? (
          <span className="candidate-commit">{commitSubject(candidate.lastCommit)}</span>
        ) : null}
      </span>
      <span className="candidate-state">
        {added ? '已在看板' : candidate.lastCommit ? relativeTime(commitDate(candidate.lastCommit)) : '加入项目'}
      </span>
    </button>
  );
}

export function AddProjectsModal({ roots = [], onClose, onChanged, toast }) {
  const [depth, setDepth] = useState(() => {
    const saved = Number(localStorage.getItem('fizzdeck.web.scanDepth') || 3);
    return Math.min(4, Math.max(1, saved || 3));
  });
  const [pathValue, setPathValue] = useState('');
  const [folder, setFolder] = useState(null);
  const [candidates, setCandidates] = useState([]);
  const [selected, setSelected] = useState(() => new Set());
  const [loading, setLoading] = useState(false);
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState('');

  closeOnEscape(true, onClose);

  const available = candidates.filter((candidate) => !candidate.added);
  const selectedCount = selected.size;

  useEffect(() => {
    localStorage.setItem('fizzdeck.web.scanDepth', String(depth));
  }, [depth]);

  const scan = async (value = pathValue, nextDepth = depth) => {
    const target = String(value || '').trim();
    if (!target) {
      toast?.('先选择或输入一个文件夹', true);
      return;
    }
    setLoading(true);
    try {
      const result = await api.folders(target, nextDepth);
      setFolder(result.base || target);
      setPathValue(result.base || target);
      setCandidates(result.found || []);
      setSelected(new Set());
    } catch (error) {
      toast?.(error.message, true);
    } finally {
      setLoading(false);
    }
  };

  const choose = async () => {
    try {
      const result = await api.pickFolder();
      if (result.dir) {
        setPathValue(result.dir);
        await scan(result.dir, depth);
      }
    } catch (error) {
      if (error.message !== '已取消') toast?.(error.message, true);
    }
  };

  const toggle = (candidate) => {
    if (candidate.added) return;
    const next = new Set(selected);
    if (next.has(candidate.path)) next.delete(candidate.path);
    else next.add(candidate.path);
    setSelected(next);
  };

  const addPaths = async (paths) => {
    if (!paths.length || adding) return;
    setAdding(true);
    let added = 0;
    try {
      for (const path of paths) {
        await api.addRoot(path);
        added += 1;
      }
      setCandidates((current) => current.map((candidate) => (
        paths.includes(candidate.path) ? { ...candidate, added: true } : candidate
      )));
      setSelected(new Set());
      toast?.(`已加入 ${added} 个项目`);
      await onChanged?.();
    } catch (error) {
      toast?.(error.message, true);
      if (added) await onChanged?.();
    } finally {
      setAdding(false);
    }
  };

  const addSelected = () => {
    const paths = available.filter((candidate) => selected.has(candidate.path)).map((candidate) => candidate.path);
    addPaths(paths);
  };

  const removeRoot = async (path) => {
    if (removing) return;
    setRemoving(path);
    try {
      await api.removeRoot(path);
      if (folder === path) {
        setFolder(null);
        setCandidates([]);
        setSelected(new Set());
      }
      toast?.(`已移除 ${baseName(path)}（文件保留）`);
      await onChanged?.();
    } catch (error) {
      toast?.(error.message, true);
    } finally {
      setRemoving('');
    }
  };

  return (
    <div className="fizz-overlay" onClick={onClose}>
      <div className="fizz-sheet fizz-add-sheet" onClick={(event) => event.stopPropagation()}>
        <div className="fizz-sheet-head">
          <FolderPlus size={14} style={{ color: 'var(--fizz-accent)' }} />
          <div className="fizz-sheet-title">添加项目</div>
          <button type="button" className="fizz-icon-btn plain" onClick={onClose} title="关闭">
            <X size={13} />
          </button>
        </div>

        <div className="fizz-add-body">
          <aside className="fizz-add-side">
            <div className="fizz-add-side-head">
              <strong>文件夹</strong>
              <span>{roots.length}</span>
            </div>
            <div className="fizz-add-roots">
              {roots.length ? roots.map((path) => (
                <RootRow
                  key={path}
                  path={path}
                  active={folder === path}
                  disabled={Boolean(removing) || loading || adding}
                  onOpen={() => {
                    setPathValue(path);
                    scan(path, depth);
                  }}
                  onRemove={() => removeRoot(path)}
                />
              )) : (
                <div className="fizz-add-side-empty">
                  <Folder size={20} />
                  <span>还没有加入文件夹</span>
                </div>
              )}
            </div>
            <div className="fizz-add-side-foot">
              <button type="button" className="fizz-btn" onClick={choose} disabled={loading || adding}>
                <Plus size={11} />添加文件夹…
              </button>
            </div>
          </aside>

          <section className="fizz-add-main">
            <div className="fizz-add-path">
              <div className="fizz-add-input-wrap">
                <Search size={12} />
                <input
                  className="fizz-input mono"
                  value={pathValue}
                  onChange={(event) => setPathValue(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === 'Enter') scan();
                  }}
                  placeholder="~/Projects"
                />
              </div>
              <select
                className="fizz-select"
                value={depth}
                onChange={(event) => {
                  const next = Number(event.target.value);
                  setDepth(next);
                  if (folder) scan(folder, next);
                }}
                title="扫描层级"
              >
                {[1, 2, 3, 4].map((value) => <option key={value} value={value}>{value} 层</option>)}
              </select>
              <button type="button" className="fizz-btn" onClick={() => scan()} disabled={loading}>
                {loading ? <Spinner size={11} /> : <Search size={11} />}
                扫描
              </button>
            </div>

            {folder ? (
              <>
                <div className="fizz-add-scan-head">
                  <FolderOpen size={15} style={{ color: 'var(--fizz-blue)' }} />
                  <div>
                    <strong>{baseName(folder)}</strong>
                    <span>{shortPath(folder)}</span>
                  </div>
                  <span className="fizz-spacer" />
                  <span className="fizz-panel-sub">
                    {loading ? '正在查找项目…' : `发现 ${candidates.length} 个`}
                  </span>
                </div>

                <div className="fizz-candidate-list">
                  {loading ? (
                    <div className="fizz-add-loading"><Spinner size={18} /><span>正在查找项目…</span></div>
                  ) : candidates.length ? candidates.map((candidate) => (
                    <CandidateRow
                      key={candidate.path}
                      candidate={candidate}
                      checked={selected.has(candidate.path)}
                      disabled={adding}
                      onToggle={() => toggle(candidate)}
                    />
                  )) : (
                    <div className="fizz-add-empty">
                      <Folder size={24} />
                      <strong>没有发现项目</strong>
                      <p>没有匹配到 .git、package.json 等项目特征。可以只把这个文件夹加入看板。</p>
                      <button
                        type="button"
                        className="fizz-btn primary"
                        disabled={adding}
                        onClick={() => addPaths([folder])}
                      >
                        <Plus size={11} />只添加当前文件夹
                      </button>
                    </div>
                  )}
                </div>
              </>
            ) : (
              <div className="fizz-add-empty is-intro">
                <FolderPlus size={27} />
                <strong>选择一个文件夹开始扫描</strong>
                <p>从左侧选择已加入的文件夹，或输入路径、使用系统文件夹选择器。</p>
                <button type="button" className="fizz-btn primary" onClick={choose}>
                  <FolderOpen size={11} />选择文件夹…
                </button>
              </div>
            )}
          </section>
        </div>

        {folder && candidates.length ? (
          <div className="fizz-sheet-foot">
            <button
              type="button"
              className="fizz-btn small ghost"
              onClick={() => setSelected(new Set(available.map((candidate) => candidate.path)))}
              disabled={!available.length || adding}
            >
              全选
            </button>
            <button
              type="button"
              className="fizz-btn small ghost"
              onClick={() => setSelected(new Set())}
              disabled={!selectedCount || adding}
            >
              清空
            </button>
            <span className="fizz-spacer" />
            <span className="fizz-panel-sub">已选 {selectedCount}</span>
            <button
              type="button"
              className="fizz-btn primary"
              disabled={!selectedCount || adding}
              onClick={addSelected}
            >
              {adding ? <Spinner size={11} /> : <Plus size={11} />}
              {adding ? '加入中' : `加入 ${selectedCount} 个项目`}
            </button>
          </div>
        ) : null}
      </div>
    </div>
  );
}

const APPEARANCES = [
  { value: 'system', title: '跟随系统', detail: '随 macOS 自动切换', icon: Monitor },
  { value: 'light', title: '浅色', detail: '明亮干净的白色工作区', icon: Sun },
  { value: 'dark', title: '暗色', detail: '低饱和炭黑界面', icon: Moon },
];

export function SettingsModal({ appearance, onAppearance, state, projects, onClose }) {
  closeOnEscape(true, onClose);
  const shortcuts = [
    ['快速打开', '⌘K'],
    ['工作台', '⌘1'],
    ['项目库', '⌘2'],
    ['可清理', '⌘3'],
    ['重新扫描', '⌘R'],
    ['侧栏', '⌃⌘S'],
    ['返回工作台', '⌘0'],
    ['设置', '⌘,'],
  ];

  return (
    <div className="fizz-overlay" onClick={onClose}>
      <div className="fizz-sheet fizz-settings-sheet" onClick={(event) => event.stopPropagation()}>
        <div className="fizz-sheet-head">
          <Settings size={14} style={{ color: 'var(--fizz-accent)' }} />
          <div className="fizz-sheet-title">设置</div>
          <button type="button" className="fizz-icon-btn plain" onClick={onClose} title="关闭">
            <X size={13} />
          </button>
        </div>
        <div className="fizz-settings-body">
          <section className="fizz-setting-section">
            <div className="fizz-setting-title">外观</div>
            <div className="fizz-setting-card">
              <div className="fizz-setting-copy">
                <strong>界面主题</strong>
                <span>默认跟随系统，也可以固定浅色或低饱和暗色。</span>
              </div>
              <div className="fizz-appearance-grid">
                {APPEARANCES.map((item) => {
                  const Icon = item.icon;
                  return (
                    <button
                      type="button"
                      key={item.value}
                      className={`fizz-appearance-option${appearance === item.value ? ' is-active' : ''}`}
                      onClick={() => onAppearance(item.value)}
                    >
                      <Icon size={16} />
                      <strong>{item.title}</strong>
                      <span>{item.detail}</span>
                      {appearance === item.value ? <Check size={12} className="check" /> : null}
                    </button>
                  );
                })}
              </div>
            </div>
          </section>

          <section className="fizz-setting-section">
            <div className="fizz-setting-title">本地服务</div>
            <div className="fizz-setting-card">
              <div className="fizz-connection-grid">
                <div><span>连接</span><strong style={{ color: 'var(--fizz-green)' }}>已连接</strong></div>
                <div><span>项目</span><strong>{projects.length}</strong></div>
                <div><span>最近扫描</span><strong>{state?.scannedAt ? relativeTime(state.scannedAt) : '—'}</strong></div>
                <div><span>扫描耗时</span><strong>{state?.scan?.durationMs != null ? `${state.scan.durationMs} ms` : '—'}</strong></div>
                <div><span>磁盘可用</span><strong>{state?.disk ? fmtBytes(state.disk.free) : '—'}</strong></div>
                <div><span>自动刷新</span><strong>20 秒</strong></div>
              </div>
            </div>
          </section>

          <section className="fizz-setting-section">
            <div className="fizz-setting-title">键盘快捷键</div>
            <div className="fizz-setting-card">
              {shortcuts.map(([label, key]) => (
                <div className="fizz-shortcut-row" key={label}>
                  <span>{label}</span>
                  <kbd>{key}</kbd>
                </div>
              ))}
            </div>
          </section>
        </div>
        <div className="fizz-sheet-foot">
          <span className="fizz-panel-sub">设置保存在当前浏览器</span>
          <span className="fizz-spacer" />
          <button type="button" className="fizz-btn primary" onClick={onClose}>完成</button>
        </div>
      </div>
    </div>
  );
}

function paletteMatches(item, query) {
  if (!query) return true;
  const haystack = [item.title, item.subtitle, item.keywords].filter(Boolean).join(' ').toLowerCase();
  return haystack.includes(query);
}

export function CommandPalette({
  open, onClose, projects, selectedProject, onView, onOpenProject, onAdd, onSettings,
  onRescan, onLaunch, onStop, onReveal, onCopy, onStar, onTest, onResumeSession,
}) {
  const [query, setQuery] = useState('');
  const [selection, setSelection] = useState(0);
  const inputRef = useRef(null);
  const listRef = useRef(null);

  useEffect(() => {
    if (!open) return;
    setQuery('');
    setSelection(0);
    const timer = setTimeout(() => inputRef.current?.focus(), 30);
    return () => clearTimeout(timer);
  }, [open]);

  const items = useMemo(() => {
    const result = [];
    if (selectedProject) {
      const running = selectedProject.portState === 'running';
      result.push({
        id: 'action.open',
        group: '快捷操作',
        title: '打开当前项目',
        subtitle: selectedProject.displayName,
        icon: FolderOpen,
        tone: 'accent',
        keywords: `项目 ${selectedProject.path} ${selectedProject.branch || ''}`,
        run: () => onOpenProject(selectedProject.path),
      });
      if (selectedProject.run) {
        result.push({
          id: 'action.server',
          group: '快捷操作',
          title: running ? '停止开发服务' : '启动开发服务',
          subtitle: `${selectedProject.displayName} · ${selectedProject.run.command}`,
          icon: running ? Square : Play,
          tone: running ? 'red' : 'green',
          keywords: '服务 端口 启动 停止 dev server preview',
          run: () => (running ? onStop(selectedProject) : onLaunch(selectedProject)),
        });
      }
      result.push({
        id: 'action.reveal',
        group: '快捷操作',
        title: '在 Finder 中显示',
        subtitle: selectedProject.displayName,
        icon: FolderOpen,
        tone: 'blue',
        keywords: 'finder 目录 文件 reveal',
        run: () => onReveal(selectedProject),
      });
      result.push({
        id: 'action.path',
        group: '快捷操作',
        title: '复制项目路径',
        subtitle: selectedProject.displayName,
        icon: Copy,
        tone: 'secondary',
        keywords: '复制 路径 path',
        run: () => onCopy(selectedProject.path),
      });
      if (selectedProject.test) {
        result.push({
          id: 'action.test',
          group: '快捷操作',
          title: '运行测试',
          subtitle: `${selectedProject.displayName} · ${selectedProject.test.command}`,
          icon: ShieldCheck,
          tone: 'cyan',
          keywords: '测试 test check',
          run: () => onTest(selectedProject),
        });
      }
      const session = (selectedProject.tool?.recentSessions || []).find((item) => item.resumeCommand);
      if (session) {
        result.push({
          id: 'action.resume',
          group: '快捷操作',
          title: '继续最近的 AI 会话',
          subtitle: `${selectedProject.displayName} · ${toolTitle(session.tool)}`,
          icon: MessageCircle,
          tone: 'violet',
          keywords: '继续 会话 resume codex claude',
          run: () => onResumeSession(selectedProject, session),
        });
      }
      result.push({
        id: 'action.star',
        group: '快捷操作',
        title: selectedProject.starred ? '取消当前项目星标' : '收藏当前项目',
        subtitle: selectedProject.displayName,
        icon: Star,
        tone: 'gold',
        keywords: '星标 收藏 star',
        run: () => onStar(selectedProject),
      });
    }

    result.push(
      {
        id: 'nav.workbench',
        group: '导航',
        title: '工作台',
        subtitle: '今天的提交、会话和待处理',
        icon: House,
        tone: 'accent',
        shortcut: '⌘1',
        keywords: '首页 dashboard 总览 工作台',
        run: () => onView('workbench'),
      },
      {
        id: 'nav.library',
        group: '导航',
        title: '项目库',
        subtitle: '搜索、筛选和管理全部项目',
        icon: LayoutGrid,
        tone: 'blue',
        shortcut: '⌘2',
        keywords: '项目 列表 卡片 library',
        run: () => onView('library'),
      },
      {
        id: 'nav.cleanup',
        group: '导航',
        title: '可清理',
        subtitle: '查看依赖、构建产物和缓存',
        icon: Archive,
        tone: 'orange',
        shortcut: '⌘3',
        keywords: '清理 cleanup 空间 磁盘',
        run: () => onView('cleanup'),
      },
      {
        id: 'command.add',
        group: '命令',
        title: '添加项目',
        subtitle: '扫描新的父文件夹',
        icon: Plus,
        tone: 'green',
        keywords: '新增 导入 文件夹 添加',
        run: onAdd,
      },
      {
        id: 'command.rescan',
        group: '命令',
        title: '重新扫描项目',
        subtitle: '更新 Git、体积和运行状态',
        icon: RefreshCw,
        tone: 'blue',
        shortcut: '⌘R',
        keywords: '刷新 rescan refresh scan',
        run: onRescan,
      },
      {
        id: 'command.settings',
        group: '命令',
        title: '设置',
        subtitle: '外观、快捷键和本地服务状态',
        icon: Settings,
        tone: 'secondary',
        shortcut: '⌘,',
        keywords: '偏好设置 appearance settings',
        run: onSettings,
      },
    );

    for (const project of projects) {
      result.push({
        id: `project.${project.path}`,
        group: '项目',
        title: project.displayName,
        subtitle: [shortPath(project.path), project.branch, project.group].filter(Boolean).join(' · '),
        icon: Folder,
        tone: project.starred ? 'gold' : 'blue',
        keywords: [
          project.path,
          project.name,
          project.group,
          project.branch,
          ...(project.stack?.groups || []).flatMap((group) => group.items),
          ...(project.tool?.detected || []).map(toolTitle),
        ].join(' '),
        run: () => onOpenProject(project.path),
      });
    }
    return result;
  }, [
    projects, selectedProject, onAdd, onCopy, onLaunch, onOpenProject, onRescan,
    onResumeSession, onReveal, onSettings, onStar, onStop, onTest, onView,
  ]);

  const visible = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    const matched = items.filter((item) => paletteMatches(item, normalized));
    const groups = ['快捷操作', '导航', '命令', '项目'];
    const ordered = [];
    for (const group of groups) {
      const entries = matched.filter((item) => item.group === group);
      ordered.push(...(group === '项目' && !normalized ? entries.slice(0, 8) : entries));
    }
    return ordered;
  }, [items, query]);

  useEffect(() => {
    if (selection >= visible.length) setSelection(Math.max(0, visible.length - 1));
  }, [selection, visible.length]);

  useEffect(() => {
    if (!open) return undefined;
    const handler = (event) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        onClose();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [open, onClose]);

  useEffect(() => {
    const active = listRef.current?.querySelector('.fizz-palette-row.is-active');
    active?.scrollIntoView({ block: 'nearest' });
  }, [selection, visible]);

  if (!open) return null;

  const activate = (item) => {
    if (!item) return;
    onClose();
    setTimeout(() => item.run?.(), 0);
  };

  return (
    <div className="fizz-palette" onClick={onClose}>
      <div className="fizz-palette-panel" onClick={(event) => event.stopPropagation()}>
        <div className="fizz-palette-search">
          <Search size={15} />
          <input
            ref={inputRef}
            className="fizz-palette-input"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setSelection(0);
            }}
            onKeyDown={(event) => {
              if (event.key === 'ArrowDown') {
                event.preventDefault();
                setSelection((current) => Math.min(visible.length - 1, current + 1));
              } else if (event.key === 'ArrowUp') {
                event.preventDefault();
                setSelection((current) => Math.max(0, current - 1));
              } else if (event.key === 'Enter') {
                event.preventDefault();
                activate(visible[selection]);
              }
            }}
            placeholder="搜索项目、分支或动作"
          />
          {query ? (
            <button type="button" className="fizz-palette-clear" onClick={() => setQuery('')} title="清除">
              <X size={12} />
            </button>
          ) : null}
          <span className="fizz-kbd">⌘K</span>
        </div>

        <div className="fizz-palette-list" ref={listRef}>
          {visible.length ? visible.map((item, index) => {
            const previous = visible[index - 1];
            const Icon = item.icon;
            return (
              <React.Fragment key={item.id}>
                {!previous || previous.group !== item.group ? (
                  <div className="fizz-palette-section">{item.group}</div>
                ) : null}
                <button
                  type="button"
                  className={`fizz-palette-row${selection === index ? ' is-active' : ''}`}
                  onMouseEnter={() => setSelection(index)}
                  onClick={() => activate(item)}
                >
                  <span className="fizz-palette-icon" style={{ color: `var(--fizz-${item.tone === 'secondary' ? 'secondary' : item.tone})` }}>
                    <Icon size={14} />
                  </span>
                  <span className="fizz-palette-copy">
                    <strong>{item.title}</strong>
                    {item.subtitle ? <span>{item.subtitle}</span> : null}
                  </span>
                  {item.shortcut ? <span className="hint">{item.shortcut}</span> : null}
                </button>
              </React.Fragment>
            );
          }) : (
            <div className="fizz-palette-empty">
              <Search size={22} />
              <strong>没有匹配项</strong>
              <span>换一个项目名、分支、路径或动作。</span>
            </div>
          )}
        </div>

        <div className="fizz-palette-foot">
          <span><kbd><ArrowUp size={9} /></kbd><kbd><ArrowDown size={9} /></kbd>选择</span>
          <span><kbd><CornerDownLeft size={9} /></kbd>打开</span>
          <span><kbd>esc</kbd>关闭</span>
          <span className="fizz-spacer" />
          <span>FizzDeck 本地</span>
        </div>
      </div>
    </div>
  );
}

export function Toasts({ toasts }) {
  return (
    <div className="fizz-toast-wrap">
      {toasts.map((item) => (
        <div key={item.id} className={`fizz-toast${item.bad ? ' is-bad' : ''}`}>{item.text}</div>
      ))}
    </div>
  );
}
