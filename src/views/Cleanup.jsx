import React, { useMemo, useState } from 'react';
import {
  Archive, Boxes, Clipboard, Clock, Database, FolderMinus, Hammer, Package, Trash2,
} from 'lucide-react';
import { BadgeIcon, Panel } from '@/components/Fizz.jsx';
import { fmtBytes, relativeTime } from '@/lib/format.js';

const KIND_META = {
  deps: { icon: Package, tone: 'green' },
  build: { icon: Hammer, tone: 'orange' },
  tmp: { icon: Clock, tone: 'red' },
  archive: { icon: Archive, tone: 'violet' },
  default: { icon: FolderMinus, tone: 'secondary' },
};

const removalCommand = (item) => `rm -rf '${item.path.replace(/'/g, `'\\''`)}'`;

function CleanupRow({ item, onCopy }) {
  const meta = KIND_META[item.kind] || KIND_META.default;
  const Icon = meta.icon;
  return (
    <div className="fizz-clean-row">
      <span className="fizz-clean-icon" style={{ color: `var(--fizz-${meta.tone === 'secondary' ? 'secondary' : meta.tone})` }}>
        <Icon size={14} />
      </span>
      <div className="fizz-clean-main">
        <div className="fizz-clean-title">{item.label}<span>{fmtBytes(item.bytes)}</span></div>
        <div className="fizz-clean-sub">
          {item.reason}{item.regen ? ` · ${item.regen}` : ''}
        </div>
      </div>
      <button
        type="button"
        className="fizz-icon-btn plain"
        title="复制删除命令"
        onClick={() => onCopy(removalCommand(item))}
      >
        <Clipboard size={12} />
      </button>
    </div>
  );
}

export function Cleanup({ projects, orphans, onOpenProject, onCopy }) {
  const [feedback, setFeedback] = useState('');
  const cleanable = useMemo(() => projects
    .filter((project) => project.cleandoc?.items?.length)
    .sort((a, b) => b.cleandoc.reusableBytes - a.cleandoc.reusableBytes), [projects]);
  const totalBytes = cleanable.reduce((sum, project) => sum + project.cleandoc.reusableBytes, 0);
  const totalItems = cleanable.reduce((sum, project) => sum + project.cleandoc.items.length, 0);
  const orphanBytes = orphans?.totalBytes || 0;

  const copyAll = () => {
    const blocks = cleanable.map((project) => `# ${project.displayName}\n${project.cleandoc.items.map(removalCommand).join('\n')}`);
    onCopy(blocks.join('\n\n'));
    setFeedback(`已复制 ${cleanable.length} 个项目的全部清理命令`);
  };

  return (
    <div className="fizz-page-scroll">
      <div className="fizz-page-inner">
        <div className="fizz-page-head">
          <div>
            <h1>可清理</h1>
            <div className="fizz-page-sub">
              {cleanable.length
                ? `${fmtBytes(totalBytes)} · ${cleanable.length} 个项目 · ${totalItems} 个目录 · 只复制命令，不自动删除`
                : '只复制清理命令，不自动删除文件'}
            </div>
          </div>
          <div className="fizz-head-actions">
            {cleanable.length ? (
              <button type="button" className="fizz-btn" onClick={copyAll}>
                <Clipboard size={12} />复制全部命令
              </button>
            ) : null}
          </div>
        </div>

        {feedback ? (
          <div className="fizz-chip tone-blue" style={{ marginBottom: 12 }}>{feedback}</div>
        ) : null}

        {!cleanable.length ? (
          <div className="fizz-card fizz-empty">
            <div>
              <Archive size={26} style={{ opacity: 0.45 }} />
              <strong>没有可清理项</strong>
              <p>已扫描的项目中没有命中依赖、构建产物或缓存清理规则的目录。</p>
            </div>
          </div>
        ) : (
          <div className="fizz-stack" style={{ gap: 12 }}>
            {cleanable.map((project) => (
              <div className="fizz-clean-project" key={project.path}>
                <div className="fizz-clean-head">
                  <BadgeIcon project={project} size={26} />
                  <button
                    type="button"
                    onClick={() => onOpenProject(project.path, 'cleanup')}
                    style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 2, padding: 0, border: 0, background: 'transparent', minWidth: 0, flex: 1, textAlign: 'left' }}
                  >
                    <span className="title">{project.displayName}</span>
                    <span className="fizz-panel-sub">{project.cleandoc.items.length} 个目录</span>
                  </button>
                  <strong className="fizz-mono" style={{ color: 'var(--fizz-orange)', fontSize: 13 }}>{fmtBytes(project.cleandoc.reusableBytes)}</strong>
                  <button
                    type="button"
                    className="fizz-btn small"
                    onClick={() => {
                      onCopy(`# ${project.displayName}\n${project.cleandoc.items.map(removalCommand).join('\n')}`);
                      setFeedback(`已复制 ${project.displayName} 的清理命令`);
                    }}
                  >
                    <Clipboard size={11} />复制
                  </button>
                </div>
                <div className="fizz-divider" style={{ margin: '0 14px', opacity: 0.5 }} />
                {project.cleandoc.items.map((item) => (
                  <CleanupRow key={item.path} item={item} onCopy={(command) => {
                    onCopy(command);
                    setFeedback(`已复制 ${project.displayName}/${item.label} 清理命令`);
                  }} />
                ))}
              </div>
            ))}
          </div>
        )}

        {orphans?.groups?.length ? (
          <div style={{ marginTop: 20 }}>
            <Panel title="AI 会话历史" icon={Database} action={<span className="fizz-panel-sub">{fmtBytes(orphanBytes)}</span>}>
              <div className="fizz-panel-sub" style={{ marginTop: -4, marginBottom: 10 }}>
                历史会话只读展示，复制命令后可自行清理。
              </div>
              {orphans.groups.map((group) => (
                <div key={group.site} style={{ padding: '8px 0', borderTop: '1px solid var(--fizz-hairline)' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <Boxes size={13} className="fizz-muted" />
                    <strong style={{ fontSize: 11.5, fontWeight: 500 }}>{group.site}</strong>
                    <span className="fizz-spacer" />
                    <span className="fizz-mono fizz-muted">{fmtBytes(group.totalBytes)}</span>
                    <button
                      type="button"
                      className="fizz-btn small"
                      onClick={() => {
                        onCopy(group.pruneCommand);
                        setFeedback(`已复制 ${group.site} 清理命令`);
                      }}
                    >
                      <Clipboard size={10} />命令
                    </button>
                  </div>
                  <div className="fizz-panel-sub" style={{ marginTop: 3 }}>{group.note}</div>
                  {group.items.slice(0, 3).map((item) => (
                    <div key={item.path} style={{ display: 'flex', gap: 8, padding: '3px 0 0 21px', color: 'var(--fizz-tertiary)', fontSize: 10 }}>
                      <span className="fizz-truncate" style={{ flex: 1 }}>{item.path}</span>
                      <span>{fmtBytes(item.bytes)}</span>
                      <span>{relativeTime(item.mtime)}</span>
                    </div>
                  ))}
                </div>
              ))}
            </Panel>
          </div>
        ) : null}
      </div>
    </div>
  );
}
