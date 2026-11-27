import { addDays, dayKey, startOfDay } from '@/lib/format.js';
import { groupTone, toolTitle, toolTone } from '@/lib/tool.js';

export const ATTENTION_META = {
  testFailed: { label: '测试失败', priority: 0, tab: 'tests', tone: 'red' },
  behind: { label: '落后远端', priority: 1, tab: 'git', tone: 'orange' },
  unpushed: { label: '未推送', priority: 2, tab: 'git', tone: 'orange' },
  dirty: { label: '未提交', priority: 3, tab: 'git', tone: 'orange' },
  cleanup: { label: '可清理', priority: 4, tab: 'cleanup', tone: 'blue' },
};

export function attentionItems(projects, testRuns = {}) {
  const items = [];
  for (const project of projects) {
    const test = testRuns[project.path];
    if (test?.status === 'failed') {
      items.push({
        id: `${project.path}:testFailed`,
        kind: 'testFailed',
        project,
        title: '测试失败',
        detail: `${test.command || project.test?.command || ''}${test.exitCode != null ? ` · exit ${test.exitCode}` : ''}`,
      });
    }
    if (project.changes?.total > 0) {
      items.push({
        id: `${project.path}:dirty`,
        kind: 'dirty',
        project,
        title: `${project.changes.total} 个文件未提交`,
        detail: project.branch || project.group,
      });
    }
    if (project.behind > 0) {
      items.push({
        id: `${project.path}:behind`,
        kind: 'behind',
        project,
        title: `落后远端 ${project.behind} 个提交`,
        detail: project.branch || project.group,
      });
    }
    if (project.ahead > 0) {
      items.push({
        id: `${project.path}:unpushed`,
        kind: 'unpushed',
        project,
        title: `${project.ahead} 个提交未推送`,
        detail: project.branch || project.group,
      });
    }
    if ((project.cleandoc?.reusableBytes || 0) >= 1_000_000_000) {
      items.push({
        id: `${project.path}:cleanup`,
        kind: 'cleanup',
        project,
        title: `可回收 ${formatCompactBytes(project.cleandoc.reusableBytes)}`,
        detail: `${project.cleandoc.items?.length || 0} 个缓存或构建目录`,
      });
    }
  }
  return items.sort((a, b) => {
    const pa = ATTENTION_META[a.kind].priority;
    const pb = ATTENTION_META[b.kind].priority;
    if (pa !== pb) return pa - pb;
    return String(b.project.recent || '').localeCompare(String(a.project.recent || ''));
  });
}

function formatCompactBytes(bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = Math.max(0, Number(bytes) || 0);
  let index = 0;
  while (value >= 1000 && index < units.length - 1) {
    value /= 1000;
    index += 1;
  }
  return `${value >= 10 ? value.toFixed(0) : value.toFixed(1)} ${units[index]}`;
}

export function continueItems(projects, limit = 4) {
  const items = [];
  for (const project of projects) {
    const sessions = (project.tool?.recentSessions || [])
      .filter((session) => session.resumeCommand);
    if (!sessions.length) continue;
    const latest = sessions.reduce((best, session) => (
      !best || new Date(session.mtime) > new Date(best.mtime) ? session : best
    ), null);
    items.push({
      id: `${project.path}:${latest.tool}:${latest.id}`,
      project,
      session: latest,
      summary: latest.lastUser?.trim() || `${toolTitle(latest.tool)} 会话`,
      modified: latest.mtime,
    });
  }
  return items
    .sort((a, b) => new Date(b.modified) - new Date(a.modified))
    .slice(0, limit);
}

export function commitHeatmap(projects, weeks = 26, now = new Date()) {
  const today = startOfDay(now);
  const day = today.getDay();
  const sinceMonday = (day + 6) % 7;
  const currentMonday = addDays(today, -sinceMonday);
  const gridStart = addDays(currentMonday, -(weeks - 1) * 7);
  const byDay = new Map();
  for (const project of projects) {
    for (const [key, count] of Object.entries(project.activity?.daily || {})) {
      if (!byDay.has(key)) byDay.set(key, []);
      byDay.get(key).push({ path: project.path, name: project.displayName, count });
    }
  }
  const counts = [];
  const columns = [];
  for (let week = 0; week < weeks; week += 1) {
    const cells = [];
    for (let dayIndex = 0; dayIndex < 7; dayIndex += 1) {
      const date = addDays(gridStart, week * 7 + dayIndex);
      const key = dayKey(date);
      const isFuture = date > today;
      const projectCounts = isFuture ? [] : (byDay.get(key) || []);
      const count = projectCounts.reduce((sum, item) => sum + item.count, 0);
      if (!isFuture) counts.push(count);
      cells.push({ key, date, count, isFuture, projects: projectCounts, level: 0 });
    }
    columns.push(cells);
  }
  const nonZero = counts.filter((count) => count > 0).sort((a, b) => a - b);
  const q = (fraction) => nonZero.length ? nonZero[Math.floor((nonZero.length - 1) * fraction)] : 0;
  const thresholds = nonZero.length
    ? [Math.max(1, q(0.25)), Math.max(q(0.25) + 1, q(0.5)), Math.max(q(0.5) + 1, q(0.75))]
    : [1, 2, 4];
  let totalCommits = 0;
  for (const column of columns) {
    for (const cell of column) {
      if (cell.isFuture) continue;
      totalCommits += cell.count;
      if (cell.count > 0) {
        cell.level = cell.count <= thresholds[0] ? 1
          : cell.count <= thresholds[1] ? 2
            : cell.count <= thresholds[2] ? 3 : 4;
      }
    }
  }
  const activeDays = [];
  for (let date = gridStart; date <= today; date = addDays(date, 1)) {
    activeDays.push((byDay.get(dayKey(date)) || []).length > 0);
  }
  let longest = 0;
  let running = 0;
  for (const active of activeDays) {
    if (active) {
      running += 1;
      longest = Math.max(longest, running);
    } else {
      running = 0;
    }
  }
  let current = 0;
  let index = activeDays.length - 1;
  if (index >= 0 && !activeDays[index]) index -= 1;
  while (index >= 0 && activeDays[index]) {
    current += 1;
    index -= 1;
  }
  return { columns, totalCommits, currentStreak: current, longestStreak: longest };
}

export function weeklyKpi(projects, now = new Date()) {
  const today = startOfDay(now);
  const weekStart = addDays(today, -6);
  const prevWeekStart = addDays(today, -13);
  let weeklyCommits = 0;
  let weeklySessions = 0;
  let weeklyTokens = 0;
  let weeklyCost = 0;
  let prevWeekCost = 0;
  let hasWeeklyCost = false;
  let hasPrevWeekCost = false;
  let monthlyCost = 0;
  let hasMonthlyCost = false;
  let costIsEstimate = false;
  for (const project of projects) {
    for (const [key, count] of Object.entries(project.activity?.daily || {})) {
      const date = new Date(`${key}T00:00:00`);
      if (date >= weekStart && date <= today) weeklyCommits += count;
    }
    for (const session of project.tool?.recentSessions || []) {
      const modified = new Date(session.mtime);
      if (modified >= weekStart) {
        weeklySessions += 1;
        weeklyTokens += session.usage?.totalTokens || 0;
        if (session.costUSD != null) {
          weeklyCost += Math.max(0, session.costUSD);
          hasWeeklyCost = true;
        }
        if (session.costIsEstimate === true) costIsEstimate = true;
      } else if (modified >= prevWeekStart && session.costUSD != null) {
        prevWeekCost += Math.max(0, session.costUSD);
        hasPrevWeekCost = true;
      }
      if (modified >= addDays(today, -29) && session.costUSD != null) {
        monthlyCost += Math.max(0, session.costUSD);
        hasMonthlyCost = true;
      }
    }
  }
  const delta = hasWeeklyCost && hasPrevWeekCost && prevWeekCost > 0
    ? ((weeklyCost - prevWeekCost) / prevWeekCost) * 100
    : null;
  return {
    weeklyCommits,
    weeklySessions,
    weeklyTokens,
    weeklyCostUSD: hasWeeklyCost ? weeklyCost : null,
    monthlyCostUSD: hasMonthlyCost ? monthlyCost : null,
    costIsEstimate,
    delta,
  };
}

export function costBreakdown(projects, mode = 'tool', now = new Date()) {
  const cutoff = addDays(startOfDay(now), -6);
  const buckets = new Map();
  for (const project of projects) {
    for (const session of project.tool?.recentSessions || []) {
      if (new Date(session.mtime) < cutoff) continue;
      const cost = Math.max(0, session.costUSD || 0);
      const tokens = Math.max(0, session.usage?.totalTokens || 0);
      if (!cost && !tokens) continue;
      const key = mode === 'tool' ? session.tool : project.path;
      const label = mode === 'tool' ? toolTitle(session.tool) : project.displayName;
      const tone = mode === 'tool' ? toolTone(session.tool) : groupTone(project.group).key;
      if (!buckets.has(key)) buckets.set(key, { id: key, label, tone, cost: 0, tokens: 0 });
      const bucket = buckets.get(key);
      bucket.cost += cost;
      bucket.tokens += tokens;
    }
  }
  if (!buckets.size) return [];
  const values = [...buckets.values()];
  const totalCost = values.reduce((sum, item) => sum + item.cost, 0);
  const useCost = totalCost > 0;
  const total = useCost ? totalCost : Math.max(1, values.reduce((sum, item) => sum + item.tokens, 0));
  values.sort((a, b) => {
    const left = useCost ? a.cost : a.tokens;
    const right = useCost ? b.cost : b.tokens;
    return right - left || a.label.localeCompare(b.label);
  });
  const segments = values.slice(0, 5).map((item) => ({
    ...item,
    fraction: (useCost ? item.cost : item.tokens) / total,
  }));
  if (values.length > 5) {
    const tail = values.slice(5);
    const cost = tail.reduce((sum, item) => sum + item.cost, 0);
    const tokens = tail.reduce((sum, item) => sum + item.tokens, 0);
    segments.push({
      id: 'other',
      label: '其他',
      tone: 'secondary',
      cost,
      tokens,
      fraction: (useCost ? cost : tokens) / total,
    });
  }
  return segments;
}

export function weeklyTimeline(projects, now = new Date()) {
  const today = startOfDay(now);
  const start = addDays(today, -6);
  const byDay = new Map();
  const ensure = (key) => {
    if (!byDay.has(key)) byDay.set(key, []);
    return byDay.get(key);
  };
  for (const project of projects) {
    const grouped = new Map();
    for (const seconds of project.activity?.timestamps || []) {
      const date = new Date(seconds * 1000);
      const key = dayKey(date);
      if (date < start) continue;
      if (!grouped.has(key)) grouped.set(key, { earliestHour: 24, count: 0 });
      const entry = grouped.get(key);
      entry.earliestHour = Math.min(entry.earliestHour, date.getHours() + date.getMinutes() / 60);
      entry.count += 1;
    }
    for (const [key, group] of grouped) {
      ensure(key).push({
        id: `c:${project.path}:${key}`,
        kind: 'commit',
        startHour: group.earliestHour,
        projectName: project.displayName,
        projectPath: project.path,
        detail: group.count === 1 ? '提交' : `${group.count} 次提交`,
      });
    }
    for (const session of project.tool?.recentSessions || []) {
      const modified = new Date(session.mtime);
      if (modified < start || modified > addDays(today, 1)) continue;
      const anchor = session.startedAt ? new Date(session.startedAt) : modified;
      ensure(dayKey(modified)).push({
        id: `s:${project.path}:${session.tool}:${session.id}`,
        kind: 'session',
        startHour: anchor.getHours() + anchor.getMinutes() / 60,
        projectName: project.displayName,
        projectPath: project.path,
        detail: `${toolTitle(session.tool)} 会话`,
      });
    }
  }
  const weekday = new Intl.DateTimeFormat('zh-CN', { weekday: 'short' });
  return Array.from({ length: 7 }, (_, offset) => {
    const date = addDays(start, offset);
    const key = dayKey(date);
    return {
      key,
      date,
      weekdayLabel: weekday.format(date),
      dayNumber: date.getDate(),
      isToday: key === dayKey(today),
      blocks: (byDay.get(key) || []).sort((a, b) => a.startHour - b.startHour),
    };
  });
}

export function healthAlerts(projects, disk) {
  const alerts = [];
  if (disk?.free != null && disk.free < 20_000_000_000) {
    alerts.push({
      id: 'low-disk',
      title: '磁盘余量偏低',
      detail: `仅剩 ${formatCompactBytes(disk.free)} 可用`,
    });
  }
  const cleanupBytes = projects.reduce((sum, project) => sum + (project.cleandoc?.reusableBytes || 0), 0);
  if (cleanupBytes >= 5_000_000_000) {
    alerts.push({
      id: 'high-cleanup',
      title: '可清理空间较多',
      detail: `可释放 ${formatCompactBytes(cleanupBytes)}`,
    });
  }
  const staleCutoff = Date.now() - 30 * 86400000;
  for (const project of projects) {
    if (project.dirtyCount > 0 && project.recent && new Date(project.recent).getTime() < staleCutoff) {
      alerts.push({
        id: `stale:${project.path}`,
        title: `${project.displayName} 有陈旧未提交改动`,
        detail: `${project.dirtyCount} 处改动 · ${project.branch || project.group}`,
        projectPath: project.path,
      });
    }
  }
  return alerts;
}
