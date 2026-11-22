/* The voyage: the app's onboarding art (HarbourDawn in Sources/SteerApp/PixelScene.swift), carried down the page.
   The hero is the harbour at dawn; as you scroll the day goes by in thin pixel strips between the sections
   (morning, noon, sunset) and the footer is the harbour at night. The same boat sails further right in each one.
   Every scene is a tiny canvas (one canvas pixel = one art pixel) scaled up with crisp pixels, ~10 frames/s,
   drawn only while on screen and in a visible tab; Reduce Motion → a still frame. */
(() => {
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
  const MINI = ['.#..', '.##.', '####'];   // a far-away boat (the other sessions)
  const CLOUD = ['..####....', '.#######..', '##########'];

  const still = matchMedia('(prefers-reduced-motion: reduce)');
  const t0 = performance.now();
  const scenes = [];

  function make(host, opts) {
    const box = document.createElement('div');
    box.className = 'harbour ' + (opts.cls || '');
    box.setAttribute('aria-hidden', 'true');
    const cv = document.createElement('canvas');
    box.appendChild(cv);
    opts.place(box);
    const s = { box, cv, ctx: cv.getContext('2d'), opts, W: 0, H: 0, stars: [], visible: false, sailFrom: null, backAt: 0 };
    s.layout = () => {
      if (opts.height) box.style.height = opts.height() + 'px';
      const w = box.clientWidth, bh = box.clientHeight;
      if (!w || !bh) return;
      const px = w < 720 ? 5 : opts.px || 8;
      s.W = Math.max(60, Math.round(w / px)); s.H = Math.max(20, Math.round(bh * s.W / w));
      cv.width = s.W; cv.height = s.H;
      let seed = opts.seed || 7; const rnd = () => (seed = (seed * 9301 + 49297) % 233280) / 233280;
      s.stars = Array.from({ length: Math.round(s.W * s.H / (opts.starDensity || 260)) }, () => [Math.floor(rnd() * s.W), Math.floor(rnd() * (s.H - opts.sea - 4))]);
      draw(s);
    };
    new IntersectionObserver(([e]) => { s.visible = e.isIntersecting; tick(); }, { rootMargin: '80px' }).observe(box);
    new ResizeObserver(s.layout).observe(host);
    scenes.push(s);
    s.layout();
    return s;
  }

  function draw(s) {
    const { ctx, W, H, opts } = s;
    if (!W) return;
    const now = performance.now(), t = still.matches ? 4 : (now - t0) / 1000;
    const phase = Math.floor(t / 0.6) % 8, HZ = H - opts.sea, R = W, tod = opts.tod;
    const dot = (x, y, c, a = 1) => { if (x < 0 || x >= W || y < 0 || y >= H) return; ctx.globalAlpha = a; ctx.fillStyle = c; ctx.fillRect(x, y, 1, 1); };
    const sprite = (rows, x0, y0, col) => rows.forEach((row, y) => [...row].forEach((ch, x) => { if (ch === '#') dot(x0 + x, y0 + y, typeof col === 'function' ? col(y) : col); }));
    // sky bands into the horizon
    ctx.globalAlpha = 1;
    SKIES[tod].forEach((c, i, a) => { const y0 = Math.floor(HZ * i / a.length), y1 = Math.floor(HZ * (i + 1) / a.length); ctx.fillStyle = c; ctx.fillRect(0, y0, W, y1 - y0); });
    // stars: fading with the dawn, twinkling at night, none by day
    const dawn = tod === 'dawn' ? Math.min(1, t / 20) : 0;
    if (tod === 'dawn' || tod === 'night' || tod === 'sunset') {
      const k = tod === 'night' ? 1 : tod === 'sunset' ? 0.35 : 1 - dawn * 0.7;
      s.stars.forEach(([x, y]) => dot(x, y, C.cream, ((x + y + phase) % 3 === 0 ? 0.9 : 0.35) * k * (1 - y / HZ * (tod === 'night' ? 0.4 : 1))));
    }
    // the sun (or the moon)
    const disc = (cx, cy, r, c, a, cut = true) => { for (let y = -r; y <= r; y++) for (let x = -r; x <= r; x++) if (x * x + y * y <= r * r && (!cut || cy + y < HZ)) dot(cx + x, cy + y, c, a); };
    let sx = -99;
    if (tod === 'dawn') { sx = R - 46; disc(sx, HZ - 2 - Math.floor(dawn * 6), 6, C.amber, 0.92); }
    if (tod === 'morning') { sx = Math.round(W * 0.16); disc(sx, Math.round(HZ * 0.42), 4, '#ffd27a', 0.9); }
    if (tod === 'noon') { sx = Math.round(W * 0.66); disc(sx, Math.round(HZ * 0.2), 4, '#fff4d0', 1); }
    if (tod === 'sunset') { sx = Math.round(W * 0.7); disc(sx, HZ + 1, 8, C.amber, 0.95); }
    if (tod === 'night') { const mx = Math.round(W * 0.62), my = Math.round(HZ * 0.3); disc(mx, my, 4, C.cream, 0.85, false); disc(mx + 2, my - 1, 3, SKIES.night[2], 1, false); }
    // clouds drifting by day
    if (tod === 'morning' || tod === 'noon') {
      [[0.1, 0.18, 0.55], [0.45, 0.1, 0.4], [0.78, 0.3, 0.5]].forEach(([fx, fy, a], i) => {
        const x = (Math.round(fx * W + t * (0.5 + i * 0.25)) % (W + 14)) - 12;
        CLOUD.forEach((row, y) => [...row].forEach((ch, cx) => { if (ch === '#') dot(x + cx, Math.round(fy * HZ) + y, y === 2 ? '#9aa6bd' : '#d9dde6', a); }));
      });
    }
    // sea and waves
    ctx.globalAlpha = 1; ctx.fillStyle = SEAS[tod]; ctx.fillRect(0, HZ, W, opts.sea);
    const waveTop = tod === 'night' ? '#2a3a66' : tod === 'sunset' ? '#7a4a6a' : C.blue;
    for (let r = 0; r < Math.floor(opts.sea / 3); r++) for (let x = 0; x < W; x++)
      if ((x + phase * (r + 1) + r * 3) % 7 < 4) dot(x, HZ + 2 + r * 3, r === 0 ? waveTop : C.line2, r === 0 ? 0.6 : 0.9);
    // the sun's (moon's) reflection
    const refl = tod === 'night' ? [Math.round(W * 0.62), C.cream, 0.3] : sx > -99 ? [sx, tod === 'noon' ? '#fff1c4' : C.amber, tod === 'noon' ? 0.3 : 0.5] : null;
    if (refl) for (let r = 0; r < 3; r++) for (let x = refl[0] - 6 + r; x <= refl[0] + 6 - r; x++)
      if ((x + phase + r) % 3 !== 0) dot(x, HZ + 1 + r * 3, refl[1], refl[2] - r * 0.12);
    // far-away boats: the other sessions, rowing along the horizon
    if (tod === 'morning' || tod === 'noon') [0.3, 0.52, 0.86, 0.95].forEach((fx, i) => {
      const x = Math.round(fx * W + Math.sin(t / 3 + i) * 2);
      sprite(MINI, x, HZ - 2, (y) => (y === 2 ? C.mute : '#8d93a3'));
    });
    // buoys at noon, as in "How it works": passed ones green, the next one amber
    let boatX = Math.round(W * (opts.boat || 0.3));
    if (tod === 'noon') for (let i = 1; i <= 8; i++) {
      const bx = Math.round(W * i / 9), c = bx < boatX ? C.green : bx < boatX + 20 ? C.amber : C.mute;
      dot(bx, HZ, c); dot(bx, HZ - 1, c); dot(bx, HZ - 2, c, 0.7);
    }
    // pier (hero: by the boat; sunset and night: the harbour on the right, where the voyage ends)
    const pier = (p0, len) => {
      for (let x = p0; x < p0 + len; x++) { dot(x, HZ - 2, C.wood); dot(x, HZ - 1, C.wood2); }
      for (let x = p0 + 2; x < p0 + len; x += 6) for (let y = HZ; y < Math.min(H, HZ + 10); y++) dot(x, y, C.post);
    };
    if (tod === 'dawn') pier(R - 104, 30);
    if (tod === 'night') {
      pier(R - 48, 26);
      const lx = R - 30;   // lantern on the pier, glowing on the beat
      for (let y = HZ - 7; y < HZ - 2; y++) dot(lx, y, '#6b4a2a');
      [[-1, -9], [0, -9], [1, -9], [0, -10], [0, -8]].forEach(([dx, dy]) => dot(lx + dx, HZ + dy, C.amber, phase % 2 ? 0.6 : 1));
    }
    // lighthouse with its beam (brighter at night)
    if (tod === 'dawn' || tod === 'sunset' || tod === 'night') {
      const lx = R - 16, base = HZ - 1, night = tod === 'night';
      for (let y = 0; y < 16; y++) for (let i = 0; i < 4; i++) dot(lx + i, base - y, Math.floor(y / 3) % 2 === 1 ? C.cream : C.claude, night ? 0.75 : 1);
      for (let i = -1; i <= 4; i++) dot(lx + i, base - 16, C.post);
      [[1, 17], [2, 17], [1, 18], [2, 18]].forEach(([x, y]) => dot(lx + x, base - y, C.amber));
      const dir = phase % 8 < 4 ? -1 : 1, len = night ? 60 : 26;
      for (let k = 3; k < len; k++) dot(lx + 1 + dir * k, base - 18 + Math.floor(k / 9), C.amber, Math.max(0, (night ? 0.5 : 0.38) - k * (night ? 0.008 : 0.013)));
    }
    // gulls (by day and at dawn)
    if (tod !== 'night') {
      const n = tod === 'dawn' ? 1 : 2;
      for (let g = 0; g < n; g++) {
        const gx = Math.floor(t * (6 - g * 2) + g * 70) % (W + 20) - 10, gy = Math.max(2, Math.round(HZ * (0.3 + g * 0.15))) + (Math.floor(t * 2 + g) % 2);
        [0, -1, 0, -1, 0].forEach((dy, i) => dot(gx + i, gy + dy, C.cream, 0.85));
      }
    }
    // the boat: sails a little along its strip; in the hero it sails out while "Download" is hovered
    if (s.sailFrom && now > s.backAt) s.sailFrom = null;
    if (tod === 'dawn') boatX = Math.max(R - 70, 2);
    if (tod === 'night') boatX = R - 62;
    const drift = tod === 'dawn' || tod === 'night' ? 0 : Math.floor((t * 1.2) % 24) - 12;
    const bx = boatX + drift + (s.sailFrom ? Math.floor((now - s.sailFrom) / 1000 * 90) : 0);
    const by = HZ - 10 + (phase % 4 < 2 ? 0 : 1);
    const sail = tod === 'night' ? '#b8b2a0' : C.cream, hull = tod === 'night' ? '#b07a10' : C.amber;
    sprite(BOAT, bx, by, (y) => (y < 6 ? sail : hull));
    if (s.sailFrom || drift) for (let k = 1; k < 10; k += 2) dot(bx - k, HZ - 1 + Math.floor(k / 3) % 2, C.cream, 0.45 - k * 0.04);
    ctx.globalAlpha = 1;
  }

  let timer = 0;
  function tick() {
    clearTimeout(timer);
    const live = scenes.filter((s) => s.visible);
    live.forEach(draw);
    if (live.length && !document.hidden && !still.matches) timer = setTimeout(tick, 100);
  }
  document.addEventListener('visibilitychange', tick);
  still.addEventListener?.('change', () => { scenes.forEach(draw); tick(); });

  // Hero: the harbour at dawn, from the top of the hero down to just past the top of the video.
  const hero = document.querySelector('.hero2');
  if (hero) {
    const s = make(hero, {
      tod: 'dawn', sea: 12, cls: 'hz-hero', place: (b) => hero.prepend(b),
      height: () => {
        const vid = hero.querySelector('.herovid');
        return Math.max(200, vid ? vid.getBoundingClientRect().top - hero.getBoundingClientRect().top + 24 : hero.offsetHeight);
      },
    });
    const cta = hero.querySelector('[data-dl]');
    if (cta) cta.addEventListener('mouseenter', () => {
      if (still.matches || s.sailFrom) return;
      s.sailFrom = performance.now(); s.backAt = s.sailFrom + 6000;
    });
  }

  // The day going by: a strip before some sections, the boat further along each time.
  [['#decide', 'morning', 0.3, 11], ['#real', 'noon', 0.52, 23], ['#watch', 'sunset', 0.4, 41]].forEach(([sel, tod, boat, seed]) => {
    const sec = document.querySelector(sel);
    if (!sec) return;
    make(sec, { tod, boat, seed, sea: 9, px: 6, cls: 'hz-strip', place: (b) => sec.before(b) });
  });

  // Footer: the harbour at night, the boat moored, the lighthouse sweeping.
  const foot = document.querySelector('footer');
  if (foot) make(foot, { tod: 'night', sea: 10, px: 6, seed: 3, starDensity: 90, cls: 'hz-night', place: (b) => foot.prepend(b), height: () => foot.offsetHeight });
})();
