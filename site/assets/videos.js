// Videos on the landing. Files live in videos/<name>.mp4 (16:9) and videos/<name>-v.mp4 (9:16, served to phones held upright).
// Hero: <div data-herovid="name"><video muted loop playsinline></video><button data-play></button></div>.
// Shelf: <button data-ep="name"> opens <dialog class="epdlg"> and plays it with sound.
(function () {
  const upright = () => window.matchMedia('(max-width: 720px) and (orientation: portrait)').matches;
  const file = (name) => 'videos/' + name + (upright() ? '-v' : '') + '.mp4';
  const poster = (name) => 'videos/posters/' + name + (upright() ? '-v' : '') + '.jpg';
  const calm = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Hero: a silent, looping preview under a big PLAY VIDEO button. A click (there, or on any [data-watch] button) restarts it
  // from the top with sound and controls. When a film ends, an "up next" card offers the next episode (it starts by itself
  // after a few seconds), Replay, and the download. Scrolling away stops everything and brings the silent preview back.
  document.querySelectorAll('[data-herovid]').forEach((el) => {
    const v = el.querySelector('video'), btn = el.querySelector('[data-play]'), end = el.querySelector('.hv-end');
    const list = [{ name: el.dataset.herovid, title: 'Steerify in 47 seconds' }].concat([...document.querySelectorAll('[data-ep]')].map((b) => ({ name: b.dataset.ep, title: b.querySelector('b').textContent })));
    el.classList.toggle('vert', upright());
    let seen = false, on = false, cur = 0, timer = 0;
    const load = (i) => { cur = i; v.poster = poster(list[i].name); v.src = file(list[i].name); };
    const hideEnd = () => { clearInterval(timer); if (end) end.hidden = true; };
    function preview() {
      hideEnd(); on = false; el.classList.remove('on');
      if (cur !== 0) load(0);
      v.controls = false; v.muted = true; v.loop = true;
      if (seen && !calm) v.play().catch(() => {}); else v.pause();
    }
    function start(i) {
      hideEnd(); on = true; el.classList.add('on');
      if (i !== cur || !v.currentSrc) load(i);
      v.loop = false; v.muted = false; v.controls = true; v.currentTime = 0;
      v.play().catch(() => {});
    }
    function ended() {
      const next = cur + 1 < list.length ? cur + 1 : -1;
      if (!end) { preview(); return; }
      v.controls = false; end.hidden = false;
      end.querySelector('[data-next-title]').textContent = next < 0 ? 'That was all of them.' : list[next].title;
      end.querySelector('i').textContent = next < 0 ? 'THE END' : 'UP NEXT';
      end.querySelector('[data-next]').hidden = next < 0;
      const count = end.querySelector('[data-count]'); count.textContent = '';
      if (next < 0) return;
      let n = 5; count.textContent = `starts in ${n}`;
      timer = setInterval(() => { n--; if (n <= 0) start(next); else count.textContent = `starts in ${n}`; }, 1000);
    }
    load(0);
    btn.addEventListener('click', () => start(0));
    document.querySelectorAll('[data-watch]').forEach((w) => w.addEventListener('click', () => { el.scrollIntoView({ block: 'center' }); seen = true; start(0); }));
    v.addEventListener('ended', ended);
    if (end) {
      end.querySelector('[data-next]').addEventListener('click', () => start(cur + 1));
      end.querySelector('[data-replay]').addEventListener('click', () => start(cur));
      end.querySelector('a').addEventListener('click', () => preview());
    }
    if ('IntersectionObserver' in window) new IntersectionObserver((es) => { seen = es[0].isIntersecting; if (!on || !seen) preview(); }, { threshold: .35 }).observe(el);
    else { seen = true; preview(); }

    // MARKETING LINKS — DO NOT REMOVE (they are in emails and posts already sent; see .steerify/README.md).
    //   steerify.dev/?teaser  (or #teaser)   plays the hero film on arrival          ← sent on 20 Nov 2026
    //   steerify.dev/?v=<name>               plays that film: fast-cut, battle, deciding, in-sync, never-lost, high-score
    //   steerify.dev/?v=why-pro | why-simple | getting-started   go to the long videos on tutorial.html
    // Browsers may block sound that starts by itself: then the hero stays on its silent preview under PLAY VIDEO.
    // Redesigning the landing? Keep these working, whatever the player becomes. Check: node scripts/check-video-links.mjs
    const q = new URLSearchParams(location.search);
    const want = q.get('v') || (q.has('teaser') || location.hash === '#teaser' ? list[0].name : '');
    if (want) {
      const long = { 'getting-started': 'start', 'why-simple': 'why-simple', 'why-pro': 'why-pro' };
      if (long[want]) { location.replace('tutorial.html#' + long[want]); return; }
      const i = Math.max(0, list.findIndex((x) => x.name === want));
      el.scrollIntoView({ block: 'center' }); seen = true; start(i);
      v.play().catch(() => { if (i === 0) preview(); });
    }
  });

  const dlg = document.querySelector('.epdlg');
  if (dlg) {
    const v = dlg.querySelector('video'), cap = dlg.querySelector('span');
    const close = () => { v.pause(); v.removeAttribute('src'); v.load(); if (dlg.open) dlg.close(); };
    document.querySelectorAll('[data-ep]').forEach((b) => b.addEventListener('click', () => {
      v.poster = poster(b.dataset.ep); v.src = file(b.dataset.ep);
      cap.textContent = b.querySelector('b').textContent;
      dlg.showModal(); v.play().catch(() => {});
    }));
    dlg.querySelector('[data-close]').addEventListener('click', close);
    dlg.addEventListener('click', (e) => { if (e.target === dlg) close(); });
    dlg.addEventListener('close', () => { v.pause(); });
  }
})();
