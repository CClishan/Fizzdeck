import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
const H = os.homedir();
const rootsFile = path.join(H, '.repodeck', 'roots.json');
const roots = fs.existsSync(rootsFile) ? JSON.parse(fs.readFileSync(rootsFile, 'utf8')) : [];
if (!roots.length) {
  console.log(`没有受管项目。请先在 FizzDeck 中添加项目，或编辑 ${rootsFile}。`);
  process.exit(0);
}
const gb = (b) => (b/1e9).toFixed(2)+' GB';
const run = (d) => new Promise(r => execFile('du',['-sk',d],{maxBuffer:1<<20},(e,o)=>r(e?0:(parseInt(o)*1024))));
const files = (d, f) => { let o=[]; try{ for(const e of fs.readdirSync(d,{withFileTypes:true})){ const p=path.join(d,e.name); if(e.isDirectory()) o=o.concat(files(p,f)); else if(f(p)) o.push(p);} }catch{} return o; };
const big = (d, min=50e6) => { let o=[]; const walk=(x,dep)=>{ if(dep>3)return; let es=[]; try{es=fs.readdirSync(x,{withFileTypes:true})}catch{return} for(const e of es){const p=path.join(x,e.name); let st; try{st=fs.statSync(p)}catch{continue} if(e.isDirectory()) walk(p,dep+1); else if(st.size>min) o.push([p,st.size]);}}; walk(d,0); return o.sort((a,b)=>b[1]-a[1]); };
const out=[];
for (const r of roots) {
  if (!fs.existsSync(r)) { out.push([r,'MISSING',0,[]]); continue; }
  let total=0, items=[];
  for (const e of fs.readdirSync(r,{withFileTypes:true})) {
    if(!e.isDirectory()) continue;
    if(!/^(node_modules|\.next|\.open-next|\.svelte-kit|\.astro|\.tanstack|\.wrangler|dist|dist-[a-z]+|build|output|artifacts|releases|tmp|screens|public|img|assets-original|screenshots|logs)$/i.test(e.name)) continue;
    const p=path.join(r,e.name); const b=await run(p); total+=b; items.push([e.name,b]);
  }
  items.sort((a,b)=>b[1]-a[1]);
  out.push([r,gb(total),items,big(r)]);
}
for (const [r,t,items,bs] of out) {
  if(t==='MISSING'){console.log('\n## '+r+'  (不存在/未挂载)');continue;}
  console.log('\n## '+path.basename(r)+'  可回收 '+t);
  for (const [n,b] of items) console.log('  '+n.padEnd(18)+gb(b));
  for (const [p,b] of bs.slice(0,3)) console.log('   单文件 '+gb(b)+'  '+p.replace(H,'~'));
}
