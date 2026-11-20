// Steerify brand kit: pixel wheel + pixel icons as inline SVG. Used by the landing page and the tutorial.
(function () {
  const C = { cream: '#f2e8cf', amber: '#ffb020', ink: '#1b1305' };

  // 17×17 ship wheel, same raster as the app icon.
  function wheelCells() {
    const n = 17, c = 8, out = [];
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
      const dx = x - c, dy = y - c, r = Math.hypot(dx, dy), a = Math.atan2(dy, dx);
      const k = Math.round(a / (Math.PI / 4)), da = Math.abs(a - k * Math.PI / 4) * r;
      let col = null;
      if (r <= 2.2) col = 'a';
      else if (r >= 4.6 && r <= 5.9) col = 'c';
      else if (da < 0.55 && r <= 7.4) col = 'c';
      else if (r > 7.4 && r <= 8.3 && da < 0.9) col = 'c';
      if (col) out.push([x, y, col]);
    }
    [[7, 7], [8, 8], [7, 9]].forEach(([x, y]) => { const p = out.find((q) => q[0] === x && q[1] === y); if (p) p[2] = 'd'; });
    return out;
  }
  const fill = { a: C.amber, c: C.cream, d: C.ink };

  function wheel({ tile = false, mono = null } = {}) {
    const cells = wheelCells().map(([x, y, k]) => `<rect x="${x}" y="${y}" width="0.92" height="0.92" fill="${mono || fill[k]}"/>`).join('');
    if (!tile) return `<svg viewBox="0 0 17 17" shape-rendering="crispEdges" aria-hidden="true">${cells}</svg>`;
    return `<svg viewBox="0 0 100 100" shape-rendering="crispEdges" aria-hidden="true"><defs><linearGradient id="wt" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1a1d24"/><stop offset="1" stop-color="#07080a"/></linearGradient></defs><rect x="4" y="4" width="92" height="92" rx="22" fill="url(#wt)"/><rect x="4.5" y="4.5" width="91" height="91" rx="21.5" fill="none" stroke="#fff" stroke-opacity=".14"/><g transform="translate(15 15) scale(4.12)">${cells}</g></svg>`;
  }

  // 9×9 pixel icons (the in-app set).
  const ICONS = {
    test: ['#########', '#.......#', '#......##', '#.....#.#', '##...#..#', '#.#.#...#', '#..#....#', '#.......#', '#########'],
    choice: ['#.......#', '#.......#', '.#.....#.', '..#...#..', '...#.#...', '....#....', '....#....', '....#....', '....#....'],
    req: ['.#######.', '.#.....#.', '.#.###.#.', '.#.....#.', '.#.###.#.', '.#.....#.', '.#.##..#.', '.#.....#.', '.#######.'],
    road: ['.#.......', '.######..', '.#######.', '.######..', '.#.......', '.#.......', '.#.......', '.#.......', '###......'],
    term: ['#########', '#.......#', '#.#.....#', '#..#....#', '#.#..##.#', '#.......#', '#########', '.........', '.........'],
    play: ['.#.......', '.##......', '.###.....', '.####....', '.#####...', '.####....', '.###.....', '.##......', '.#.......'],
    ship: ['....#....', '...###...', '..#####..', '....#....', '....#....', '#########', '.#######.', '..#####..', '.........'],
    file: ['#####....', '#...##...', '#...#.#..', '#...####.', '#......#.', '#.####.#.', '#......#.', '#.####.#.', '########.'],
    feather: ['......###', '.....####', '....####.', '...####..', '..####...', '..###....', '.#.#.....', '#........', '.........'],
  };
  function icon(k) {
    let r = '';
    (ICONS[k] || []).forEach((row, y) => [...row].forEach((ch, x) => { if (ch === '#') r += `<rect x="${x}" y="${y}" width="1" height="1"/>`; }));
    return `<svg viewBox="0 0 9 9" shape-rendering="crispEdges" fill="currentColor" aria-hidden="true">${r}</svg>`;
  }


  // Credits: the people (and cats) behind it. Multi-colour pixel art; `data-pix="<name>"`, `data-pal` swaps colours.
  const PIX = {
    dragon: ['..a.......gg......', '..aa.....gggg.....', '..aaa...ggkggg....', '..aaaa..ggggggg.ra', '..aaaaa.gggrr..ra.', '...aaaaggg......r.',
      '....aaggggg.......', '...ggggggggg......', '..gggggggggggg....', '....gggggggg.gg...', '....gg.gg.gg..g...', '...gg..gg.gg..gg..'],
    phoenix: ['........r.......', '.......aa.......', '......akaa......', 'r.....aaar....r.', 'rr...aaaa....rr.', 'rrr.raaaar..rrr.', '.rrrraaaarrrrr..',
      '..rrraaaarrrr...', '....raaaar......', '.....aaaa.......', '....ra.aar......', '...r.ra.r.r.....', '..r..r..r..r....'],
boat: [
    '........c.........',
    '........cc........',
    '........ccc.......',
    '........cccc......',
    '........ccccc.....',
    '........cccccc....',
    '........ccccccc...',
    '........c.........',
    '.aaaaaaaaaaaaaaaa.',
    '..aaaaaaaaaaaaaa..',
    '...aaaaaaaaaaaa...',
    'bb..bbb..bbb..bbb.',
    '.bbb..bbb..bbb..bb',
  ],
  eye: [
    '.....cccccc.....',
    '...cc......cc...',
    '..c....aa....c..',
    '.c....aaaa....c.',
    'c....aakkaa....c',
    'c....aakkaa....c',
    '.c....aaaa....c.',
    '..c....aa....c..',
    '...cc......cc...',
    '.....cccccc.....',
  ],
  rocket: [
    '......cc......',
    '.....cccc.....',
    '....cccccc....',
    '....cccccc....',
    '....cbbbbc....',
    '....cbkkbc....',
    '....cbbbbc....',
    '....cccccc....',
    '...rcccccc.r..',
    '...rcccccc.r..',
    '..rr.cccc..rr.',
    '.....aaaa.....',
    '.....aaaa.....',
    '......aa......',
    '.....r..r.....',
  ],
  pin: [
    '....aaaaaa....',
    '...aaaaaaaa...',
    '..aaakkkkaaa..',
    '..aakkkkkkaa..',
    '..aakkkkkkaa..',
    '..aaakkkkaaa..',
    '...aaaaaaaa...',
    '....aaaaaa....',
    '.....aaaa.....',
    '......aa......',
    'm.m.m.m.m.m.m.',
  ],
    star: ['....a....', '....a....', '...aaa...', 'aaaaaaaaa', '.aaaaaaa.', '..aaaaa..', '..aaaaa..', '.aa...aa.', '.a.....a.'],
    laptop: ['.cccccccccccccc.', '.ckkkkkkkkkkkkc.', '.ckakkkkkkkkkkc.', '.ckkakcccccckkc.', '.ckakkkkkkkkkkc.', '.ckkkkkkkkkkkkc.', '.cccccccccccccc.', 'cccccccccccccccc', '.mmmmmmmmmmmmmm.'],
    cat: ['c.....c...', 'cc...cc...', 'ccccccc...', 'ckccckc...', 'ccccncc..c', '.ccccc...c', '.ccccc..c.', '.ccccc.c..', '.ccccccc..', '.cc.cc....'],
  };
  const PAL = { k: '#07080a', c: C.cream, a: C.amber, r: '#ff5a36', g: '#7fd47a', n: '#ff8fa0', b: '#8fb0ff', m: '#4a4e58' };
  const PALS = { orange: { c: C.amber, k: '#3a2508' }, black: { c: '#4a4e58', k: C.amber } };
  function pix(name, pal) {
    const rows = PIX[name] || [], F = { ...PAL, ...(PALS[pal] || {}) };
    let r = '';
    rows.forEach((row, y) => [...row].forEach((ch, x) => { if (ch !== '.' && F[ch]) r += `<rect x="${x}" y="${y}" width="1" height="1" fill="${F[ch]}"/>`; }));
    return `<svg viewBox="0 0 ${Math.max(1, ...rows.map((r) => r.length))} ${rows.length || 1}" shape-rendering="crispEdges" aria-hidden="true">${r}</svg>`;
  }

  function paint(root = document) {
    root.querySelectorAll('[data-wheel]').forEach((el) => { el.innerHTML = wheel({ tile: el.dataset.wheel === 'tile', mono: el.dataset.mono || null }); });
    root.querySelectorAll('[data-icon]').forEach((el) => { el.innerHTML = icon(el.dataset.icon); });
    root.querySelectorAll('[data-pix]').forEach((el) => { el.innerHTML = pix(el.dataset.pix, el.dataset.pal); });
  }
  window.Steerify = { wheel, icon, pix, paint };
  if (document.readyState !== 'loading') paint(); else document.addEventListener('DOMContentLoaded', () => paint());
})();
