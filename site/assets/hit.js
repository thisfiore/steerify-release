// Anonymous traffic → Steerify HQ (relay.steerify.dev/v1/hit, the Traffic tab at /hq).
// No cookies, nothing stored in the browser, no IP kept on the server: one beacon per page, plus download and
// outbound-link clicks. Open any page with #hq-ignore to stop counting this browser (#hq-count to start again).
(() => {
  try {
    if (location.hash === '#hq-ignore') localStorage.setItem('hq-ignore', '1');
    if (location.hash === '#hq-count') localStorage.removeItem('hq-ignore');
    if (localStorage.getItem('hq-ignore')) return;
  } catch {}
  const root = document.documentElement.dataset;
  if (root.moved) return; // 404.html is sending a clean URL to its page: that page counts the view
  const local = /^(localhost|127\.0\.0\.1)$/.test(location.hostname);
  const U = local ? 'http://127.0.0.1:18767/v1/hit' : 'https://relay.steerify.dev/v1/hit';
  let tz = ''; try { tz = Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch {}
  const send = (e, x) => {
    const b = JSON.stringify({ e, x, nf: root.notFound ? 1 : undefined, u: location.href, r: document.referrer, w: innerWidth, tz });
    try { if (navigator.sendBeacon && navigator.sendBeacon(U, b)) return; } catch {}
    fetch(U, { method: 'POST', body: b, keepalive: true, mode: 'no-cors' }).catch(() => {});
  };
  send('view');
  document.addEventListener('click', (ev) => {
    const a = ev.target.closest && ev.target.closest('a[href]');
    if (!a) return;
    if (/\.dmg(\?|$)/i.test(a.href)) send('download', a.href.split('/').pop().split('?')[0]);
    else if (a.host && a.host !== location.host) send('out', a.host.replace(/^www\./, '') + a.pathname.split('/').slice(0, 3).join('/'));
  }, true);
})();
