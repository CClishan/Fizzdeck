// 构建前端到 public/（server.mjs 直接托管）
import { execSync } from 'node:child_process';
execSync('npx vite build', { stdio: 'inherit' });
