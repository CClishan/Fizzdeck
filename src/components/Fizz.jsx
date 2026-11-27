import React from 'react';
import {
  Atom, Bird, Cloud, Folder, Gamepad2, Globe, Package, Triangle, Zap,
  Sparkles, Asterisk, Orbit, Gem, Waves, MessageCircle, Loader2,
} from 'lucide-react';
import { BADGE_META, badgeKind, TOOL_META, toolTitle, toolTone } from '@/lib/tool';

const BADGE_ICONS = {
  triangle: Triangle,
  zap: Zap,
  atom: Atom,
  bird: Bird,
  gamepad: Gamepad2,
  package: Package,
  cloud: Cloud,
  globe: Globe,
  folder: Folder,
};

const TOOL_ICONS = {
  sparkles: Sparkles,
  asterisk: Asterisk,
  orbit: Orbit,
  gem: Gem,
  waves: Waves,
  bubble: MessageCircle,
};

export function BadgeIcon({ project, size = 30, framed = false }) {
  const kind = badgeKind(project);
  const meta = BADGE_META[kind] || BADGE_META.other;
  const Icon = meta.icon ? BADGE_ICONS[meta.icon] : null;
  return (
    <span
      className={`fizz-badge-icon tone-${meta.tone}${framed ? ' framed' : ''}`}
      style={{ width: size, height: size, fontSize: Math.round(size * (framed ? 0.42 : 0.56)) }}
      title={meta.label}
    >
      {meta.text || (Icon ? <Icon size={Math.round(size * (framed ? 0.46 : 0.58))} strokeWidth={2.2} /> : null)}
    </span>
  );
}

export function ToolBadge({ tool, compact = false }) {
  const meta = TOOL_META[tool];
  const Icon = TOOL_ICONS[meta?.symbol || 'bubble'];
  return (
    <span className={`fizz-chip tone-${toolTone(tool)}`} title={toolTitle(tool)}>
      <Icon size={10} strokeWidth={2.1} />
      {compact ? null : toolTitle(tool)}
    </span>
  );
}

export function ToolIcon({ tool, size = 14 }) {
  const Icon = TOOL_ICONS[TOOL_META[tool]?.symbol || 'bubble'];
  return <Icon size={size} strokeWidth={2} style={{ color: `var(--fizz-${toolTone(tool)})` }} />;
}

export function Panel({ title, icon: Icon, action, children, className = '', style }) {
  return (
    <section className={`fizz-panel ${className}`} style={style}>
      {title ? (
        <div className="fizz-panel-head">
          {Icon ? <Icon size={13} strokeWidth={2} className="fizz-muted" /> : null}
          <div className="fizz-panel-title">{title}</div>
          <div className="fizz-spacer" />
          {action}
        </div>
      ) : null}
      {children}
    </section>
  );
}

export function StatCard({ title, icon: Icon, value, unit, detail, bars, peak, tint }) {
  return (
    <div className="fizz-stat-card">
      <div className="fizz-stat-title">
        {Icon ? <Icon size={13} strokeWidth={2} style={{ color: tint }} /> : null}
        {title}
      </div>
      <div className="fizz-stat-value">
        {value}
        {unit ? <small>{unit}</small> : null}
      </div>
      {bars?.length ? (
        <div className="fizz-bars">
          {bars.map((value, index) => (
            <span
              key={index}
              className={index === peak ? 'is-peak' : ''}
              style={{ height: `${Math.max(6, Math.round(value * 100))}%`, background: index === peak && tint ? tint : undefined }}
            />
          ))}
        </div>
      ) : null}
      {detail ? <div className="fizz-stat-detail fizz-line-2">{detail}</div> : null}
    </div>
  );
}

export function EmptyState({ icon: Icon = Folder, title, detail, action }) {
  return (
    <div className="fizz-empty">
      <div>
        <Icon size={26} strokeWidth={1.6} style={{ margin: '0 auto', opacity: 0.55 }} />
        <strong>{title}</strong>
        {detail ? <p>{detail}</p> : null}
        {action ? <div style={{ marginTop: 12 }}>{action}</div> : null}
      </div>
    </div>
  );
}

export function Segmented({ options, value, onChange, className = '' }) {
  return (
    <div className={`fizz-seg ${className}`}>
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          className={value === option.value ? 'is-active' : ''}
          onClick={() => onChange(option.value)}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

export function Spinner({ size = 14 }) {
  return <Loader2 size={size} className="fizz-spin" />;
}

export function StatusDot({ running, tone = 'green' }) {
  return <span className={`fizz-dot ${running ? tone : 'secondary'}`} />;
}
