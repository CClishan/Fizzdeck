export const GROUP_PALETTE = [
  { key: 'blue', hex: '#477fe8' },
  { key: 'violet', hex: '#9e6bea' },
  { key: 'green', hex: '#4db27a' },
  { key: 'orange', hex: '#e0a23c' },
  { key: 'pink', hex: '#e06a9a' },
  { key: 'teal', hex: '#35aaa8' },
  { key: 'indigo', hex: '#5e68d8' },
  { key: 'brown', hex: '#9b7358' },
];

export const TAG_COLORS = {
  red: '#cc5952',
  amber: '#ebaa3d',
  green: '#4db27a',
  blue: '#478ceb',
  violet: '#9e6bea',
};

export function groupTone(group) {
  let hash = 14695981039346656037n;
  for (const byte of new TextEncoder().encode(String(group || ''))) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 1099511628211n);
  }
  return GROUP_PALETTE[Number(hash % BigInt(GROUP_PALETTE.length))];
}

export function tagColor(project) {
  if (project?.color && TAG_COLORS[project.color]) return TAG_COLORS[project.color];
  return groupTone(project?.group || '其他').hex;
}

export function badgeKind(project) {
  const items = new Set((project?.stack?.groups || []).flatMap((group) => group.items.map((item) => item.toLowerCase())));
  const has = (...values) => values.some((value) => items.has(value));
  if (has('next.js', 'next')) return 'next';
  if (has('nuxt')) return 'nuxt';
  if (has('sveltekit', 'svelte')) return 'svelte';
  if (has('astro')) return 'astro';
  if (has('vue')) return 'vue';
  if (has('react', 'react native')) return 'react';
  if (has('vite')) return 'vite';
  if (has('swift', 'swiftui', 'appkit')) return 'swift';
  if (has('flutter')) return 'flutter';
  if (has('unity', 'godot', 'unreal')) return 'game';
  if (has('go', 'golang', 'go module')) return 'go';
  if (has('rust', 'cargo')) return 'rust';
  if (has('python', 'django', 'flask', 'fastapi')) return 'python';
  if (has('docker', 'docker-compose')) return 'docker';
  if (has('cloudflare', 'd1', 'r2', 'kv')) return 'cloudflare';
  return 'web';
}

export const BADGE_META = {
  next: { label: 'Next.js', text: '', icon: 'triangle', tone: 'neutral' },
  vite: { label: 'Vite', text: '', icon: 'zap', tone: 'violet' },
  react: { label: 'React', text: '', icon: 'atom', tone: 'cyan' },
  vue: { label: 'Vue', text: 'V', icon: null, tone: 'green' },
  svelte: { label: 'Svelte', text: 'S', icon: null, tone: 'orange' },
  astro: { label: 'Astro', text: 'A', icon: null, tone: 'violet' },
  nuxt: { label: 'Nuxt', text: 'N', icon: null, tone: 'green' },
  swift: { label: 'Swift', text: '', icon: 'bird', tone: 'orange' },
  flutter: { label: 'Flutter', text: 'F', icon: null, tone: 'cyan' },
  game: { label: 'Game', text: '', icon: 'gamepad', tone: 'pink' },
  go: { label: 'Go', text: 'G', icon: null, tone: 'cyan' },
  rust: { label: 'Rust', text: 'R', icon: null, tone: 'orange' },
  python: { label: 'Python', text: 'P', icon: null, tone: 'blue' },
  docker: { label: 'Docker', text: '', icon: 'package', tone: 'blue' },
  cloudflare: { label: 'Cloudflare', text: '', icon: 'cloud', tone: 'orange' },
  web: { label: 'Web', text: '', icon: 'globe', tone: 'blue' },
  other: { label: 'Project', text: '', icon: 'folder', tone: 'secondary' },
};

export const TOOL_META = {
  codex: { title: 'Codex', symbol: 'sparkles', tone: 'violet' },
  claude: { title: 'Claude Code', symbol: 'asterisk', tone: 'orange' },
  grok: { title: 'Grok', symbol: 'orbit', tone: 'cyan' },
  gemini: { title: 'Gemini CLI', symbol: 'gem', tone: 'blue' },
  deepseek: { title: 'DeepSeek', symbol: 'waves', tone: 'green' },
};

export function toolTitle(tool) {
  return TOOL_META[tool]?.title || String(tool || '').replace(/^./, (c) => c.toUpperCase());
}

export function toolTone(tool) {
  return TOOL_META[tool]?.tone || 'secondary';
}

export function toolSymbol(tool) {
  return TOOL_META[tool]?.symbol || 'bubble';
}

export function stackChipTone(key) {
  return {
    framework: 'blue',
    language: 'violet',
    infra: 'green',
    feature: 'orange',
  }[key] || 'secondary';
}

export function allToolNames(project) {
  const tools = new Set(project?.tool?.detected || []);
  for (const item of project?.tool?.byTool || []) tools.add(item.tool);
  for (const session of project?.tool?.recentSessions || []) tools.add(session.tool);
  return [...tools];
}

export function projectKindLabel(project) {
  return project?.group || '其他';
}
