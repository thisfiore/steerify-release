// The landing's menu: "Features" opens a panel of anchors (a dropdown on desktop, a full sheet behind the burger on phones).
// On a phone or tablet there is nothing to install, so the Download button becomes "Send to my Mac": the share sheet
// (AirDrop, Messages, Mail), or an email to yourself where sharing is not available.
(function () {
  const menu = document.getElementById('menu'); if (!menu) return;
  const openers = [...document.querySelectorAll('[data-menu]')], root = document.documentElement;
  const set = (on) => { menu.classList.toggle('open', on); root.classList.toggle('menu-open', on); openers.forEach((b) => b.setAttribute('aria-expanded', on)); };
  openers.forEach((b) => b.addEventListener('click', (e) => { e.stopPropagation(); set(!menu.classList.contains('open')); }));
  menu.addEventListener('click', (e) => { if (e.target.closest('a')) set(false); });
  document.addEventListener('click', (e) => { if (!menu.contains(e.target)) set(false); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') set(false); });

  const touch = matchMedia('(pointer: coarse)').matches && (!/Macintosh/.test(navigator.userAgent) || navigator.maxTouchPoints > 1);
  if (touch) { root.classList.add('no-mac'); document.querySelectorAll('[data-send-swap]').forEach((a) => { a.textContent = 'Send to Mac'; a.setAttribute('data-send', ''); }); }
  const url = 'https://steerify.dev/#get', text = 'Steerify for Mac. Download it here:';
  document.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-send]'); if (!b) return; e.preventDefault(); set(false);
    if (navigator.share) { try { await navigator.share({ title: 'Steerify', text, url }); } catch (_) {} return; }
    location.href = 'mailto:?subject=' + encodeURIComponent('Steerify for Mac') + '&body=' + encodeURIComponent(text + ' ' + url);
  });
})();
