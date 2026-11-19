// Tutorial Room–style player: one slide per chapter, the voice plays, then the next slide (900 ms after the clip;
// a reading timer when there is no audio). Keys: ← → Space, M voice, C captions.
(async function () {
  const AFTER_VOICE_MS = 900, MIN_READ_MS = 4500, MS_PER_CHAR = 62;
  const doc = await fetch('tutorial/tutorial.json').then((r) => r.json());
  const S = doc.slides, $ = (id) => document.getElementById(id), audio = $('audio');
  let i = 0, playing = false, voice = true, captions = true, timer = null;
  const show = (t) => t.replace(/\[(.+?)\]/g, '<span class="kc">$1</span>');
  $('chapters').innerHTML = S.map((s, k) => `<li><button data-k="${k}"><b>${String(k + 1).padStart(2, '0')}</b>${s.title}</button></li>`).join('');
  $('bar').innerHTML = S.map(() => '<i></i>').join('');
  const prov = S.find((s) => s.audio)?.audio.provider;
  $('voicenote').textContent = prov === 'say' ? 'Voice preview (system voice). The ElevenLabs voice replaces it with one command.' : '';
  function render() {
    const s = S[i];
    $('stage').innerHTML = s.img ? `<img src="${s.img}" alt="${s.title}">` : `<div class="info" data-info="${s.info}"></div>`;
    if (s.info && window.SteerifyInfo) window.SteerifyInfo.paint($('stage'));
    $('chapn').textContent = String(i + 1).padStart(2, '0') + ' · ' + s.title;
    $('caption').innerHTML = captions ? show(s.text) : '';
    [...$('bar').children].forEach((b, k) => b.className = k < i ? 'done' : k === i ? 'on' : '');
    [...$('chapters').querySelectorAll('button')].forEach((b, k) => b.classList.toggle('on', k === i));
    clearTimeout(timer); audio.pause();
    if (!playing) return;
    if (voice && s.audio) { audio.src = 'tutorial/' + s.audio.src; audio.play().catch(() => {}); }
    else timer = setTimeout(next, Math.max(MIN_READ_MS, s.text.length * MS_PER_CHAR));
  }
  function go(k) { i = Math.max(0, Math.min(S.length - 1, k)); render(); }
  function next() { if (i < S.length - 1) go(i + 1); else { playing = false; setPlay(); render(); } }
  function setPlay() { $('playlbl').textContent = playing ? 'Pause' : (i === S.length - 1 ? 'Replay' : 'Play'); }
  audio.addEventListener('ended', () => { if (playing) timer = setTimeout(next, AFTER_VOICE_MS); });
  $('play').onclick = () => { if (!playing && i === S.length - 1) i = 0; playing = !playing; setPlay(); render(); };
  $('next').onclick = () => go(i + 1); $('prev').onclick = () => go(i - 1);
  $('mute').onclick = () => { voice = !voice; $('mute').textContent = voice ? 'Voice on' : 'Voice off'; render(); };
  $('chapters').onclick = (e) => { const b = e.target.closest('button'); if (b) go(+b.dataset.k); };
  addEventListener('keydown', (e) => {
    if (e.target.closest('input,textarea')) return;
    if (e.key === 'ArrowRight') go(i + 1); else if (e.key === 'ArrowLeft') go(i - 1);
    else if (e.key === ' ') { e.preventDefault(); $('play').click(); }
    else if (e.key === 'm' || e.key === 'M') $('mute').click();
    else if (e.key === 'c' || e.key === 'C') { captions = !captions; render(); }
  });
  render();
})();
