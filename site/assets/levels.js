// "Anyone can steer": pick a character, the pixel window shows the same bakery project at that level.
// Same characters as the app (Sources/SteerApp/Level.swift). Rotates by itself until someone picks.
(() => {
  const root = document.querySelector('[data-levels]');
  if (!root) return;
  const C = { k:'#16171c', s:'#f2c79a', h:'#5a3b22', a:'#ffb020', g:'#4ade80', b:'#8fb0ff', c:'#efe6cf', r:'#f87171', m:'#7b7f8a', v:'#c4a7ff', o:'#d97757' };
  const ART = {
    explorer: [[8,3,8,3,'g'],[6,5,12,2,'g'],[8,7,8,6,'s'],[9,9,2,2,'k'],[13,9,2,2,'k'],[10,12,4,1,'o'],[7,13,10,7,'b'],[4,14,3,6,'h'],[17,13,4,4,'a'],[18,14,2,2,'r'],[8,20,3,3,'h'],[13,20,3,3,'h']],
    tinkerer: [[8,3,8,4,'v'],[8,7,8,6,'s'],[8,8,8,3,'m'],[9,9,2,1,'b'],[13,9,2,1,'b'],[10,12,4,1,'k'],[7,13,10,7,'a'],[18,10,2,8,'m'],[17,9,4,2,'m'],[4,15,3,3,'s'],[8,20,3,3,'k'],[13,20,3,3,'k']],
    builder:  [[7,3,10,3,'o'],[7,6,12,1,'o'],[8,7,8,6,'s'],[9,9,2,2,'k'],[13,9,2,2,'k'],[10,12,4,1,'k'],[7,13,10,7,'m'],[3,15,10,6,'c'],[4,16,8,4,'b'],[2,21,12,1,'m'],[13,20,3,3,'k']]
  };
  root.querySelectorAll('canvas[data-px]').forEach(cv => {
    const x = cv.getContext('2d');
    (ART[cv.dataset.px] || []).forEach(([l, t, w, h, c]) => { x.fillStyle = C[c]; x.fillRect(l, t, w, h) });
  });

  // The same moment in the same project (a bakery's new menu page), at each level.
  const L = {
    explorer: { c:'#4ade80', term:'0px', fold:false, pill:'Just the board',
      tabs:['To check','Choices','Plan'],
      done:'Your new menu page is ready. Have a look, then press Publish.',
      ask:'New orders: show them at once, or once an hour?', opts:['At once','Once an hour (free)'], rec:1,
      go:'Publish', steps:'Claude handles the rest',
      diff:['Everyday words','Only what you see or pay','Just the board · Publish'] },
    tinkerer: { c:'#c4a7ff', term:'0px', fold:true, pill:'Terminal folded',
      tabs:['To test','Choices','Roadmap','Release'],
      done:'Menu page done. It goes on your website (Vercel) when you release.',
      ask:'New orders: live with Zapier (€20/month) or read from the sheet every hour (free)?', opts:['Live · Zapier','Hourly · sheet'], rec:1,
      go:'Release', steps:'1 check · 2 publish · 3 live',
      diff:['Plain, tools named','The big ones, costs up front','Terminal folded · Release'] },
    builder: { c:'#d97757', term:'44%', fold:false, pill:'steer/menu ↑2',
      tabs:['To test','Choices','Requirements','Roadmap','Release'],
      done:'Menu page on steer/menu: 3 files, tests green. Merge to main on OK.',
      ask:'Orders: webhook into a Vercel function, or a cron polling the sheet?', opts:['Webhook','Cron · 1 h'], rec:0,
      go:'Release · deploy', steps:'ff-merge main · vercel --prod',
      diff:['Technical, as usual','Every tech choice','Full terminal · branches'] }
  };
  const $ = s => root.querySelector(s);
  const esc = s => s.replace(/[&<>]/g, ch => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;' }[ch]));
  const fade = $('.lv-fade');
  let cur = 'explorer', auto = true;

  function show(k) {
    cur = k;
    const l = L[k];
    root.style.setProperty('--c', l.c);
    root.querySelectorAll('.lv-who').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.lv === k)));
    fade.classList.add('out');
    setTimeout(() => {
      $('.lv-body').style.setProperty('--term', l.term);
      $('.lv-pill').textContent = l.pill;
      $('.lv-tabs').innerHTML = l.tabs.map((t, i) => `<span class="${i ? '' : 'on'}">${esc(t)}</span>`).join('');
      $('[data-done]').textContent = l.done;
      $('[data-ask]').textContent = l.ask;
      $('.lv-opts').innerHTML = l.opts.map((o, i) => `<span class="${i === l.rec ? 'rec' : ''}">${esc(o)}</span>`).join('');
      $('.lv-go').textContent = l.go;
      $('.lv-steps').textContent = l.steps;
      $('.lv-fold').style.display = l.fold ? 'block' : 'none';
      root.querySelectorAll('.lv-diff span').forEach((s, i) => { s.textContent = l.diff[i] });
      fade.classList.remove('out');
    }, 180);
  }
  root.querySelectorAll('.lv-who').forEach(b => b.addEventListener('click', () => { auto = false; show(b.dataset.lv) }));
  const order = ['explorer', 'tinkerer', 'builder'];
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  let seen = false;
  new IntersectionObserver(es => { seen = es.some(e => e.isIntersecting) }).observe(root);
  if (!still) setInterval(() => { if (auto && seen && !document.hidden) show(order[(order.indexOf(cur) + 1) % 3]) }, 4200);
  const forced = new URLSearchParams(location.search).get('level');   // ?level=builder opens on that one (screenshots)
  show(L[forced] ? forced : 'explorer');
  if (L[forced]) auto = false;
})();
