/* Steerify prototype engine (generic; do not edit per project — copy it as is).
 *
 * A prototype is one HTML file in <board>/protos/ that loads the project's kit:
 *   <link rel=stylesheet href="../kit/tokens.css"> <link rel=stylesheet href="../kit/components.css">
 *   <script src="../kit/data.js"></script> <script src="../kit/proto.js"></script>
 * and holds one <section> per variant:
 *   <section data-v="today" data-label="Today"> … </section>
 *   <section data-v="A" data-label="Inline note"> … </section>
 *   <section data-v="B" data-label="Side panel"> … </section>
 *
 * What it does:
 *  - a switch bar on top: Today ↔ A / B / C (keys ← →, 1-4, t = Today). Hidden in small views (thumbnails) or with ?bare.
 *  - ?v=B opens on variant B (use it in each option's "proto": "protos/<id>.html?v=B").
 *  - every section is drawn at the design size (data-w × data-h on <body>, default 1200 × 750) and scaled to fit,
 *    so the thumbnail is a miniature of the real screen and the live view is the real screen.
 *  - templating from the sample data (window.KIT_DATA, kit/data.js):
 *      <div data-each="tests">  …{{title}} {{area}}…  </div>   repeats its children per row (data-each="tests:3" = first 3)
 *      {{path.to.value}} anywhere inside a section, filled from KIT_DATA
 *      <x data-if="field"> shown only when the row's field is truthy; data-ifnot the opposite
 *  - data-tap="B" on any element: click jumps to variant B (click-through flows).
 */
(function () {
  const D = window.KIT_DATA || {};
  const qs = new URLSearchParams(location.search);
  const W = +(document.body.dataset.w || 1200), H = +(document.body.dataset.h || 750);

  const get = (o, path) => path.split('.').reduce((a, k) => (a == null ? a : a[k]), o);
  const fillText = (s, row) => s.replace(/\{\{\s*([\w.$]+)\s*\}\}/g, (_, p) => {
    let v = row && get(row, p); if (v == null) v = get(D, p);
    return v == null ? '' : String(v);
  });
  function fill(el, row) {
    // repeaters first (innermost rows resolve against their own row)
    el.querySelectorAll('[data-each]').forEach(rep => {
      if (rep.closest('[data-each-done]')) return;
      const [key, n] = rep.dataset.each.split(':');
      let rows = (row && get(row, key)) || get(D, key) || [];
      if (n) rows = rows.slice(0, +n);
      const tpl = rep.innerHTML; rep.innerHTML = '';
      rows.forEach((r, i) => {
        const box = document.createElement('div'); box.innerHTML = tpl;
        const ctx = Object.assign({ $i: i + 1 }, typeof r === 'object' ? r : { $: r });
        fill(box, ctx);
        while (box.firstChild) rep.appendChild(box.firstChild);
      });
      rep.setAttribute('data-each-done', '');
    });
    el.querySelectorAll('[data-if],[data-ifnot]').forEach(x => {
      const f = x.dataset.if || x.dataset.ifnot; let v = row && get(row, f); if (v == null) v = get(D, f);
      if (x.dataset.if ? !v : v) x.remove(); else { x.removeAttribute('data-if'); x.removeAttribute('data-ifnot'); }
    });
    const walk = n => {
      if (n.nodeType === 3) { if (n.nodeValue.includes('{{')) n.nodeValue = fillText(n.nodeValue, row); return; }
      if (n.nodeType !== 1 || n.hasAttribute('data-each-done') && n !== el) return;
      for (const a of n.attributes) if (a.value.includes('{{')) a.value = fillText(a.value, row);
      n.childNodes.forEach(walk);
    };
    walk(el);
  }

  const secs = [...document.querySelectorAll('body > section[data-v]')];
  secs.forEach(s => fill(s, null));
  const ids = secs.map(s => s.dataset.v);
  let cur = ids.includes(qs.get('v')) ? qs.get('v') : (ids.includes('A') ? 'A' : ids[0]);

  // stage + bar
  const css = document.createElement('style');
  css.textContent = `
  html,body{margin:0;height:100%;overflow:hidden}
  body>section[data-v]{display:none}
  .kit-stage{position:absolute;left:0;right:0;bottom:0;top:0;overflow:hidden}
  .kit-frame{position:absolute;left:0;top:0;transform-origin:0 0;overflow:hidden}
  .kit-bar{position:absolute;left:0;right:0;top:0;height:34px;display:flex;align-items:center;gap:6px;padding:0 10px;
    background:#0d0e11;border-bottom:1px solid #2a2d35;font:600 11.5px -apple-system,system-ui;color:#bdb8aa;z-index:9;box-sizing:border-box}
  .kit-bar b{font:700 9px ui-monospace,Menlo,monospace;letter-spacing:.8px;color:#8f8a7d;margin-right:4px}
  .kit-bar button{all:unset;cursor:pointer;padding:3px 9px;border-radius:6px;border:1px solid #343944;color:#e6e1d4}
  .kit-bar button.on{background:#ffb020;border-color:#ffb020;color:#1a1200}
  .kit-bar button.today.on{background:#8fb0ff;border-color:#8fb0ff;color:#0a1020}
  .kit-bar .sep{width:1px;height:16px;background:#343944;margin:0 4px}
  .kit-bar .lbl{margin-left:6px;color:#8f8a7d;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}`;
  document.head.appendChild(css);

  const stage = document.createElement('div'); stage.className = 'kit-stage';
  const frame = document.createElement('div'); frame.className = 'kit-frame';
  frame.style.width = W + 'px'; frame.style.height = H + 'px';
  stage.appendChild(frame); document.body.appendChild(stage);
  secs.forEach(s => { s.style.width = W + 'px'; s.style.height = H + 'px'; frame.appendChild(s); });

  const bare = qs.has('bare') || innerWidth < 560 || ids.length < 2;
  let bar = null;
  if (!bare) {
    bar = document.createElement('div'); bar.className = 'kit-bar';
    const hasToday = ids.includes('today');
    let html = '<b>PROTOTYPE</b>';
    if (hasToday) html += `<button class="today" data-go="today">Today</button><span class="sep"></span>`;
    ids.filter(v => v !== 'today').forEach(v => { html += `<button data-go="${v}">${v}</button>`; });
    html += '<span class="lbl"></span>';
    bar.innerHTML = html;
    bar.addEventListener('click', e => { const b = e.target.closest('[data-go]'); if (b) show(b.dataset.go); });
    document.body.appendChild(bar);
    stage.style.top = '34px';
  }

  function fit() {
    const r = stage.getBoundingClientRect();
    const k = Math.min(r.width / W, r.height / H);
    frame.style.transform = `scale(${k})`;
    frame.style.left = Math.max(0, (r.width - W * k) / 2) + 'px';
    frame.style.top = Math.max(0, (r.height - H * k) / 2) + 'px';
  }
  function show(v) {
    if (!ids.includes(v)) return; cur = v;
    secs.forEach(s => { s.style.display = s.dataset.v === v ? 'block' : 'none'; });
    if (bar) {
      bar.querySelectorAll('[data-go]').forEach(b => b.classList.toggle('on', b.dataset.go === v));
      const s = secs[ids.indexOf(v)];
      bar.querySelector('.lbl').textContent = s.dataset.label ? (v === 'today' ? '' : v + ' · ') + s.dataset.label : '';
    }
    try { history.replaceState(null, '', '?v=' + v); } catch (e) {}
  }
  addEventListener('resize', fit);
  addEventListener('keydown', e => {
    const i = ids.indexOf(cur);
    if (e.key === 'ArrowRight') show(ids[(i + 1) % ids.length]);
    else if (e.key === 'ArrowLeft') show(ids[(i + ids.length - 1) % ids.length]);
    else if (e.key === 't') show('today');
    else if (/^[1-9]$/.test(e.key) && ids[+e.key - 1]) show(ids[+e.key - 1]);
  });
  document.addEventListener('click', e => { const t = e.target.closest('[data-tap]'); if (t) { e.preventDefault(); show(t.dataset.tap); } });
  show(cur); fit();
  window.KIT = { show, data: D, fill };
})();
