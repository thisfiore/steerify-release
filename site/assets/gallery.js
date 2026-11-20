// Screenshot gallery: <div data-gallery> holding <figure data-label><a href="full.png"><img></a><figcaption>.
// One figure on stage, arrows, thumbnails, arrow keys, swipe, and a click to see it full size. No dependencies.
(function () {
  function mount(el) {
    const figs = [...el.querySelectorAll('figure')];
    if (figs.length < 2) return;
    el.classList.add('gal-on');
    const stage = document.createElement('div'); stage.className = 'gal-stage';
    figs.forEach((f) => stage.appendChild(f));
    const nav = (cls, label, ch) => { const b = document.createElement('button'); b.type = 'button'; b.className = 'gal-nav ' + cls; b.setAttribute('aria-label', label); b.textContent = ch; stage.appendChild(b); return b; };
    const prev = nav('prev', 'Previous screenshot', '<'), next = nav('next', 'Next screenshot', '>');
    const thumbs = document.createElement('div'); thumbs.className = 'gal-thumbs';
    const tbs = figs.map((f, i) => {
      const img = f.querySelector('img'), b = document.createElement('button');
      b.type = 'button'; b.setAttribute('aria-label', 'Show: ' + f.dataset.label);
      b.innerHTML = `<img src="${img.getAttribute('src')}" alt="" loading="lazy" width="320" height="209"><span>${f.dataset.label}</span>`;
      b.addEventListener('click', () => show(i));
      thumbs.appendChild(b);
      const n = document.createElement('i'); n.textContent = `${i + 1} / ${figs.length}`; f.querySelector('figcaption').appendChild(n);
      return b;
    });
    const zoom = document.createElement('dialog'); zoom.className = 'gal-zoom'; zoom.setAttribute('aria-label', 'Screenshot, full size');
    zoom.innerHTML = '<img alt=""><p><span></span><button type="button">CLOSE</button></p>';
    el.append(stage, thumbs, zoom);
    let cur = 0;
    function show(i) {
      cur = (i + figs.length) % figs.length;
      figs.forEach((f, k) => { f.hidden = k !== cur; });
      tbs.forEach((b, k) => { b.classList.toggle('on', k === cur); if (k === cur) b.setAttribute('aria-current', 'true'); else b.removeAttribute('aria-current'); });
      const img = figs[cur].querySelector('img'); img.loading = 'eager';
      if (zoom.open) fill();
    }
    function fill() {
      const f = figs[cur], img = f.querySelector('img');
      zoom.querySelector('img').src = f.querySelector('a').getAttribute('href');
      zoom.querySelector('img').alt = img.alt;
      zoom.querySelector('span').textContent = f.querySelector('figcaption span').textContent;
    }
    prev.addEventListener('click', () => show(cur - 1));
    next.addEventListener('click', () => show(cur + 1));
    figs.forEach((f) => f.querySelector('a').addEventListener('click', (e) => { e.preventDefault(); fill(); zoom.showModal(); }));
    zoom.addEventListener('click', (e) => { if (e.target.tagName !== 'SPAN' && e.target.tagName !== 'P') zoom.close(); });
    const keys = (e) => { if (e.key === 'ArrowLeft') { show(cur - 1); e.preventDefault(); } if (e.key === 'ArrowRight') { show(cur + 1); e.preventDefault(); } };
    el.addEventListener('keydown', keys);
    let x0 = null;
    stage.addEventListener('touchstart', (e) => { x0 = e.touches[0].clientX; }, { passive: true });
    stage.addEventListener('touchend', (e) => { if (x0 == null) return; const dx = e.changedTouches[0].clientX - x0; x0 = null; if (Math.abs(dx) > 50) show(cur + (dx < 0 ? 1 : -1)); });
    show(0);
  }
  function init() { document.querySelectorAll('[data-gallery]').forEach(mount); }
  if (document.readyState !== 'loading') init(); else document.addEventListener('DOMContentLoaded', init);
})();
