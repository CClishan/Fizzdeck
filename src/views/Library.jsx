import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Check, ChevronDown, ChevronRight, GitBranch, LayoutGrid, List, Search, Star, X,
} from 'lucide-react';
import { BadgeIcon, Segmented, ToolBadge } from '@/components/Fizz.jsx';
import { fmtBytes, relativeTime, shortPath } from '@/lib/format.js';
import { allToolNames, groupTone, stackChipTone, toolTitle, toolTone } from '@/lib/tool.js';

const SORTS = [
  { value: 'recent', label: '最近活动' },
  { value: 'name', label: '名称' },
  { value: 'size', label: '体积' },
  { value: 'dirty', label: '改动数' },
];

function sortProjects(projects, sort) {
  const list = [...projects];
  list.sort((a, b) => {
    if (sort === 'name') return a.displayName.localeCompare(b.displayName, 'zh-CN');
    if (sort === 'size') return b.size.totalBytes - a.size.totalBytes;
    if (sort === 'dirty') return (b.dirtyCount || 0) - (a.dirtyCount || 0) || String(b.recent || '').localeCompare(String(a.recent || ''));
    return String(b.recent || '').localeCompare(String(a.recent || ''));
  });
  return list;
}

function activeFilterCount(query) {
  return ['group', 'color', 'tool', 'framework', 'commitDayKey'].filter((key) => query[key]).length;
}

function ProjectCard({ project, selecting, selected, onClick, onToggle }) {
  const firstStack = project.stack?.groups?.flatMap((group) => group.items)[0];
  const firstGroup = project.stack?.groups?.[0];
  const detail = project.note?.trim() || project.lastCommit?.subject || project.intro?.text || '没有可读活动';
  return (
    <div
      className={`fizz-project-card fizz-card-hover${selected ? ' is-selected' : ''}`}
      role="button"
      tabIndex={0}
      onClick={() => (selecting ? onToggle(project.path) : onClick(project.path))}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          if (selecting) onToggle(project.path);
          else onClick(project.path);
        }
      }}
      title={selecting ? (selected ? `取消选择 ${project.displayName}` : `选择 ${project.displayName}`) : `打开 ${project.displayName}`}
    >
      <div className="fizz-project-card-head">
        <BadgeIcon project={project} size={32} />
        <div className="fizz-project-card-title">
          <strong>
            {project.displayName}
            {project.starred ? <Star size={9} fill="var(--fizz-gold)" stroke="none" /> : null}
          </strong>
          <div className="fizz-project-card-sub">
            {project.group}{project.branch ? ` · ${project.branch}` : ''}
            {project.dirtyCount ? <span className="fizz-chip tone-orange compact" style={{ marginLeft: 5 }}>{project.dirtyCount} 处改动</span> : null}
          </div>
        </div>
        {selecting ? (
          <span className={`fizz-checkbox${selected ? ' is-on' : ''}`}>
            {selected ? <Check size={10} strokeWidth={3} /> : null}
          </span>
        ) : project.portState === 'running' ? (
          <span className="fizz-chip tone-green compact">:{project.run?.port}</span>
        ) : null}
      </div>
      <div className={`fizz-project-detail${project.note?.trim() ? ' has-note' : ''}`}>{detail}</div>
      <div className="fizz-project-foot">
        {firstStack ? (
          <span className={`fizz-chip tone-${stackChipTone(firstGroup?.key)} compact`}>{firstStack}</span>
        ) : null}
        {project.tool?.lastTool ? <ToolBadge tool={project.tool.lastTool} compact /> : null}
        <span className="fizz-spacer" />
        <span className="fizz-panel-sub">{relativeTime(project.recent)}</span>
      </div>
    </div>
  );
}

function Table({ projects, selecting, selected, onToggle, onOpen }) {
  return (
    <div className="fizz-card" style={{ overflow: 'hidden' }}>
      <table className="fizz-table">
        <thead>
          <tr>
            {selecting ? <th style={{ width: 28 }} /> : null}
            <th>项目</th>
            <th>分组</th>
            <th>技术栈</th>
            <th className="num">体积</th>
            <th className="num">可回收</th>
            <th className="num">改动</th>
            <th>AI</th>
            <th className="num">最近</th>
          </tr>
        </thead>
        <tbody>
          {projects.map((project) => (
            <tr
              key={project.path}
              onClick={() => (selecting ? onToggle(project.path) : onOpen(project.path))}
            >
              {selecting ? (
                <td>
                  <span className={`fizz-checkbox${selected.has(project.path) ? ' is-on' : ''}`}>
                    {selected.has(project.path) ? <Check size={10} strokeWidth={3} /> : null}
                  </span>
                </td>
              ) : null}
              <td>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span className="fizz-dot" style={{ background: groupTone(project.group).hex }} />
                  <BadgeIcon project={project} size={18} />
                  <strong style={{ fontWeight: 500 }}>{project.displayName}</strong>
                  {project.portState === 'running' ? <span className="fizz-chip tone-green compact">:{project.run?.port}</span> : null}
                </div>
              </td>
              <td style={{ color: 'var(--fizz-secondary)' }}>{project.group}</td>
              <td style={{ color: 'var(--fizz-secondary)', maxWidth: 220, overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {project.stack.groups.flatMap((group) => group.items).slice(0, 3).join(' · ') || '—'}
              </td>
              <td className="num">{fmtBytes(project.size.totalBytes)}</td>
              <td className="num" style={{ color: project.cleandoc.reusableBytes ? 'var(--fizz-orange)' : 'var(--fizz-tertiary)' }}>
                {project.cleandoc.reusableBytes ? fmtBytes(project.cleandoc.reusableBytes) : '—'}
              </td>
              <td className="num" style={{ color: project.dirtyCount ? 'var(--fizz-orange)' : 'var(--fizz-tertiary)' }}>
                {project.dirtyCount || '—'}
              </td>
              <td style={{ color: 'var(--fizz-secondary)' }}>
                {project.tool?.lastTool ? <ToolBadge tool={project.tool.lastTool} compact /> : '—'}
              </td>
              <td className="num" style={{ color: 'var(--fizz-secondary)' }}>{relativeTime(project.recent)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function Library({
  projects, initialQuery, onOpenProject, onToggleStar, onBatchStar, onBatchGroup, onBatchFetch,
  onCopy, onRescan, onAdd,
}) {
  const [query, setQuery] = useState(() => ({ sort: 'recent', mode: 'cards', ...(initialQuery || {}) }));
  const [selectionMode, setSelectionMode] = useState(false);
  const [selected, setSelected] = useState(() => new Set());
  const [showIdle, setShowIdle] = useState(false);
  const [batchFeedback, setBatchFeedback] = useState('');
  const searchRef = useRef(null);

  useEffect(() => {
    setQuery((current) => ({ ...current, ...(initialQuery || {}) }));
  }, [initialQuery]);

  useEffect(() => {
    const handler = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'f') {
        event.preventDefault();
        searchRef.current?.focus();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, []);

  const groups = useMemo(() => [...new Set(projects.map((project) => project.group))], [projects]);
  const tools = useMemo(() => [...new Set(projects.flatMap(allToolNames))], [projects]);
  const frameworks = useMemo(() => [...new Set(projects.flatMap((project) => [
    ...(project.stack?.frameworks || []),
    ...(project.stack?.languages || []),
  ]))].slice(0, 40), [projects]);
  const colors = ['red', 'amber', 'green', 'blue', 'violet'];

  const filtered = useMemo(() => {
    const text = String(query.searchText || '').trim().toLowerCase();
    return projects.filter((project) => {
      if (query.group && project.group !== query.group) return false;
      if (query.color && project.color !== query.color) return false;
      if (query.tool && !allToolNames(project).includes(query.tool)) return false;
      if (query.framework && ![...(project.stack?.languages || []), ...(project.stack?.frameworks || [])].includes(query.framework)) return false;
      if (query.commitDayKey && !(project.activity?.daily?.[query.commitDayKey] > 0)) return false;
      if (text) {
        const haystack = [
          project.displayName, project.name, project.path, project.note, project.group, project.branch,
          ...(project.stack?.groups || []).flatMap((group) => group.items),
        ].join(' ').toLowerCase();
        if (!haystack.includes(text)) return false;
      }
      return true;
    });
  }, [projects, query]);

  const sorted = useMemo(() => sortProjects(filtered, query.sort), [filtered, query.sort]);
  const active = useMemo(() => sorted.filter((project) => {
    if (query.commitDayKey) return true;
    if (project.portState === 'running' || project.dirtyCount > 0) return true;
    if (!project.recent) return false;
    return Date.now() - new Date(project.recent).getTime() < 14 * 86400000;
  }), [sorted, query.commitDayKey]);
  const idle = useMemo(() => (query.commitDayKey ? [] : sorted.filter((project) => !active.includes(project))), [sorted, active, query.commitDayKey]);
  const selectedProjects = sorted.filter((project) => selected.has(project.path));
  const activeFilterTotal = activeFilterCount(query);
  const runningCount = sorted.filter((project) => project.portState === 'running').length;

  const toggleSelection = (path) => {
    const next = new Set(selected);
    if (next.has(path)) next.delete(path);
    else next.add(path);
    setSelected(next);
  };

  const selectAll = () => {
    setSelected(new Set(sorted.map((project) => project.path)));
  };

  const clearFilters = () => {
    setQuery((current) => ({
      ...current,
      group: null, color: null, tool: null, framework: null, commitDayKey: null,
    }));
  };

  const batchCopyCleanup = () => {
    const blocks = selectedProjects.map((project) => {
      const commands = project.cleandoc.items.map((item) => `rm -rf '${item.path.replace(/'/g, `'\\''`)}'`).join('\n');
      return commands ? `# ${project.displayName}\n${commands}` : null;
    }).filter(Boolean);
    if (!blocks.length) {
      setBatchFeedback('所选项目没有可清理目录');
      return;
    }
    onCopy(blocks.join('\n'));
    setBatchFeedback(`已复制 ${blocks.length} 个项目的清理命令`);
  };

  const batchGroup = () => {
    const name = window.prompt('把所选项目归到哪个分组？', selectedProjects[0]?.group || '');
    if (!name?.trim()) return;
    onBatchGroup([...selected], name.trim());
    setBatchFeedback(`已移动到「${name.trim()}」`);
  };

  return (
    <div className="fizz-page-scroll">
      <div className="fizz-page-inner">
        <div className="fizz-page-head">
          <div>
            <h1>项目库</h1>
            <div className="fizz-page-sub">
              {sorted.length} 个{activeFilterTotal ? ` · 筛选自 ${projects.length} 个` : ''}
              {runningCount ? ` · ${runningCount} 个运行中` : ''}
            </div>
          </div>
          <div className="fizz-head-actions">
            <Segmented
              value={query.mode}
              onChange={(value) => setQuery((current) => ({ ...current, mode: value }))}
              options={[
                { value: 'cards', label: '卡片' },
                { value: 'list', label: '表格' },
              ]}
            />
            <button
              type="button"
              className={`fizz-btn${selectionMode ? ' primary' : ''}`}
              onClick={() => {
                setSelectionMode(!selectionMode);
                if (selectionMode) setSelected(new Set());
              }}
            >
              {selectionMode ? <X size={12} /> : <Check size={12} />}
              {selectionMode ? '退出选择' : '选择'}
            </button>
            <button type="button" className="fizz-btn" onClick={onAdd}>添加项目</button>
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 14 }}>
          <div className="fizz-filterbar">
            <div style={{ position: 'relative', flex: '1 1 260px', maxWidth: 420 }}>
              <Search size={13} style={{ position: 'absolute', left: 9, top: 9, color: 'var(--fizz-tertiary)' }} />
              <input
                ref={searchRef}
                value={query.searchText || ''}
                onChange={(event) => setQuery((current) => ({ ...current, searchText: event.target.value }))}
                className="fizz-input"
                style={{ paddingLeft: 30 }}
                placeholder="搜索项目、分支、路径或技术栈（⌘F）"
              />
            </div>
            <select className="fizz-select" value={query.group || ''} onChange={(event) => setQuery((current) => ({ ...current, group: event.target.value || null }))}>
              <option value="">全部分组</option>
              {groups.map((group) => <option key={group} value={group}>{group}</option>)}
            </select>
            <select className="fizz-select" value={query.color || ''} onChange={(event) => setQuery((current) => ({ ...current, color: event.target.value || null }))}>
              <option value="">全部颜色</option>
              {colors.map((color) => <option key={color} value={color}>{color}</option>)}
            </select>
            <select className="fizz-select" value={query.tool || ''} onChange={(event) => setQuery((current) => ({ ...current, tool: event.target.value || null }))}>
              <option value="">全部 AI 工具</option>
              {tools.map((tool) => <option key={tool} value={tool}>{toolTitle(tool)}</option>)}
            </select>
            {frameworks.length ? (
              <select className="fizz-select" value={query.framework || ''} onChange={(event) => setQuery((current) => ({ ...current, framework: event.target.value || null }))}>
                <option value="">全部框架</option>
                {frameworks.map((framework) => <option key={framework} value={framework}>{framework}</option>)}
              </select>
            ) : null}
            <select className="fizz-select" value={query.sort} onChange={(event) => setQuery((current) => ({ ...current, sort: event.target.value }))}>
              {SORTS.map((sort) => <option key={sort.value} value={sort.value}>{sort.label}</option>)}
            </select>
            {activeFilterTotal ? (
              <button type="button" className="fizz-filter-chip is-active" onClick={clearFilters}>
                清除 {activeFilterTotal} 项筛选 <X size={10} />
              </button>
            ) : null}
          </div>
          {query.commitDayKey ? (
            <div className="fizz-chip tone-gold" style={{ alignSelf: 'flex-start' }}>
              提交日 {query.commitDayKey}
              <button
                type="button"
                onClick={() => setQuery((current) => ({ ...current, commitDayKey: null }))}
                style={{ border: 0, background: 'transparent', color: 'inherit', padding: 0, display: 'grid', placeItems: 'center' }}
              ><X size={10} /></button>
            </div>
          ) : null}
        </div>

        {!sorted.length ? (
          <div className="fizz-card fizz-empty">
            <div>
              <LayoutGrid size={26} style={{ opacity: 0.45 }} />
              <strong>没有匹配的项目</strong>
              <p>换个搜索词或清除筛选。</p>
            </div>
          </div>
        ) : query.mode === 'list' ? (
          <Table
            projects={sorted}
            selecting={selectionMode}
            selected={selected}
            onToggle={toggleSelection}
            onOpen={onOpenProject}
          />
        ) : (
          <>
            <div className="fizz-grid fizz-auto-grid">
              {active.map((project) => (
                <ProjectCard
                  key={project.path}
                  project={project}
                  selecting={selectionMode}
                  selected={selected.has(project.path)}
                  onClick={onOpenProject}
                  onToggle={toggleSelection}
                />
              ))}
            </div>
            {idle.length ? (
              <div style={{ marginTop: 16 }}>
                <div className="fizz-idle-fold">
                  <button type="button" onClick={() => setShowIdle(!showIdle)}>
                    {showIdle ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
                    {' '}闲置项目 {idle.length}
                  </button>
                  <span className="fizz-tertiary">14 天以上没有活动</span>
                </div>
                {showIdle ? (
                  <div className="fizz-grid fizz-auto-grid">
                    {idle.map((project) => (
                      <ProjectCard
                        key={project.path}
                        project={project}
                        selecting={selectionMode}
                        selected={selected.has(project.path)}
                        onClick={onOpenProject}
                        onToggle={toggleSelection}
                      />
                    ))}
                  </div>
                ) : null}
              </div>
            ) : null}
          </>
        )}
      </div>

      {selectionMode && selected.size ? (
        <div className="fizz-batch-bar">
          <span className="count">已选 {selected.size}</span>
          <button type="button" className="fizz-btn small" onClick={() => onBatchStar([...selected])}><Star size={11} />星标</button>
          <button type="button" className="fizz-btn small" onClick={batchGroup}>分组</button>
          <button type="button" className="fizz-btn small" onClick={() => onBatchFetch([...selected])}><GitBranch size={11} />同步远程</button>
          <button type="button" className="fizz-btn small" onClick={() => onRescan()}>重新扫描</button>
          <button type="button" className="fizz-btn small" onClick={batchCopyCleanup}>复制清理</button>
          <button type="button" className="fizz-btn small ghost" onClick={selectAll}>全选</button>
          <button type="button" className="fizz-btn small ghost" onClick={() => setSelected(new Set())}>清空</button>
          <button type="button" className="fizz-btn small primary" onClick={() => { setSelectionMode(false); setSelected(new Set()); }}>完成</button>
          {batchFeedback ? <span className="count">{batchFeedback}</span> : null}
        </div>
      ) : null}
    </div>
  );
}
