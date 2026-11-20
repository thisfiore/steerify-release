#!/usr/bin/env node
// Voice-over for a tutorial/teaser JSON (one line per slide), the SB Tutorial Room way:
// ElevenLabs eleven_multilingual_v2, mp3_44100_128, one file per slide, skipped when text+voice are unchanged.
//   node scripts/voice.mjs site/tutorial/tutorial.json   (key from env or ~/.config/steerify/elevenlabs.key)
// Without a key it writes a macOS `say` preview (same file names), so timing and the player work today.
import { readFile, writeFile, mkdir, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';

const file = process.argv[2];
if (!file) { console.error('usage: voice.mjs <tutorial.json> [--force]'); process.exit(1); }
const force = process.argv.includes('--force');
const doc = JSON.parse(await readFile(file, 'utf8'));
const dir = join(dirname(file), 'voice'); await mkdir(dir, { recursive: true });
import { homedir } from 'node:os';
// Key: env ELEVENLABS_API_KEY, or a private file ~/.config/steerify/elevenlabs.key (chmod 600), never in the repo.
const keyFile = join(homedir(), '.config/steerify/elevenlabs.key');
const key = process.env.ELEVENLABS_API_KEY || (await readFile(keyFile, 'utf8').then((t) => t.trim(), () => ''));
const v = doc.voice || {};
const spoken = (t) => t.replace(/\[(.+?)\]/g, (_, k) => k.replace('⌘', 'command ').replace('J', 'J'));
const exists = (p) => stat(p).then(() => true, () => false);
const duration = (p) => Number(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', p]).toString().trim());

for (const s of doc.slides) {
  const provider = key ? 'elevenlabs' : 'say';
  const hash = createHash('sha1').update(`${provider}|${v.voiceId}|${s.text}`).digest('hex').slice(0, 10);
  const out = join(dir, `${s.id}.mp3`);
  if (!force && s.audio?.hash === hash && await exists(out)) { console.log(`= ${s.id}`); continue; }
  if (key) {
    const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${v.voiceId}?output_format=mp3_44100_128`, {
      method: 'POST', headers: { 'xi-api-key': key, 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
      body: JSON.stringify({ text: spoken(s.text), model_id: v.model || 'eleven_multilingual_v2', voice_settings: v.settings }),
    });
    if (!r.ok) { console.error(`✕ ${s.id}: ${r.status} ${(await r.text()).slice(0, 200)}`); process.exit(1); }
    await writeFile(out, Buffer.from(await r.arrayBuffer()));
  } else {
    const aiff = out.replace(/\.mp3$/, '.aiff');
    execFileSync('say', ['-v', 'Samantha', '-r', '175', '-o', aiff, spoken(s.text)]);
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', aiff, '-ar', '44100', '-b:a', '128k', out]);
    execFileSync('rm', [aiff]);
  }
  s.audio = { src: `voice/${s.id}.mp3`, hash, provider, durationMs: Math.round(duration(out) * 1000) };
  console.log(`✓ ${s.id} ${provider} ${s.audio.durationMs} ms`);
}
await writeFile(file, JSON.stringify(doc, null, 1) + '\n');
