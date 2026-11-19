# Teaser (30 s, pixel art + voice)

1. Voice: `ELEVENLABS_API_KEY=… node scripts/voice.mjs site/teaser/teaser.json` (without a key: macOS `say` preview).
2. Video: needs Python + Pillow and the Silkscreen font (OFL) next to `teaser.py`:
   ```sh
   python3 -m venv .venv && .venv/bin/pip install pillow
   curl -sLO https://github.com/google/fonts/raw/main/ofl/silkscreen/Silkscreen-Regular.ttf
   curl -sLO https://github.com/google/fonts/raw/main/ofl/silkscreen/Silkscreen-Bold.ttf
   # timing.json = the voice line lengths: {"durations":[…]} (seconds; the last gets +1.8 s for the end card)
   .venv/bin/python teaser.py silent.mp4 && python3 mux.py ../../site/teaser . ../../site/teaser/teaser.mp4
   ```
Scenes are drawn at 320×180 and scaled ×6 (nearest) to 1920×1080, 24 fps.

## Voice

Recorded with ElevenLabs (voice Sarah); see voice.mjs.
