// Beta sign-up ("Ask for the build") → Formspree, + the 30-second teaser dialog.
// The form id lives in index.html: <form id="beta-form" data-formspree="xxxxxxxx"> (or a full URL).
// Empty id = "Sign-ups open very soon", nothing is sent.
(function () {
  // Every sign-up form: the Mac updates list (#beta-form) and the iPhone TestFlight invite (#ios-form, data-kind="testflight").
  document.querySelectorAll('form[data-formspree]').forEach((f) => {
    const msg = f.querySelector('.msg'), btn = f.querySelector('button[type=submit]'), email = f.querySelector('input[type=email]');
    const tf = f.dataset.kind === 'testflight';
    const done = tf ? "Asked. The invite comes from TestFlight, by email." : "Done. We'll write when a new version is out.";
    const say = (t, cls) => { msg.textContent = t; msg.className = 'msg' + (cls ? ' ' + cls : ''); };
    f.addEventListener('submit', async (e) => {
      e.preventDefault();
      const v = email.value.trim();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v)) { say('That email looks off. Try again?', 'err'); email.focus(); return; }
      if (f.elements._gotcha.value) { say(done, 'ok'); return; }
      const id = (f.dataset.formspree || '').trim();
      const url = !id ? '' : /^https?:/.test(id) ? id : 'https://formspree.io/f/' + id;
      if (!url) { say('Sign-ups open very soon. Come back tomorrow?', 'err'); return; }
      btn.disabled = true; say('Sending…');
      try {
        const body = tf
          ? { email: v, source: 'steerify.dev', kind: 'testflight-ios', _subject: 'Steerify iPhone TestFlight invite: ' + v }
          : { email: v, source: 'steerify.dev', _subject: 'Steerify updates: ' + v };
        const r = await fetch(url, { method: 'POST', headers: { 'Accept': 'application/json', 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
        if (!r.ok) {
          const j = await r.json().catch(() => ({}));
          if (r.status === 422 && j.errors && j.errors.some((x) => x.field === 'email')) { say('That email looks off. Try again?', 'err'); email.focus(); btn.disabled = false; return; }
          throw new Error(r.status);
        }
        f.reset(); say(done, 'ok');
      } catch (_) { say("Couldn't send it. Try again in a minute?", 'err'); }
      btn.disabled = false;
    });
  });
  // iPhone card: the ironic headline changes, and pixel Frenk laughs at each new one.
  const rot = document.querySelector('.ip-rot[data-rot]'), face = document.querySelector('.me-laugh');
  if (rot && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
    const lines = rot.dataset.rot.split('|');
    let i = 0;
    setInterval(() => {
      if (document.hidden) return;
      rot.classList.add('out');
      setTimeout(() => {
        i = (i + 1) % lines.length; rot.textContent = lines[i]; rot.classList.remove('out');
        if (face) { face.classList.add('on'); setTimeout(() => face.classList.remove('on'), 1400); }
      }, 260);
    }, 3200);
  }
  const d = document.getElementById('teaser');
  if (d) {
    const v = d.querySelector('video');
    document.querySelectorAll('[data-teaser]').forEach((b) => b.addEventListener('click', () => { d.showModal(); v.play().catch(() => {}); }));
    const close = () => { v.pause(); d.close(); };
    d.querySelector('[data-close]').addEventListener('click', close);
    d.addEventListener('click', (e) => { if (e.target === d) close(); });
    d.addEventListener('close', () => v.pause());
    // The ?teaser / ?v= marketing links now live in videos.js (MARKETING LINKS). Keep them working.
  }
})();
