#!/usr/bin/env node
// Pixel art for the relay's emails: the landing page's harbour (site/assets/harbour.js), one scene per moment,
// rendered as small looping GIFs (8 frames) with crisp pixels, into site/assets/mail/.
//   received → dawn at the pier · planned → morning · in-progress → noon on the buoys · ready → sunset, harbour in sight
//   live → night, moored, fireworks · answer → a gull bringing a letter · wheel → the footer logo
// No dependencies: a tiny raster, a GIF encoder (LZW) and Node's fs. Run: node scripts/email-art.mjs
import fs from 'node:fs';
import path from 'node:path';

const OUT = path.join(path.dirname(new URL(import.meta.url).pathname), '..', 'site', 'assets', 'mail');
const W = 120, H = 32, SEA = 9, SCALE = 5, FRAMES = 8, DELAY = 30;   // 600×160, 0.3 s a frame

const C = { cream: '#f2e8cf', amber: '#ffb020', blue: '#8fb0ff', line2: '#343944', claude: '#d97757', green: '#4ade80',
  mute: '#5b5f6b', wood: '#8a5a2b', wood2: '#5c3b1c', post: '#4a2f16' };
const SKIES = {
  dawn:   ['#1a1430', '#2a1a3a', '#40223e', '#5e2c40', '#7f3a42', '#a24a46', '#c0604c', '#d97757'],
  morning:['#121a30', '#16223d', '#1b2b4b', '#223759', '#2c4467', '#3a5374', '#55667d', '#7a7a80'],
  noon:   ['#173064', '#1d3a74', '#244683', '#2c5390', '#36619c', '#4270a7', '#5280b1', '#6691ba'],
  sunset: ['#160f2a', '#24133a', '#3a1846', '#561d4a', '#7a2647', '#a33a40', '#cc5a3a', '#f08a3a'],
  night:  ['#05060c', '#070913', '#090c19', '#0b0f1f', '#0d1225', '#10162b', '#131a31', '#161e37'],
};
const SEAS = { dawn: '#0d1020', morning: '#0c1424', noon: '#0b1628', sunset: '#120d1e', night: '#05070f' };
const BOAT = ['......#.......', '......##......', '......###.....', '......####....', '......#####...', '......#.......',
  '##############', '.############.', '..##########..'];
const MINI = ['.#..', '.##.', '####'];
const CLOUD = ['..####....', '.#######..', '##########'];
const LETTER = ['#########', '##.....##', '#.#...#.#', '#..#.#..#', '#...#...#', '#.......#', '#########'];

const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));

/** One frame of a scene as RGB triples, W×H. */
function frame(scene, phase) {
  const { tod, boat = 0.3, sail = false, extra } = scene;
  const px = new Array(W * H).fill(null).map(() => [0, 0, 0]);
  const dot = (x, y, c, a = 1) => {
    x = Math.round(x); y = Math.round(y);
    if (x < 0 || x >= W || y < 0 || y >= H || a <= 0) return;
    const p = px[y * W + x], q = hex(c);
    for (let i = 0; i < 3; i++) p[i] = Math.round(p[i] * (1 - a) + q[i] * a);
  };
  const sprite = (rows, x0, y0, col) => rows.forEach((row, y) => [...row].forEach((ch, x) => { if (ch === '#') dot(x0 + x, y0 + y, typeof col === 'function' ? col(y, x) : col); }));
  const HZ = H - SEA, R = W;
  SKIES[tod].forEach((c, i, a) => { for (let y = Math.floor(HZ * i / a.length); y < Math.floor(HZ * (i + 1) / a.length); y++) for (let x = 0; x < W; x++) dot(x, y, c); });
  // stars
  let seed = scene.seed || 7; const rnd = () => (seed = (seed * 9301 + 49297) % 233280) / 233280;
  const stars = Array.from({ length: Math.round(W * H / (tod === 'night' ? 70 : 200)) }, () => [Math.floor(rnd() * W), Math.floor(rnd() * (HZ - 4))]);
  if (tod === 'dawn' || tod === 'night' || tod === 'sunset') {
    const k = tod === 'night' ? 1 : tod === 'sunset' ? 0.35 : 0.85;
    stars.forEach(([x, y]) => dot(x, y, C.cream, ((x + y + phase) % 3 === 0 ? 0.9 : 0.35) * k * (1 - y / HZ * (tod === 'night' ? 0.4 : 1))));
  }
  const disc = (cx, cy, r, c, a, cut = true) => { for (let y = -r; y <= r; y++) for (let x = -r; x <= r; x++) if (x * x + y * y <= r * r && (!cut || cy + y < HZ)) dot(cx + x, cy + y, c, a); };
  let sx = -99;
  if (tod === 'dawn') { sx = Math.round(W * 0.62); disc(sx, HZ - 3, 6, C.amber, 0.92); }
  if (tod === 'morning') { sx = Math.round(W * 0.16); disc(sx, Math.round(HZ * 0.42), 4, '#ffd27a', 0.9); }
  if (tod === 'noon') { sx = Math.round(W * 0.8); disc(sx, Math.round(HZ * 0.25), 4, '#fff4d0', 1); }
  if (tod === 'sunset') { sx = Math.round(W * 0.55); disc(sx, HZ + 1, 8, C.amber, 0.95); }
  if (tod === 'night') { const mx = Math.round(W * 0.26), my = Math.round(HZ * 0.3); disc(mx, my, 4, C.cream, 0.85, false); disc(mx + 2, my - 1, 3, SKIES.night[2], 1, false); }
  if (tod === 'morning' || tod === 'noon') [[0.3, 0.18, 0.55], [0.6, 0.08, 0.4], [0.86, 0.32, 0.5]].forEach(([fx, fy, a], i) => {
    const x = Math.round(fx * W) + (phase >> 2) * (i % 2 ? 1 : -1);
    CLOUD.forEach((row, y) => [...row].forEach((ch, cx) => { if (ch === '#') dot(x + cx, Math.round(fy * HZ) + y, y === 2 ? '#9aa6bd' : '#d9dde6', a); }));
  });
  // sea and waves (period 7 → shift by phase, loops over 8 frames closely enough at this speed)
  for (let y = HZ; y < H; y++) for (let x = 0; x < W; x++) dot(x, y, SEAS[tod]);
  const waveTop = tod === 'night' ? '#2a3a66' : tod === 'sunset' ? '#7a4a6a' : C.blue;
  for (let r = 0; r < Math.floor(SEA / 3); r++) for (let x = 0; x < W; x++)
    if ((x + phase * (r % 2 ? -1 : 1) + r * 3 + 56) % 8 < 4) dot(x, HZ + 2 + r * 3, r === 0 ? waveTop : C.line2, r === 0 ? 0.6 : 0.9);
  const refl = tod === 'night' ? [Math.round(W * 0.26), C.cream, 0.3] : sx > -99 ? [sx, tod === 'noon' ? '#fff1c4' : C.amber, tod === 'noon' ? 0.3 : 0.5] : null;
  if (refl) for (let r = 0; r < 3; r++) for (let x = refl[0] - 6 + r; x <= refl[0] + 6 - r; x++)
    if ((x + phase + r) % 3 !== 0) dot(x, HZ + 1 + r * 3, refl[1], refl[2] - r * 0.12);
  if (tod === 'morning' || tod === 'noon') [0.12, 0.7, 0.93].forEach((fx, i) => sprite(MINI, Math.round(fx * W) + ((phase + i * 3) % 8 < 4 ? 0 : 1), HZ - 2, (y) => (y === 2 ? C.mute : '#8d93a3')));
  const boatX = Math.round(W * boat);
  // buoys: five, one per step; passed green, current amber
  if (scene.buoys !== undefined) for (let i = 0; i < 5; i++) {
    const bx = Math.round(W * (0.1 + i * 0.2)), c = i < scene.buoys ? C.green : i === scene.buoys ? C.amber : C.mute;
    const blink = i === scene.buoys && phase % 4 >= 2 ? 0.55 : 1;
    dot(bx, HZ, c, blink); dot(bx, HZ - 1, c, blink); dot(bx, HZ - 2, c, 0.7 * blink);
  }
  const pier = (p0, len) => {
    for (let x = p0; x < p0 + len; x++) { dot(x, HZ - 2, C.wood); dot(x, HZ - 1, C.wood2); }
    for (let x = p0 + 2; x < p0 + len; x += 6) for (let y = HZ; y < Math.min(H, HZ + 10); y++) dot(x, y, C.post);
  };
  if (tod === 'dawn') pier(2, 26);
  if (tod === 'night') {
    pier(R - 44, 26);
    const lx = R - 26;
    for (let y = HZ - 7; y < HZ - 2; y++) dot(lx, y, '#6b4a2a');
    [[-1, -9], [0, -9], [1, -9], [0, -10], [0, -8]].forEach(([dx, dy]) => dot(lx + dx, HZ + dy, C.amber, phase % 2 ? 0.6 : 1));
  }
  if (tod === 'dawn' || tod === 'sunset' || tod === 'night') {
    const lx = R - 12, base = HZ - 1, night = tod === 'night';
    for (let y = 0; y < 16; y++) for (let i = 0; i < 4; i++) dot(lx + i, base - y, Math.floor(y / 3) % 2 === 1 ? C.cream : C.claude, night ? 0.75 : 1);
    for (let i = -1; i <= 4; i++) dot(lx + i, base - 16, C.post);
    [[1, 17], [2, 17], [1, 18], [2, 18]].forEach(([x, y]) => dot(lx + x, base - y, C.amber));
    const dir = phase < 4 ? -1 : 1, len = night ? 60 : 26;
    for (let k = 3; k < len; k++) dot(lx + 1 + dir * k, base - 18 + Math.floor(k / 9), C.amber, Math.max(0, (night ? 0.5 : 0.38) - k * (night ? 0.008 : 0.013)));
  }
  // gulls, flapping
  const gull = (gx, gy, f) => (f ? [0, -1, 0, -1, 0] : [-1, 0, 0, 0, -1]).forEach((dy, i) => dot(gx + i, gy + dy, C.cream, 0.9));
  if (tod !== 'night' && !scene.letter) [[0.22, 0.3], [0.45, 0.18]].slice(0, tod === 'dawn' ? 1 : 2).forEach(([fx, fy], g) => gull(Math.round(W * fx) + ((phase + g) % 4 < 2 ? 0 : 1), Math.round(HZ * fy), (phase + g) % 2));
  // the boat
  const by = HZ - 10 + (phase % 4 < 2 ? 0 : 1);
  const sailC = tod === 'night' ? '#b8b2a0' : C.cream, hull = tod === 'night' ? '#b07a10' : C.amber;
  sprite(BOAT, boatX, by, (y) => (y < 6 ? sailC : hull));
  if (sail) for (let k = 1; k < 12; k += 2) dot(boatX - k + (phase % 2), HZ - 1 + Math.floor(k / 3) % 2, C.cream, 0.5 - k * 0.04);
  // a gull flying in with a letter, over the boat
  if (scene.letter) {
    const gx = boatX + 22 - phase, gy = 4 + (phase % 2);
    gull(gx, gy, phase % 2);
    for (let i = 0; i < 2; i++) dot(gx + 2, gy + 1 + i, '#9aa6bd', 0.8);
    LETTER.forEach((row, y) => [...row].forEach((ch, x) => dot(gx - 2 + x, gy + 3 + y, ch === '#' ? C.claude : C.cream)));
  }
  // fireworks over the harbour: two bursts out of phase
  if (scene.fireworks) [[0.56, 0.3, 0, C.amber], [0.78, 0.22, 4, C.green], [0.14, 0.4, 2, C.blue], [0.4, 0.16, 6, C.claude]].forEach(([fx, fy, off, c]) => {
    const t = (phase + off) % 8, cx = Math.round(W * fx), cy = Math.round(HZ * fy);
    if (t < 2) { for (let y = 0; y < 3; y++) dot(cx, cy + 6 - t * 3 + y, C.cream, 0.4 + y * 0.2); return; }
    const r = (t - 1) * 1.6, a = Math.max(0.15, 1 - (t - 2) * 0.16), fall = t > 4 ? t - 4 : 0;
    for (let k = 0; k < 12; k++) {
      const ang = k * Math.PI / 6;
      dot(cx + Math.cos(ang) * r, cy + Math.sin(ang) * r + fall, k % 3 ? c : C.cream, a);
      if (t > 2) dot(cx + Math.cos(ang) * (r - 1.6), cy + Math.sin(ang) * (r - 1.6) + fall, c, a * 0.5);
    }
    if (t < 4) { dot(cx, cy, C.cream, 1); dot(cx + 1, cy, c, 0.7); dot(cx - 1, cy, c, 0.7); dot(cx, cy + 1, c, 0.7); dot(cx, cy - 1, c, 0.7); }
  });
  return px;
}

// ---------- the footer wheel (brand.js) ----------
function wheel() {
  const n = 17, c = 8, S = 3, px = new Array(n * n).fill(null).map(() => [17, 19, 24]);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    const dx = x - c, dy = y - c, r = Math.hypot(dx, dy), a = Math.atan2(dy, dx);
    const k = Math.round(a / (Math.PI / 4)), da = Math.abs(a - k * Math.PI / 4) * r;
    let col = null;
    if (r <= 2.2) col = C.amber;
    else if ((r >= 4.6 && r <= 5.9) || (da < 0.55 && r <= 7.4) || (r > 7.4 && r <= 8.3 && da < 0.9)) col = C.cream;
    if ([[7, 7], [8, 8], [7, 9]].some(([a, b]) => a === x && b === y) && col) col = '#1b1305';
    if (col) px[y * n + x] = hex(col);
  }
  return { w: n, h: n, frames: [px], scale: S };
}

// ---------- GIF ----------
function gif({ w, h, frames, scale }) {
  const key = (p) => (p[0] << 16) | (p[1] << 8) | p[2];
  let colors = [...new Set(frames.flat().map(key))];
  let q = 0;   // too many blends: round the channels until the palette fits
  while (colors.length > 256) { q++; const m = ~((1 << q) - 1) & 255; frames = frames.map((f) => f.map((p) => p.map((v) => v & m))); colors = [...new Set(frames.flat().map(key))]; }
  let depth = 1; while ((1 << depth) < colors.length) depth++;
  const index = new Map(colors.map((c, i) => [c, i]));
  const W2 = w * scale, H2 = h * scale, bytes = [];
  const u16 = (v) => bytes.push(v & 255, v >> 8);
  bytes.push(...Buffer.from('GIF89a')); u16(W2); u16(H2); bytes.push(0xf0 | (depth - 1), 0, 0);
  for (let i = 0; i < 1 << depth; i++) { const c = colors[i] ?? 0; bytes.push(c >> 16, (c >> 8) & 255, c & 255); }
  if (frames.length > 1) bytes.push(0x21, 0xff, 11, ...Buffer.from('NETSCAPE2.0'), 3, 1, 0, 0, 0);
  for (const f of frames) {
    bytes.push(0x21, 0xf9, 4, 0x04); u16(DELAY); bytes.push(0, 0);
    bytes.push(0x2c); u16(0); u16(0); u16(W2); u16(H2); bytes.push(0);
    const idx = new Uint8Array(W2 * H2);
    for (let y = 0; y < H2; y++) for (let x = 0; x < W2; x++) idx[y * W2 + x] = index.get(key(f[Math.floor(y / scale) * w + Math.floor(x / scale)]));
    const min = Math.max(2, depth); bytes.push(min);
    const data = lzw(idx, min);
    for (let i = 0; i < data.length; i += 255) { const part = data.slice(i, i + 255); bytes.push(part.length, ...part); }
    bytes.push(0);
  }
  bytes.push(0x3b);
  return Buffer.from(bytes);
}
function lzw(idx, min) {
  const clear = 1 << min, eoi = clear + 1, out = [];
  let size = min + 1, next = eoi + 1, dict = new Map(), buf = 0, bits = 0;
  const emit = (c) => { buf |= c << bits; bits += size; while (bits >= 8) { out.push(buf & 255); buf >>>= 8; bits -= 8; } };
  emit(clear);
  let prefix = idx[0];
  for (let i = 1; i < idx.length; i++) {
    const k = idx[i], key = (prefix << 8) | k;
    const hit = dict.get(key);
    if (hit !== undefined) { prefix = hit; continue; }
    emit(prefix);
    if (next === 4096) { emit(clear); dict = new Map(); next = eoi + 1; size = min + 1; }
    else { if (next >= 1 << size) size++; dict.set(key, next++); }
    prefix = k;
  }
  emit(prefix); emit(eoi);
  if (bits > 0) out.push(buf & 255);
  return out;
}

const SCENES = {
  received:      { tod: 'dawn', boat: 0.16, seed: 7 },
  planned:       { tod: 'morning', boat: 0.3, sail: true, seed: 11 },
  'in-progress': { tod: 'noon', boat: 0.36, sail: true, buoys: 2, seed: 23 },
  ready:         { tod: 'sunset', boat: 0.6, sail: true, seed: 41 },
  live:          { tod: 'night', boat: 0.52, fireworks: true, seed: 3 },
  answer:        { tod: 'morning', boat: 0.3, letter: true, seed: 17 },
};
fs.mkdirSync(OUT, { recursive: true });
for (const [name, s] of Object.entries(SCENES)) {
  const frames = Array.from({ length: FRAMES }, (_, p) => frame(s, p));
  const buf = gif({ w: W, h: H, frames, scale: SCALE });
  fs.writeFileSync(path.join(OUT, name + '.gif'), buf);
  console.log(name.padEnd(12), (buf.length / 1024).toFixed(0) + ' KB');
}
const wb = gif(wheel());
fs.writeFileSync(path.join(OUT, 'wheel.gif'), wb);
console.log('wheel'.padEnd(12), (wb.length / 1024).toFixed(1) + ' KB');
