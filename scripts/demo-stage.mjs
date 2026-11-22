#!/usr/bin/env node
// Copies the frozen demo to <dir> and shifts every timestamp on its board so the newest one is <minutes> ago.
// Relative times in the app ("20 min ago") then read the same on every run.
//   node scripts/demo-stage.mjs <dir> [minutes=20] [demo=tiny-todo]   → prints the board folder
import { cpSync, rmSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';

const root = join(dirname(new URL(import.meta.url).pathname), '..');
const [dir, mins = '20', demo = 'tiny-todo'] = process.argv.slice(2);
if (!dir) { console.error('usage: demo-stage.mjs <dir> [minutes]'); process.exit(1); }
rmSync(dir, { recursive: true, force: true });
cpSync(join(root, 'demo', demo), dir, { recursive: true });
const board = join(dir, '.steerify');
const ISO = /"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z)"/g;
const jsons = readdirSync(board).filter((f) => f.endsWith('.json'));
let newest = 0;
for (const f of jsons) for (const m of readFileSync(join(board, f), 'utf8').matchAll(ISO)) newest = Math.max(newest, Date.parse(m[1]));
const shift = newest ? Date.now() - +mins * 60e3 - newest : 0;
for (const f of jsons) {
  const p = join(board, f);
  writeFileSync(p, readFileSync(p, 'utf8').replace(ISO, (_, t) => `"${new Date(Date.parse(t) + shift).toISOString()}"`));
}
console.log(board);
