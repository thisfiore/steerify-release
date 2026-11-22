#!/usr/bin/env node
// The changelogs, from the release notes (scripts/release-notes.mjs Markdown, the GitHub Release body):
//   site/releases.html  one <article id="v<version>"> on top (steerify.dev "What's new"), hero count, title
//   CHANGELOG.md        one "## <version> · <date>" section on top (public repo)
//   site/llms.txt + site/sitemap.xml   latest version / lastmod
//   node scripts/changelog.mjs <version> <notes.md> [dateISO] [--out <dir>]
// Same version again = that entry is replaced, never duplicated. --out writes copies there (dry run).
// --changelog-only: CHANGELOG.md alone (backfilling old versions; their site entries are hand-written).
// STEERIFY_RELEASE_HEADLINE overrides the entry's headline (default: the first feature's title).
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const ONLY_CL = args.includes('--changelog-only') && args.splice(args.indexOf('--changelog-only'), 1);
const oi = args.indexOf('--out');
const outDir = oi >= 0 ? args.splice(oi, 2)[1] : null;
const [version, notesFile, dateArg] = args;
if (!version || !notesFile) { console.error('usage: changelog.mjs <version> <notes.md> [dateISO] [--out dir]'); process.exit(1); }
const date = dateArg ? new Date(dateArg) : new Date();
const read = (f) => readFileSync(join(root, f), 'utf8');
const write = (f, s) => { const p = outDir ? join(outDir, f) : join(root, f); mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, s); };

// 1. Notes Markdown → sections [{title, items:[{title, what[]}]}].
const sections = [];
for (const line of readFileSync(notesFile, 'utf8').split('\n')) {
  const h = line.match(/^### (.+)/);
  if (h) { sections.push({ title: h[1].trim(), items: [] }); continue; }
  const m = line.match(/^- \*\*(.+?)\*\*(?: — (.*))?$/);
  if (m && sections.length) sections.at(-1).items.push({ title: m[1], what: (m[2] || '').split(' · ').map((w) => w.trim()).filter(Boolean) });
}
const items = sections.flatMap((s) => s.items);
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const month = date.toLocaleString('en-GB', { month: 'short', timeZone: 'Europe/Rome' });
const day = Number(date.toLocaleString('en-GB', { day: 'numeric', timeZone: 'Europe/Rome' }));
const when = `${day} ${month}`;
const isoDay = date.toLocaleDateString('sv-SE', { timeZone: 'Europe/Rome' });

// 2. steerify.dev/releases.html (+ llms.txt, sitemap lastmod)
const icons = [[/roadmap|chapter|key result/i, 'road'], [/request|⌘N|screenshot/i, 'req'], [/choice|pick/i, 'choice'],
  [/session|terminal|claude/i, 'term'], [/to test|test note|verdict/i, 'test'], [/release|update|deploy|speed|performance/i, 'ship'],
  [/demo|shots|site|steerify\.dev/i, 'file'], [/start|resume|next/i, 'play']];
const icon = (t) => (icons.find(([re]) => re.test(t)) || [, 'feather'])[1];
const sentence = (w) => w.map((x) => x.replace(/[.\s]+$/, '')).join('. ') + (w.length ? '.' : '');
const headline = process.env.STEERIFY_RELEASE_HEADLINE || (items[0] ? items[0].title.replace(/[.:\s]+$/, '') + '.' : 'Small fixes and polish.');
const li = (it) => `<li><span class="ri" data-icon="${icon(it.title)}"></span><div><h3>${esc(it.title)}</h3><p>${esc(sentence(it.what))}</p></div></li>`;
const groups = sections.filter((s) => s.items.length).map((s) => `<div class="rel-group"><h4>${esc(s.title)}</h4><ul>${s.items.map(li).join('')}</ul></div>`);
const article = `      <article class="rel" id="v${esc(version)}">
        <header><span class="ver">v${esc(version)}</span><span class="when">${when}</span><h2>${esc(headline)}</h2></header>
        <div class="rel-body solo">${groups.join('') || '<ul><li><span class="ri" data-icon="feather"></span><div><h3>Small fixes and polish</h3><p>Nothing new to see, a few things work better.</p></div></li></ul>'}</div>
      </article>
`;
if (!ONLY_CL) {
let html = read('site/releases.html');
const own = new RegExp(`      <article class="rel" id="v${version.replace(/\./g, '\\.')}">[\\s\\S]*?</article>\\n`);
if (own.test(html)) html = html.replace(own, article);
else html = html.replace(/(<div class="wrap rels">\n)/, `$1${article}`);
if (!html.includes(`id="v${version}"`)) { console.error('releases.html: no <div class="wrap rels"> to insert into'); process.exit(1); }
// Hero: "<N> releases. <D> days." (v0.1–v0.4 shipped before the tags; days since 18 Nov 2026, the first one).
const tags = new Set(execSync('git tag -l "v*"', { cwd: root }).toString().split('\n').filter(Boolean));
tags.add('v' + version);
const n = tags.size + 4;
const days = Math.floor((Date.parse(isoDay) - Date.parse('2026-11-18')) / 864e5) + 1;
const words = ['Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
const word = (x) => x < 20 ? words[x] : x < 100 ? tens[Math.floor(x / 10)] + (x % 10 ? '-' + words[x % 10].toLowerCase() : '') : String(x);
html = html.replace(/<h1 class="rel-title">[^<]*<\/h1>/, `<h1 class="rel-title">${word(n)} releases. ${word(days)} ${days === 1 ? 'day' : 'days'}.</h1>`);
html = html.replace(/release notes v0\.1 to v[\d.]+/g, `release notes v0.1 to v${version}`);
html = html.replace(/("datePublished":"[^"]*")/, `$1,"dateModified":"${isoDay}"`).replace(/,"dateModified":"[^"]*"(?=,"dateModified")/, '');
write('site/releases.html', html);
write('site/llms.txt', read('site/llms.txt').replace(/release notes v0\.1 to v[\d.]+/, `release notes v0.1 to v${version}`));
write('site/sitemap.xml', read('site/sitemap.xml').replace(/(<loc>https:\/\/steerify\.dev\/releases\.html<\/loc>\s*<lastmod>)[^<]*/, `$1${isoDay}`));
}

// 3. CHANGELOG.md (public repo)
const head = '# Changelog\n\nEvery Steerify release, newest first. Downloads: https://github.com/thisfiore/steerify-release/releases · with pictures: https://steerify.dev/releases.html\n';
let cl = existsSync(join(root, 'CHANGELOG.md')) ? read('CHANGELOG.md') : head;
const md = [`## ${version} · ${isoDay}`, ''];
for (const s of sections) {
  md.push(`### ${s.title}`, '');
  for (const it of s.items) md.push(`- **${it.title}**${it.what.length ? ' — ' + it.what.join(' · ') : ''}`);
  md.push('');
}
if (!items.length) md.push('Small fixes and polish.', '');
const entry = md.join('\n');
const ownMd = new RegExp(`## ${version.replace(/\./g, '\\.')} · [^\\n]*\\n[\\s\\S]*?(?=\\n## |$)`);
if (ownMd.test(cl)) cl = cl.replace(ownMd, entry.trimEnd() + '\n');
else {
  // Newest first: before the first section with a lower version.
  const cmp = (a, b) => { const x = a.split('.').map(Number), y = b.split('.').map(Number); for (let k = 0; k < 3; k++) if ((x[k] || 0) !== (y[k] || 0)) return (x[k] || 0) - (y[k] || 0); return 0; };
  const re = /\n## (\d+\.\d+(?:\.\d+)?) · /g; let at = -1, m;
  while ((m = re.exec(cl))) if (cmp(m[1], version) < 0) { at = m.index; break; }
  cl = at < 0 ? cl.trimEnd() + '\n\n' + entry : cl.slice(0, at + 1) + entry + '\n' + cl.slice(at + 1);
}
write('CHANGELOG.md', cl.replace(/\n{3,}/g, '\n\n'));

console.log(`changelog: v${version} (${items.length} items) → ${ONLY_CL ? '' : 'site/releases.html, '}CHANGELOG.md${outDir ? ' in ' + outDir : ''}`);
