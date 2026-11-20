#!/usr/bin/env node
// Renders the landing's pixel scenes (site/assets/story.js) to GIFs for the README, into docs/img/.
//   node scripts/readme-art.mjs        (needs ffmpeg)
// The scenes only ever call fillRect, so a tiny software canvas is enough: no browser involved.
import { readFileSync, mkdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = fileURLToPath(new URL('..', import.meta.url));
const win = {}, doc = { readyState: 'loading', addEventListener() {}, querySelectorAll: () => [] };
vm.runInNewContext(readFileSync(root + 'site/assets/story.js', 'utf8'), { window: win, document: doc });
const S = win.SteerifyStory, W = 240, FPS = 15;

function canvas(h) {
  const buf = Buffer.alloc(W * h * 3);
  return {
    buf, globalAlpha: 1, fillStyle: '#000000',
    fillRect(x, y, w, hh) {
      const c = parseInt(this.fillStyle.slice(1), 16), r = c >> 16, g = (c >> 8) & 255, b = c & 255, a = this.globalAlpha;
      for (let yy = Math.max(0, y); yy < Math.min(h, y + hh); yy++) for (let xx = Math.max(0, x); xx < Math.min(W, x + w); xx++) {
        const i = (yy * W + xx) * 3;
        buf[i] = buf[i] + (r - buf[i]) * a; buf[i + 1] = buf[i + 1] + (g - buf[i + 1]) * a; buf[i + 2] = buf[i + 2] + (b - buf[i + 2]) * a;
      }
    },
  };
}

// name → [scene (index or name), height, with the voyage strip, scale]
const OUT = {
  hero: ['hero', 90, false, 4], problem: ['crowd', 92, false, 4], decide: ['decide', 120, false, 4],
  build: [2, 124, false, 3], sync: [3, 124, false, 3], filter: [4, 124, false, 3], standard: [5, 124, false, 3],
  mac: ['mac', 144, false, 3], flows: ['flows', 104, false, 4],
};
mkdirSync(root + 'docs/img', { recursive: true });
for (const [name, [key, h, strip, k]] of Object.entries(OUT)) {
  const idx = typeof key === 'number' ? key : -1, s = idx < 0 ? S.named[key] : S.scenes[idx];
  const frames = [], n = Math.round((s.dur + 1.4) * FPS);
  for (let f = 0; f < n; f++) { const c = canvas(h); S.paint(c, s, idx, Math.min(f / FPS, s.dur), h, strip); frames.push(Buffer.from(c.buf)); }
  const out = `${root}docs/img/${name}.gif`;
  const r = spawnSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', `${W}x${h}`, '-r', String(FPS), '-i', '-',
    '-vf', `scale=iw*${k}:ih*${k}:flags=neighbor,split[a][b];[a]palettegen=max_colors=32:stats_mode=diff[p];[b][p]paletteuse=dither=none`, '-loop', '0', out],
    { input: Buffer.concat(frames), maxBuffer: 1 << 28 });
  if (r.status !== 0) { console.error(String(r.stderr)); process.exit(1); }
  console.log(`docs/img/${name}.gif  ${W * k}x${h * k}  ${n} frames`);
}
