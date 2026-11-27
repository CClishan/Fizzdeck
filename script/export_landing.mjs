// Copy exactly the built landing and its Vite asset graph to the koroo site.
// The dashboard's server, project data, and JS entry are never published.
import { copyFile, mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
const publicDir = new URL('../public/', import.meta.url);
const output = process.argv[2];
if (!output) throw new Error('Usage: node script/export_landing.mjs /path/to/koroo-blog');
await readFile(path.join(output, 'app/fizzdeck/route.ts'));
const manifest = JSON.parse(await readFile(new URL('.vite/manifest.json', publicDir), 'utf8'));
const files = new Set(), visited = new Set();
function collect(key) {
  if (visited.has(key)) return;
  visited.add(key);
  const item = manifest[key];
  for (const file of [item.file, ...(item.css || []), ...(item.assets || [])]) files.add(file);
  for (const dependency of [...(item.imports || []), ...(item.dynamicImports || [])]) collect(dependency);
}
collect('landing.html');
const html = await readFile(new URL('landing.html', publicDir), 'utf8');
for (const match of html.matchAll(/(?:src|href)="\/(assets\/[^"?#]+)"/g)) files.add(match[1]);
for (const file of files) {
  if (!/^assets\/[\w.-]+$/.test(file)) throw new Error(`Unexpected landing asset: ${file}`);
  const destination = path.join(output, 'public', file);
  await mkdir(path.dirname(destination), { recursive: true });
  await copyFile(new URL(file, publicDir), destination);
}
await copyFile(new URL('landing.html', publicDir), path.join(output, 'app/fizzdeck/landing.html'));
console.log(`Exported landing.html and ${files.size} assets.`);
