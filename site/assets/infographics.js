// Pixel infographics for the key ideas. 1 SVG unit = 1 pixel of the art; crisp edges, a few CSS loops.
(function () {
  const K = { bg: '#0d0f13', panel: '#111318', line: '#343944', ink: '#050607', cream: '#f2e8cf', mute: '#4a4e58', amber: '#ffb020', green: '#4ade80', blue: '#8fb0ff', red: '#ff5a36' };
  const R = (x, y, w, h, f, cls = '') => `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${f}"${cls ? ` class="${cls}"` : ''}/>`;
  const T = (x, y, t, f = K.mute, size = 4, anchor = 'start') => `<text x="${x}" y="${y}" fill="${f}" font-family="Silkscreen, monospace" font-size="${size}" text-anchor="${anchor}">${t}</text>`;
  const box = (x, y, w, h, fill = K.panel, edge = K.line) => R(x, y, w, h, edge) + R(x + 1, y + 1, w - 2, h - 2, fill);
  const svg = (inner, w = 160, h = 90) => `<svg viewBox="0 0 ${w} ${h}" shape-rendering="crispEdges" role="img">${inner}</svg>`;

  // 1 · Every roadmap item has its session, and they stay in sync.
  function sync() {
    let s = T(6, 9, 'ROADMAP', K.amber) + T(154, 9, 'SESSIONS', K.amber, 4, 'end');
    const rows = [['done', K.green, 26], ['review', K.blue, 20], ['wip', K.amber, 30]];
    rows.forEach(([st, col, len], i) => {
      const y = 16 + i * 24;
      s += box(4, y, 64, 18);
      s += st === 'done' ? R(9, y + 6, 6, 6, col) : st === 'review' ? box(9, y + 6, 6, 6, K.panel, col) : R(9, y + 6, 6, 6, K.line) + R(9, y + 6, 3, 6, col);
      s += R(19, y + 6, len, 2, K.cream) + R(19, y + 10, len - 8, 2, K.mute);
      s += T(64, y + 15, st.toUpperCase(), col, 3, 'end');
      for (let x = 70; x < 96; x += 3) s += R(x, y + 8, 2, 1, col);
      s += `<g class="pulse p${i}">${R(69, y + 7, 3, 3, col)}</g>`;
      s += box(98, y, 58, 18, K.ink);
      s += R(99, y + 1, 56, 3, K.panel) + R(101, y + 2, 1, 1, K.red) + R(103, y + 2, 1, 1, K.amber) + R(105, y + 2, 1, 1, K.green);
      s += R(102, y + 8, 1, 1, K.amber) + R(103, y + 9, 1, 1, K.amber) + R(102, y + 10, 1, 1, K.amber);
      s += R(106, y + 8, st === 'wip' ? 18 : 30, 2, K.cream) + R(106, y + 12, 22, 1, K.mute);
      if (st === 'wip') s += R(126, y + 8, 2, 3, K.amber, 'blink');
      if (st === 'done') s += T(152, y + 15, '✓', K.green, 4, 'end');
    });
    return svg(s);
  }

  // 2 · Review by looking: a wall of chat vs one picture with two pins.
  function review() {
    let s = T(6, 9, 'READ THIS', K.mute) + T(154, 9, 'OR LOOK', K.amber, 4, 'end');
    s += box(4, 13, 58, 66, K.bg);
    const ws = [44, 50, 38, 48, 30, 52, 46, 34, 50, 40, 48, 26, 44, 50, 36, 46, 30, 42, 50, 38];
    ws.forEach((w, i) => { s += R(7, 16 + i * 3, w, 1, i % 5 === 0 ? '#5d616b' : K.mute); });
    s += T(33, 86, '312 LINES', K.mute, 3.5, 'middle');
    // arrow
    for (let i = 0; i < 4; i++) s += R(67 + i * 3, 45, 2, 2, K.amber);
    s += R(80, 42, 2, 8, K.amber) + R(82, 43, 2, 6, K.amber) + R(84, 44, 2, 4, K.amber) + R(86, 45, 2, 2, K.amber);
    // picture
    s += box(92, 13, 64, 46, '#1a1d24', K.cream);
    s += R(93, 14, 62, 20, '#1d2230');
    [[136, 18, 6], [135, 19, 8], [134, 20, 10], [134, 21, 10], [135, 22, 8], [136, 23, 6]].forEach(([x, y, w]) => { s += R(x, y, w, 1, K.amber); });
    for (let i = 0; i < 18; i++) { s += R(100 + i, 40 - Math.min(i, 17 - i), 1, 18 + Math.min(i, 17 - i), '#3f9a52'); }
    for (let i = 0; i < 26; i++) { s += R(118 + i, 44 - Math.min(i, 25 - i) * 0.8 | 0, 1, 14 + (Math.min(i, 25 - i) * 0.8 | 0), '#2f6e3d'); }
    s += R(93, 52, 62, 6, '#24414f');
    // pins
    s += `<g class="pin pin1">${R(104, 24, 7, 7, K.amber)}${T(107.5, 30, '1', K.ink, 5, 'middle')}</g>`;
    s += `<g class="pin pin2">${R(140, 38, 7, 7, K.amber)}${T(143.5, 44, '2', K.ink, 5, 'middle')}</g>`;
    // buttons
    s += R(92, 64, 18, 8, K.green) + T(101, 70, 'OK', K.ink, 4, 'middle');
    s += R(113, 64, 26, 8, K.amber) + T(126, 70, 'REFINE', K.ink, 4, 'middle');
    s += box(142, 64, 14, 8, K.bg, K.red) + T(149, 70, '✕', K.red, 4, 'middle');
    s += T(124, 86, '1 PICTURE · 2 PINS', K.amber, 3.5, 'middle');
    return svg(s);
  }

  // 3 · Organised progress: every item moves through four lanes; the bar fills itself.
  function progress() {
    const lanes = [['CHOOSE', K.amber, 1], ['BUILD', K.blue, 2], ['TO TEST', K.cream, 2], ['SHIPPED', K.green, 3]];
    let s = '';
    lanes.forEach(([name, col, n], i) => {
      const x = 4 + i * 39;
      s += box(x, 6, 36, 62, K.bg);
      s += T(x + 18, 13, name, col, 3.5, 'middle') + R(x + 4, 16, 28, 1, K.line);
      for (let j = 0; j < n; j++) {
        const y = 20 + j * 11;
        s += box(x + 4, y, 28, 9, K.panel) + R(x + 7, y + 3, 14, 1, K.cream) + R(x + 7, y + 5, 9, 1, K.mute);
        if (name === 'SHIPPED') s += R(x + 26, y + 3, 3, 3, K.green);
        if (name === 'TO TEST') s += R(x + 26, y + 3, 3, 3, K.blue);
      }
      if (i < 3) s += R(x + 36, 36, 3, 1, K.line);
    });
    // a card on its way: To test → Shipped
    s += `<g class="mover">${box(86, 42, 28, 9, '#1b2a1f', K.green)}${R(89, 45, 14, 1, K.cream)}${R(108, 45, 3, 3, K.green)}</g>`;
    // progress bar
    const segs = [[7, K.green], [3, K.blue], [1, K.amber], [8, K.line]];
    let x = 4;
    segs.forEach(([n, c]) => { const w = n * 8; s += R(x, 76, w - 1, 4, c); x += w; });
    s += T(4, 88, '7 OF 19 DONE', K.cream, 3.5) + T(156, 88, 'NOBODY UPDATED THIS BY HAND', K.mute, 3, 'end');
    return svg(s);
  }

  // 4 · Choose: three options, each a picture; one suggested, you pick, blend, add a note.
  function choose() {
    let s = T(6, 9, 'CLAUDE ASKS', K.amber) + T(154, 9, 'BEFORE IT BUILDS', K.mute, 4, 'end');
    const arts = [
      (x, y) => R(x + 4, y + 4, 30, 4, K.cream) + R(x + 4, y + 10, 22, 2, K.mute) + R(x + 4, y + 14, 26, 2, K.mute) + R(x + 4, y + 20, 12, 5, K.amber),
      (x, y) => [0, 1, 2].map((i) => [0, 1].map((j) => R(x + 4 + i * 11, y + 4 + j * 11, 9, 9, j === 0 && i === 1 ? K.blue : '#2a2e37')).join('')).join(''),
      (x, y) => [[14, 4, 10], [11, 6, 16], [9, 9, 20], [9, 13, 20], [11, 17, 16], [14, 20, 10]].map(([dx, dy, w]) => R(x + dx, y + dy, w, 3, K.green)).join(''),
    ];
    ['A', 'B', 'C'].forEach((l, i) => {
      const x = 4 + i * 52, y = 14, on = i === 1;
      s += box(x, y, 48, 46, K.bg, on ? K.amber : K.line);
      s += box(x + 4, y + 4, 40, 28, K.panel);
      s += arts[i](x + 4, y + 4);
      s += T(x + 5, y + 40, l, on ? K.amber : K.cream, 5);
      s += R(x + 12, y + 36, 18, 1, K.mute) + R(x + 12, y + 39, 12, 1, K.mute);
      if (i === 0) s += box(x + 30, y + 35, 15, 6, K.bg, K.blue) + T(x + 37.5, y + 39.5, 'SUGG', K.blue, 2.6, 'middle');
      if (on) s += `<g class="pick">${R(x + 39, y - 3, 8, 8, K.amber)}${R(x + 41, y + 1, 1, 1, K.ink)}${R(x + 42, y + 2, 1, 1, K.ink)}${R(x + 43, y + 1, 1, 1, K.ink)}${R(x + 44, y, 1, 1, K.ink)}</g>`;
    });
    s += `<g class="cursor">${R(84, 44, 1, 7, K.cream)}${R(85, 45, 1, 5, K.cream)}${R(86, 46, 1, 3, K.cream)}${R(87, 47, 1, 1, K.cream)}</g>`;
    s += box(4, 66, 112, 12, K.bg) + T(8, 74, 'NOTE: B, WITH THE COLOURS OF A', K.cream, 3.4) + R(108, 69, 2, 6, K.amber, 'blink');
    s += R(120, 66, 36, 12, K.amber) + T(138, 74, 'CHOOSE', K.ink, 4, 'middle');
    s += T(80, 87, 'PICK ONE · BLEND TWO · OR WRITE YOUR OWN', K.mute, 3, 'middle');
    return svg(s);
  }

  // 5 · Ship: OK → commit → push → live, done by the session that built it; the roadmap fills itself.
  function ship() {
    let s = T(6, 9, 'YOU SAY OK', K.amber) + T(154, 9, 'THE SESSION SHIPS IT', K.mute, 4, 'end');
    const steps = [['OK', K.green], ['COMMIT', K.cream], ['PUSH', K.cream], ['DEPLOY', K.cream], ['LIVE', K.green]];
    steps.forEach(([n, col], i) => {
      const x = 4 + i * 31;
      s += box(x, 18, 28, 18, i === 0 ? '#16281b' : i === 4 ? '#16281b' : K.bg, i === 0 || i === 4 ? K.green : K.line);
      s += T(x + 14, 30, n, col, n.length > 4 ? 3.3 : 4, 'middle');
      if (i < 4) for (let d = 0; d < 3; d++) s += R(x + 28 + d, 27, 1, 1, K.line);
    });
    s += `<g class="travel">${R(14, 40, 8, 4, K.amber)}${R(16, 39, 4, 1, K.amber)}${R(22, 41, 2, 2, K.amber)}</g>`;
    s += box(4, 50, 152, 22, K.bg);
    s += T(8, 57, 'ROADMAP', K.amber, 3.4) + T(152, 57, 'MARKS ITSELF', K.mute, 3.4, 'end');
    s += R(8, 61, 144, 5, K.line) + `<g class="fill">${R(8, 61, 144, 5, K.green)}</g>`;
    s += T(80, 86, 'NOBODY UPDATES IT BY HAND', K.mute, 3.2, 'middle');
    return svg(s);
  }

  // 6 · Never lost: the chapter you were on (last / next / resume) and the menu bar that says whose turn it is.
  function leftoff() {
    let s = T(6, 9, 'WHERE YOU LEFT OFF', K.amber) + T(154, 9, 'MENU BAR', K.amber, 4, 'end');
    s += box(4, 13, 98, 72, K.bg);
    s += box(8, 17, 12, 12, K.panel, K.amber) + R(11, 22, 6, 2, K.amber) + R(13, 20, 2, 6, K.amber);
    s += R(24, 18, 52, 3, K.cream) + R(24, 23, 36, 2, K.mute);
    for (let i = 0; i < 14; i++) s += R(8 + i * 5, 33, 4, 3, i < 9 ? K.green : i === 9 ? K.amber : K.line);
    s += T(84, 36, '9/14', K.green, 3.6);
    s += T(8, 45, 'LAST', K.mute, 3) + R(26, 42, 52, 2, K.cream) + T(98, 45, '1H AGO', K.mute, 2.8, 'end');
    s += T(8, 53, 'NEXT', K.mute, 3) + R(26, 50, 60, 2, K.cream);
    s += R(8, 60, 60, 16, K.amber) + R(12, 65, 2, 6, K.ink) + R(14, 66, 1, 4, K.ink) + R(15, 67, 1, 2, K.ink) + T(42, 70, 'RESUME', K.ink, 4.4, 'middle');
    s += R(71, 61, 26, 1, K.mute) + R(71, 64, 18, 1, K.mute);
    // menu bar panel
    s += box(108, 13, 48, 72, K.ink);
    s += R(110, 17, 4, 4, K.cream) + R(111, 18, 2, 2, K.amber) + R(116, 18, 18, 2, K.cream);
    s += `<g class="blink">${R(110, 25, 3, 3, K.amber)}</g>` + T(115, 28, 'YOUR TURN · 3', K.amber, 3);
    s += R(110, 32, 44, 16, K.amber) + R(113, 35, 22, 2, K.ink) + R(113, 39, 34, 2, '#5a3d00') + R(113, 43, 26, 2, '#5a3d00');
    s += box(110, 52, 21, 13, K.panel) + T(113, 61, '2', K.cream, 5) + R(120, 58, 8, 1, K.green);
    s += box(133, 52, 21, 13, K.panel) + T(136, 61, '3', K.cream, 5) + R(143, 58, 8, 1, K.blue);
    [0, 1].forEach((i) => { s += R(110, 69 + i * 7, 44, 5, K.panel) + R(112, 71 + i * 7, 16, 1, K.cream) + R(144, 71 + i * 7, 8, 1, K.amber); });
    return svg(s);
  }

  const MAP = { sync, review, progress, choose, ship, leftoff };
  window.SteerifyInfo = { paint: (root = document) => root.querySelectorAll('[data-info]').forEach((el) => { el.innerHTML = (MAP[el.dataset.info] || (() => ''))(); }) };
  function paint() { document.querySelectorAll('[data-info]').forEach((el) => { el.innerHTML = (MAP[el.dataset.info] || (() => ''))(); }); }
  if (document.readyState !== 'loading') paint(); else document.addEventListener('DOMContentLoaded', paint);
})();
