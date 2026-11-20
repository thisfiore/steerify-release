#!/usr/bin/env python3
# Getting-started video (about 2.5 min): the demo screenshots and a few pixel cards, a caption per sentence, the voice,
# and a pixel Frenk in the corner who changes expression. 1920x1080, 15 fps (it is mostly still pictures).
#   python3 scripts/tutorial/getting-started.py            render everything -> site/videos/getting-started.mp4
#   python3 scripts/tutorial/getting-started.py 1-6        render only those slides (segments are cached in build/tutorial)
#   python3 scripts/tutorial/getting-started.py --still 7  write build/tutorial/still-07.png (the slide's last frame)
# Needs Pillow, ffmpeg, and three fonts in build/fonts (or $FONT_DIR): Silkscreen-Bold.ttf, Silkscreen-Regular.ttf (OFL,
# github.com/google/fonts) and JetBrainsMono-Regular.ttf (OFL, github.com/JetBrains/JetBrainsMono).
# Words: scripts/tutorial/lines.json. Voice: scripts/tutorial/voice/<id>.mp3, one per line.
import json, os, re, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, '..', '..')
FONTS = os.environ.get('FONT_DIR', os.path.join(ROOT, 'build', 'fonts')); OUT = os.path.join(ROOT, 'build', 'tutorial')
W, H, FPS, GAP = 1920, 1080, 15, 0.5
C = dict(bg=(7, 8, 10), bg2=(13, 15, 19), panel=(17, 19, 24), line=(35, 38, 46), line2=(52, 57, 68), cream=(242, 232, 207), amber=(255, 176, 32),
         mute=(110, 114, 126), green=(74, 222, 128), blue=(143, 176, 255), ink=(5, 6, 7), red=(255, 90, 54))
F = lambda name, s: ImageFont.truetype(os.path.join(FONTS, name), s)
PB = lambda s: F('Silkscreen-Bold.ttf', s); PR = lambda s: F('Silkscreen-Regular.ttf', s); MONO = lambda s: F('JetBrainsMono-Regular.ttf', s)
SHOT = lambda n: os.path.join(ROOT, 'site', 'assets', 'shots', 'demo', n + '.png')
STAGE = (48, 110, 1480, 826)              # x, y, w, h of the picture area
FACE = (1326, 610)                        # top-left of the face bubble (336 px), over the picture's bottom-right corner

doc = json.load(open(os.path.join(HERE, 'lines.json')))
SL = doc['slides']
sentences = lambda t: re.split(r'(?<=[.?!])\s+', t.strip())
def dur(i):
    p = os.path.join(HERE, 'voice', SL[i]['id'] + '.mp3')
    return float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', p]).decode())

# The face: a round "camera" bubble over the corner of the picture, so it reads as a person talking over the slides.
# frenk.png holds four expressions (0 plain, 1 brow up, 2 unimpressed, 3 smirk) on a 48x48 pixel grid; the mouth is
# redrawn on top (small / big while the voice is loud, a grin with teeth for the jokes), then everything is scaled x6.
CELLS = Image.open(os.path.join(ROOT, 'site', 'assets', 'frenk.png')).convert('RGB').resize((192, 48), Image.NEAREST)
MOUTH = {0: (24, 30, 40), 1: (24, 30, 40), 2: (24, 31, 39), 3: (24, 31, 39)}   # x0, x1 (exclusive), middle row
DARK, TONGUE, TEETH, CAM = (58, 22, 24), (196, 92, 96), (245, 240, 228), (24, 28, 38)
_bubbles = {}
def bubble(expr, mouth):
    if (expr, mouth) in _bubbles: return _bubbles[(expr, mouth)]
    f = CELLS.crop((expr * 48, 0, expr * 48 + 48, 48)).copy(); p = f.load(); x0, x1, y = MOUTH[expr]; bg = p[0, 0]
    for yy in range(48):
        for xx in range(48):
            if p[xx, yy] == bg: p[xx, yy] = CAM
    if mouth == 1:
        for x in range(x0 + 1, x1 - 1): p[x, y] = DARK
    if mouth == 2:
        for yy in (y - 1, y, y + 1):
            for x in range(x0 + (yy != y), x1 - (yy != y)): p[x, yy] = DARK
        for x in range(x0 + 2, x1 - 2): p[x, y + 1] = TONGUE
    if mouth == 3:
        for x in range(x0, x1): p[x, y - 1] = TEETH if x0 < x < x1 - 1 else DARK; p[x, y] = DARK
    n = 56; out = Image.new('RGBA', (n, n), (0, 0, 0, 0)); q = out.load(); c = 25.5   # 48 face cells + ring + room for the shadow
    for yy in range(n):
        for xx in range(n):
            r = ((xx - c) ** 2 + (yy - c) ** 2) ** .5; rs = ((xx - c - 3) ** 2 + (yy - c - 3) ** 2) ** .5
            if r <= 24: q[xx, yy] = f.getpixel((min(47, max(0, xx - 2)), min(47, max(0, yy - 2)))) + (255,)
            elif r <= 25.6: q[xx, yy] = C['amber'] + (255,)
            elif rs <= 25.6 and (xx + yy) % 2 == 0: q[xx, yy] = (0, 0, 0, 255)   # a pixelated shadow, down and to the right
    _bubbles[(expr, mouth)] = out.resize((n * 6, n * 6), Image.NEAREST); return _bubbles[(expr, mouth)]

_env = {}
def loud(i, t):  # 0 quiet, 1 speaking, 2 speaking loudly, from the voice clip itself (sampled 7.5 times a second)
    if i not in _env:
        raw = subprocess.check_output(['ffmpeg', '-loglevel', 'error', '-i', os.path.join(HERE, 'voice', SL[i]['id'] + '.mp3'), '-f', 's16le', '-ac', '1', '-ar', '8000', '-'])
        import array; a = array.array('h'); a.frombytes(raw[:len(raw) // 2 * 2]); step = 8000 * 2 // FPS
        rms = [(sum(v * v for v in a[j:j + step]) / max(1, len(a[j:j + step]))) ** .5 for j in range(0, len(a), step)]; top = max(rms) or 1
        _env[i] = [0 if v < .12 * top else 1 if v < .45 * top else 2 for v in rms]
    j = int((t - 0.15) * FPS / 2)
    return _env[i][j] if t >= 0.15 and 0 <= j < len(_env[i]) else 0
ICON = Image.open(os.path.join(ROOT, 'site', 'assets', 'icons', 'icon-256.png')).convert('RGBA')

def wrap(d, text, font, width):
    out, cur = [], ''
    for w in text.split():
        t = (cur + ' ' + w).strip()
        if d.textlength(t, font=font) <= width or not cur: cur = t
        else: out.append(cur); cur = w
    return out + [cur] if cur else out

# ---------- what each slide shows. Screens: (shot, highlights per sentence, tag). Cards: a function(draw, image, k), k = sentence index.
TAB = dict(ready=(30, 88, 150, 56), test=(204, 88, 240, 56), choices=(468, 88, 240, 56), reqs=(732, 88, 276, 56), road=(1026, 88, 198, 56), release=(1242, 88, 198, 56))
def card_title(d, im, k):
    d.text((120, 300), 'GETTING', font=PB(150), fill=C['cream']); d.text((120, 470), 'STARTED', font=PB(150), fill=C['amber'])
    d.text((124, 680), 'FROM ZERO TO YOUR FIRST PROJECT', font=PB(40), fill=C['cream'])
    d.text((124, 750), 'ABOUT TWO MINUTES. NO EXPERIENCE NEEDED.', font=PR(28), fill=C['mute'])
def tiles(d, items, k):
    for j, (at, big, small, col) in enumerate(items):
        x = 110 + j * 470; on = k >= at
        d.rectangle([x, 300, x + 420, 720], fill=C['bg2'], outline=col if on else C['line2'], width=4)
        d.text((x + 34, 340), str(j + 1), font=PB(72), fill=col if on else C['line2'])
        for n, ln in enumerate(big): d.text((x + 34, 470 + n * 58), ln, font=PB(44), fill=C['cream'] if on else C['line2'])
        for n, ln in enumerate(small): d.text((x + 34, 610 + n * 36), ln, font=PR(24), fill=C['mute'] if on else C['line'])
def card_three(d, im, k):
    d.text((110, 170), 'YOU NEED THREE THINGS', font=PB(54), fill=C['cream'])
    tiles(d, [(1, ['A MAC'], ['MACOS 15 OR LATER'], C['cream']), (2, ['CLAUDE', 'CODE'], ['THE AI THAT BUILDS'], C['amber']), (3, ['STEERIFY'], ['WHERE YOU STEER IT', 'AND CHECK ITS WORK'], C['green'])], k)
def card_terminal(d, im, k):
    d.text((110, 150), 'INSTALL CLAUDE CODE', font=PB(54), fill=C['cream'])
    d.rectangle([110, 250, 1420, 760], fill=C['ink'], outline=C['line2'], width=3); d.rectangle([113, 253, 1417, 300], fill=C['panel'])
    for j, col in enumerate([C['red'], C['amber'], C['green']]): d.ellipse([134 + j * 34, 266, 154 + j * 34, 286], fill=col)
    d.text((765, 276), 'Terminal', font=MONO(24), fill=C['mute'], anchor='mm')
    if k >= 3:
        d.text((150, 350), '$', font=MONO(40), fill=C['amber']); d.text((196, 350), 'curl -fsSL https://claude.ai/install.sh | bash', font=MONO(40), fill=C['cream'])
        d.text((150, 420), 'paste, press Enter, wait a minute', font=MONO(28), fill=C['mute'])
    if k >= 4:
        d.text((150, 520), '$', font=MONO(40), fill=C['amber']); d.text((196, 520), 'claude', font=MONO(40), fill=C['cream'])
        d.text((150, 590), 'then sign in with your Claude account', font=MONO(28), fill=C['mute'])
    if k >= 5: d.text((150, 690), 'That is all the Terminal you need.', font=MONO(28), fill=C['green'])
    d.text((110, 800), 'THE COMMAND IS FROM THE CLAUDE CODE DOCS: CODE.CLAUDE.COM/DOCS', font=PR(22), fill=C['mute'])
def rows(d, title, items, k, foot=None):
    d.text((110, 170), title, font=PB(54), fill=C['cream'])
    for j, (at, head, sub) in enumerate(items):
        y = 300 + j * 160; on = k >= at; last = j + 1 == len(items) or k < items[j + 1][0]
        d.rectangle([110, y, 1420, y + 130], fill=C['bg2'], outline=C['amber'] if on and last else C['line2'], width=3)
        d.text((150, y + 30), str(j + 1), font=PB(64), fill=C['amber'] if on else C['line2'])
        d.text((250, y + 28), head, font=PB(36), fill=C['cream'] if on else C['line2'])
        d.text((250, y + 82), sub, font=PR(24), fill=C['mute'] if on else C['line'])
    if foot: d.text((110, 300 + len(items) * 160 + 10), foot, font=PR(24), fill=C['mute'])
def card_install(d, im, k):
    rows(d, 'INSTALL STEERIFY', [(1, 'STEERIFY.DEV > DOWNLOAD FOR MAC', 'IT IS FREE AND OPEN SOURCE'), (1, 'OPEN THE FILE, DRAG IT TO APPLICATIONS', 'LIKE ANY OTHER MAC APP'),
                                 (2, 'MAC COMPLAINS THE FIRST TIME?', 'SYSTEM SETTINGS > PRIVACY & SECURITY > OPEN ANYWAY')], k)
def card_own(d, im, k):
    rows(d, 'YOUR OWN PROJECT', [(1, 'ADD PROJECT > PICK ANY FOLDER', 'EVEN AN EMPTY ONE'), (3, 'SET UP WITH CLAUDE', 'ONE BUTTON. IT STARTS A CLAUDE SESSION FOR YOU'),
                                 (4, 'CLAUDE READS IT AND ASKS YOU', 'WHAT IT UNDERSTOOD, THEN QUESTIONS WITH PICTURES')], k, 'ABOUT TEN MINUTES. STOP AND RESUME ANY TIME.')
def card_folder(d, im, k):
    d.text((110, 150), 'THE BOARD LIVES IN YOUR FOLDER', font=PB(54), fill=C['cream'])
    d.rectangle([110, 250, 1420, 800], fill=C['ink'], outline=C['line2'], width=3)
    tree = [('my-project/', C['cream'], '', 0), ('├─ index.html', C['mute'], '', 0), ('├─ app.js', C['mute'], '', 0), ('└─ .steerify/', C['amber'], 'the board', 2),
            ('   ├─ board.json', C['cream'], 'choices, requirements, roadmap', 2), ('   ├─ decisions.json', C['cream'], 'your picks and verdicts', 2),
            ('   └─ delivered.json', C['cream'], 'the To test tab', 2)]
    for j, (t, col, note, at) in enumerate(tree):
        if k < at: continue
        d.text((160, 290 + j * 62), t, font=MONO(38), fill=col)
        if note: d.text((760, 296 + j * 62), note, font=MONO(28), fill=C['green'] if j == 3 else C['mute'])
    if k >= 3: d.text((110, 830), 'DELETE STEERIFY AND IT IS ALL STILL YOURS.', font=PR(24), fill=C['green'])
def card_loop(d, im, k):
    d.text((110, 170), 'THAT IS THE WHOLE LOOP', font=PB(54), fill=C['cream'])
    for j, (t, col) in enumerate([('YOU SAY IT', C['cream']), ('YOU PICK', C['cream']), ('CLAUDE BUILDS', C['amber']), ('YOU LOOK', C['cream']), ('IT SHIPS', C['green'])]):
        x = 110 + j * 266; on = k >= j + 1
        d.rectangle([x, 300, x + 246, 440], fill=C['bg2'], outline=(col if on else C['line2']), width=4)
        ls = t.split(' ', 1) if len(t) > 9 else [t]
        for n, ln in enumerate(ls): d.text((x + 123, 370 + (n - (len(ls) - 1) / 2) * 44), ln, font=PB(30), fill=col if on else C['line2'], anchor='mm')
    if k >= 6:
        d.rectangle([110, 490, 1420, 620], fill=C['bg2'], outline=C['amber'], width=3); d.text((150, 512), 'LOST?  PRESS  COMMAND + J', font=PB(40), fill=C['amber'])
        d.text((150, 572), 'IT TAKES YOU TO THE NEXT THING WAITING ON YOU', font=PR(24), fill=C['mute'])
    if k >= 8: d.text((110, 680), 'STEERIFY.DEV', font=PB(90), fill=C['cream']); d.text((114, 800), 'SOMEONE HAS TO HOLD THE WHEEL.', font=PR(30), fill=C['amber'])
LEFT, RIGHT = (0, 150, 1636, 1806), (1650, 150, 1350, 1806)
BOTH = [(LEFT, 'THE BOARD', 'blue'), (RIGHT, 'CLAUDE CODE', 'amber')]
BAR = [((24, 82, 1424, 68), '', 'amber')]
VIEW = {
    'l01': card_title, 'l02': card_three, 'l03': card_terminal, 'l04': card_install,
    'l05': ('choices', {}, 'TINY TODO, THE DEMO PROJECT'), 'l06': card_own,
    'l07': ('roadmap', {2: [(RIGHT, 'CLAUDE CODE, A REAL TERMINAL', 'amber')], 3: [(LEFT, 'THE BOARD', 'blue')], 4: BOTH, 5: BOTH}, None),
    'l08': card_folder,
    'l09': ('ready', {1: BAR, 2: BAR}, None),
    'l10': ('choices', {'*': [(TAB['choices'], '', 'amber')]}, None), 'l11': ('requirements', {'*': [(TAB['reqs'], '', 'amber')]}, None),
    'l12': ('roadmap', {'*': [(TAB['road'], '', 'amber')]}, None), 'l13': ('test', {'*': [(TAB['test'], '', 'amber')]}, None),
    'l14': ('release', {'*': [(TAB['release'], '', 'amber')]}, None), 'l15': ('ready', {'*': [(TAB['ready'], '', 'amber')]}, None),
    'l16': ('new-request', {}, None), 'l17': card_loop,
}
# Expression per sentence (default: brow up on a question, smirk on the last line, plain otherwise). 4 = smirk that ends in a grin.
MOOD = {'l01': [3, 4, 2, 0, 1, 4], 'l02': [0, 0, 3, 4], 'l03': [0, 0, 2, 0, 0, 4], 'l04': [0, 0, 2], 'l05': [0, 1, 3, 4], 'l06': [1, 0, 4, 0, 0, 3, 3],
        'l07': [1, 4, 0, 0, 0, 3], 'l08': [1, 3, 0, 4], 'l09': [0, 0, 4], 'l10': [0, 0, 3, 3], 'l13': [0, 0, 1, 3, 2, 3], 'l14': [0, 0, 4], 'l15': [3, 0, 4],
        'l16': [1, 0, 3], 'l17': [0, 0, 0, 3, 0, 3, 1, 0, 3, 4]}
def mood(i, k):
    s = sentences(SL[i]['text']); m = MOOD.get(SL[i]['id'])
    if m and k < len(m): return m[k]
    return 1 if s[k].endswith('?') else 3 if k == len(s) - 1 else 0
def face(i, k, t, st, T):  # (expression, mouth) at time t of slide i
    m = mood(i, k); talk = loud(i, t); end = st[k + 1] if k + 1 < len(st) else T - GAP + 0.15
    if t - st[k] < 0.3 and k > 0 and m == 0: m = 1                # a little brow pop at the start of a plain sentence
    if m == 4: return (3, talk if talk else 3 if t > end - 0.5 else 0)  # the grin lands as the line ends
    return (m, talk)

_shots = {}
def shot(name):
    if name not in _shots:
        im = Image.open(SHOT(name)).convert('RGB'); x, y, w, h = STAGE
        sc = min(w / im.width, h / im.height); _shots[name] = (im.resize((round(im.width * sc), round(im.height * sc)), Image.LANCZOS), sc)
    return _shots[name]

def frame(i, k, pulse, who=(0, 0)):
    s = SL[i]; im = Image.new('RGB', (W, H), C['bg']); d = ImageDraw.Draw(im)
    # right column: where we are
    d.text((1500, 150), f'{i + 1:02d}', font=PB(120), fill=C['amber'])
    for n, ln in enumerate(wrap(d, s['chapter'].upper(), PB(30), 380)[:4]): d.text((1500, 310 + n * 44), ln, font=PB(30), fill=C['cream'])
    # top bar + progress
    ic = ICON.resize((56, 56), Image.LANCZOS); im.paste(ic, (44, 22), ic)
    d.text((116, 50), 'STEERIFY', font=PB(30), fill=C['cream'], anchor='lm'); d.text((330, 51), 'GETTING STARTED', font=PR(22), fill=C['mute'], anchor='lm')
    d.text((W - 48, 50), f"{i + 1:02d} / {len(SL)}   {s['chapter'].upper()}", font=PB(26), fill=C['amber'], anchor='rm')
    seg = (W - 96) / len(SL)
    for j in range(len(SL)): d.rectangle([48 + j * seg, 92, 48 + (j + 1) * seg - 6, 97], fill=C['green'] if j < i else C['amber'] if j == i else C['line'])
    # stage
    v = VIEW[s['id']]
    if callable(v): v(d, im, k)
    else:
        name, hl, tag = v; pic, sc = shot(name); x, y, w, h = STAGE; px, py = x + (w - pic.width) // 2, y + (h - pic.height) // 2
        im.paste(pic, (px, py)); d.rectangle([px - 2, py - 2, px + pic.width + 1, py + pic.height + 1], outline=C['line2'], width=2)
        for (rx, ry, rw, rh), label, col in hl.get(k, hl.get('*', [])):
            a = [px + rx * sc, py + ry * sc, px + (rx + rw) * sc, py + (ry + rh) * sc]
            d.rectangle(a, outline=C[col], width=7 if pulse else 4)
            if label:
                tw = d.textlength(label, font=PB(30)); d.rectangle([a[0] + 16, a[1] + 16, a[0] + 44 + tw, a[1] + 72], fill=C[col]); d.text((a[0] + 30, a[1] + 26), label, font=PB(30), fill=C['ink'])
        if tag:
            tw = d.textlength(tag, font=PB(30)); d.rectangle([px + 24, py + pic.height - 84, px + 56 + tw, py + pic.height - 24], fill=C['amber'])
            d.text((px + 40, py + pic.height - 72), tag, font=PB(30), fill=C['ink'])
    # caption: the sentence being spoken
    d.rectangle([0, 954, W, H], fill=C['bg2']); d.rectangle([0, 954, W, 955], fill=C['line'])
    ls = wrap(d, sentences(s['text'])[k].upper(), PR(30), W - 96)[:3]
    for n, ln in enumerate(ls): d.text((48, 1017 + (n - (len(ls) - 1) / 2) * 40), ln, font=PR(30), fill=C['cream'], anchor='lm')
    # the face, in its round bubble
    b = bubble(*who); im.paste(b, FACE, b)
    return im

def times(i):  # (slide length, sentence start times)
    a = dur(i); s = sentences(SL[i]['text']); n = sum(len(x) for x in s); t, out = 0.15, []
    for x in s: out.append(t); t += a * len(x) / n
    return a + GAP, out

def render(i):
    os.makedirs(OUT, exist_ok=True); T, st = times(i); out = os.path.join(OUT, f'seg-{i + 1:02d}.mp4')
    ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
                           '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'veryfast', '-g', str(FPS * 2), out], stdin=subprocess.PIPE)
    cache = {}
    for f in range(round(T * FPS)):
        t = f / FPS; k = max(j for j, x in enumerate(st) if x <= t or j == 0); who = face(i, k, t, st, T); key = (k, int(t * 2) % 2, who)
        if key not in cache: cache[key] = frame(i, k, key[1], who).tobytes()
        ff.stdin.write(cache[key])
    ff.stdin.close(); ff.wait(); return T

def main():
    args = sys.argv[1:]
    if args[:1] == ['--still']:
        i = int(args[1]) - 1; k = int(args[2]) if len(args) > 2 else len(sentences(SL[i]['text'])) - 1
        who = (int(args[3]), int(args[4])) if len(args) > 4 else (mood(i, k) % 4, 0)
        os.makedirs(OUT, exist_ok=True); frame(i, k, 1, who).save(os.path.join(OUT, f'still-{i + 1:02d}.png')); return
    todo = range(len(SL))
    if args and re.fullmatch(r'\d+-\d+', args[0]): a, b = args[0].split('-'); todo = range(int(a) - 1, int(b))
    for i in todo: print(SL[i]['id'], round(render(i), 2), flush=True)
    if not all(os.path.exists(os.path.join(OUT, f'seg-{j + 1:02d}.mp4')) for j in range(len(SL))): return
    # join the segments, lay the voice lines at their slide starts
    lens = [times(i)[0] for i in range(len(SL))]; starts = [sum(lens[:i]) for i in range(len(SL))]
    lst = os.path.join(OUT, 'list.txt'); open(lst, 'w').write(''.join(f"file 'seg-{i + 1:02d}.mp4'\n" for i in range(len(SL))))
    silent = os.path.join(OUT, 'silent.mp4'); subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', silent], check=True)
    inputs, filt = [], []
    for i in range(len(SL)):
        inputs += ['-i', os.path.join(HERE, 'voice', SL[i]['id'] + '.mp3')]; ms = int((starts[i] + 0.15) * 1000); filt.append(f'[{i + 1}:a]adelay={ms}|{ms}[a{i}]')
    filt.append(''.join(f'[a{i}]' for i in range(len(SL))) + f'amix=inputs={len(SL)}:normalize=0,loudnorm=I=-16,apad[a]')
    dest = os.path.join(ROOT, 'site', 'videos', 'getting-started.mp4')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', silent, *inputs, '-filter_complex', ';'.join(filt), '-map', '0:v', '-map', '[a]', '-c:v', 'copy',
                    '-c:a', 'aac', '-b:a', '160k', '-shortest', '-movflags', '+faststart', dest], check=True)
    chapters = [dict(id=s['id'], t=round(starts[i], 2), label=s['chapter']) for i, s in enumerate(SL)]
    json.dump(dict(title=doc['title'], seconds=round(sum(lens), 1), chapters=chapters), open(os.path.join(ROOT, 'site', 'tutorial', 'getting-started.json'), 'w'), indent=1)
    print('total', round(sum(lens), 1), '->', dest)

if __name__ == '__main__': main()
