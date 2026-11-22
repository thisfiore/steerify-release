// Sign-ups → Steerify HQ (relay.steerify.dev/v1/signup, the CMS at /hq), + the 30-second teaser dialog.
// HQ down? The same sign-up goes to Formspree instead (the form id in index.html: data-formspree="xxxxxxxx"),
// so nobody is lost; import Formspree's CSV in HQ later.
(function () {
  // Served locally (python -m http.server 18780 in site/): post to the local HQ (PORT=18767), never the live list.
  const HQ = /^(localhost|127\.0\.0\.1)$/.test(location.hostname) ? 'http://127.0.0.1:18767/v1/signup' : 'https://relay.steerify.dev/v1/signup';
  // Every sign-up form: the Mac updates list (#beta-form), the iPhone TestFlight invite (#ios-form, data-kind="testflight")
  // and the Windows waitlist (#win-form, data-kind="windows").
  document.querySelectorAll('form[data-formspree]').forEach((f) => {
    const msg = f.querySelector('.msg'), btn = f.querySelector('button[type=submit]'), email = f.querySelector('input[type=email]');
    const kind = ['testflight', 'windows'].includes(f.dataset.kind) ? f.dataset.kind : 'newsletter', tf = kind === 'testflight';
    const done = tf ? "Asked. The invite comes from TestFlight, by email." : kind === 'windows' ? "You're on the list. One email if Windows happens." : "Done. We'll write when a new version is out.";
    const say = (t, cls) => { msg.textContent = t; msg.className = 'msg' + (cls ? ' ' + cls : ''); };
    f.addEventListener('submit', async (e) => {
      e.preventDefault();
      const v = email.value.trim();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v)) { say('That email looks off. Try again?', 'err'); email.focus(); return; }
      if (f.elements._gotcha.value) { say(done, 'ok'); return; }
      const id = (f.dataset.formspree || '').trim();
      const url = !id ? '' : /^https?:/.test(id) ? id : 'https://formspree.io/f/' + id;
      btn.disabled = true; say('Sending…');
      try {
        const r = await fetch(HQ, { method: 'POST', signal: AbortSignal.timeout(6000), headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: v, kind, page: location.href, ref: document.referrer }) });
        if (r.status === 422) { say('That email looks off. Try again?', 'err'); email.focus(); btn.disabled = false; return; }
        if (r.ok) { f.reset(); say(done, 'ok'); btn.disabled = false; return; }
      } catch (_) {}
      if (!url) { say("Couldn't send it. Try again in a minute?", 'err'); btn.disabled = false; return; }
      try {
        const body = tf
          ? { email: v, source: 'steerify.dev', kind: 'testflight-ios', _subject: 'Steerify iPhone TestFlight invite: ' + v }
          : kind === 'windows' ? { email: v, source: 'steerify.dev', kind: 'windows', _subject: 'Steerify Windows waitlist: ' + v }
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
