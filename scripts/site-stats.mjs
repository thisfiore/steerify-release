#!/usr/bin/env node
// Writes the "Built in itself" numbers into site/index.html from the Steerify board (.steerify).
// Run before deploying the site: node scripts/site-stats.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const j = (f) => JSON.parse(readFileSync(join(root, '.steerify', f), 'utf8'));
const choices = j('decisions.json').choices || {}, items = j('delivered.json').items || [];
const answered = Object.entries(choices).filter(([k, c]) => !k.includes(':') && c && c.pick != null).length;
const verdict = (it) => (choices['ship:' + it.id] || {}).pick;
const versions = items.reduce((n, it) => n + (it.version || 1), 0);
const ok = items.filter((it) => verdict(it) === 'ok').length;
const dates = Object.values(choices).map((c) => c && c.at).filter(Boolean).sort();
// Calendar days, first answer to last, both counted.
const day = (t) => Math.floor(Date.parse(t.slice(0, 10)) / 864e5);
const days = dates.length ? day(dates.at(-1)) - day(dates[0]) + 1 : 1;
const stats = [[answered, 'choices answered'], [versions, 'deliveries looked at'], [ok, 'marked OK'], [0, 'status meetings'], [days, (days === 1 ? 'day' : 'days') + ' from the first idea to this page']];
const html = stats.map(([n, l]) => `<div class="stat"><b>${n}</b><span>${l}</span></div>`).join('\n');
const p = join(root, 'site', 'index.html'), s = readFileSync(p, 'utf8');
const out = s.replace(/<!-- stats:start -->[\s\S]*?<!-- stats:end -->/, `<!-- stats:start -->\n${html}\n<!-- stats:end -->`);
if (out === s && !s.includes('<!-- stats:start -->')) { console.error('no stats markers in site/index.html'); process.exit(1); }
writeFileSync(p, out);
console.log(stats.map(([n, l]) => `${n} ${l}`).join(' · '));
