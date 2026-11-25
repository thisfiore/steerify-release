#!/usr/bin/env node
// No 404s on steerify.dev. Run before shipping the site:
//   node scripts/check-links.mjs          every link / src / url() in site/ points at a file that exists
//   node scripts/check-links.mjs --live   + every page, asset and clean URL answers on https://steerify.dev
// Clean URLs (/releases, /privacy …) are served by 404.html, which sends them to the .html page: that list must
// cover every page, so a shared or typed link never lands on "Off course".
import fs from 'node:fs';
import path from 'node:path';

const SITE = path.resolve(new URL('../site', import.meta.url).pathname);
const LIVE = process.argv.includes('--live');
const ORIGIN = 'https://steerify.dev';
let bad = 0;
const fail = (m) => { bad++; console.error('FAIL ' + m); };

const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) =>
  e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]);
const files = walk(SITE);
const rel = (f) => '/' + path.relative(SITE, f).split(path.sep).join('/');
const exists = new Set(files.map(rel));
const pages = files.filter((f) => /\.html$/.test(f) && path.dirname(f) === SITE).map(rel);

// 1. Local references: href, src, srcset, poster, url(), and steerify.dev links in the text files.
const refs = new Map(); // site path → first file that uses it
const add = (p, from) => { if (!refs.has(p)) refs.set(p, from); };
for (const f of files.filter((x) => /\.(html|css|js|json|txt|xml)$/.test(x))) {
  const src = fs.readFileSync(f, 'utf8').replace(/^\s*\/\/.*$/gm, ''), base = path.posix.dirname(rel(f));
  const found = [
    ...[...src.matchAll(/\b(?:href|src|poster)="([^"]+)"/g)].map((m) => m[1]),
    ...[...src.matchAll(/\bsrcset="([^"]+)"/g)].flatMap((m) => m[1].split(',').map((s) => s.trim().split(/\s+/)[0])),
    ...(/\.(css|html)$/.test(f) ? [...src.matchAll(/url\(\s*['"]?([^'")]+)['"]?\s*\)/g)].map((m) => m[1]) : []),
    ...[...src.matchAll(/https:\/\/(?:www\.)?steerify\.dev(\/[^\s"'<>)\]]*)/g)].map((m) => m[1]),
  ];
  for (let u of found) {
    if (/^(https?:|mailto:|data:|#|javascript:|steerify:|tel:)/.test(u) || /[{}$`+]/.test(u)) continue;
    u = u.split('#')[0].split('?')[0];
    if (!u) continue;
    const p = u.startsWith('/') ? path.posix.normalize(u) : path.posix.normalize(path.posix.join(base, u));
    add(p, rel(f));
  }
}
const resolve = (p) => (p === '/' ? '/index.html' : p.endsWith('/') ? p + 'index.html' : p);
let n = 0;
for (const [p, from] of refs) {
  n++;
  const r = resolve(p);
  if (!exists.has(r) && !exists.has(r + '.html')) fail(`${p} (used in ${from}) is not in site/`);
}
console.log(`ok   ${n} local links checked in ${files.length} files`);

// 2. Every page is reachable by its clean URL through 404.html.
const nf = fs.readFileSync(path.join(SITE, '404.html'), 'utf8');
const clean = (nf.match(/PAGES\s*=\s*\[([^\]]*)\]/) || [])[1] || '';
for (const p of pages) {
  const name = p.replace(/\.html$/, '').slice(1);
  if (['index', '404'].includes(name)) continue;
  if (!new RegExp(`['"]${name}['"]`).test(clean)) fail(`/${name} has no clean URL: add '${name}' to PAGES in site/404.html`);
}

// 3. Live: the pages, every asset referenced and every clean URL.
if (LIVE) {
  const get = async (u) => { try { const r = await fetch(u, { redirect: 'follow' }); return r.status; } catch (e) { return 'ERR ' + e.message; } };
  const urls = [...new Set(['/', ...pages.filter((p) => p !== '/404.html'), ...refs.keys()].map((p) => p.replace(/\/index\.html$/, '/')))];
  const out = await Promise.all(urls.map(async (p) => [p, await get(ORIGIN + p)]));
  for (const [p, s] of out) if (s !== 200) fail(`${ORIGIN}${p} → ${s}`);
  console.log(`ok   ${out.filter(([, s]) => s === 200).length}/${out.length} live URLs answer 200`);
  // Clean URLs answer with 404.html, which must carry the redirect to the .html page.
  for (const p of pages) {
    const name = p.replace(/\.html$/, '').slice(1);
    if (['index', '404'].includes(name)) continue;
    const r = await fetch(`${ORIGIN}/${name}`).then((x) => x.text()).catch(() => '');
    if (!/PAGES\s*=/.test(r) || !r.includes(`'${name}'`)) fail(`${ORIGIN}/${name} is a dead end (404 page without the redirect)`);
  }
  console.log('ok   clean URLs checked live');
}
if (bad) { console.error(`${bad} broken`); process.exit(1); }
console.log('no broken links');
