// Beta sign-up ("Ask for the build") → Formspree, + the 30-second teaser dialog.
// The form id lives in index.html: <form id="beta-form" data-formspree="xxxxxxxx"> (or a full URL).
// Empty id = "Sign-ups open very soon", nothing is sent.
(function () {
  const f = document.getElementById('beta-form');
  if (f) {
    const msg = f.querySelector('.msg'), btn = f.querySelector('button[type=submit]'), email = f.querySelector('input[type=email]');
    const say = (t, cls) => { msg.textContent = t; msg.className = 'msg' + (cls ? ' ' + cls : ''); };
    f.addEventListener('submit', async (e) => {
      e.preventDefault();
      const v = email.value.trim();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v)) { say('That email looks off. Try again?', 'err'); email.focus(); return; }
      if (f.elements._gotcha.value) { say("Done. We'll write when a new version is out.", 'ok'); return; }
      const id = (f.dataset.formspree || '').trim();
      const url = !id ? '' : /^https?:/.test(id) ? id : 'https://formspree.io/f/' + id;
      if (!url) { say('Sign-ups open very soon. Come back tomorrow?', 'err'); return; }
      btn.disabled = true; say('Sending…');
      try {
        const r = await fetch(url, { method: 'POST', headers: { 'Accept': 'application/json', 'Content-Type': 'application/json' }, body: JSON.stringify({ email: v, source: 'steerify.dev', _subject: 'Steerify updates: ' + v }) });
        if (!r.ok) {
          const j = await r.json().catch(() => ({}));
          if (r.status === 422 && j.errors && j.errors.some((x) => x.field === 'email')) { say('That email looks off. Try again?', 'err'); email.focus(); btn.disabled = false; return; }
          throw new Error(r.status);
        }
        f.reset(); say("Done. We'll write when a new version is out.", 'ok');
      } catch (_) { say("Couldn't send it. Try again in a minute?", 'err'); }
      btn.disabled = false;
    });
  }
  const d = document.getElementById('teaser');
  if (d) {
    const v = d.querySelector('video');
    document.querySelectorAll('[data-teaser]').forEach((b) => b.addEventListener('click', () => { d.showModal(); v.play().catch(() => {}); }));
    const close = () => { v.pause(); d.close(); };
    d.querySelector('[data-close]').addEventListener('click', close);
    d.addEventListener('click', (e) => { if (e.target === d) close(); });
    d.addEventListener('close', () => v.pause());
    // A link that opens the teaser on arrival: steerify.dev/?teaser (or #teaser). Sound autoplay may be blocked by
    // the browser: the video then waits on its poster with the play button. The address is cleaned on close.
    const q = new URLSearchParams(location.search);
    if (q.has('teaser') || location.hash === '#teaser') {
      v.preload = 'auto';
      d.showModal();
      v.play().catch(() => {});
      d.addEventListener('close', () => {
        q.delete('teaser');
        const rest = q.toString();
        history.replaceState(null, '', location.pathname + (rest ? '?' + rest : ''));
      }, { once: true });
    }
  }
})();
