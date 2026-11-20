// Download button + GitHub star count, read from the public repo (no token; cached 10 minutes per tab).
// [data-dl] href → newest .dmg · [data-dl-meta] → "v0.5.1 · 4.8 MB" · [data-dl-pre] shown for early (not notarized) builds
// [data-brew] shown once the Homebrew cask is in the repo (or with ?brew=1, to preview) · [data-stars] → the count, once there are a few.
(function () {
  const REPO = 'thisfiore/steerify-release', KEY = 'steerify-gh-v2', FORCE_BREW = /[?&]brew=1/.test(location.search);
  const all = (s) => document.querySelectorAll(s);
  function apply(d) {
    all('[data-brew]').forEach((e) => { e.hidden = !(d.cask || FORCE_BREW); });
    if (d.stars >= 10) all('[data-stars]').forEach((e) => { e.textContent = d.stars; e.hidden = false; });
    if (!d.dmg) return;
    all('[data-dl]').forEach((a) => { a.href = d.dmg; });
    all('[data-dl-meta]').forEach((e) => { e.textContent = `v${d.version} · ${d.mb} MB · free and open source`; });
    all('[data-dl-pre]').forEach((e) => { e.hidden = !d.pre; });
  }
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-copy]');
    if (!b) return;
    const done = () => { const was = b.textContent; b.textContent = 'COPIED'; setTimeout(() => { b.textContent = was; }, 1400); };
    if (navigator.clipboard) navigator.clipboard.writeText(b.dataset.copy).then(done, () => {});
  });
  if (FORCE_BREW) all('[data-brew]').forEach((e) => { e.hidden = false; });
  let c = null;
  try { c = JSON.parse(sessionStorage.getItem(KEY)); } catch (_) {}
  if (c && Date.now() - c.at < 6e5) { apply(c); return; }
  const get = (u) => fetch('https://api.github.com/repos/' + REPO + u, { headers: { Accept: 'application/vnd.github+json' } }).then((r) => (r.ok ? r.json() : Promise.reject(r.status)));
  Promise.allSettled([get(''), get('/releases?per_page=10'), get('/contents/Casks/steerify.rb')]).then(([repo, rels, cask]) => {
    const d = { at: Date.now(), cask: cask.status === 'fulfilled' };
    if (repo.status === 'fulfilled') d.stars = repo.value.stargazers_count;
    if (rels.status === 'fulfilled') {
      const dmg = (r) => r.assets.find((a) => /\.dmg$/.test(a.name));
      const r = rels.value.find((x) => !x.draft && dmg(x));
      if (r) { const a = dmg(r); d.dmg = a.browser_download_url; d.version = r.tag_name.replace(/^v/, ''); d.mb = (a.size / 1048576).toFixed(1); d.pre = r.prerelease; }
    }
    apply(d);
    try { sessionStorage.setItem(KEY, JSON.stringify(d)); } catch (_) {}
  });
})();
