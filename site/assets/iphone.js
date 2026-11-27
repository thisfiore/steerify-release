// The iPhone card: the big phone cycles through the app's screens (Ready, Test, Pick, Resume, Ask, Reply, Squash).
// Pauses on hover / focus and while off screen; a tap on a label jumps there. Reduced motion: no auto-advance.
(function () {
  const f = document.querySelector('[data-rotate]'); if (!f) return;
  const imgs = [...f.querySelectorAll('img')], dots = [...document.querySelectorAll('.ip-dots button')];
  let i = 0, t = null, hold = false, seen = false;
  const show = (n) => { i = (n + imgs.length) % imgs.length; imgs.forEach((im, k) => im.classList.toggle('on', k === i)); dots.forEach((d, k) => d.toggleAttribute('aria-current', k === i)); };
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const tick = () => { clearTimeout(t); if (still || hold || !seen) return; t = setTimeout(() => { show(i + 1); tick(); }, 3200); };
  dots.forEach((d, k) => d.addEventListener('click', () => { show(k); tick(); }));
  const box = f.parentElement;
  box.addEventListener('mouseenter', () => { hold = true; clearTimeout(t); }); box.addEventListener('mouseleave', () => { hold = false; tick(); });
  new IntersectionObserver((es) => { seen = es[0].isIntersecting; tick(); }, { threshold: 0.3 }).observe(f);
})();
