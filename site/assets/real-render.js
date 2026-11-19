// Renders the real Steerify board data (assets/real.js) into the "A real day / choice / note" sections.
(function () {
  const R = window.STEERIFY_REAL; if (!R) return;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const $ = (id) => document.getElementById(id);
  const ev = R.timeline, ch = ev.filter((e) => e.k === 'choice'), te = ev.filter((e) => e.k === 'test');
  const ok = te.filter((e) => e.verdict === 'ok').length, broken = te.filter((e) => e.verdict === 'broken').length;
  const [h0, m0] = ev[0].t.split(':').map(Number), [h1, m1] = ev[ev.length - 1].t.split(':').map(Number);
  const hrs = Math.round((h1 * 60 + m1 - h0 * 60 - m0) / 60);
  if ($('stats')) $('stats').innerHTML = [[ch.length, 'choices answered'], [te.length, 'deliveries tested'], [ok, 'marked OK'], [broken, 'broken'], [hrs + ' H', `${ev[0].t} → ${ev[ev.length - 1].t}, one afternoon`]]
    .map(([n, l]) => `<div class="stat"><b>${esc(n)}</b><span>${esc(l)}</span></div>`).join('');
  if ($('timeline')) $('timeline').innerHTML = ev.map((e) => e.k === 'choice'
    ? `<li class="ev choice"><time>${e.t}</time><span class="pill amber">YOU PICKED</span><span class="t">${esc(e.title)}</span><span class="r">${esc(e.pick)}</span></li>`
    : `<li class="ev test"><time>${e.t}</time><span class="pill blue">TO TEST</span><span class="t">${esc(e.title)}</span><span class="r ok">✓ OK${e.v > 1 ? ` · v${e.v}` : ''}</span></li>`).join('');
  const B = R.brand;
  if ($('brand-title')) $('brand-title').textContent = B.title;
  if ($('brand-opts')) $('brand-opts').innerHTML = B.options.map((o) => `<div class="opt${o.id === B.pick ? ' on' : ''}">
      <div class="mock"><div class="in">${o.mock}</div></div>
      <div class="ol"><span>${esc(o.label)}</span>${o.rec ? '<span class="pill amber">SUGGESTED</span>' : ''}${o.id === B.pick ? '<span class="pill green">PICKED</span>' : ''}</div></div>`).join('');
  if ($('brand-note')) $('brand-note').textContent = '“' + B.note + '”';
  if ($('landing-note')) $('landing-note').innerHTML = R.landingNote.split('\n').map(esc).join('<br>');
  // Mockups were drawn for a 600×380 card: scale each to its box.
  const fit = () => document.querySelectorAll('.opt .mock').forEach((m) => { m.firstElementChild.style.transform = `scale(${m.clientWidth / 600})`; });
  fit(); addEventListener('resize', fit);
})();
