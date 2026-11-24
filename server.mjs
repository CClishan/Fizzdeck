import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import { execFile, execSync, spawn } from 'node:child_process';

const HOME = os.homedir();
const PORT = Number(process.env.PORT || 4770);
const STATE_DIR = path.join(HOME, '.repodeck');
const STATE_FILE = path.join(STATE_DIR, 'state.json');
const ROOTS_FILE = path.join(STATE_DIR, 'roots.json');
const PUBLIC = path.join(path.dirname(new URL(import.meta.url).pathname), 'public');

const ROOT_HOME = HOME;
const DEFAULT_ROOTS = [
  path.join(ROOT_HOME, 'pixloading'),
  path.join(ROOT_HOME, 'video-tem'),
  path.join(ROOT_HOME, 'noplan_officesite'),
  path.join(ROOT_HOME, 'Cardfun'),
  path.join(ROOT_HOME, 'A2O-LITE-NEON-AI'),
  '/Volumes/back/TapinChina',
];
const GROUP_HINTS = [
  [/workspace|cpa-manager/i, '工作区'],
  [/^tsys/i, '上屏管家'],
  [/Converter-tools|alimama-cli|cliproxyapi|shipany/i, '工具库'],
  [/noplan/i, '官网'],
  [/zoopfizz|video-tem|^pixloading|^Cardfun|a2o|tapinchina/i, '产品站'],
];

const CLEAN_RULES = [
  { re: /^node_modules$/, reason: '依赖，可重装', regen: 'npm ci', rule: 'deps' },
  { re: /^(\.next|\.open-next|\.svelte-kit|\.astro|\.tanstack|\.output)$/, reason: '框架缓存，可重建', regen: '构建时自动生成', rule: 'build' },
  { re: /^(dist|dist-[a-z]+|build)$/, reason: '构建产物，可重建', regen: 'npm run build', rule: 'build' },
  { re: /^(tmp|\.tmp)$/, reason: '临时产物', regen: '', rule: 'tmp' },
  { re: /^(output|artifacts|releases|reports)$/, reason: '历史归档，确认后再删', regen: '', rule: 'archive' },
];
// 目录名与产品名不一致时的展示别名（不改磁盘目录）
const ALIASES = {
  [path.join(ROOT_HOME, 'video-tem')]: 'zoopfizz',
  [path.join(ROOT_HOME, 'A2O-LITE-NEON-AI')]: 'NEONLITE.AI',
  [path.join(ROOT_HOME, 'noplan_officesite')]: 'Noplan 官网',
};

const KNOWN_PORTS = { pixloading: 3000, 'video-tem': 4317, noplan_officesite: 5173, Cardfun: 4321, TapinChina: 5173 };

const readJSON = (file, fallback) => {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
};
const writeJSON = (file, data) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
};

function exec(cmd, args, cwd) {
  return new Promise((resolve) => {
    execFile(cmd, args, { cwd, maxBuffer: 16 << 20, timeout: 20000 }, (err, stdout) => {
      resolve(err ? null : String(stdout).trim());
    });
  });
}

function dirBytes(dir) {
  return new Promise((resolve) => {
    execFile('du', ['-sk', dir], { maxBuffer: 1 << 20, timeout: 30000 }, (err, out) => {
      resolve(err ? 0 : (Number(String(out).split('\t')[0]) || 0) * 1024);
    });
  });
}

async function scanSize(dir) {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return { totalBytes: 0, breakdown: [] }; }
  const rows = [];
  let fileTotal = 0;
  for (const e of entries) {
    if (e.isSymbolicLink()) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) rows.push({ label: e.name, path: p, dir: true, bytes: 0 });
    else {
      try { const b = fs.statSync(p).size; rows.push({ label: e.name, path: p, bytes: b }); fileTotal += b; } catch {}
    }
  }
  await Promise.all(rows.filter((r) => r.dir).map(async (r) => { r.bytes = await dirBytes(r.path); }));
  const top = rows.map(({ label, bytes }) => ({ label, bytes })).filter((r) => r.bytes > 0).sort((a, b) => b.bytes - a.bytes);
  const total = top.reduce((s, r) => s + r.bytes, 0) + fileTotal;
  return { totalBytes: total, breakdown: [...top, ...(fileTotal ? [{ label: '(根目录文件)', bytes: fileTotal }] : [])].sort((a, b) => b.bytes - a.bytes).slice(0, 10) };
}

async function cleandoc(dir) {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch {}
  const items = [];
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    const rule = CLEAN_RULES.find((r) => r.re.test(e.name));
    if (!rule) continue;
    const p = path.join(dir, e.name);
    const bytes = await dirBytes(p);
    if (bytes > 0) items.push({ label: e.name, path: p, bytes, reason: rule.reason, regen: rule.regen, kind: rule.rule });
  }
  items.sort((a, b) => b.bytes - a.bytes);
  return { reusableBytes: items.reduce((s, i) => s + i.bytes, 0), items };
}

const readFileSafe = (dir, f) => { try { return fs.readFileSync(path.join(dir, f), 'utf8'); } catch { return ''; } };

function detectStack(dir) {
  const has = (f) => fs.existsSync(path.join(dir, f));
  const languages = [], frameworks = [], tags = [];
  const add = (arr, v) => { if (!arr.includes(v)) arr.push(v); };

  if (has('tsconfig.json') || has('next-env.d.ts')) add(languages, 'TS');
  if (has('jsconfig.json')) add(languages, 'JS');
  if (has('astro.config.mjs') || has('astro.config.ts')) add(frameworks, 'Astro');
  if (has('svelte.config.js')) { add(languages, 'Svelte'); add(frameworks, 'SvelteKit'); }
  if (has('vite.config.js') || has('vite.config.ts')) add(languages, 'Vite');
  if (has('pom.xml')) { add(languages, 'Java'); add(frameworks, 'Spring Boot'); }
  if (has('build.gradle')) { add(languages, 'Android'); add(frameworks, 'Gradle'); }
  if (has('manifest.json') && has('pages')) add(languages, 'uni-app');
  if (fs.existsSync(path.join(dir, 'go.mod'))) { add(languages, 'Go'); add(frameworks, 'Go Module'); }
  if (fs.existsSync(path.join(dir, 'requirements.txt')) || fs.existsSync(path.join(dir, 'pyproject.toml'))) add(languages, 'Python');
  if (fs.existsSync(path.join(dir, 'Cargo.toml'))) { add(languages, 'Rust'); add(frameworks, 'Cargo'); }
  if (fs.existsSync(path.join(dir, 'Dockerfile')) || fs.existsSync(path.join(dir, 'docker-compose.yml'))) add(tags, 'Docker');
  if (fs.existsSync(path.join(dir, 'SKILL.md')) || fs.existsSync(path.join(dir, '.agents'))) add(tags, 'Agent Skill');

  let deps = {};
  try { const p = JSON.parse(readFileSafe(dir, 'package.json') || '{}'); deps = { ...p.dependencies, ...p.devDependencies }; } catch {}
  const dep = (n) => n in deps;
  if (dep('next')) add(frameworks, 'Next.js');
  if (dep('react')) add(languages, 'React');
  if (dep('vue')) add(languages, 'Vue');
  if (dep('@tanstack/react-start')) { add(frameworks, 'TanStack Start'); add(tags, 'Cloudflare'); }
  if (dep('svelte')) add(languages, 'Svelte');
  if (dep('wrangler') || has('wrangler.toml') || has('wrangler.json') || has('wrangler.jsonc')) add(tags, 'Cloudflare');
  const wr = readFileSafe(dir, 'wrangler.toml') + readFileSafe(dir, 'wrangler.json') + readFileSafe(dir, 'wrangler.jsonc');
  if (/d1_databases/.test(wr)) add(tags, 'D1');
  if (/r2_buckets/.test(wr)) add(tags, 'R2');
  if (/kv_namespaces/.test(wr)) add(tags, 'KV');
  if (dep('drizzle-orm')) add(tags, 'Drizzle');
  if (dep('stripe')) add(tags, 'Stripe');
  if (dep('better-auth')) add(tags, 'Auth');
  if (dep('gsap')) add(tags, 'GSAP');
  if (dep('three') || has('src/lib/gl')) add(tags, 'WebGL');
  if (/adapter-static/.test(readFileSafe(dir, 'svelte.config.js'))) add(tags, 'SSG');
  const scanned = readFileSafe(dir, 'build.mjs') + readFileSafe(dir, 'README.md').slice(0, 500);
  if (/node:|from 'node:|require\(/.test(scanned)) add(languages, 'Node');
  if (!languages.length) add(languages, '其他');
  return { languages, frameworks, tags, groups: groupStack(languages, frameworks, tags) };
}

const LANG_KEYS = ['TS', 'JS', 'TypeScript', 'JavaScript', 'React', 'Vue', 'Svelte', 'Astro', 'Vite', 'Java', 'Android', 'uni-app', 'Node', 'Go', 'Python', 'Rust'];
const FRAMEWORK_KEYS = ['Next.js', 'TanStack Start', 'SvelteKit', 'Astro', 'Nuxt', 'RuoYi', 'Spring Boot', 'Gradle', 'Go Module', 'Cargo'];
const INFRA_KEYS = ['Cloudflare', 'D1', 'R2', 'KV', 'Drizzle', 'Stripe', 'Auth', 'MQTT', 'Docker'];
const FEATURE_KEYS = ['GSAP', 'WebGL', 'SSG', 'Agent Skill'];

function groupStack(languages, frameworks, tags) {
  const all = [...frameworks, ...languages, ...tags];
  const take = (keys) => all.filter((x) => keys.includes(x));
  const rest = all.filter((x) => ![...LANG_KEYS, ...FRAMEWORK_KEYS, ...INFRA_KEYS, ...FEATURE_KEYS].includes(x));
  return [
    { key: 'framework', label: '框架', items: take(FRAMEWORK_KEYS) },
    { key: 'language', label: '语言', items: take(LANG_KEYS) },
    { key: 'infra', label: '基础设施', items: take(INFRA_KEYS) },
    { key: 'feature', label: '能力', items: [...take(FEATURE_KEYS), ...rest] },
  ].filter((g) => g.items.length);
}

async function gitInfo(dir) {
  if (!fs.existsSync(path.join(dir, '.git'))) return null;
  const [branch, log, status] = await Promise.all([
    exec('git', ['rev-parse', '--abbrev-ref', 'HEAD'], dir),
    exec('git', ['log', '-1', '--format=%H%n%ad%n%s%n%an', '--date=iso-strict'], dir),
    exec('git', ['status', '--porcelain', '-uall'], dir),
  ]);
  const lines = (status || '').split('\n').filter(Boolean);
  const untracked = lines.filter((l) => l.startsWith('??')).length;
  const tracked = lines.length - untracked;
  const changes = { tracked, untracked, total: lines.length };
  if (!log) return { branch, lastCommit: null, dirtyCount: tracked, changes };
  const [hash, date, subject, author] = log.split('\n');
  return { branch, lastCommit: { hash: hash.slice(0, 7), date, subject, author }, dirtyCount: tracked, changes };
}


// ---------- 项目介绍：从文档抓取 ----------
const INTRO_DOCS = [
  { file: 'PRODUCT.md', weight: 0 },
  { file: 'README.md', weight: 1 },
  { file: 'README.zh-CN.md', weight: 1 },
  { file: 'HANDOFF.MD', weight: 3 },
  { file: 'CLAUDE.md', weight: 4 },
  { file: 'AGENTS.md', weight: 6 },
];

function stripMarkdown(t) {
  return t
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/```[\s\S]*?```/g, '')
    .replace(/^#{1,6}\s*/gm, '')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[*_`>]/g, '')
    .replace(/\|/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractIntro(dir) {
  const read = (f) => { try { return fs.readFileSync(path.join(dir, f), 'utf8'); } catch { return ''; } };
  // 1) PRODUCT.md 的 Purpose / 摘要段
  const product = read('PRODUCT.md');
  if (product) {
    const sec = product.match(/##\s*(Product Purpose|Purpose|Overview|Summary)[\s\S]*?(?=\n##\s|$)/i);
    if (sec) {
      const body = stripMarkdown(sec[0].replace(/^##[^\n]*\n/, ''));
      if (body.length > 30) return { text: body.slice(0, 320), source: 'PRODUCT.md' };
    }
    const users = product.match(/##\s*Users[\s\S]*?(?=\n##\s|$)/i);
    if (users) {
      const body = stripMarkdown(users[0].replace(/^##[^\n]*\n/, ''));
      if (body.length > 30) return { text: body.slice(0, 320), source: 'PRODUCT.md' };
    }
  }
  // 2) README 首段（跳过标题与徽章）
  for (const doc of INTRO_DOCS) {
    const raw = read(doc.file);
    if (!raw) continue;
    const lines = raw.split('\n').filter((l) => l.trim() && !/^\s*[<![|]/.test(l.trim()) && !/^#\s/.test(l));
    const para = [];
    for (const l of lines) {
      if (/^#{1,6}\s/.test(l) && para.length) break;
      if (/^#{1,6}\s/.test(l)) continue;
      para.push(l);
      if (para.join(' ').length > 220) break;
    }
    const text = stripMarkdown(para.join(' '));
    if (text.length > 24) return { text: text.slice(0, 320), source: doc.file };
  }
  // 3) package.json description
  try {
    const pkg = JSON.parse(read('package.json') || '{}');
    if (pkg.description) return { text: String(pkg.description).slice(0, 320), source: 'package.json' };
  } catch {}
  return { text: '', source: null };
}

// ---------- 测试命令 ----------
function detectTestScript(dir) {
  const read = (f) => { try { return JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')); } catch { return null; } };
  const pkg = read('package.json');
  if (pkg?.scripts) {
    const mgr = fs.existsSync(path.join(dir, 'pnpm-lock.yaml')) ? 'pnpm' : fs.existsSync(path.join(dir, 'bun.lock')) ? 'bun' : 'npm';
    for (const k of ['test', 'test:unit', 'vitest', 'check', 'typecheck', 'lint']) {
      if (pkg.scripts[k] && !/no test specified|exit 1/.test(pkg.scripts[k])) return { label: k, command: `${mgr} run ${k}` };
    }
  }
  if (fs.existsSync(path.join(dir, 'pom.xml'))) return { label: 'mvn test', command: 'mvn -q test' };
  if (fs.existsSync(path.join(dir, 'build.gradle'))) return { label: 'gradle test', command: 'gradle test' };
  if (fs.existsSync(path.join(dir, 'go.mod'))) return { label: 'go test', command: 'go test ./...' };
  return null;
}

async function resolveRun(dir) {
  const has = (f) => fs.existsSync(path.join(dir, f));
  if (has('package.json')) {
    let pkg = {};
    try { pkg = JSON.parse(readFileSafe(dir, 'package.json')); } catch {}
    const scripts = pkg.scripts || {};
    const name = scripts.dev ? 'dev' : scripts['dev:pages'] ? 'dev:pages' : null;
    if (!name) return null;
    const mgr = has('pnpm-lock.yaml') ? 'pnpm' : has('bun.lock') ? 'bun' : 'npm';
    const envPort = (readFileSafe(dir, '.env') + readFileSafe(dir, '.dev.vars')).match(/^PORT=(\d{3,5})/m)?.[1];
    const port = Number(envPort || KNOWN_PORTS[path.basename(dir)] || 5173);
    return { command: `${mgr} run ${name}`, port, previewUrl: `http://127.0.0.1:${port}` };
  }
  if (has('pom.xml')) return { command: 'mvn spring-boot:run -pl ruoyi-admin', port: 8988, previewUrl: 'http://127.0.0.1:8988' };
  if (has('build.gradle')) return { command: 'gradle assembleDebug', port: 0, previewUrl: null };
  return null;
}

function walkFiles(root, filter, depth = 0) {
  const out = [];
  let es = [];
  try { es = fs.readdirSync(root, { withFileTypes: true }); } catch { return out; }
  for (const e of es) {
    const p = path.join(root, e.name);
    if (e.isDirectory()) { if (depth < 6) out.push(...walkFiles(p, filter, depth + 1)); }
    else if (filter(e.name)) out.push(p);
  }
  return out;
}

function tailText(file, bytes = 256 * 1024) {
  let st;
  try { st = fs.statSync(file); } catch { return ''; }
  const start = Math.max(0, st.size - bytes);
  try {
    const fd = fs.openSync(file, 'r');
    const buf = Buffer.alloc(st.size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    fs.closeSync(fd);
    return buf.toString('utf8');
  } catch { return ''; }
}

function headText(file, bytes = 64 * 1024) {
  try {
    const fd = fs.openSync(file, 'r');
    const buf = Buffer.alloc(bytes);
    const n = fs.readSync(fd, buf, 0, bytes, 0);
    fs.closeSync(fd);
    return buf.toString('utf8', 0, n);
  } catch { return ''; }
}

const cleanUserText = (t) => String(t || '')
  .replace(/<environment_context>[\s\S]*?<\/environment_context>/g, '')
  .replace(/<user_instructions>[\s\S]*?<\/user_instructions>/g, '')
  .trim()
  .slice(0, 400);

function parseCodexFile(file) {
  let st;
  try { st = fs.statSync(file); } catch { return null; }
  let meta = null;
  try { meta = JSON.parse(headText(file, 32 * 1024).split('\n')[0]); } catch { return null; }
  const p = meta.payload || {};
  const cwd = p.cwd || null;
  if (!cwd) return null;
  let lastUser = null;
  const lines = tailText(file).split('\n');
  for (let i = lines.length - 1; i >= 0 && !lastUser; i--) {
    const line = lines[i].trim();
    if (!line || !line.includes('"user"')) continue;
    try {
      const o = JSON.parse(line);
      const pl = o.payload || {};
      if (pl.role === 'user' && o.type !== 'event_msg') {
        const c = pl.content;
        const txt = Array.isArray(c) ? c.map((x) => x.text || '').join(' ') : String(c || '');
        const clean = cleanUserText(txt);
        if (clean && !clean.startsWith('<')) lastUser = clean;
      }
    } catch {}
  }
  return { tool: 'codex', id: p.session_id || p.id || path.basename(file), cwd, startedAt: meta.timestamp || null, mtime: st.mtime.toISOString(), lastUser };
}

function parseClaudeFile(file, dirName) {
  let st;
  try { st = fs.statSync(file); } catch { return null; }
  let lastUser = null, cwd = null;
  const lines = tailText(file).split('\n');
  for (let i = lines.length - 1; i >= 0 && (!lastUser || !cwd); i--) {
    const line = lines[i].trim();
    if (!line) continue;
    try {
      const o = JSON.parse(line);
      if (!cwd && o.cwd) cwd = o.cwd;
      if (!lastUser && o.type === 'user' && o.message && o.message.role === 'user') {
        const c = o.message.content;
        const txt = typeof c === 'string' ? c : Array.isArray(c) ? c.map((x) => x.text || '').join(' ') : '';
        const clean = cleanUserText(txt);
        if (clean && !clean.startsWith('<')) lastUser = clean;
      }
    } catch {}
  }
  if (!cwd) cwd = dirName.replace(/^-/, '/').replace(/-/g, '/');
  return { tool: 'claude', id: path.basename(file, '.jsonl'), cwd, startedAt: null, mtime: st.mtime.toISOString(), lastUser };
}

function buildSessionIndex() {
  const codexRoot = path.join(HOME, '.codex', 'sessions');
  const claudeRoot = path.join(HOME, '.claude', 'projects');
  const sessions = [];
  for (const f of walkFiles(codexRoot, (n) => n.startsWith('rollout-') && n.endsWith('.jsonl'))) {
    const s = parseCodexFile(f);
    if (s) sessions.push(s);
  }
  let dirs = [];
  try { dirs = fs.readdirSync(claudeRoot, { withFileTypes: true }).filter((e) => e.isDirectory()); } catch {}
  for (const d of dirs) {
    for (const f of walkFiles(path.join(claudeRoot, d.name), (n) => n.endsWith('.jsonl'))) {
      const s = parseClaudeFile(f, d.name);
      if (s) sessions.push(s);
    }
  }
  return sessions.sort((a, b) => (b.mtime > a.mtime ? 1 : -1));
}

function normPath(p) {
  if (!p) return p;
  return path.resolve(p).replace(/\/+$/, '');
}

function sessionsFor(dir, index) {
  const target = normPath(dir);
  const hits = index.filter((s) => s.cwd && normPath(s.cwd) === target);
  const byTool = [];
  for (const h of hits) {
    let t = byTool.find((x) => x.tool === h.tool);
    if (!t) { t = { tool: h.tool, sessionCount: 0, lastSessionAt: h.mtime, lastSessionId: h.id, lastUserMessage: h.lastUser }; byTool.push(t); }
    t.sessionCount += 1;
  }
  byTool.sort((a, b) => (b.lastSessionAt > a.lastSessionAt ? 1 : -1));
  return {
    detected: byTool.map((t) => t.tool),
    lastSessionAt: byTool[0]?.lastSessionAt || null,
    lastUserMessage: byTool[0]?.lastUserMessage || null,
    lastSessionId: byTool[0]?.lastSessionId || null,
    lastTool: byTool[0]?.tool || null,
    sessionCount: hits.length,
    byTool,
  };
}

function aiStatus() {
  return new Promise((resolve) => {
    execFile('ps', ['-axo', 'args'], { maxBuffer: 32 << 20 }, (err, out) => {
      const text = err ? '' : String(out);
      const agents = text.split('\n').filter((l) => /(^|[\s/])(codex|claude|grok)(\s|$|\/)/.test(l) && !/repo-dashboard|node --test|grep/.test(l));
      const sess = buildSessionIndex();
      const recent = (tool) => {
        const s = sess.find((x) => x.tool === tool);
        return s ? s.mtime : null;
      };
      const state = (tool) => {
        const running = agents.some((l) => new RegExp(`(^|[\\s/])${tool}(\\s|$)`).test(l) || (tool === 'codex' && /Codex\.app/.test(l)));
        if (running) return 'running';
        const t = recent(tool);
        if (t && Date.now() - new Date(t).getTime() < 30 * 60 * 1000) return 'recent';
        return 'idle';
      };
      resolve({ codex: state('codex'), claude: state('claude'), grok: state('grok'), sessionCounts: { codex: sess.filter((s) => s.tool === 'codex').length, claude: sess.filter((s) => s.tool === 'claude').length } });
    });
  });
}

function probePort(port) {
  return new Promise((resolve) => {
    const s = new net.Socket();
    let done = false;
    const finish = (v) => { if (!done) { done = true; s.destroy(); resolve(v); } };
    s.setTimeout(500);
    s.once('connect', () => finish('running'));
    s.once('timeout', () => finish('stopped'));
    s.once('error', () => finish('stopped'));
    s.connect(port, '127.0.0.1');
  });
}

async function portStatus(projects) {
  const out = {};
  await Promise.all(projects.map(async (p) => {
    out[p.path] = p.run && p.run.port ? await probePort(p.run.port) : 'no-preview';
  }));
  return out;
}

async function orphans() {
  const codexRoot = path.join(HOME, '.codex', 'sessions');
  const claudeRoot = path.join(HOME, '.claude', 'projects');
  const items = (root, filter) => walkFiles(root, filter).map((p) => {
    try { const st = fs.statSync(p); return { path: p, bytes: st.size, mtime: st.mtime.toISOString() }; } catch { return null; }
  }).filter(Boolean).sort((a, b) => b.bytes - a.bytes).slice(0, 10);

  const groups = [
    {
      site: '~/.codex/sessions',
      dir: codexRoot,
      note: 'Codex 历史会话；截图等大附件也在这里，最早的可整段删',
      pruneCommand: "find ~/.codex/sessions -name 'rollout-*.jsonl' -mtime +30 -delete",
      items: items(codexRoot, (n) => n.startsWith('rollout-') && n.endsWith('.jsonl')),
      totalBytes: await dirBytes(codexRoot),
    },
    {
      site: '~/.claude/projects',
      dir: claudeRoot,
      note: 'Claude Code 历史会话',
      pruneCommand: "find ~/.claude/projects -name '*.jsonl' -mtime +30 -delete",
      items: items(claudeRoot, (n) => n.endsWith('.jsonl')),
      totalBytes: await dirBytes(claudeRoot),
    },
  ];
  return { totalBytes: groups.reduce((s, g) => s + g.totalBytes, 0), groups };
}

let cache = null;

async function scan() {
  const t0 = Date.now();
  const roots = getRoots();
  const meta = readJSON(STATE_FILE, {});
  const index = buildSessionIndex();
  const projects = [];
  for (const dir of roots) {
    const name = path.basename(dir);
    const group = (GROUP_HINTS.find(([re]) => re.test(name) || re.test(dir)) || [, '其他'])[1];
    const [size, clean, run, git, weekly] = await Promise.all([scanSize(dir), cleandoc(dir), resolveRun(dir), gitInfo(dir), weeklyCommits(dir)]);
    const tool = sessionsFor(dir, index);
    const m = meta[dir] || {};
    projects.push({
      path: dir, name, displayName: ALIASES[dir] || name, group,
      recent: git?.lastCommit?.date || tool.lastSessionAt || null,
      branch: git?.branch || null,
      lastCommit: git?.lastCommit || null,
      dirtyCount: git?.dirtyCount || 0,
      changes: git?.changes || { tracked: 0, untracked: 0, total: 0 },
      weekly: weekly || {},
      stack: detectStack(dir),
      size, cleandoc: clean, run, tool,
      intro: extractIntro(dir), test: detectTestScript(dir),
      starred: !!m.starred, color: m.color || null, note: m.note || '',
    });
  }
  projects.sort((a, b) => (b.recent > a.recent ? 1 : -1));
  const [ai, ports] = await Promise.all([aiStatus(), portStatus(projects)]);
  cache = { scannedAt: new Date().toISOString(), roots, projects, aiStatus: ai, portStatus: ports, scan: { durationMs: Date.now() - t0 } };
  return cache;
}


// ---------- 扫描本地文件夹 ----------
const SKIP_DIRS = new Set([
  'node_modules', 'Library', 'Applications', 'Pictures', 'Movies', 'Music', 'Downloads',
  'Desktop', 'Documents', 'Public', 'Trash', '.Trash', 'System', 'Volumes', 'private',
]);
const PROJECT_MARKERS = ['package.json', 'pom.xml', 'build.gradle', 'Cargo.toml', 'go.mod', 'pyproject.toml', 'Gemfile', 'settings.gradle', 'composer.json', 'mix.exs'];
// 构建产物目录里的 index.html 不算工程
const OUTPUT_DIRS = /^(dist|dist-[a-z0-9]+|build|out|\.next|public|release|coverage)$/i;

function scanFolder(dir, depth, out, maxDepth) {
  if (depth > maxDepth) return;
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
  const names = new Set(entries.filter((e) => e.isDirectory()).map((e) => e.name));
  const hasManifest = PROJECT_MARKERS.some((m) => fs.existsSync(path.join(dir, m)));
  const isProject = (names.has('.git') && !OUTPUT_DIRS.test(path.basename(dir))) || hasManifest;
  if (isProject) {
    let lastCommit = null, dirtyCount = 0, remote = null;
    try {
      lastCommit = execSync('git log -1 --format=%H%n%ad%n%s --date=iso-strict', { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
      const rows = execSync('git status --porcelain -uall', { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).split('\n').filter(Boolean);
      const untrackedRows = rows.filter((r) => r.startsWith('??')).length;
      dirtyCount = rows.length - untrackedRows;
      remote = execSync('git remote get-url origin', { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
    } catch {}
    out.push({ path: dir, name: path.basename(dir), hasGit: names.has('.git'), lastCommit, dirtyCount, remote });
  }
  for (const e of entries) {
    if (!e.isDirectory() || e.name.startsWith('.') || SKIP_DIRS.has(e.name) || OUTPUT_DIRS.test(e.name)) continue;
    scanFolder(path.join(dir, e.name), depth + 1, out, maxDepth);
  }
}

function setRoots(list) {
  const clean = [...new Set(list.map((r) => path.resolve(r)).filter((r) => fs.existsSync(r) && fs.statSync(r).isDirectory()))];
  writeJSON(ROOTS_FILE, clean);
  cache = null;
  return clean;
}
const getRoots = () => {
  const saved = readJSON(ROOTS_FILE, null);
  const list = Array.isArray(saved) ? saved : DEFAULT_ROOTS;
  return [...new Set(list.filter((r) => fs.existsSync(r)))];
};

function runCommand(dir) {
  return resolveRun(dir);
}

async function launch(dir) {
  const run = await runCommand(dir);
  if (!run) return { ok: false, message: '该项目未识别到可运行命令' };
  const [cmd, ...args] = run.command.split(' ');
  const logDir = path.join(STATE_DIR, 'logs');
  fs.mkdirSync(logDir, { recursive: true });
  const log = path.join(logDir, path.basename(dir) + '.log');
  const out = fs.openSync(log, 'a');
  fs.writeSync(out, `\n--- ${new Date().toISOString()} ${run.command}\n`);
  const child = spawn(cmd, args, { cwd: dir, detached: true, stdio: ['ignore', out, out], env: { ...process.env, BROWSER: 'none' } });
  child.unref();
  return { ok: true, message: `已启动 ${run.command}（PID ${child.pid}），等待 ${run.port} 就绪`, log };
}

function reveal(dir) {
  return new Promise((resolve) => {
    execFile('open', ['-R', dir], () => resolve({ ok: true, message: '已在 Finder 中显示' }));
  });
}

async function stop(dir) {
  const run = await runCommand(dir);
  if (!run || !run.port) return { ok: false, message: '该项目无端口' };
  const pids = await exec('lsof', ['-ti', `tcp:${run.port}`, '-sTCP:LISTEN'], dir);
  if (!pids) return { ok: false, message: `端口 ${run.port} 没有监听进程` };
  const killed = [];
  for (const pid of pids.split('\n').filter(Boolean)) {
    try { process.kill(Number(pid), 'SIGTERM'); killed.push(pid); } catch {}
  }
  return { ok: killed.length > 0, message: `已停止端口 ${run.port}（PID ${killed.join(', ')}）` };
}


// ---------- 提交测试：后台跑测试命令并收集输出 ----------
const TEST_RUNS = new Map();

function runTests(dir) {
  return new Promise((resolve) => {
    const t = detectTestScript(dir);
    if (!t) return resolve({ ok: false, message: '该项目没有可识别的测试命令' });
    if (TEST_RUNS.get(dir)?.status === 'running') return resolve({ ok: false, message: '测试已在运行中' });
    const startedAt = Date.now();
    const [cmd, ...args] = t.command.split(' ');
    const logDir = path.join(STATE_DIR, 'logs');
    fs.mkdirSync(logDir, { recursive: true });
    const logFile = path.join(logDir, `test-${path.basename(dir)}.log`);
    const child = spawn(cmd, args, { cwd: dir, env: { ...process.env, CI: '1', FORCE_COLOR: '0' } });
    const run = { status: 'running', command: t.command, startedAt, logFile, output: '' };
    TEST_RUNS.set(dir, run);
    const push = (buf) => {
      run.output = (run.output + buf.toString()).slice(-12000);
      fs.appendFileSync(logFile, buf);
    };
    child.stdout.on('data', push);
    child.stderr.on('data', push);
    child.on('error', (e) => {
      run.status = 'failed';
      run.exitCode = -1;
      run.output = String(e.message);
      run.durationMs = Date.now() - startedAt;
    });
    child.on('close', (code) => {
      run.status = code === 0 ? 'passed' : 'failed';
      run.exitCode = code;
      run.durationMs = Date.now() - startedAt;
    });
    resolve({ ok: true, run: { status: run.status, command: run.command, startedAt, logFile } });
  });
}

const readTestRun = (dir) => {
  const r = TEST_RUNS.get(dir);
  if (!r) return { status: 'idle' };
  return { ...r, output: r.output.split('\n').slice(-80).join('\n') };
};

// ---------- 整项目移除 ----------
const NAME_RE = /^[A-Za-z0-9._\u4e00-\u9fa5][A-Za-z0-9._\-\u4e00-\u9fa5 ]{0,80}$/;
const PROTECTED = new Set(['', '/', path.dirname(HOME), HOME, '/Volumes', '/System', '/Applications']);

async function removeProject(dir, mode, confirmName) {
  const p = path.resolve(dir);
  if (PROTECTED.has(p) || p.split(path.sep).length <= 3) return { ok: false, message: '拒绝删除过高层级目录' };
  if (!getRoots().includes(p)) return { ok: false, message: '不在受管项目内' };
  if (mode === 'unmanage') {
    setRoots(getRoots().filter((r) => r !== p));
    return { ok: true, message: '已从看板移除（文件保留）' };
  }
  if (mode !== 'delete-trash' && mode !== 'delete-permanent') return { ok: false, message: '未知移除方式' };
  if (!fs.existsSync(p)) return { ok: false, message: '路径不存在' };
  const base = path.basename(p);
  if (String(confirmName || '').trim() !== base) return { ok: false, message: `确认名称不匹配，请输入「${base}」` };
  if (TEST_RUNS.get(p)?.status === 'running') return { ok: false, message: '该项目的测试仍在运行，先等待结束' };

  if (mode === 'delete-trash') {
    await new Promise((resolve, reject) => {
      execFile('osascript', ['-e', `tell application "Finder" to delete POSIX file "${p.replace(/"/g, '\\"')}"`], (err) => (err ? reject(err) : resolve()));
    }).catch(() => {});
    const gone = !fs.existsSync(p);
    if (gone) setRoots(getRoots().filter((r) => r !== p));
    return { ok: gone, message: gone ? `已移到废纸篓：${base}` : '移到废纸篓失败（可能被系统阻止），未做任何删除' };
  }

  // 永久删除：先复制到 ~/.repodeck/trash 再删，保留 7 天可恢复
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dest = path.join(STATE_DIR, 'trash', `${base}-${stamp}`);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  if (!NAME_RE.test(base)) return { ok: false, message: '目录名含特殊字符，拒绝处理' };
  try {
    fs.cpSync(p, dest, { recursive: true, dereference: false, verbatimSymlinks: true, errorOnExist: true, preserveTimestamps: true });
  } catch (e) {
    return { ok: false, message: `备份到 ~/.repodeck/trash 失败，未删除：${e.message}` };
  }
  fs.rmSync(p, { recursive: true, force: true });
  setRoots(getRoots().filter((r) => r !== p));
  return { ok: true, message: `已删除 ${base}，副本保存在 ~/.repodeck/trash` };
}


// ---------- Git 扩展信息 ----------
async function gitExtra(dir) {
  if (!fs.existsSync(path.join(dir, '.git'))) return null;
  const [branches, status, remote, ahead, aheadBehind, stash, lastTag] = await Promise.all([
    exec('git', ['branch', '--format=%(refname:short)|%(committerdate:iso-strict)|%(upstream:short)', '--sort=-committerdate'], dir),
    exec('git', ['status', '--porcelain=v1', '-uall'], dir),
    exec('git', ['remote', 'get-url', 'origin'], dir),
    exec('git', ['rev-list', '--count', '--left-right', '@{u}...HEAD'], dir),
    exec('git', ['rev-list', '--count', '--left-right', '@{u}...HEAD'], dir),
    exec('git', ['stash', 'list'], dir),
    exec('git', ['describe', '--tags', '--abbrev=0'], dir),
  ]);
  const list = (branches || '').split('\n').filter(Boolean).map((l) => {
    const [name, date, upstream] = l.split('|');
    return { name, date, upstream: upstream || null };
  });
  const files = (status || '').split('\n').filter(Boolean).map((l) => ({
    code: l.slice(0, 2).trim(),
    path: l.slice(3),
    untracked: l.startsWith('??'),
  }));
  let aheadCount = 0, behindCount = 0;
  if (ahead && ahead.includes('\t')) {
    const [b, a] = ahead.split('\t').map(Number);
    aheadCount = a || 0;
    behindCount = b || 0;
  }
  return {
    branches: list.slice(0, 40),
    branchCount: list.length,
    files: files.slice(0, 200),
    changedCount: files.length,
    remote: remote || null,
    ahead: aheadCount,
    behind: behindCount,
    aheadBehind: aheadBehind || null,
    stashCount: (stash || '').split('\n').filter(Boolean).length,
    lastTag: lastTag || null,
  };
}

// ---------- 文档清单 ----------
const DOC_CANDIDATES = ['README.md', 'PRODUCT.md', 'HANDOFF.MD', 'CLAUDE.md', 'AGENTS.md', 'DESIGN.md', 'ARCHITECTURE.md', 'lessons.md', 'task_plan.md', 'progress.md'];
function listDocs(dir) {
  const out = [];
  for (const f of DOC_CANDIDATES) {
    const p = path.join(dir, f);
    try {
      const st = fs.statSync(p);
      if (!st.isFile()) continue;
      const raw = fs.readFileSync(p, 'utf8');
      const title = (raw.match(/^#\s+(.+)$/m) || [])[1] || f;
      out.push({ file: f, title: title.slice(0, 80), bytes: st.size, mtime: st.mtime.toISOString(), lines: raw.split('\n').length });
    } catch {}
  }
  return out;
}

function readDoc(dir, file) {
  if (!DOC_CANDIDATES.includes(file)) return { ok: false, message: '不支持的文件' };
  const p = path.join(dir, file);
  if (!fs.existsSync(p)) return { ok: false, message: '文件不存在' };
  const text = fs.readFileSync(p, 'utf8').slice(0, 200000);
  return { ok: true, file, text };
}

async function recentCommits(dir, n = 12) {
  if (!fs.existsSync(path.join(dir, '.git'))) return [];
  const out = await exec('git', ['log', `-${n}`, '--format=%H%n%h%n%ad%n%an%n%s%n%D', '--date=iso-strict'], dir);
  if (!out) return [];
  const lines = out.split('\n');
  const res = [];
  for (let i = 0; i + 5 < lines.length; i += 6) {
    res.push({ full: lines[i], hash: lines[i + 1], date: lines[i + 2], author: lines[i + 3], subject: lines[i + 4], refs: lines[i + 5] });
  }
  return res;
}


async function weeklyCommits(dir) {
  if (!fs.existsSync(path.join(dir, '.git'))) return null;
  const out = await exec('git', ['log', '--since=7.days', '--date=short', '--format=%ad'], dir);
  if (out === null) return null;
  const m = {};
  for (const d of out.split('\n').filter(Boolean)) m[d] = (m[d] || 0) + 1;
  return m;
}

async function projectDetail(dir) {
  if (!getRoots().includes(dir)) return { ok: false, message: '不在受管项目内' };
  const [git, commits] = await Promise.all([gitExtra(dir), recentCommits(dir)]);
  return { ok: true, git, commits, docs: listDocs(dir) };
}

// ---------- 切换分支 ----------
async function checkout(dir, branch) {
  if (!getRoots().includes(dir)) return { ok: false, message: '不在受管项目内' };
  if (!/^[A-Za-z0-9._\/-]{1,120}$/.test(branch)) return { ok: false, message: '分支名非法' };
  const st = await exec('git', ['status', '--porcelain', '-uall'], dir);
  if (st && st.split('\n').filter(Boolean).length > 0) {
    return { ok: false, message: `有 ${st.split('\n').filter(Boolean).length} 个未提交改动，先处理再切分支` };
  }
  const out = await exec('git', ['checkout', branch], dir);
  if (out === null) return { ok: false, message: `切换失败：${branch}` };
  cache = null;
  return { ok: true, message: `已切换到 ${branch}` };
}

async function fetchRemote(dir) {
  if (!getRoots().includes(dir)) return { ok: false, message: '不在受管项目内' };
  const out = await new Promise((resolve) => {
    execFile('git', ['fetch', '--all', '--prune', '--quiet'], { cwd: dir, timeout: 60000 }, (err, _s, stderr) => resolve(err ? (stderr || 'fetch 失败') : 'ok'));
  });
  if (out !== 'ok') return { ok: false, message: String(out).slice(0, 200) };
  cache = null;
  return { ok: true, message: '已同步远程' };
}

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.json': 'application/json' };

function send(res, code, data, type = 'application/json') {
  res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(typeof data === 'string' || data instanceof Uint8Array ? data : JSON.stringify(data));
}

function readBody(req) {
  return new Promise((resolve) => {
    let b = '';
    req.on('data', (c) => { b += c; if (b.length > 1 << 20) req.destroy(); });
    req.on('end', () => { try { resolve(JSON.parse(b || '{}')); } catch { resolve({}); } });
  });
}

const VALID_COLORS = new Set(['red', 'amber', 'green', 'blue', 'violet']);
const ALLOWED_ROOTS = () => getRoots();

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const origin = req.headers.origin;
  if (origin && !/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(origin)) return send(res, 403, { ok: false, message: 'forbidden origin' });
  try {
    if (url.pathname === '/api/state') return send(res, 200, cache || (await scan()));
    if (url.pathname === '/api/rescan') return send(res, 200, await scan());

    if (url.pathname === '/api/pick-folder' && req.method === 'POST') {
      return new Promise((resolve) => {
        execFile('osascript', ['-e', 'POSIX path of (choose folder with prompt "选择要扫描的目录")'], { timeout: 120000 }, (err, out) => {
          if (err) return resolve(send(res, 200, { ok: false, message: '已取消' }));
          resolve(send(res, 200, { ok: true, dir: String(out).trim().replace(/\/$/, '') }));
        });
      });
    }
    if (url.pathname === '/api/folders' && req.method === 'POST') {
      const { dir, depth } = await readBody(req);
      const base = dir || HOME;
      if (!base || !fs.existsSync(base)) return send(res, 400, { ok: false, message: '目录不存在' });
      const out = [];
      scanFolder(path.resolve(base), 0, out, Math.min(Number(depth) || 2, 4));
      const managed = new Set(getRoots());
      return send(res, 200, { ok: true, base, found: out.map((f) => ({ ...f, added: managed.has(f.path) })) });
    }
    if (url.pathname === '/api/roots' && req.method === 'POST') {
      const { add, remove } = await readBody(req);
      let list = getRoots();
      if (add) {
        const p = path.resolve(String(add));
        if (!fs.existsSync(p) || !fs.statSync(p).isDirectory()) return send(res, 400, { ok: false, message: '不是有效目录' });
        list = [...list, p];
      }
      if (remove) list = list.filter((r) => r !== path.resolve(String(remove)));
      const saved = setRoots(list);
      return send(res, 200, { ok: true, roots: saved });
    }

    if (url.pathname === '/api/test' && req.method === 'POST') {
      const { path: p } = await readBody(req);
      if (!p || !ALLOWED_ROOTS().includes(p)) return send(res, 400, { ok: false, message: '不在受管项目内' });
      return send(res, 200, await runTests(p));
    }
    if (url.pathname === '/api/test-run') {
      const p = url.searchParams.get('path');
      if (!p || !ALLOWED_ROOTS().includes(p)) return send(res, 400, { ok: false, message: '不在受管项目内' });
      return send(res, 200, { ok: true, ...readTestRun(p) });
    }
    if (url.pathname === '/api/remove' && req.method === 'POST') {
      const { path: p, mode, confirm } = await readBody(req);
      return send(res, 200, await removeProject(p, mode, confirm));
    }

    if (url.pathname === '/api/project') {
      const p = url.searchParams.get('path');
      if (!p) return send(res, 400, { ok: false, message: '缺少 path' });
      return send(res, 200, await projectDetail(p));
    }
    if (url.pathname === '/api/doc') {
      const p = url.searchParams.get('path');
      const f = url.searchParams.get('file');
      if (!p || !getRoots().includes(p)) return send(res, 400, { ok: false, message: '不在受管项目内' });
      return send(res, 200, readDoc(p, f));
    }
    if (url.pathname === '/api/git' && req.method === 'POST') {
      const { path: p, action, branch } = await readBody(req);
      if (action === 'checkout') return send(res, 200, await checkout(p, branch));
      if (action === 'fetch') return send(res, 200, await fetchRemote(p));
      return send(res, 400, { ok: false, message: '未知动作' });
    }
    if (url.pathname === '/api/orphans') return send(res, 200, await orphans());
    if (url.pathname === '/api/action' && req.method === 'POST') {
      const { path: p, action } = await readBody(req);
      if (!p || !ALLOWED_ROOTS().includes(p)) return send(res, 400, { ok: false, message: '不在受管项目内' });
      if (!fs.existsSync(p)) return send(res, 400, { ok: false, message: '路径不存在' });
      if (action === 'launch') return send(res, 200, await launch(p));
      if (action === 'reveal') return send(res, 200, await reveal(p));
      if (action === 'stop') return send(res, 200, await stop(p));
      return send(res, 400, { ok: false, message: '未知动作' });
    }
    if ((url.pathname === '/api/star' || url.pathname === '/api/meta') && req.method === 'POST') {
      const body = await readBody(req);
      if (!body.path || !ALLOWED_ROOTS().includes(body.path)) return send(res, 400, { ok: false, message: '不在受管项目内' });
      const meta = readJSON(STATE_FILE, {});
      const entry = { ...(meta[body.path] || {}) };
      if (url.pathname === '/api/star') entry.starred = !!body.starred;
      else {
        if ('color' in body) entry.color = VALID_COLORS.has(body.color) ? body.color : null;
        if ('note' in body) entry.note = String(body.note || '').slice(0, 200);
      }
      meta[body.path] = entry;
      writeJSON(STATE_FILE, meta);
      if (cache) {
        const proj = cache.projects.find((x) => x.path === body.path);
        if (proj) Object.assign(proj, entry);
      }
      return send(res, 200, { ok: true });
    }
    const rel = url.pathname === '/'
      ? 'index.html'
      : url.pathname === '/landing' || url.pathname === '/landing/'
        ? 'landing.html'
        : url.pathname.replace(/^\//, '');
    const file = path.join(PUBLIC, rel);
    if (!path.resolve(file).startsWith(path.resolve(PUBLIC))) return send(res, 403, 'forbidden', 'text/plain');
    if (!fs.existsSync(file)) return send(res, 404, 'not found', 'text/plain');
    return send(res, 200, fs.readFileSync(file), MIME[path.extname(file)] || 'application/octet-stream');
  } catch (e) {
    return send(res, 500, { ok: false, message: String(e && e.message) });
  }
});

server.listen(PORT, '127.0.0.1', async () => {
  console.log(`FizzDeck → http://127.0.0.1:${PORT}`);
  const s = await scan();
  console.log(`  已扫描 ${s.projects.length} 个项目，用时 ${s.scan.durationMs}ms`);
});
