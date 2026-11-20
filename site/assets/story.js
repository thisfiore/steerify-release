// Steerify story: a pixel film of how it works. One low-res canvas (240×150), eight scenes, its own 3×5 font.
// Mount: <div data-story></div>. No dependencies; safe to drop into any page next to story.css.
(function () {
  const W = 240;
  let CH = 150; // height of the canvas being painted
  const K = { bg: '#07080a', bg2: '#0d0f13', panel: '#111318', line: '#23262e', line2: '#343944', ink: '#050607', cream: '#f2e8cf', mute: '#4a4e58', dim: '#8f8a7d', amber: '#ffb020', amberDim: '#2a2110', green: '#4ade80', greenDim: '#10231a', blue: '#8fb0ff', red: '#ff5a36', sea: '#0b1524', wave: '#2a4470', tile: '#2a2e37' };
  const FONT = {
    A: '010101111101101', B: '110101110101110', C: '011100100100011', D: '110101101101110', E: '111100110100111', F: '111100110100100',
    G: '011100101101011', H: '101101111101101', I: '111010010010111', J: '001001001101010', K: '101101110101101', L: '100100100100111',
    M: '101111111101101', N: '110101101101101', O: '010101101101010', P: '110101110100100', Q: '010101101111011', R: '110101110101101',
    S: '011100010001110', T: '111010010010010', U: '101101101101111', V: '101101101101010', W: '101101111111101', X: '101101010101101',
    Y: '101101010010010', Z: '111001010100111',
    0: '111101101101111', 1: '010110010010111', 2: '110001010100111', 3: '110001010001110', 4: '101101111001001',
    5: '111100110001110', 6: '011100111101111', 7: '111001010010010', 8: '111101111101111', 9: '111101111001110',
    '.': '000000000000010', ',': '000000000010100', ':': '000010000010000', '-': '000000111000000', '?': '110001010000010',
    '!': '010010010000010', '/': '001001010100100', "'": '010010000000000', '+': '000010111010000', '=': '000111000111000',
  };
  const BOAT = ['........c.........', '........cc........', '........ccc.......', '........cccc......', '........ccccc.....', '........cccccc....', '........ccccccc...', '........c.........', '.aaaaaaaaaaaaaaaa.', '..aaaaaaaaaaaaaa..', '...aaaaaaaaaaaa...'];
  const CUR = ['ck....', 'cck...', 'ccck..', 'cccck.', 'ccccck', 'cckck.', 'ck.cck', 'k...ck'];
  const PAL = { c: K.cream, a: K.amber, k: K.ink };

  let ctx;
  const R = (x, y, w, h, c) => { ctx.fillStyle = c; ctx.fillRect(Math.round(x), Math.round(y), Math.round(w), Math.round(h)); };
  const box = (x, y, w, h, fill = K.panel, edge = K.line2) => { R(x, y, w, h, edge); R(x + 1, y + 1, w - 2, h - 2, fill); };
  const tw = (s, sc = 1) => String(s).length * 4 * sc - sc;
  function txt(x, y, s, c = K.dim, sc = 1, align = 'left') {
    s = String(s).toUpperCase();
    if (align === 'center') x -= tw(s, sc) / 2; else if (align === 'right') x -= tw(s, sc);
    x = Math.round(x); y = Math.round(y);
    for (const ch of s) {
      const g = FONT[ch];
      if (g) for (let i = 0; i < 15; i++) if (g[i] === '1') R(x + (i % 3) * sc, y + ((i / 3) | 0) * sc, sc, sc, c);
      x += 4 * sc;
    }
  }
  function spr(rows, x, y, sc = 1) {
    x = Math.round(x); y = Math.round(y);
    rows.forEach((row, j) => { for (let i = 0; i < row.length; i++) { const c = PAL[row[i]]; if (c) R(x + i * sc, y + j * sc, sc, sc, c); } });
  }
  const cl = (v) => Math.max(0, Math.min(1, v));
  const pr = (t, a, b) => cl((t - a) / (b - a));
  const lerp = (a, b, p) => a + (b - a) * p;
  const ease = (p) => p * p * (3 - 2 * p);
  const blink = (t) => ((t * 2) | 0) % 2 === 0;
  const alpha = (a, fn) => { ctx.globalAlpha = a; fn(); ctx.globalAlpha = 1; };
  const check = (x, y, c) => { [[0, 2], [1, 3], [2, 2], [3, 1], [4, 0]].forEach(([dx, dy]) => R(x + dx, y + dy, 1, 2, c)); };
  const chev = (x, y, c) => { R(x, y, 1, 1, c); R(x + 1, y + 1, 1, 1, c); R(x, y + 2, 1, 1, c); };
  function term(x, y, w, h, edge = K.line2) {
    box(x, y, w, h, K.ink, edge);
    R(x + 1, y + 1, w - 2, 4, K.panel);
    R(x + 3, y + 2, 1, 1, K.red); R(x + 5, y + 2, 1, 1, K.amber); R(x + 7, y + 2, 1, 1, K.green);
  }
  function mock(i, x, y) { // three little page layouts, 56×38
    if (i === 0) { R(x + 5, y + 5, 30, 4, K.cream); R(x + 5, y + 12, 42, 2, K.mute); R(x + 5, y + 16, 34, 2, K.mute); R(x + 5, y + 25, 18, 7, K.amber); }
    if (i === 1) for (let a = 0; a < 3; a++) for (let b = 0; b < 2; b++) R(x + 5 + a * 16, y + 5 + b * 15, 14, 13, a === 1 && b === 0 ? K.blue : K.tile);
    if (i === 2) { R(x + 5, y + 5, 20, 28, K.green); R(x + 29, y + 6, 20, 3, K.cream); R(x + 29, y + 12, 18, 2, K.mute); R(x + 29, y + 16, 14, 2, K.mute); R(x + 29, y + 26, 12, 6, K.amber); }
  }

  // 1 · Say it: one sentence becomes requirements, docs and a roadmap.
  function s1(t) {
    const msg = 'A SHOP FOR MY CAT TOYS';
    const n = Math.floor(pr(t, .4, 1.9) * msg.length);
    const up = ease(pr(t, 2.2, 2.8));
    const by = Math.round(lerp(54, 8, up));
    if (up === 0) txt(120, by - 10, 'SAY WHAT YOU WANT', K.dim, 1, 'center');
    const g = pr(t, 2.8, 3.3);
    if (g > 0) {
      R(120, 23, 1, 9, K.line2);
      const half = Math.round(76 * g); R(120 - half, 32, half * 2 + 1, 1, K.line2);
    }
    box(40, by, 160, 15, K.ink, up < 1 ? K.amber : K.line2);
    chev(45, by + 5, K.amber);
    txt(51, by + 5, msg.slice(0, n), K.cream);
    if (up === 0 && blink(t)) R(51 + n * 4, by + 4, 2, 7, K.amber);
    [['REQUIREMENTS', K.amber], ['DOCS', K.blue], ['ROADMAP', K.green]].forEach(([name, col], i) => {
      const p0 = 3.3 + i * .3;
      if (t < p0) return;
      const x = 8 + i * 76, y = 40, cx = x + 36;
      R(cx, 32, 1, 8, K.line2);
      box(x, y, 72, 78, K.bg2);
      txt(x + 6, y + 6, name, col);
      R(x + 6, y + 14, 60, 1, K.line);
      const q = pr(t, p0 + .2, p0 + 1.8);
      if (i === 0) [38, 46, 30, 42, 34, 44].forEach((w, j) => {
        if (j >= q * 6) return;
        const yy = y + 20 + j * 9;
        box(x + 6, yy, 5, 5, K.bg2, col); R(x + 15, yy, w, 2, K.cream); R(x + 15, yy + 4, w - 12, 1, K.mute);
      });
      if (i === 1) [[x + 7, y + 20], [x + 30, y + 28]].forEach(([px, py], j) => {
        if (q < j * .4 + .05) return;
        box(px, py, 35, 44, K.panel);
        R(px + 28, py, 7, 7, K.bg2); R(px + 28, py + 6, 7, 1, K.line2); R(px + 28, py, 1, 7, K.line2);
        R(px + 5, py + 6, 16, 2, col);
        const k = Math.floor(pr(q, j * .4, j * .4 + .6) * 7);
        for (let l = 0; l < k; l++) R(px + 5, py + 13 + l * 4, [24, 20, 26, 16, 24, 22, 14][l], 1, K.mute);
      });
      if (i === 2) [0, 1, 2].forEach((j) => {
        if (j >= q * 3) return;
        const yy = y + 21 + j * 19;
        box(x + 6, yy, 6, 6, K.bg2, col); R(x + 16, yy + 1, [36, 28, 40][j], 2, K.cream);
        for (let s = 0; s < 4; s++) R(x + 6 + s * 15, yy + 10, 13, 3, K.line2);
      });
    });
  }

  // 2 · Confirm with pictures: three mockups, you pick the one you meant.
  function s2(t) {
    box(30, 6, 180, 13, K.ink);
    txt(120, 10, 'CLAUDE ASKS: HOW SHOULD IT LOOK?', K.cream, 1, 'center');
    const picked = t > 3.1;
    ['A', 'B', 'C'].forEach((l, i) => {
      if (t < .4 + i * .3) return;
      const x = 12 + i * 76, y = 28, on = i === 1 && picked;
      alpha(picked && i !== 1 ? .3 : 1, () => {
        box(x, y, 64, 62, K.bg2, on ? K.amber : K.line2);
        box(x + 4, y + 4, 56, 38, K.panel, K.line);
        mock(i, x + 4, y + 4);
        txt(x + 5, y + 47, l, on ? K.amber : K.cream, 2);
        R(x + 16, y + 48, 30, 2, K.mute); R(x + 16, y + 53, 22, 2, K.mute);
      });
      if (on) { R(x + 54, y - 4, 13, 12, K.amber); check(x + 58, y, K.ink); }
    });
    if (t > 3.7) { box(50, 100, 140, 15, K.greenDim, K.green); check(62, 105, K.green); txt(72, 105, 'REQUIREMENT CONFIRMED', K.green); }
    if (t > 1.2 && t < 4.4) { const c = ease(pr(t, 1.6, 2.8)); spr(CUR, lerp(214, 124, c), lerp(116, 64, c)); }
  }

  // 3 + 4 share a stage: roadmap items on the left, their sessions on the right.
  const IY = [8, 40, 72];
  function item(i, st) {
    const y = IY[i], col = st === 'wip' ? K.amber : st === 'test' ? K.blue : K.line2;
    box(8, y, 88, 26, K.bg2);
    if (st === 'todo') box(13, y + 6, 7, 7, K.bg2, K.line2);
    if (st === 'wip') { R(13, y + 6, 7, 7, K.line2); R(13, y + 6, 4, 7, K.amber); }
    if (st === 'test') R(13, y + 6, 7, 7, K.blue);
    R(25, y + 6, [44, 36, 50][i], 3, K.cream); R(25, y + 12, [30, 40, 26][i], 2, K.mute);
    if (st !== 'todo') txt(92, y + 18, st === 'wip' ? 'BUILDING' : 'TO TEST', col, 1, 'right');
  }
  function link(i, col, p = 1) { for (let x = 99; x < 99 + 42 * p; x += 3) R(x, IY[i] + 12, 2, 1, col); }

  // 3 · Build the right thing: each answer starts a session, already briefed.
  function s3(t) {
    [0, 1, 2].forEach((i) => {
      const y = IY[i], s0 = .8 + i * 1.2, go = pr(t, s0, s0 + .7);
      item(i, go > 0 ? 'wip' : 'todo');
      if (go === 0) { R(64, y + 15, 28, 8, t > s0 - .25 ? K.cream : K.amber); txt(78, y + 17, 'START', K.ink, 1, 'center'); }
      if (go > 0) link(i, K.amber, go);
      if (go > 0 && go < 1) { const px = lerp(98, 138, go); box(px, y + 8, 7, 9, K.amber, K.amber); R(px + 2, y + 10, 3, 1, K.ink); R(px + 2, y + 12, 3, 1, K.ink); R(px + 2, y + 14, 2, 1, K.ink); }
      if (go === 1) {
        term(144, y, 88, 26);
        chev(149, y + 9, K.amber);
        const w = Math.round([44, 36, 50][i] * pr(t, s0 + .8, s0 + 1.6));
        R(153, y + 9, w, 3, K.cream);
        if (blink(t)) R(154 + w, y + 8, 2, 5, K.amber);
        if (t > s0 + 1.7) R(153, y + 16, 30, 2, K.mute);
      }
    });
    if (t > 4.7) txt(120, 110, 'ONE SESSION PER TOPIC, ALREADY BRIEFED', K.dim, 1, 'center');
  }

  // 4 · Always in sync: the session delivers, the roadmap item moves on its own.
  function s4(t) {
    let done = 0;
    [0, 1, 2].forEach((i) => {
      const y = IY[i], d0 = 1.4 + i * 1.3, d = t >= d0;
      if (d) done++;
      item(i, d ? 'test' : 'wip');
      link(i, d ? K.blue : K.amber);
      term(144, y, 88, 26, d ? K.blue : K.line2);
      chev(149, y + 9, K.amber);
      if (!d) {
        const f = (t * 5 + i * 3) | 0;
        R(153, y + 9, 20 + (f * 7) % 40, 3, K.cream); R(153, y + 15, 14 + (f * 11) % 44, 2, K.mute); R(153, y + 20, 10 + (f * 5) % 30, 2, K.mute);
      } else {
        R(153, y + 9, 40, 3, K.cream); txt(153, y + 16, 'DELIVERED', K.blue); check(222, y + 15, K.blue);
        const p = pr(t, d0, d0 + .6);
        if (p < 1) R(lerp(140, 98, p), y + 11, 3, 3, K.cream);
      }
    });
    R(8, 104, 224, 5, K.line);
    for (let s = 0; s < 6; s++) R(8 + s * 37.5, 104, 36, 5, s < 2 ? K.green : s < 2 + done ? K.blue : K.line);
    txt(8, 113, `${2 + done} OF 6 DELIVERED`, K.cream);
    txt(232, 113, 'NOBODY UPDATED THIS BY HAND', K.mute, 1, 'right');
  }

  // 5 · Only what needs you: nine sessions, three waiting; filter to those.
  function s5(t) {
    const wait = [1, 5, 6], on = t > 2.4;
    [['ALL 9', 22, 30], ['WORKING 6', 56, 46], ['YOUR TURN 3', 106, 54]].forEach(([s, x, w], i) => {
      const act = on ? i === 2 : i === 0;
      if (act) R(x, 6, w, 11, i === 2 ? K.amber : K.cream); else box(x, 6, w, 11, K.bg2);
      txt(x + w / 2, 9, s, act ? K.ink : K.dim, 1, 'center');
    });
    const fade = 1 - pr(t, 2.4, 2.9), mv = ease(pr(t, 3, 3.7));
    for (let i = 0; i < 9; i++) {
      const c = i % 3, r = (i / 3) | 0, k = wait.indexOf(i);
      let x = 22 + c * 68, y = 24 + r * 28;
      if (k < 0) {
        if (fade <= 0) continue;
        alpha(fade, () => {
          term(x, y, 60, 22);
          const f = (t * 5 + i * 4) | 0;
          R(x + 5, y + 8, 14 + (f * 7) % 34, 2, K.cream); R(x + 5, y + 13, 10 + (f * 11) % 36, 2, K.mute);
        });
      } else {
        x = lerp(x, 22 + k * 68, mv); y = lerp(y, 40, mv);
        term(x, y, 60, 22, K.amber);
        if (blink(t)) R(x + 5, y + 9, 3, 3, K.amber);
        txt(x + 11, y + 9, 'YOUR TURN', K.amber);
        if (mv === 1 && t > 3.9 + k * .2) txt(x + 30, y + 28, ['PICK ONE', 'TAKE A LOOK', 'SAY SHIP'][k], K.cream, 1, 'center');
      }
    }
    if (t > 4.7) txt(120, 92, '3 NEED YOU. 6 KEEP WORKING.', K.dim, 1, 'center');
    if (t > .9 && t < 3.1) { const c = ease(pr(t, 1.2, 2.2)); spr(CUR, lerp(206, 134, c), lerp(112, 11, c)); }
  }

  // 6 · One standard: every delivery checked against the same design and the same tests.
  function s6(t) {
    box(8, 8, 66, 110, K.bg2);
    txt(14, 14, 'DESIGN', K.amber);
    [K.amber, K.cream, K.blue, K.green].forEach((c, i) => R(14 + i * 13, 23, 10, 10, c));
    R(14, 39, 40, 4, K.cream); R(14, 46, 30, 2, K.mute);
    txt(14, 58, 'TESTS', K.amber);
    [34, 28, 38].forEach((w, j) => { box(14, 68 + j * 11, 5, 5, K.bg2, K.green); R(23, 69 + j * 11, w, 2, K.cream); });
    txt(14, 107, 'ONE STANDARD', K.dim);
    [0, 1, 2].forEach((i) => {
      if (t < .3 + i * .25) return;
      const x = 86 + i * 50, y = 12, s0 = 1.2 + i * 1.1, by = lerp(y, y + 86, pr(t, s0, s0 + .8));
      const fixed = t > s0 + 2.2, bad = i === 1 && !fixed, scanned = t > s0 + .8;
      box(x, y, 44, 86, K.bg2, scanned ? (bad ? K.amber : K.green) : K.line2);
      box(x + 4, y + 4, 36, 30, K.panel, K.line);
      [K.amber, K.cream, K.blue, K.green].forEach((c, k) => R(x + 7 + (k % 2) * 16, y + 7 + ((k / 2) | 0) * 13, 14, 11, bad && k === 2 ? K.red : c));
      [0, 1, 2].forEach((j) => {
        const yy = y + 42 + j * 11, pass = by > yy + 5;
        if (!pass) box(x + 5, yy, 5, 5, K.bg2, K.line2); else R(x + 5, yy, 5, 5, bad && j === 0 ? K.red : K.green);
        R(x + 14, yy + 1, [22, 18, 24][j], 2, pass ? K.cream : K.mute);
      });
      if (bad && by > y + 30) { R(x + 9, y + 16, 7, 7, K.amber); txt(x + 11, y + 17, '1', K.ink); }
      if (scanned) txt(x + 22, y + 77, bad ? 'REFINE' : 'OK', bad ? K.amber : K.green, 1, 'center');
      if (t > s0 && t < s0 + .8) R(x - 2, by, 48, 1, K.amber);
    });
    if (t > 4.9) txt(158, 107, 'SAME CHECKS, EVERY DELIVERY', K.dim, 1, 'center');
  }

  // 7 · Skills, not repeats: build it once, every session reuses it.
  function s7(t) {
    box(98, 6, 44, 22, K.amberDim, K.amber);
    txt(120, 12, 'SKILL', K.amber, 2, 'center');
    for (let k = 0; k < 9; k++) R(102 + k * 4, 28, 2, 2, K.amber);
    const rows = [[K.cream, 34], [K.mute, 24], [K.blue, 40], [K.mute, 28], [K.green, 20], [K.amber, 36]];
    [0, 1, 2].forEach((i) => {
      const x = 12 + i * 76, y = 50, a0 = .6 + i * .5, fly = ease(pr(t, a0, a0 + .7));
      term(x, y, 64, 56, fly === 1 ? K.amber : K.line2);
      if (fly > 0) { const cx = lerp(110, x + 22, fly), cy = lerp(30, y - 6, fly); box(cx, cy, 20, 8, K.amberDim, K.amber); R(cx + 4, cy + 3, 12, 2, K.amber); }
      const q = pr(t, a0 + .9, a0 + 2.3);
      rows.forEach(([c, w], j) => { if (j < q * 6) R(x + 6, y + 10 + j * 7, w, 3, c); });
    });
    if (t > 4.3) [79, 155].forEach((x) => { R(x, 76, 6, 2, K.green); R(x, 80, 6, 2, K.green); });
    if (t > 4.7) txt(120, 113, 'BUILT ONCE, REUSED BY EVERY SESSION', K.dim, 1, 'center');
  }

  // 8 · You just steer.
  function s8(t) {
    [[14, 12], [40, 70], [66, 8], [200, 10], [226, 58], [182, 78], [22, 88], [120, 64], [150, 6], [96, 84], [214, 92]].forEach(([x, y], i) => { if ((i + ((t * 2) | 0)) % 4) R(x, y, 1, 1, i % 3 ? K.mute : K.cream); });
    const a = 'YOU DECIDE.', b = 'CLAUDE BUILDS.';
    txt(120 - tw(a, 3) / 2, 16, a.slice(0, Math.floor(pr(t, .3, 1.1) * a.length + .01)), K.cream, 3);
    txt(120 - tw(b, 3) / 2, 38, b.slice(0, Math.floor(pr(t, 1.3, 2.3) * b.length + .01)), K.amber, 3);
    R(0, 106, W, CH - 106, K.sea);
    for (let x = -4; x < W; x += 6) R(x + ((t * 4) | 0) % 6, 106 + ((x / 6) & 1), 3, 1, K.wave);
    const bx = lerp(-60, 93, ease(pr(t, .3, 2.8))), bob = Math.round(Math.sin(t * 3));
    spr(BOAT, bx, 76 + bob, 3);
    for (let k = 0; k < 5; k++) if (t > 3.2 + k * .3) { const x = 76 + k * 19; box(x, 60, 11, 11, K.greenDim, K.green); check(x + 3, 63, K.green); }
  }

  // 0 · Hero strip (240×90): the whole loop in one line.
  function s0(t) {
    const act = Math.min(4, (t / 1.2) | 0), f = (t * 5) | 0;
    [['YOU SAY', K.cream], ['YOU PICK', K.cream], ['CLAUDE BUILDS', K.amber], ['YOU LOOK', K.cream], ['SHIPPED', K.green]].forEach(([l, c], i) => {
      const x = 6 + i * 47, y = 8, on = i === act, past = i < act;
      box(x, y, 40, 34, K.bg2, on ? K.amber : past ? K.green : K.line2);
      if (i < 4) for (let d = 0; d < 3; d++) R(x + 41 + d * 2, y + 17, 1, 1, past ? K.green : K.line2);
      if (i === 0) { box(x + 5, y + 12, 30, 10, K.ink); chev(x + 8, y + 15, K.amber); const w = on ? Math.min(16, f * 2 % 20) : 16; R(x + 12, y + 16, w, 2, K.cream); if (on && blink(t)) R(x + 13 + w, y + 14, 2, 6, K.amber); }
      if (i === 1) for (let j = 0; j < 3; j++) box(x + 5 + j * 11, y + 10, 9, 14, j === 1 && act >= 1 ? K.amber : K.panel, j === 1 && act >= 1 ? K.amber : K.line2);
      if (i === 2) { term(x + 5, y + 6, 30, 22); R(x + 8, y + 14, on ? 8 + (f * 7) % 16 : 18, 2, K.cream); R(x + 8, y + 19, on ? 6 + (f * 11) % 18 : 12, 2, K.mute); }
      if (i === 3) { box(x + 6, y + 7, 28, 20, K.panel, K.line); for (let k = 0; k < 12; k++) R(x + 10 + k, y + 22 - Math.min(k, 11 - k), 1, 4 + Math.min(k, 11 - k), '#3f9a52'); if (act >= 3) R(x + 24, y + 10, 5, 5, K.amber); }
      if (i === 4) [[0, 2], [1, 3], [2, 2], [3, 1], [4, 0]].forEach(([dx, dy]) => R(x + 13 + dx * 3, y + 9 + dy * 3, 3, 6, act >= 4 ? K.green : K.line2));
      alpha(on || past ? 1 : .45, () => txt(x + 20, 47, l, c, 1, 'center'));
    });
    R(0, 77, W, CH - 77, K.sea);
    for (let x = -4; x < W; x += 6) R(x + ((t * 4) | 0) % 6, 76 + ((x / 6) & 1), 3, 1, K.wave);
    spr(BOAT, 17 + 47 * Math.min(4, t / 1.2), 66 + Math.round(Math.sin(t * 3) * .6));
  }
  const HERO = { title: 'You say, you pick, Claude builds, you look, it ships.', text: '', dur: 6.4, draw: s0, h: 90, strip: false };

  // On your Mac: the small jobs go through Apple Intelligence's on-device model, not the cloud.
  function sMac(t) {
    const rows = [['SESSION LOG', 'SUMMARY'], ['NEW REQUEST', 'SORTED: FIX'], ['COMMITS', 'ROADMAP IDEA'], ['SCREENSHOT', 'LOOKS RIGHT']];
    let busy = false;
    rows.forEach(([a, b], i) => {
      const y = 12 + i * 26, a0 = .5 + i * 1.1, inn = t >= a0, think = t >= a0 + .35 && t < a0 + .8, out = t >= a0 + .8;
      if (think) busy = true;
      const lc = inn ? K.blue : K.line2, rc = out ? K.blue : K.line2;
      box(8, y, 70, 18, K.bg2, inn && !out ? K.blue : K.line2);
      txt(13, y + 7, a, inn ? K.cream : K.dim);
      for (let x = 79; x < 88; x += 3) R(x, y + 9, 2, 1, lc);
      R(88, Math.min(y + 9, 62), 1, Math.abs(y + 9 - 62) + 1, lc);
      for (let x = 153; x < 162; x += 3) R(x, y + 9, 2, 1, rc);
      R(152, Math.min(y + 9, 62), 1, Math.abs(y + 9 - 62) + 1, rc);
      if (out) { box(162, y, 70, 18, K.bg2, K.blue); txt(167, y + 7, b, K.cream); if (i === 3) check(222, y + 6, K.green); }
      else box(162, y, 70, 18, K.bg, K.line);
    });
    R(89, 62, 9, 1, K.line2); R(142, 62, 10, 1, K.line2);
    for (let k = 0; k < 5; k++) { R(103 + k * 8, 36, 3, 4, K.mute); R(103 + k * 8, 84, 3, 4, K.mute); R(94, 45 + k * 8, 4, 3, K.mute); R(142, 45 + k * 8, 4, 3, K.mute); }
    box(98, 40, 44, 44, '#0f1728', K.blue);
    box(107, 49, 26, 26, busy ? K.blue : '#16223c', K.blue);
    R(116, 58, 8, 8, busy && blink(t * 4) ? K.cream : busy ? K.ink : K.blue);
    txt(120, 94, 'ON THIS MAC', K.blue, 1, 'center');
    if (t > 5.2) txt(120, 132, 'THESE JOBS NEVER LEAVE YOUR MAC', K.dim, 1, 'center');
  }
  const MAC = { title: 'On your Mac.', text: 'Session summaries, request sorting, roadmap ideas from commits and screenshot checks run through the on-device model.', dur: 6.4, draw: sMac, h: 144, strip: false };
  // How you start (240×96): add a folder, the skill installs itself, start an item.
  function sStart(t) {
    const act = Math.min(2, (t / 1.7) | 0);
    ['ADD A FOLDER', 'SKILL INSTALLS', 'START AN ITEM'].forEach((cap, i) => {
      const x = 8 + i * 76, y = 8, on = i === act, seen = i <= act, lt = t - i * 1.7;
      box(x, y, 72, 62, K.bg2, on ? K.amber : i < act ? K.green : K.line2);
      if (i < 2) for (let d = 0; d < 2; d++) R(x + 73 + d * 2, y + 31, 1, 1, i < act ? K.green : K.line2);
      txt(x + 5, y + 5, i + 1, seen ? K.amber : K.mute);
      if (i === 0) {
        R(x + 12, y + 14, 8, 2, K.amber); R(x + 12, y + 16, 18, 10, K.amber);
        txt(x + 34, y + 18, 'MY-SHOP/', K.cream);
        if (lt > .5) { R(x + 16, y + 28, 1, 8, K.line2); R(x + 16, y + 35, 5, 1, K.line2); txt(x + 23, y + 33, '.STEERIFY/', K.amber); }
        ['BOARD', 'ROADMAP'].forEach((f, j) => { if (lt > .8 + j * .25) { R(x + 27, y + 41 + j * 8, 3, 4, K.mute); txt(x + 33, y + 41 + j * 8, f, K.dim); } });
      }
      if (i === 1) {
        term(x + 8, y + 26, 56, 30, seen && lt > .9 ? K.amber : K.line2);
        txt(x + 12, y + 35, 'CLAUDE CODE', seen ? K.cream : K.mute);
        if (seen && lt > 1) { check(x + 12, y + 44, K.green); txt(x + 20, y + 44, 'STEERIFY', K.green); }
        const cy = seen ? lerp(y + 6, y + 18, ease(pr(lt, .1, .8))) : y + 6;
        box(x + 26, cy, 20, 8, K.amberDim, seen ? K.amber : K.line2); R(x + 30, cy + 3, 12, 2, seen ? K.amber : K.line2);
      }
      if (i === 2) {
        term(x + 4, y + 18, 64, 34);
        const cmd = '/STEERIFY BUILD', n = seen ? Math.floor(pr(lt, .2, 1.2) * cmd.length) : 0;
        txt(x + 7, y + 26, cmd.slice(0, n), K.cream);
        if (seen && blink(t)) R(x + 7 + n * 4, y + 25, 2, 7, K.amber);
        if (seen && lt > 1.4) { R(x + 7, y + 36, 34, 2, K.mute); R(x + 7, y + 41, 24, 2, K.mute); }
      }
      alpha(seen ? 1 : .45, () => txt(x + 36, 78, cap, on ? K.amber : K.cream, 1, 'center'));
    });
  }

  // How sessions use git (240×104): on main, a worktree per feature, or a branch with a pull request.
  function sFlows(t) {
    const ok = t > 3.4, merged = t > 4;
    [['ON MAIN', 'SIMPLE PROJECTS'], ['WORKTREE', 'MERGED ON YOUR OK'], ['PULL REQUEST', 'YOUR OK MERGES IT']].forEach(([name, note], i) => {
      const x = 6 + i * 78, my = 66;
      box(x, 6, 72, 92, K.bg2);
      txt(x + 36, 12, name, K.amber, 1, 'center');
      R(x + 6, my + 1, 60, 1, K.cream);
      const n = Math.floor(pr(t, .4, 3) * 5);
      if (i === 0) for (let k = 0; k < 5; k++) if (k < n) R(x + 9 + k * 13, my, 3, 3, k === n - 1 && !merged ? K.amber : K.green);
      if (i > 0) {
        R(x + 9, my, 3, 3, K.green);
        for (let k = 0; k < 8; k++) R(x + 12 + k, my - 1 - k * 3, 1, 3, K.blue);          // branch off
        R(x + 20, my - 24, 26, 1, K.blue);
        for (let k = 0; k < 3; k++) if (k < n) R(x + 22 + k * 9, my - 25, 3, 3, K.blue);
        txt(x + 36, my - 36, 'STEER/FEATURE', K.blue, 1, 'center');
        if (i === 2 && t > 2.6) { box(x + 50, my - 30, 15, 11, merged ? K.greenDim : K.bg, merged ? K.green : K.blue); txt(x + 58, my - 27, 'PR', merged ? K.green : K.blue, 1, 'center'); }
        if (merged) { for (let k = 0; k < 8; k++) R(x + 46 + k, my - 24 + k * 3, 1, 3, K.green); R(x + 54, my, 3, 3, K.green); }
      }
      if (i > 0 && ok && !merged) { R(x + 28, my + 8, 16, 9, K.green); txt(x + 36, my + 10, 'OK', K.ink, 1, 'center'); }
      txt(x + 36, 88, note, K.dim, 1, 'center');
    });
  }
  const START = { title: 'How you start.', text: 'Add a folder, the Steerify skill installs itself, start an item.', dur: 5.6, draw: sStart, h: 90, strip: false };
  const FLOWS = { title: 'How sessions use git.', text: 'On main, a worktree per feature, or a branch with a pull request merged by your OK.', dur: 5.4, draw: sFlows, h: 104, strip: false };
  // How you decide (240×124): look at the options, choose (pick, blend, note), done → build.
  function sDecide(t) {
    const stage = t < 1.6 ? 0 : t < 4.2 ? 1 : 2, picked = t > 2.3, blended = t > 2.9, done = t > 4.2;
    ['1 LOOK', '2 CHOOSE', '3 DONE'].forEach((l, i) => {
      const x = 48 + i * 50;
      if (i === stage) R(x, 4, 44, 10, K.amber); else box(x, 4, 44, 10, K.bg2, i < stage ? K.green : K.line2);
      txt(x + 22, 7, l, i === stage ? K.ink : i < stage ? K.green : K.dim, 1, 'center');
    });
    txt(120, 19, 'CLAUDE ASKS: WHICH HOME PAGE?', K.cream, 1, 'center');
    ['A', 'B', 'C'].forEach((l, i) => {
      if (t < .3 + i * .25) return;
      const x = 16 + i * 74, y = 28, on = i === 1 && picked, mix = i === 0 && blended;
      alpha(picked && !on && !mix ? .35 : 1, () => {
        box(x, y, 60, 50, K.bg2, on ? K.amber : mix ? K.blue : K.line2);
        box(x + 2, y + 2, 56, 38, K.panel, K.line);
        mock(i, x + 2, y + 2);
        txt(x + 4, y + 43, l, on ? K.amber : K.cream);
        if (i === 0) txt(x + 56, y + 43, 'SUGGESTED', K.blue, 1, 'right');
      });
      if (on) { R(x + 50, y - 4, 13, 12, K.amber); check(x + 54, y, K.ink); }
      if (mix) { R(x + 50, y - 4, 13, 12, K.blue); txt(x + 55, y - 1, '+', K.ink); }
    });
    if (!done) {
      const note = 'B, WITH THE COLOURS OF A', n = Math.floor(pr(t, 3.1, 3.9) * note.length);
      box(16, 84, 150, 13, K.ink, t > 2.9 ? K.amber : K.line2);
      if (n === 0) txt(21, 88, 'ADD A NOTE', K.mute); else txt(21, 88, note.slice(0, n), K.cream);
      if (t > 2.9 && t < 4 && blink(t)) R(21 + n * 4, 87, 2, 7, K.amber);
      R(172, 84, 52, 13, t > 4.05 ? K.cream : picked ? K.amber : K.line2); txt(198, 88, 'DONE', K.ink, 1, 'center');
      txt(120, 106, 'PICK ONE - BLEND TWO - WRITE YOUR OWN - PARK IT', K.mute, 1, 'center');
    } else {
      box(16, 84, 208, 16, K.greenDim, K.green); check(22, 90, K.green); txt(32, 90, 'YOU CHOSE B + A', K.green);
      R(152, 87, 68, 10, t > 5 && blink(t * 2) ? K.cream : K.amber); txt(186, 90, 'BUILD MY PICK', K.ink, 1, 'center');
      if (t > 4.8) txt(120, 108, 'YOUR ANSWER STARTS THE BUILD', K.dim, 1, 'center');
    }
    if (t > 1.2 && t < 4.4) {
      const a = ease(pr(t, 1.6, 2.2)), b = ease(pr(t, 2.4, 2.85)), c = ease(pr(t, 3.9, 4.05));
      let x = lerp(204, 122, a), y = lerp(112, 56, a);
      x = lerp(x, 72, b); y = lerp(y, 30, b);
      x = lerp(x, 200, c); y = lerp(y, 91, c);
      spr(CUR, x, y);
    }
  }
  const DECIDE = { title: 'How you decide.', text: 'Claude asks with three options as pictures; you pick B, blend in A with a note, press Done, and your answer starts the build.', dur: 6.2, draw: sDecide, h: 120, strip: false };
  // The problem (240×92): 9 sessions, fine, 19, okay, 99; three of them are waiting on you.
  function sCrowd(t) {
    const n = t < 1 ? 9 : t < 2 ? 19 : Math.min(99, 19 + Math.floor(pr(t, 2, 3.4) * 80));
    const wait = [3, 5, 8], found = t > 5;
    for (let k = 0; k < n; k++) {
      const i = (k * 37) % 99, x = 10 + (i % 11) * 20, y = 6 + ((i / 11) | 0) * 8, w = wait.includes(k) && t > 3.8;
      alpha(found && !w ? .25 : 1, () => {
        box(x, y, 18, 6, K.ink, w && (found || blink(t * 1.5)) ? K.amber : K.line2);
        R(x + 3, y + 2, w ? 12 : 4 + (k * 5 + ((t * 4) | 0) * (k % 3)) % 10, 2, w ? K.amber : K.cream);
      });
    }
    txt(10, 83, `${n} SESSIONS OPEN`, n > 9 && t < 3.8 ? K.amber : K.cream);
    if (t > 3.8) txt(230, 83, found ? 'STEERIFY KNOWS WHICH 3' : '3 ARE WAITING ON YOU', K.amber, 1, 'right');
  }
  const CROWD = { title: 'Ninety-nine sessions, three waiting on you.', text: 'A wall of terminals grows from 9 to 19 to 99; three of them turn amber.', dur: 6.6, draw: sCrowd, h: 92, strip: false };
  const NAMED = { hero: HERO, mac: MAC, start: START, flows: FLOWS, decide: DECIDE, crowd: CROWD };

  const SCENES = [
    { name: 'Say it', title: 'Say what you want.', text: 'Write it in plain words. Steerify turns it into requirements, docs and a roadmap.', dur: 6, draw: s1 },
    { name: 'Confirm', title: 'Confirm it with pictures.', text: 'Before anything is built, Claude shows the options as mockups. You pick the one you meant.', dur: 5.4, draw: s2 },
    { name: 'Build', title: 'Build the right thing.', text: 'Each answer starts a Claude session, already briefed, in the right repo.', dur: 5.8, draw: s3 },
    { name: 'Sync', title: 'Always in sync.', text: 'Every session sits on its roadmap item. The status moves on its own.', dur: 5.6, draw: s4 },
    { name: 'Filter', title: 'Only what needs you.', text: 'Nine sessions running, three waiting on you. You see those three.', dur: 5.8, draw: s5 },
    { name: 'Check', title: 'One standard.', text: 'Every delivery is checked against the same design and the same tests.', dur: 6, draw: s6 },
    { name: 'Reuse', title: 'Skills, not repeats.', text: 'What works becomes a skill. Every session reuses it, so everything stays aligned.', dur: 5.8, draw: s7 },
    { name: 'Steer', title: 'You just steer.', text: 'You choose, look and say ship. Claude does the rest.', dur: 6, draw: s8 },
  ];

  function strip(idx, frac, t) { // the voyage: one buoy per scene, the boat sails the film
    const last = idx === SCENES.length - 1, bxs = SCENES.map((_, i) => 26 + i * 28.5);
    if (!last) { R(0, 137, W, 13, K.sea); for (let x = -4; x < W; x += 6) R(x + ((t * 4) | 0) % 6, 136 + ((x / 6) & 1), 3, 1, K.wave); }
    bxs.forEach((bx, i) => {
      const c = i < idx || (last && frac > .5) ? K.green : i === idx ? K.amber : K.mute;
      R(bx + 1, 129, 1, 3, K.dim); R(bx, 132, 3, 5, c); txt(bx + 2, 141, i + 1, c, 1, 'center');
    });
    if (!last) spr(BOAT, lerp(bxs[idx], bxs[idx] + 28.5, frac) - 21, 126 + Math.round(Math.sin(t * 3) * .6));
  }

  function paint(c2, s, idx, t, h, withStrip) {
    ctx = c2; CH = h;
    R(0, 0, W, h, K.bg);
    s.draw(t);
    if (t < .35) { const q = t / .35; for (let bx = 0; bx < 24; bx++) for (let by = 0; by * 10 < h; by++) if (((bx * 7 + by * 13) % 10) / 10 >= q) R(bx * 10, by * 10, 10, 10, K.bg); }
    if (withStrip) strip(idx, cl(t / s.dur), t);
  }

  // One scene on a loop, for a scrolling page: <div data-scene="0…7 | hero | mac" [data-h="124"] [data-strip="0"]>.
  function mountScene(el) {
    const reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    const key = el.dataset.scene, idx = NAMED[key] ? -1 : +key, s = NAMED[key] || SCENES[idx];
    const h = +(el.dataset.h || s.h || 150), withStrip = idx >= 0 && el.dataset.strip !== '0';
    el.classList.add('st-stage');
    el.innerHTML = `<canvas width="${W}" height="${h}" style="aspect-ratio:${W}/${h}" role="img"></canvas>`;
    const cv = el.querySelector('canvas'), c2 = cv.getContext('2d');
    cv.setAttribute('aria-label', el.getAttribute('aria-label') || `${s.title} ${s.text}`.trim());
    el.removeAttribute('aria-label');
    let t = reduce ? s.dur : 0, playing = !reduce, visible = false, prev = 0, raf = 0;
    const draw = () => paint(c2, s, idx, Math.min(t, s.dur), h, withStrip);
    function tick(now) { raf = 0; t += Math.min(.1, (now - prev) / 1000); prev = now; if (t > s.dur + 1.6) t = 0; draw(); loop(); }
    function loop() { if (playing && visible && !raf) { prev = performance.now(); raf = requestAnimationFrame(tick); } }
    cv.addEventListener('click', () => { playing = !playing; loop(); });
    if ('IntersectionObserver' in window) new IntersectionObserver((es) => { visible = es[0].isIntersecting; loop(); }, { threshold: .2 }).observe(el);
    else visible = true;
    draw();
    el._scene = { seek: (tt) => { t = tt; playing = false; draw(); } };
  }

  function mount(el) {
    const reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    el.classList.add('story');
    el.innerHTML = `<div class="st-stage"><canvas width="${W}" height="150" style="aspect-ratio:${W}/150" role="img" aria-label="Pixel animation: how Steerify works, in eight scenes"></canvas><button class="st-play" type="button"></button></div>
<div class="st-cap" aria-live="polite"><span class="st-num"></span><div><h3></h3><p></p></div></div>
<ol class="st-rail">${SCENES.map((s, i) => `<li><button type="button" data-i="${i}"><b>${i + 1}</b>${s.name}</button></li>`).join('')}</ol>`;
    const cv = el.querySelector('canvas'), play = el.querySelector('.st-play'), num = el.querySelector('.st-num'), h = el.querySelector('h3'), p = el.querySelector('.st-cap p');
    const btns = [...el.querySelectorAll('.st-rail button')];
    const c2 = cv.getContext('2d');
    let idx = 0, t = reduce ? SCENES[0].dur : 0, playing = !reduce, visible = false, prev = 0, raf = 0, shown = -1;

    function render() {
      const s = SCENES[idx];
      paint(c2, s, idx, t, 150, true);
      if (shown !== idx) {
        shown = idx; num.textContent = String(idx + 1).padStart(2, '0'); h.textContent = s.title; p.textContent = s.text;
        btns.forEach((b, i) => { b.classList.toggle('on', i === idx); b.classList.toggle('past', i < idx); if (i === idx) b.setAttribute('aria-current', 'step'); else b.removeAttribute('aria-current'); });
      }
      btns[idx].style.setProperty('--p', cl(t / s.dur));
      play.textContent = playing ? 'PAUSE' : 'PLAY';
      play.setAttribute('aria-label', playing ? 'Pause the animation' : 'Play the animation');
    }
    function tick(now) {
      raf = 0;
      const dt = Math.min(.1, (now - prev) / 1000); prev = now;
      t += dt;
      if (t >= SCENES[idx].dur) { idx = (idx + 1) % SCENES.length; t = 0; }
      render();
      loop();
    }
    function loop() { if (playing && visible && !raf) { prev = performance.now(); raf = requestAnimationFrame(tick); } }
    function go(i) { idx = (i + SCENES.length) % SCENES.length; t = playing ? 0 : SCENES[idx].dur; render(); loop(); }
    function toggle() { playing = !playing; if (playing && t >= SCENES[idx].dur) t = 0; render(); loop(); }

    play.addEventListener('click', (e) => { e.stopPropagation(); toggle(); });
    cv.addEventListener('click', toggle);
    btns.forEach((b) => b.addEventListener('click', () => go(+b.dataset.i)));
    el.addEventListener('keydown', (e) => { if (e.key === 'ArrowRight') go(idx + 1); if (e.key === 'ArrowLeft') go(idx - 1); });
    if ('IntersectionObserver' in window) new IntersectionObserver((es) => { visible = es[0].isIntersecting; loop(); }, { threshold: .25 }).observe(el);
    else visible = true;
    document.addEventListener('visibilitychange', () => { if (!document.hidden) loop(); });
    render();
    el._story = { go, toggle, seek: (i, tt) => { idx = i; t = tt; playing = false; render(); } };
  }

  function init() {
    document.querySelectorAll('[data-story]').forEach((el) => { if (!el._story) mount(el); });
    document.querySelectorAll('[data-scene]').forEach((el) => { if (!el._scene) mountScene(el); });
  }
  window.SteerifyStory = { init, scenes: SCENES, named: NAMED, paint }; // named + paint: used by scripts/readme-art.mjs
  if (document.readyState !== 'loading') init(); else document.addEventListener('DOMContentLoaded', init);
})();
