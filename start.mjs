import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const dir = path.dirname(new URL(import.meta.url).pathname);
const PORT = process.env.PORT || 4770;

const up = await fetch(`http://127.0.0.1:${PORT}/api/state`).then(() => true).catch(() => false);
if (up) {
  console.log(`已在运行 → http://127.0.0.1:${PORT}`);
} else {
  const child = spawn(process.execPath, [path.join(dir, 'server.mjs')], { detached: true, stdio: 'ignore', env: { ...process.env, PORT } });
  child.unref();
  for (let i = 0; i < 40; i++) {
    await new Promise((r) => setTimeout(r, 500));
    if (await fetch(`http://127.0.0.1:${PORT}/api/state`).then(() => true).catch(() => false)) break;
  }
  console.log(`已启动 → http://127.0.0.1:${PORT}`);
}
spawn('open', [`http://127.0.0.1:${PORT}`], { stdio: 'ignore' }).unref();
