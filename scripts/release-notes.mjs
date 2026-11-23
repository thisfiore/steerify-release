#!/usr/bin/env node
// Release notes from the board: To test items you marked OK since the last release, written for the people
// who use Steerify (not for us).
//   node scripts/release-notes.mjs <version> [sinceISO]          → all public notes (GitHub release, changelogs)
//   node scripts/release-notes.mjs <version> [sinceISO] --app    → the Mac app only (its "What's new" + the update panel)
// Each approved item goes to one audience:
//   app      the Mac app (area mac)
//   iphone   the iPhone app (area mac, title about the iPhone and not the Mac)
//   site     steerify.dev (area site)
//   internal our own tooling and marketing (HQ, demos, shots, changelogs, perf checks, other repos): left out
// A delivery can say it itself with "notes": "app" | "iphone" | "site" | "internal".
// Only titles + short "what" lines: no screenshots, no private board content.
// The same Markdown becomes the steerify.dev/releases.html entry + CHANGELOG.md (scripts/changelog.mjs).
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const j = (f) => JSON.parse(readFileSync(join(root, '.steerify', f), 'utf8'));
const args = process.argv.slice(2);
const appOnly = args.includes('--app');
const [version, since = ''] = args.filter((a) => !a.startsWith('--'));
const choices = j('decisions.json').choices || {};
const items = j('delivered.json').items || [];

const INTERNAL = /\b(HQ|demo|Tiny Todo|Nonna Says|marketing|README|changelogs?|perf(ormance)? (check|budget)|own repo|archived|framed|shots|TestFlight invite|waitlist|sign-ups)\b/i;
// Our own Mac and test setup, wherever the item mentions it.
const DEV_ONLY = /\b(Homebrew|MongoDB|blender-mcp|test cop(y|ies)|test builds?)\b/i;
export function audience(it) {
  if (['app', 'iphone', 'site', 'internal'].includes(it.notes)) return it.notes;
  const t = it.title || '';
  if (INTERNAL.test(t) || DEV_ONLY.test(t + '\n' + (it.what || ''))) return 'internal';
  if (it.area === 'site') return 'site';
  if (/\biPhone\b/i.test(t) && !/\bMac\b/.test(t)) return 'iphone';
  return 'app';
}

const approved = items
  .map((it) => ({ it, v: choices['ship:' + it.id] }))
  .filter(({ v }) => v && v.pick === 'ok' && (!since || (v.at || '') > since))
  .sort((a, b) => (a.v.at || '').localeCompare(b.v.at || ''));

const firstLine = (w) => String(w || '').split(/\n|,(?=[A-Z])/).map((l) => l.replace(/^[-•]\s*/, '').trim())
  .filter((l) => l && !/^(Released|Live|Pushed|Bundled|Deployed)\b/i.test(l));
const sections = appOnly ? [['app', 'In the app']] : [['app', 'In the app'], ['iphone', 'On the iPhone'], ['site', 'On steerify.dev']];
const out = [`## Steerify ${version}`, ''];
let n = 0;
for (const [key, head] of sections) {
  const rows = approved.filter(({ it }) => audience(it) === key);
  if (!rows.length) continue;
  out.push(`### ${head}`, '');
  for (const { it } of rows) {
    const what = firstLine(it.what);
    const short = what.length > 1 ? what.slice(0, 4).join(' · ') : (what[0] || '').split(/(?<=\.)\s/)[0];
    out.push(`- **${it.title}**${short ? ' — ' + short : ''}`);
    n++;
  }
  out.push('');
}
if (!n) out.push('Small fixes and polish.', '');
out.push(`Full notes: https://steerify.dev/releases.html#v${version}`);
console.log(out.join('\n'));
