import React, { useMemo, useState } from 'react';
import {
  Archive, ChevronDown, ChevronRight, House, LayoutGrid, PanelLeftClose, PanelLeftOpen,
  Plus, Search, Settings, Star,
} from 'lucide-react';
import fizzLogo from '@/assets/fizzdeck-logo.png';
import { BadgeIcon } from '@/components/Fizz.jsx';
import { fmtBytes } from '@/lib/format.js';

function SidebarProjectRow({ project, selected, running, port, onOpen }) {
  return (
    <button
      type="button"
      className={`fizz-project-row${selected ? ' is-active' : ''}`}
      onClick={() => onOpen(project.path)}
      title={project.path}
    >
      <BadgeIcon project={project} size={20} />
      <span className="name">{project.displayName}</span>
      {running ? <span className="port">:{port}</span> : null}
    </button>
  );
}

function SectionHeader({ icon, title, action }) {
  return (
    <div className="fizz-side-head">
      {icon}
      <span>{title}</span>
      <span className="fizz-spacer" />
      {action}
    </div>
  );
}

export function Sidebar({
  projects, view, selectedPath, onView, onOpenProject, onPalette, onAdd, onSettings,
  collapsed, onToggleCollapsed, disk,
}) {
  const [closedGroups, setClosedGroups] = useState(() => new Set());
  const runningProjects = projects.filter((project) => project.portState === 'running');
  const starred = projects.filter((project) => project.starred);
  const cleanupBytes = projects.reduce((sum, project) => sum + (project.cleandoc?.reusableBytes || 0), 0);
  const groups = useMemo(() => {
    const map = new Map();
    for (const project of projects) {
      const group = project.group || '其他';
      if (!map.has(group)) map.set(group, []);
      map.get(group).push(project);
    }
    return [...map.entries()];
  }, [projects]);

  const usedFraction = disk?.total ? Math.min(1, Math.max(0, 1 - disk.free / disk.total)) : 0;

  if (collapsed) {
    return (
      <aside className="fizz-sidebar is-collapsed">
        <div className="fizz-sidebar-scroll" style={{ paddingBottom: 8 }}>
          <div className="fizz-rail">
            <button type="button" className="fizz-rail-btn" title="展开侧栏" onClick={onToggleCollapsed}>
              <PanelLeftOpen size={15} />
            </button>
            <button type="button" className="fizz-rail-btn" title="搜索项目和动作（⌘K）" onClick={onPalette}>
              <Search size={15} />
            </button>
            <div className="fizz-rail-scroll">
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2 }}>
                <button type="button" className={`fizz-rail-btn${view === 'workbench' ? ' is-active' : ''}`} title="工作台" onClick={() => onView('workbench')}>
                  <House size={15} />
                  {runningProjects.length ? <span className="dot" /> : null}
                </button>
                <button type="button" className={`fizz-rail-btn${view === 'library' ? ' is-active' : ''}`} title="项目库" onClick={() => onView('library')}>
                  <LayoutGrid size={15} />
                </button>
                <button type="button" className={`fizz-rail-btn${view === 'cleanup' ? ' is-active' : ''}`} title={`可清理 ${fmtBytes(cleanupBytes)}`} onClick={() => onView('cleanup')}>
                  <Archive size={15} />
                  {cleanupBytes ? <span className="dot" /> : null}
                </button>
                <div className="fizz-rail-divider" />
                {starred.map((project) => (
                  <button
                    type="button"
                    key={project.path}
                    className={`fizz-rail-btn${selectedPath === project.path ? ' is-active' : ''}`}
                    title={project.displayName}
                    onClick={() => onOpenProject(project.path)}
                    style={{ height: 30 }}
                  >
                    <BadgeIcon project={project} size={20} />
                    {project.portState === 'running' ? <span className="dot" /> : null}
                  </button>
                ))}
                {starred.length ? <div className="fizz-rail-divider" /> : null}
                {projects.filter((project) => !project.starred).map((project) => (
                  <button
                    type="button"
                    key={project.path}
                    className={`fizz-rail-btn${selectedPath === project.path ? ' is-active' : ''}`}
                    title={project.displayName}
                    onClick={() => onOpenProject(project.path)}
                    style={{ height: 30 }}
                  >
                    <BadgeIcon project={project} size={20} />
                    {project.portState === 'running' ? <span className="dot" /> : null}
                  </button>
                ))}
              </div>
            </div>
            <button type="button" className="fizz-rail-btn" title="设置" onClick={onSettings}>
              <Settings size={15} />
            </button>
          </div>
        </div>
      </aside>
    );
  }

  return (
    <aside className="fizz-sidebar">
      <div className="fizz-sidebar-scroll">
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '0 4px 10px' }}>
          <img src={fizzLogo} alt="" width={24} height={24} style={{ objectFit: 'contain' }} />
          <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '-0.01em' }}>FizzDeck</div>
          <span className="fizz-spacer" />
          <button type="button" className="fizz-icon-btn plain" title="收起侧栏" onClick={onToggleCollapsed} style={{ width: 24, height: 24 }}>
            <PanelLeftClose size={14} />
          </button>
        </div>

        <button type="button" className="fizz-search" onClick={onPalette}>
          <Search size={13} />
          <span>搜索</span>
          <span className="fizz-kbd">⌘K</span>
        </button>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 1, marginTop: 10 }}>
          <button type="button" className={`fizz-nav-row${view === 'workbench' ? ' is-active' : ''}`} onClick={() => onView('workbench')}>
            <House size={14} />
            <span>工作台</span>
            <span className={`fizz-nav-detail${runningProjects.length ? ' is-green' : ''}`}>
              {runningProjects.length ? `${runningProjects.length} 运行中` : ''}
            </span>
          </button>
          <button type="button" className={`fizz-nav-row${view === 'library' ? ' is-active' : ''}`} onClick={() => onView('library')}>
            <LayoutGrid size={14} />
            <span>项目库</span>
            <span className="fizz-nav-detail">{projects.length}</span>
          </button>
          <button type="button" className={`fizz-nav-row${view === 'cleanup' ? ' is-active' : ''}`} onClick={() => onView('cleanup')}>
            <Archive size={14} />
            <span>可清理</span>
            <span className="fizz-nav-detail">{fmtBytes(cleanupBytes)}</span>
          </button>
        </div>

        <div className="fizz-side-section">
          {starred.length ? (
            <>
              <SectionHeader icon={<Star size={10} fill="var(--fizz-gold)" stroke="none" />} title="星标" />
              {starred.map((project) => (
                <SidebarProjectRow
                  key={project.path}
                  project={project}
                  selected={selectedPath === project.path}
                  running={project.portState === 'running'}
                  port={project.run?.port}
                  onOpen={onOpenProject}
                />
              ))}
            </>
          ) : null}

          {runningProjects.length ? (
            <>
              <SectionHeader icon={<span className="fizz-dot green" />} title="正在运行" />
              {runningProjects.map((project) => (
                <SidebarProjectRow
                  key={project.path}
                  project={project}
                  selected={selectedPath === project.path}
                  running
                  port={project.run?.port}
                  onOpen={onOpenProject}
                />
              ))}
            </>
          ) : null}

          {groups.map(([group, items]) => {
            const closed = closedGroups.has(group);
            return (
              <div key={group} className="fizz-side-section" style={{ marginTop: 6 }}>
                <div className="fizz-side-head">
                  <button
                    type="button"
                    onClick={() => {
                      const next = new Set(closedGroups);
                      if (next.has(group)) next.delete(group);
                      else next.add(group);
                      setClosedGroups(next);
                    }}
                    title={closed ? `展开 ${group}` : `折叠 ${group}`}
                  >
                    {closed ? <ChevronRight size={11} /> : <ChevronDown size={11} />}
                  </button>
                  <span>{group}</span>
                  <span className="fizz-spacer" />
                  <button type="button" onClick={onAdd} title="添加项目目录"><Plus size={12} /></button>
                </div>
                {closed ? null : items.map((project) => (
                  <SidebarProjectRow
                    key={project.path}
                    project={project}
                    selected={selectedPath === project.path}
                    running={project.portState === 'running'}
                    port={project.run?.port}
                    onOpen={onOpenProject}
                  />
                ))}
              </div>
            );
          })}
        </div>
      </div>

      <div className="fizz-side-footer">
        {disk ? (
          <div className="fizz-side-metric" title="磁盘可用空间">
            <span className="fizz-value">{fmtBytes(disk.free)}</span>
            <span>可用</span>
            <span className="fizz-spacer" />
            <span className="fizz-disk-bar"><span style={{ width: `${Math.max(4, usedFraction * 100)}%` }} /></span>
          </div>
        ) : null}
        <button type="button" className="fizz-settings-row" onClick={onSettings}>
          <Settings size={14} />
          <span>设置</span>
          <span className="fizz-spacer" />
          <span className="fizz-kbd">⌘,</span>
        </button>
      </div>
    </aside>
  );
}
