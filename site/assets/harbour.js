/* Hero background: the app's onboarding art (HarbourDawn in Sources/SteerApp/PixelScene.swift), on the web.
   A pixel harbour at dawn: sky bands, stars fading, the sun rising, a lighthouse beam, a gull, the boat at the pier.
   Hovering "Download for Mac" sails the boat out (as pressing Set up does in the app).
   Drawn on a tiny canvas (one canvas pixel = one art pixel) scaled up with crisp pixels, ~10 frames/s;
   paused off screen, in a hidden tab, and a still frame with Reduce Motion. */
(() => {
  const hero = document.querySelector('.hero2');
  if (!hero) return;
  const C = { cream: '#f2e8cf', amber: '#ffb020', blue: '#8fb0ff', line2: '#343944', claude: '#d97757',
    sea: '#0d1020', wood: '#8a5a2b', wood2: '#5c3b1c', post: '#4a2f16' };
  const BANDS = ['#1a1430', '#2a1a3a', '#40223e', '#5e2c40', '#7f3a42', '#a24a46', '#c0604c', '#d97757'];
  const SEA = 12;   // sea rows under the horizon
  const BOAT = ['......#.......', '......##......', '......###.....', '......####....', '......#####...', '......#.......',
    '##############', '.############.', '..##########..'];

  const box = document.createElement('div');
  box.className = 'harbour';
  box.setAttribute('aria-hidden', 'true');
  const cv = document.createElement('canvas');
  box.appendChild(cv);
  hero.prepend(box);
  const ctx = cv.getContext('2d');

  const still = matchMedia('(prefers-reduced-motion: reduce)');
  const t0 = performance.now();
  let W = 156, H = 50, sailFrom = null, backAt = 0, visible = true, timer = 0, stars = [];

  // The band runs from the top of the hero to just past the top of the video: the sky behind the text,
  // the horizon and sea between the "Mac only" line and the video. ~8 CSS px per art pixel (6 on phones).
  function layout() {
    const vid = hero.querySelector('.herovid');
    const h = vid ? vid.getBoundingClientRect().top - hero.getBoundingClientRect().top + 24 : hero.offsetHeight;
    box.style.height = Math.max(200, h) + 'px';
    const w = box.clientWidth, bh = box.clientHeight, px = w < 720 ? 6 : 8;
    W = Math.max(60, Math.round(w / px)); H = Math.max(40, Math.round(bh * W / w));
    cv.width = W; cv.height = H;
    let seed = 7; const rnd = () => (seed = (seed * 9301 + 49297) % 233280) / 233280;
    stars = Array.from({ length: Math.round(W * H / 260) }, () => [Math.floor(rnd() * W), Math.floor(rnd() * (H - SEA - 8))]);
    draw();
  }

  function dot(x, y, c, a = 1) {
    if (x < 0 || x >= W || y < 0 || y >= H) return;
    ctx.globalAlpha = a; ctx.fillStyle = c; ctx.fillRect(x, y, 1, 1);
  }

  function draw() {
    const now = performance.now();
    const t = still.matches ? 4 : (now - t0) / 1000;
    const phase = Math.floor(t / 0.6) % 8, HZ = H - SEA, R = W;
    // sky: night violet at the top into Claude orange at the horizon (banded, pixel-style)
    ctx.globalAlpha = 1;
    BANDS.forEach((c, i) => {
      const y0 = Math.floor(HZ * i / BANDS.length), y1 = Math.floor(HZ * (i + 1) / BANDS.length);
      ctx.fillStyle = c; ctx.fillRect(0, y0, W, y1 - y0);
    });
    // stars fade as the sun comes up
    const dawn = Math.min(1, t / 20);
    stars.forEach(([x, y]) => dot(x, y, C.cream, ((x + phase) % 3 === 0 ? 0.9 : 0.4) * (1 - dawn * 0.7) * (1 - y / HZ)));
    // sun rising (6 px in the first 20 s), cut by the horizon
    const sx = R - 46, sy = HZ - 2 - Math.floor(dawn * 6);
    for (let y = -6; y <= 6; y++) for (let x = -6; x <= 6; x++)
      if (x * x + y * y <= 36 && sy + y < HZ) dot(sx + x, sy + y, C.amber, 0.92);
    // sea, waves, the sun's reflection
    ctx.globalAlpha = 1; ctx.fillStyle = C.sea; ctx.fillRect(0, HZ, W, SEA);
    for (let r = 0; r < 4; r++) for (let x = 0; x < W; x++)
      if ((x + phase * (r + 1) + r * 3) % 7 < 4) dot(x, HZ + 2 + r * 3, r === 0 ? C.blue : C.line2, r === 0 ? 0.6 : 0.9);
    for (let r = 0; r < 3; r++) for (let x = sx - 6 + r; x <= sx + 6 - r; x++)
      if ((x + phase + r) % 3 !== 0) dot(x, HZ + 1 + r * 3, C.amber, 0.5 - r * 0.12);
    // pier
    const p0 = R - 104;
    for (let x = p0; x < p0 + 30; x++) { dot(x, HZ - 2, C.wood); dot(x, HZ - 1, C.wood2); }
    for (let x = p0 + 2; x < p0 + 30; x += 6) for (let y = HZ; y < HZ + 10; y++) dot(x, y, C.post);
    // lighthouse: striped tower, lamp, sweeping beam
    const lx = R - 16, base = HZ - 1;
    for (let y = 0; y < 16; y++) for (let i = 0; i < 4; i++) dot(lx + i, base - y, Math.floor(y / 3) % 2 === 1 ? C.cream : C.claude);
    for (let i = -1; i <= 4; i++) dot(lx + i, base - 16, C.post);
    [[1, 17], [2, 17], [1, 18], [2, 18]].forEach(([x, y]) => dot(lx + x, base - y, C.amber));
    const dir = phase % 8 < 4 ? -1 : 1;
    for (let k = 3; k < 26; k++) dot(lx + 1 + dir * k, base - 18 + Math.floor(k / 9), C.amber, Math.max(0, 0.38 - k * 0.013));
    // a gull crossing
    const gx = Math.floor(t * 6) % (W + 20) - 10, gy = HZ - 26 + (Math.floor(t * 2) % 2);
    [0, -1, 0, -1, 0].forEach((dy, i) => dot(gx + i, gy + dy, C.cream, 0.85));
    // the boat: bobs at the pier, sails out while "Download" is hovered, comes back a while later
    if (sailFrom && now > backAt) sailFrom = null;
    const bx = Math.max(p0 + 34, 2) + (sailFrom ? Math.floor((now - sailFrom) / 1000 * 90) : 0);
    const by = HZ - 10 + (phase % 4 < 2 ? 0 : 1);
    BOAT.forEach((row, y) => [...row].forEach((ch, x) => { if (ch === '#') dot(bx + x, by + y, y < 6 ? C.cream : C.amber); }));
    if (sailFrom) for (let k = 1; k < 10; k += 2) dot(bx - k, HZ - 1 + Math.floor(k / 3) % 2, C.cream, 0.5 - k * 0.05);
    ctx.globalAlpha = 1;
  }

  function loop() {
    clearTimeout(timer);
    if (!visible || document.hidden || still.matches) return;
    draw();
    timer = setTimeout(loop, 100);
  }

  const cta = hero.querySelector('[data-dl]');
  if (cta) cta.addEventListener('mouseenter', () => {
    if (still.matches || sailFrom) return;
    sailFrom = performance.now(); backAt = sailFrom + 6000;
  });
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; loop(); }).observe(box);
  document.addEventListener('visibilitychange', loop);
  still.addEventListener?.('change', () => { draw(); loop(); });
  new ResizeObserver(layout).observe(hero);
  layout(); loop();
})();
