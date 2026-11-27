export function fmtBytes(value) {
  const bytes = Math.max(0, Number(value) || 0);
  if (bytes < 1000) return `${bytes} B`;
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  let v = bytes / 1000;
  let index = 0;
  while (v >= 1000 && index < units.length - 1) {
    v /= 1000;
    index += 1;
  }
  const digits = v >= 100 ? 0 : v >= 10 ? 1 : 2;
  return `${v.toFixed(digits).replace(/\.0+$/, '')} ${units[index]}`;
}

export function splitBytes(value) {
  const bytes = Math.max(0, Number(value) || 0);
  if (bytes < 1000) return { value: String(bytes), unit: 'B' };
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  let v = bytes / 1000;
  let index = 0;
  while (v >= 999.95 && index < units.length - 1) {
    v /= 1000;
    index += 1;
  }
  return {
    value: v >= 100 ? v.toFixed(0) : v >= 10 ? v.toFixed(1) : v.toFixed(2),
    unit: units[index],
  };
}

export function fmtTokens(value) {
  const n = Math.max(0, Number(value) || 0);
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(n);
}

export function fmtCost(value, estimated = false) {
  if (value == null || !Number.isFinite(Number(value)) || Number(value) < 0) return null;
  const n = Number(value);
  const prefix = estimated ? '~' : '';
  if (n === 0) return `${prefix}$0`;
  if (n < 0.01) return `${prefix}<$0.01`;
  if (n < 10) return `${prefix}$${n.toFixed(2)}`;
  return `${prefix}$${n.toFixed(1)}`;
}

export function relativeTime(iso) {
  if (!iso) return '—';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '—';
  const diff = (Date.now() - date.getTime()) / 1000;
  if (Math.abs(diff) < 10) return '刚刚';
  if (diff < 60) return `${Math.max(1, Math.floor(diff))} 秒前`;
  if (diff < 3600) return `${Math.floor(diff / 60)} 分钟前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} 小时前`;
  if (diff < 86400 * 30) return `${Math.floor(diff / 86400)} 天前`;
  if (diff < 86400 * 365) return `${Math.floor(diff / 86400 / 30)} 个月前`;
  return `${(diff / 86400 / 365).toFixed(1)} 年前`;
}

export function shortPath(path) {
  return String(path || '').replace(/^\/(?:Users|home)\/[^/]+/, '~');
}

export function todayTitle(date = new Date()) {
  return new Intl.DateTimeFormat('zh-CN', {
    month: 'long',
    day: 'numeric',
    weekday: 'long',
  }).format(date);
}

export function shortTime(iso) {
  if (!iso) return '—';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(date);
}

export function dayKey(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

export function addDays(date, days) {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

export function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

export function copyText(text) {
  return navigator.clipboard.writeText(String(text ?? ''));
}

export function stripAnsi(text) {
  return String(text ?? '').replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, '');
}
