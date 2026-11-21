#!/usr/bin/env node
// Marketing links on the landing must keep working (they are in emails and posts already sent):
//   steerify.dev/?teaser · #teaser · ?v=<name>. Run before shipping the site: node scripts/check-video-links.mjs
import fs from 'node:fs';
const src = fs.readFileSync(new URL('../site/assets/videos.js', import.meta.url), 'utf8');
const html = fs.readFileSync(new URL('../site/index.html', import.meta.url), 'utf8');
const eps = [...html.matchAll(/data-ep="([a-z-]+)"/g)].map((m) => m[1]);
const hero = (html.match(/data-herovid="([a-z-]+)"/) || [])[1];
let bad = 0;
const fail = (m) => { bad++; console.error('FAIL ' + m); };
if (!hero) fail('no hero video (data-herovid) on the landing');
if (!/MARKETING LINKS/.test(src)) fail('the MARKETING LINKS block is gone from site/assets/videos.js');

function run(search, hash) {
  const log = [];
  const v = { pause() {}, load() {}, removeAttribute() {}, addEventListener() {}, play() { log.push('play'); return Promise.resolve(); }, set src(x) { log.push('src=' + x); }, get currentSrc() { return ''; } };
  const node = () => ({ addEventListener() {}, querySelector: () => node(), hidden: true, textContent: '' });
  const el = { dataset: { herovid: hero }, classList: { toggle() {}, add() { log.push('on'); }, remove() {} }, scrollIntoView() { log.push('scroll'); },
    querySelector: (s) => (s === 'video' ? v : s === '.hv-end' ? null : node()) };
  const ep = (name) => ({ dataset: { ep: name }, querySelector: () => ({ textContent: name }), addEventListener() {} });
  const g = { matchMedia: () => ({ matches: false }), location: { search, hash, replace: (u) => log.push('goto ' + u) }, URLSearchParams,
    document: { querySelectorAll: (s) => (s === '[data-herovid]' ? [el] : s === '[data-ep]' ? eps.map(ep) : []), querySelector: () => null } };
  g.window = g;
  new Function(...Object.keys(g), src)(...Object.values(g));
  return log.join(' ');
}
const expect = (search, hash, re, what) => { const out = run(search, hash); if (!re.test(out)) fail(`${search}${hash} should ${what}; got: ${out || 'nothing'}`); else console.log(`ok   ${search}${hash || ''} → ${what}`); };
if (hero) {
  expect('?teaser', '', new RegExp(`scroll.*src=videos/${hero}\\.mp4.*play|src=videos/${hero}\\.mp4.*scroll.*play`), 'play the hero film');
  expect('', '#teaser', /scroll.*play/, 'play the hero film');
  for (const e of eps) expect('?v=' + e, '', new RegExp(`src=videos/${e}\\.mp4.*play`), `play ${e}`);
  expect('?v=why-pro', '', /goto tutorial\.html#why-pro/, 'open the long video on tutorial.html');
  const plain = run('', ''); if (/scroll|on\b/.test(plain)) fail('a plain visit must not start a film; got: ' + plain); else console.log('ok   plain visit → nothing starts');
}
for (const id of ['start', 'why-simple', 'why-pro']) if (!new RegExp(`id="${id}"`).test(fs.readFileSync(new URL('../site/tutorial.html', import.meta.url), 'utf8'))) fail(`tutorial.html lost #${id}`);
process.exit(bad ? 1 : 0);
