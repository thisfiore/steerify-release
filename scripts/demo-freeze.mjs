#!/usr/bin/env node
// Freezes the demo project (Tiny Todo) into demo/tiny-todo: the repo's tracked files + its board.
// Real sessions keep working in ~/Sites/tiny-todo; screenshots, the tutorial and the app's "Try the demo project"
// all use this frozen copy, so pictures don't move between runs.
//
//   node scripts/demo-freeze.mjs [source]        (default ~/Sites/tiny-todo)
//
// Checks: no private words (client names, team) and no sessions.json (conversation ids stay on this Mac).
import { execFileSync } from 'node:child_process';
import { cpSync, rmSync, mkdirSync, readFileSync, existsSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';

const root = join(dirname(new URL(import.meta.url).pathname), '..');
const src = process.argv[2] || join(homedir(), 'Sites/tiny-todo');
const out = join(root, 'demo/tiny-todo');
const skip = new Set(['.steerify/sessions.json', '.steerify/decisions.prev.json']);
const PRIVATE = /save the duck|kiton|valentino|moschino|armani|synthetic brain|blink|frenk|francesco/i;

const files = execFileSync('git', ['ls-files'], { cwd: src }).toString().split('\n').filter(Boolean)
  .filter((f) => !skip.has(f));
rmSync(out, { recursive: true, force: true });
for (const f of files) {
  mkdirSync(dirname(join(out, f)), { recursive: true });
  cpSync(join(src, f), join(out, f));
  if (/\.(json|md|html|js|css)$/.test(f)) {
    const hit = readFileSync(join(out, f), 'utf8').match(PRIVATE);
    if (hit) { console.error(`private word "${hit[0]}" in ${f}: fix it in ${src}, then freeze again`); process.exit(1); }
  }
}
const head = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: src }).toString().trim();
writeFileSync(join(out, '.frozen'), `${head} ${new Date().toISOString()}\n`);
console.log(`froze ${files.length} files from ${src} @ ${head} → demo/tiny-todo`);
