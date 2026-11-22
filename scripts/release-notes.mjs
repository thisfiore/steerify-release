#!/usr/bin/env node
// Release notes from the board: To test items you marked OK since the last release.
//   node scripts/release-notes.mjs <version> [sinceISO]   → Markdown on stdout
// Only titles + short "what" lines: no screenshots, no private board content.
// The same Markdown becomes the steerify.dev/releases.html entry + CHANGELOG.md (scripts/changelog.mjs).
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const j = (f) => JSON.parse(readFileSync(join(root, '.steerify', f), 'utf8'));
const [version, since = ''] = process.argv.slice(2);
const choices = j('decisions.json').choices || {};
const items = j('delivered.json').items || [];

const approved = items
  .map((it) => ({ it, v: choices['ship:' + it.id] }))
  .filter(({ v }) => v && v.pick === 'ok' && (!since || (v.at || '') > since))
  .sort((a, b) => (a.v.at || '').localeCompare(b.v.at || ''));

const firstLine = (w) => String(w || '').split(/\n|,(?=[A-Z])/).map((l) => l.replace(/^[-•]\s*/, "").trim())
  .filter((l) => l && !/^(Released|Live|Pushed|Bundled|Deployed)\b/i.test(l));
const group = { mac: 'In the app', site: 'On steerify.dev' };
const out = [`## Steerify ${version}`, ''];
for (const area of ['mac', 'site', null]) {
  const rows = approved.filter(({ it }) => (area ? it.area === area : !group[it.area]));
  if (!rows.length) continue;
  out.push(`### ${area ? group[area] : 'Also'}`, '');
  for (const { it } of rows) {
    const what = firstLine(it.what);
    const short = what.length > 1 ? what.slice(0, 4).join(' · ') : (what[0] || '').split(/(?<=\.)\s/)[0];
    out.push(`- **${it.title}**${short ? ' — ' + short : ''}`);
  }
  out.push('');
}
if (!approved.length) out.push('Small fixes and polish.', '');
out.push(`Full notes: https://steerify.dev/releases.html#v${version}`);
console.log(out.join('\n'));
