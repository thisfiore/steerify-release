#!/usr/bin/env python3
# Narrated videos for steerify.dev: demo screenshots and pixel cards, a caption per sentence, Frenk's voice, and a pixel
# Frenk in a round bubble who talks and changes expression. 1920x1080, 15 fps (mostly still pictures).
#   python3 scripts/tutorial/video.py getting-started           render it -> site/videos/getting-started.mp4
#   python3 scripts/tutorial/video.py why-pro 1-6               only those slides (segments are cached in build/tutorial/<name>)
#   python3 scripts/tutorial/video.py why-simple --still 7 [k]  build/tutorial/<name>/still-07.png (sentence k, default the last)
# Videos: getting-started (from zero to a first project), why-simple (for people who do not code), why-pro (for developers).
# Needs Pillow, ffmpeg, and three fonts in build/fonts (or $FONT_DIR): Silkscreen-Bold.ttf, Silkscreen-Regular.ttf (OFL,
# github.com/google/fonts) and JetBrainsMono-Regular.ttf (OFL, github.com/JetBrains/JetBrainsMono).
# Words: scripts/tutorial/<name>.json. Voice: scripts/tutorial/voice/<name>/<id>.mp3, one clip per line.
import array, json, os, re, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, '..', '..')
NAME = sys.argv[1] if len(sys.argv) > 1 else 'getting-started'
FONTS = os.environ.get('FONT_DIR', os.path.join(ROOT, 'build', 'fonts')); OUT = os.path.join(ROOT, 'build', 'tutorial', NAME)
W, H, FPS, GAP = 1920, 1080, 15, 0.5
C = dict(bg=(7, 8, 10), bg2=(13, 15, 19), panel=(17, 19, 24), line=(35, 38, 46), line2=(52, 57, 68), cream=(242, 232, 207), amber=(255, 176, 32),
         mute=(110, 114, 126), green=(74, 222, 128), blue=(143, 176, 255), violet=(196, 167, 255), ink=(5, 6, 7), red=(255, 90, 54), grey=(140, 144, 154))
F = lambda name, s: ImageFont.truetype(os.path.join(FONTS, name), s)
PB = lambda s: F('Silkscreen-Bold.ttf', s); PR = lambda s: F('Silkscreen-Regular.ttf', s); MONO = lambda s: F('JetBrainsMono-Regular.ttf', s)
SHOT = lambda n: os.path.join(ROOT, 'site', 'assets', 'shots', 'demo', n + '.png')
STAGE = (48, 110, 1480, 826)   # x, y, w, h of the picture area
FACE = (1326, 610)             # top-left of the face bubble (336 px), over the picture's bottom-right corner

doc = json.load(open(os.path.join(HERE, NAME + '.json')))
SL = doc['slides']
VOICE = lambda i: os.path.join(HERE, 'voice', NAME, SL[i]['id'] + '.mp3')
sentences = lambda t: re.split(r'(?<=[.?!])\s+', t.strip())
def dur(i): return float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', VOICE(i)]).decode())

# ---------- the face: a round "camera" bubble, so it reads as a person talking over the slides.
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
        raw = subprocess.check_output(['ffmpeg', '-loglevel', 'error', '-i', VOICE(i), '-f', 's16le', '-ac', '1', '-ar', '8000', '-'])
        a = array.array('h'); a.frombytes(raw[:len(raw) // 2 * 2]); step = 8000 * 2 // FPS
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

# ---------- card building blocks. Every card is a function(draw, image, k): k = index of the sentence being spoken.
def title(d, text): d.text((110, 170), text, font=PB(54), fill=C['cream'])
def say(d, k, items, top=290):  # big statements, one under the other: (from sentence, text, size, colour)
    y = top
    for at, text, size, col in items:
        ls = wrap(d, text, PB(size), 1180)
        for ln in ls:
            if k >= at: d.text((110, y), ln, font=PB(size), fill=C[col])
            y += int(size * 1.3)
        y += int(size * .45)
def tiles(d, items, k):
    for j, (at, big, small, col) in enumerate(items):
        x = 110 + j * 440; on = k >= at
        d.rectangle([x, 270, x + 400, 590], fill=C['bg2'], outline=C[col] if on else C['line2'], width=4)
        d.text((x + 34, 296), str(j + 1), font=PB(64), fill=C[col] if on else C['line2'])
        for n, ln in enumerate(big): d.text((x + 34, 396 + n * 46), ln, font=PB(34), fill=C['cream'] if on else C['line2'])
        for n, ln in enumerate(small): d.text((x + 34, 508 + n * 32), ln, font=PR(21), fill=C['mute'] if on else C['line'])
def rows(d, head, items, k, foot=None, cols=None):
    title(d, head)
    for j, (at, big, sub) in enumerate(items):
        y = 290 + j * 150; on = k >= at; last = j + 1 == len(items) or k < items[j + 1][0]; col = C[cols[j]] if cols else C['amber']
        d.rectangle([110, y, 1300, y + 126], fill=C['bg2'], outline=col if on and (last or cols) else C['line2'], width=3)
        d.text((150, y + 28), str(j + 1), font=PB(64), fill=col if on else C['line2'])
        d.text((250, y + 26), big, font=PB(34), fill=C['cream'] if on else C['line2'])
        d.text((250, y + 80), sub, font=PR(23), fill=C['mute'] if on else C['line'])
    if foot: d.text((110, 290 + len(items) * 150 + 10), foot, font=PR(24), fill=C['mute'])
def wall(d, x, y, cols, rws, amber=(), cw=92, ch=40):  # a wall of little terminals; some of them waiting (amber)
    for r in range(rws):
        for c in range(cols):
            i = r * cols + c; a = [x + c * (cw + 8), y + r * (ch + 8), x + c * (cw + 8) + cw, y + r * (ch + 8) + ch]; on = i in amber
            d.rectangle(a, fill=C['panel'], outline=C['amber'] if on else C['line2'], width=3 if on else 2)
            d.rectangle([a[0] + 8, a[1] + 10, a[0] + 8 + 20 + (i * 13) % 50, a[1] + 14], fill=C['amber'] if on else C['mute'])
            d.rectangle([a[0] + 8, a[1] + 22, a[0] + 8 + 14 + (i * 7) % 40, a[1] + 26], fill=C['line2'])
def terminal(d, lines, k, head, foot=None):
    title(d, head)
    d.rectangle([110, 250, 1420, 760], fill=C['ink'], outline=C['line2'], width=3); d.rectangle([113, 253, 1417, 300], fill=C['panel'])
    for j, col in enumerate([C['red'], C['amber'], C['green']]): d.ellipse([134 + j * 34, 266, 154 + j * 34, 286], fill=col)
    d.text((765, 276), 'Terminal', font=MONO(24), fill=C['mute'], anchor='mm')
    for at, y, prompt, text, size, col in lines:
        if k < at: continue
        if prompt: d.text((150, y), '$', font=MONO(size), fill=C['amber'])
        d.text((196 if prompt else 150, y), text, font=MONO(size), fill=C[col])
    if foot: d.text((110, 800), foot, font=PR(22), fill=C['mute'])
def tree(d, k, head, items, foot=None, foot_at=0):
    title(d, head)
    d.rectangle([110, 250, 1420, 800], fill=C['ink'], outline=C['line2'], width=3)
    for j, (t, col, note, at) in enumerate(items):
        if k < at: continue
        d.text((160, 280 + j * 56), t, font=MONO(34), fill=C[col])
        if note: d.text((720, 286 + j * 56), note, font=MONO(26), fill=C['green'] if col == 'amber' else C['mute'])
    if foot and k >= foot_at: d.text((110, 830), foot, font=PR(24), fill=C['green'])
def house(d, x, y, s, col):   # a small pixel house: body, roof, door
    d.rectangle([x, y, x + 12 * s, y + 8 * s], fill=col)
    for r in range(6): d.rectangle([x - s + r * s, y - (r + 1) * s, x + 13 * s - r * s, y - r * s], fill=C['amber'])
    d.rectangle([x + 5 * s, y + 3 * s, x + 7 * s, y + 8 * s], fill=C['ink'])
def castle(d, x, y, s, col):  # three towers with teeth, a gate
    for tx, th in ((0, 14), (8, 10), (16, 14)):
        d.rectangle([x + tx * s, y - th * s, x + (tx + 6) * s, y], fill=col)
        for c in range(3): d.rectangle([x + (tx + c * 2 + .3) * s, y - (th + 1.4) * s, x + (tx + c * 2 + 1.5) * s, y - th * s], fill=col)
    d.rectangle([x + 9.5 * s, y - 5 * s, x + 12.5 * s, y], fill=C['ink']); d.rectangle([x + 2 * s, y - 10 * s, x + 4 * s, y - 7 * s], fill=C['ink']); d.rectangle([x + 18 * s, y - 10 * s, x + 20 * s, y - 7 * s], fill=C['ink'])

# ---------- getting-started
def gs_title(d, im, k):
    d.text((120, 300), 'GETTING', font=PB(150), fill=C['cream']); d.text((120, 470), 'STARTED', font=PB(150), fill=C['amber'])
    d.text((124, 680), 'FROM ZERO TO YOUR FIRST PROJECT', font=PB(40), fill=C['cream']); d.text((124, 750), 'ABOUT TWO AND A HALF MINUTES. NO EXPERIENCE NEEDED.', font=PR(28), fill=C['mute'])
def gs_three(d, im, k):
    title(d, 'YOU NEED THREE THINGS')
    tiles(d, [(1, ['A MAC'], ['MACOS 15 OR LATER'], 'cream'), (2, ['CLAUDE', 'CODE'], ['THE AI THAT BUILDS'], 'amber'), (3, ['STEERIFY'], ['WHERE YOU STEER IT', 'AND CHECK ITS WORK'], 'green')], k)
def gs_terminal(d, im, k):
    terminal(d, [(3, 350, 1, 'curl -fsSL https://claude.ai/install.sh | bash', 40, 'cream'), (3, 420, 0, 'paste, press Enter, wait a minute', 28, 'mute'),
                 (4, 520, 1, 'claude', 40, 'cream'), (4, 590, 0, 'then sign in with your Claude account', 28, 'mute'), (5, 690, 0, 'That is all the Terminal you need.', 28, 'green')],
             k, 'INSTALL CLAUDE CODE', 'THE COMMAND IS FROM THE CLAUDE CODE DOCS: CODE.CLAUDE.COM/DOCS')
def gs_install(d, im, k):
    rows(d, 'INSTALL STEERIFY', [(1, 'STEERIFY.DEV > DOWNLOAD FOR MAC', 'IT IS FREE AND OPEN SOURCE'), (1, 'OPEN THE FILE, DRAG IT TO APPLICATIONS', 'LIKE ANY OTHER MAC APP'),
                                 (2, 'MAC COMPLAINS THE FIRST TIME?', 'SYSTEM SETTINGS > PRIVACY & SECURITY > OPEN ANYWAY')], k)
def gs_own(d, im, k):
    rows(d, 'YOUR OWN PROJECT', [(1, 'DRAG YOUR FOLDER ONTO STEERIFY', 'ANY FOLDER, EVEN AN EMPTY ONE'), (3, 'SET UP WITH CLAUDE', 'ONE BUTTON. CLAUDE READS YOUR PROJECT'),
                                 (4, 'THE BOARD FILLS IN WHILE YOU WATCH', 'THEN CLAUDE ASKS YOU QUESTIONS, WITH PICTURES')], k, 'ABOUT TEN MINUTES. STOP AND RESUME ANY TIME.')
def gs_folder(d, im, k):
    tree(d, k, 'THE BOARD LIVES IN YOUR FOLDER', [('my-project/', 'cream', '', 0), ('├─ index.html', 'mute', '', 0), ('├─ app.js', 'mute', '', 0), ('└─ .steerify/', 'amber', 'the board', 2),
         ('   ├─ board.json', 'cream', 'choices, requirements, roadmap', 2), ('   ├─ decisions.json', 'cream', 'your picks and verdicts', 2), ('   └─ delivered.json', 'cream', 'the To test tab', 2)],
         'DELETE STEERIFY AND IT IS ALL STILL YOURS.', 3)
def gs_tasks(d, im, k):
    rows(d, 'TASKS, THE NEWEST TAB', [(1, 'THINGS CLAUDE DOES THAT ARE NOT CODE', 'A REPORT. A WEEKLY CHECK.'), (4, 'IT HANDS IN A RESULT', 'YOU SAY OK, OR REDO')], k,
         'ADDED AFTER THE SCREENSHOTS IN THIS VIDEO WERE TAKEN.')
def gs_loop(d, im, k):
    title(d, 'THAT IS THE WHOLE LOOP')
    for j, (t, col) in enumerate([('YOU SAY IT', 'cream'), ('YOU PICK', 'cream'), ('CLAUDE BUILDS', 'amber'), ('YOU LOOK', 'cream'), ('IT SHIPS', 'green')]):
        x = 110 + j * 266; on = k >= j + 1
        d.rectangle([x, 300, x + 246, 440], fill=C['bg2'], outline=(C[col] if on else C['line2']), width=4)
        ls = t.split(' ', 1) if len(t) > 9 else [t]
        for n, ln in enumerate(ls): d.text((x + 123, 370 + (n - (len(ls) - 1) / 2) * 44), ln, font=PB(30), fill=C[col] if on else C['line2'], anchor='mm')
    if k >= 6:
        d.rectangle([110, 490, 1420, 620], fill=C['bg2'], outline=C['amber'], width=3); d.text((150, 512), 'LOST?  PRESS  COMMAND + J', font=PB(40), fill=C['amber'])
        d.text((150, 572), 'IT TAKES YOU TO THE NEXT THING WAITING ON YOU', font=PR(24), fill=C['mute'])
    if k >= 8: d.text((110, 680), 'STEERIFY.DEV', font=PB(90), fill=C['cream']); d.text((114, 800), 'SOMEONE HAS TO HOLD THE WHEEL.', font=PR(30), fill=C['amber'])

# ---------- why-simple (for people who do not code)
def ws_builder(d, im, k):
    say(d, k, [(0, 'THE FASTEST BUILDER IN THE WORLD', 64, 'cream'), (2, 'ONE SMALL PROBLEM.', 44, 'mute'), (3, 'HE NEVER ASKS WHAT YOU WANTED.', 54, 'amber')], 180)
    if k >= 1: house(d, 860, 720, 16, C['cream'])
def ws_castle(d, im, k):
    title(d, 'MEET CLAUDE')
    d.text((180, 300), 'YOU ASKED FOR', font=PR(28), fill=C['mute']); house(d, 230, 620, 14, C['cream']); d.text((180, 760), 'A DOG HOUSE', font=PB(36), fill=C['cream'])
    if k >= 3: d.text((700, 300), 'YOU GOT', font=PR(28), fill=C['mute']); castle(d, 720, 730, 22, C['amber']); d.text((700, 760), 'A CASTLE', font=PB(36), fill=C['amber'])
    if k >= 4: d.text((700, 812), 'A VERY NICE CASTLE.', font=PR(26), fill=C['mute'])
def ws_wall(d, im, k):
    title(d, '99 BUILDERS, ALL AT ONCE')
    wall(d, 110, 270, 11, 9, amber=(13, 47, 82) if k >= 2 else ())
    if k >= 3: d.text((110, 720), '3 ARE WAITING ON YOU. WHICH 3?', font=PB(44), fill=C['amber'])
def ws_clipboard(d, im, k):
    title(d, 'STEERIFY IS THE CLIPBOARD')
    d.rectangle([110, 270, 1300, 680], fill=C['bg2'], outline=C['cream'], width=4); d.rectangle([580, 240, 830, 300], fill=C['cream'])
    for j, (at, head, col, lines) in enumerate([(2, 'HERE IS MY QUESTION', 'amber', ['WHICH HOME PAGE?', 'HOW DO DATES SHOW?']), (3, 'HERE IS WHAT I FINISHED', 'green', ['THE FIRST VERSION', 'THE ORDER PAGE'])]):
        x = 160 + j * 570
        if k < at: continue
        d.text((x, 350), head, font=PB(34), fill=C[col])
        for n, ln in enumerate(lines): d.rectangle([x, 430 + n * 110, x + 510, 430 + n * 110 + 84], fill=C['panel'], outline=C[col], width=3); d.text((x + 28, 456 + n * 110), ln, font=PR(28), fill=C['cream'])
def ws_type(d, im, k):
    title(d, 'SAY WHAT YOU WANT')
    d.rectangle([110, 330, 1420, 470], fill=C['ink'], outline=C['amber'], width=4)
    if k >= 1: d.text((160, 372), 'A WEBSITE FOR MY BAKERY', font=PB(52), fill=C['cream'])
    if k >= 3: d.text((110, 540), 'NORMAL WORDS. LIKE YOU WOULD SAY IT TO A PERSON.', font=PR(30), fill=C['mute'])
def ws_coffee(d, im, k):
    say(d, k, [(0, 'CLAUDE BUILDS.', 90, 'amber'), (1, 'YOU DO SOMETHING ELSE.', 54, 'cream'), (2, 'COFFEE IS A VALID CHOICE.', 44, 'mute')], 220)
    if k >= 2:
        d.rectangle([1040, 600, 1220, 780], fill=C['cream']); d.rectangle([1220, 640, 1280, 740], outline=C['cream'], width=18); d.rectangle([1060, 620, 1200, 660], fill=(110, 70, 40))
        for s in range(3): d.rectangle([1080 + s * 50, 520, 1092 + s * 50, 580], fill=C['mute'])
def ws_ok(d, im, k):
    title(d, 'YOU SAY OK')
    d.rectangle([110, 320, 520, 520], fill=C['green']); d.text((315, 420), 'OK', font=PB(120), fill=C['ink'], anchor='mm')
    if k >= 1:
        for j in range(6): d.rectangle([560 + j * 40, 412, 584 + j * 40, 428], fill=C['green'])
        d.rectangle([820, 320, 1420, 520], fill=C['bg2'], outline=C['green'], width=4); d.text((1120, 420), 'IT IS LIVE', font=PB(64), fill=C['green'], anchor='mm')
        d.text((110, 580), 'ONE BUTTON.', font=PR(30), fill=C['mute'])
def ws_tasks(d, im, k):
    rows(d, 'NOT ONLY BUILDING', [(1, 'EVERY MONDAY: A REPORT', 'YOU ASK ONCE'), (1, 'HE HANDS IT IN', 'FOR YOU TO CHECK: OK, OR REDO'), (2, 'LIKE HOMEWORK', 'HIS HOMEWORK')], k)
def ws_never(d, im, k):
    title(d, 'WHAT YOU NEVER DO')
    for j, (t, at) in enumerate([('READ CODE', 0), ('SCROLL A THOUSAND LINES OF CHAT', 1)]):
        if k >= at: d.text((110, 290 + j * 80), t, font=PB(44), fill=C['mute']); d.rectangle([100, 314 + j * 80, 120 + d.textlength(t, font=PB(44)), 320 + j * 80], fill=C['red'])
    for j, t in enumerate(['YOU LOOK.', 'YOU CHOOSE.', 'YOU SAY SHIP.']):
        if k >= j + 2: d.text((110, 500 + j * 100), t, font=PB(72), fill=C['green'] if j == 2 else C['cream'])
def end_card(lines):
    def f(d, im, k):
        ic = ICON.resize((160, 160), Image.LANCZOS); im.paste(ic, (110, 240), ic); d.text((310, 320), 'STEERIFY', font=PB(110), fill=C['cream'], anchor='lm')
        y = 470
        for at, t, size, col in lines:
            if k >= at: d.text((110, y), t, font=PB(size), fill=C[col])
            y += int(size * 1.5)
    return f

# ---------- why-pro (for people with 99 terminals)
def wp_hook(d, im, k):
    wall(d, 110, 150, 11, 6, amber=(7, 30, 52))
    say(d, k, [(0, '99 CLAUDE SESSIONS IN A TERMINAL.', 50, 'cream'), (1, 'I DID TOO.', 40, 'mute'), (2, 'HERE IS WHAT REPLACED MY TAB BAR.', 50, 'amber')], 500)
def wp_state(d, im, k):
    rows(d, 'THE PROBLEM IS STATE, NOT SPEED', [(2, 'WHICH SESSION IS ON WHAT', 'NINETY-NINE TABS, ONE TITLE EACH: "CLAUDE"'), (3, 'WHAT IT ASSUMED', 'IT DID NOT ASK. IT GUESSED'),
                                                (4, 'WHAT IS WAITING ON ME', 'SOMEWHERE IN THE SCROLLBACK'), (5, 'WHAT IS ACTUALLY DONE', 'AND WHAT ONLY SAYS IT IS')], k)
def wp_board(d, im, k):
    tree(d, k, 'ONE BOARD, AS JSON, IN YOUR REPO', [('my-repo/.steerify/', 'amber', 'the board', 1), ('├─ board.json', 'cream', 'choices, requirements, roadmap', 2), ('├─ decisions.json', 'cream', 'your picks, notes, verdicts', 2),
         ('├─ delivered.json', 'cream', 'the To test tab', 2), ('├─ requests.json', 'cream', 'what you asked, where it went', 2), ('├─ tasks.json', 'cream', 'tasks and their runs', 2),
         ('└─ steerify.json', 'cream', 'repos, release, environments', 2)], 'SESSIONS READ AND WRITE IT: A CLAUDE CODE SKILL + AN MCP SERVER.', 3)
def wp_sessions(d, im, k):
    rows(d, 'SESSIONS ON THE ROADMAP', [(0, 'ONE ITEM, ONE SESSION, ALREADY BRIEFED', 'IN THE RIGHT REPO'), (2, 'ROWING', 'CLAUDE IS WORKING'), (3, 'YOUR TURN', 'IT WAITS ON YOU: TEST, ANSWER, RELEASE'),
                                        (4, 'DONE', 'NOTHING LEFT THAT LIVES ONLY IN ITS CHAT')], k, cols=['amber', 'blue', 'violet', 'grey'])
def wp_git(d, im, k):
    title(d, 'GIT, YOUR WAY, PER PROJECT')
    tiles(d, [(1, ['ON MAIN'], ['ONE FOLDER, ONE BRANCH', 'SIMPLE PROJECTS'], 'cream'), (2, ['WORKTREE', 'PER FEATURE'], ['OWN FOLDER, OWN BRANCH', 'MERGED AFTER YOUR OK'], 'blue'),
              (3, ['BRANCH +', 'PULL REQUEST'], ['PUSHED, OPENED AS A PR', 'YOUR OK MERGES IT'], 'green')], k)
def wp_release(d, im, k):
    rows(d, 'RELEASE', [(0, 'WHAT YOU APPROVED WAITS HERE', 'NOTHING SHIPS WITHOUT YOUR OK'), (1, 'ONE CLICK: COMMIT, PUSH, DEPLOY', 'YOUR DEPLOY COMMAND, IN A VISIBLE TERMINAL TAB'),
                        (2, 'A LIVE CHECK URL', 'ITEMS TURN LIVE WHEN THE DEPLOYED COMMIT CATCHES UP')], k)
def wp_tasks(d, im, k):
    rows(d, 'TASKS: OUTCOMES, NOT CODE', [(2, 'A REPORT. A DATA PULL. A TUTORIAL.', 'WITH YOUR TOOLS. ONCE, OR ON A SCHEDULE'), (6, 'A RUN COUNTS WHEN A RESULT IS HANDED IN', 'SUMMARY, FILES, EACH CHECK MET OR NOT'),
                                          (6, 'YOU SAY OK, OR REDO', 'TASKS NEVER GO ON THE ROADMAP'), (7, 'NO RESULT BY THE DEADLINE?', 'STEERIFY TELLS YOU, WITH A RETRY')], k)
def wp_next(d, im, k):
    rows(d, 'WHAT NOW?', [(0, 'THE NEXT STRIP', 'AT MOST TWO THINGS TO DO NOW, ONE BUTTON EACH'), (1, 'A PING IN THE APP', 'WHEN A SESSION DELIVERS, OR NEEDS YOU')], k)
def wp_end(d, im, k):
    say(d, k, [(1, '99 SESSIONS IS FINE.', 60, 'mute'), (2, '99 SESSIONS AND ONE BOARD IS BETTER.', 60, 'cream')], 200)
    if k >= 3: ic = ICON.resize((120, 120), Image.LANCZOS); im.paste(ic, (110, 560), ic); d.text((260, 620), 'STEERIFY.DEV', font=PB(80), fill=C['amber'], anchor='lm')
    if k >= 4: d.text((114, 730), 'FREE. OPEN SOURCE. FOR MAC.', font=PR(32), fill=C['cream'])

TAB = dict(ready=(30, 88, 150, 56), test=(204, 88, 240, 56), choices=(468, 88, 240, 56), reqs=(732, 88, 276, 56), road=(1026, 88, 198, 56), release=(1242, 88, 198, 56))
LEFT, RIGHT = (0, 150, 1636, 1806), (1650, 150, 1350, 1806)
BOTH = [(LEFT, 'THE BOARD', 'blue'), (RIGHT, 'CLAUDE CODE', 'amber')]
BAR = [((24, 82, 1424, 68), '', 'amber')]
T = lambda name: [(TAB[name], '', 'amber')]
# A screen is (shot, highlights per sentence, tag): shot may be a list of (from sentence, shot); '*' = every sentence.
VIEWS = {
 'getting-started': {
    'l01': gs_title, 'l02': gs_three, 'l03': gs_terminal, 'l04': gs_install, 'l05': ('choices', {}, 'TINY TODO, THE DEMO PROJECT'), 'l06': gs_own,
    'l07': ('roadmap', {2: [(RIGHT, 'CLAUDE CODE, A REAL TERMINAL', 'amber')], 3: [(LEFT, 'THE BOARD', 'blue')], 4: BOTH, 5: BOTH}, None), 'l08': gs_folder,
    'l09': ('ready', {1: BAR, 2: BAR}, None), 'l10': ('choices', {'*': T('choices')}, None), 'l11': ('requirements', {'*': T('reqs')}, None),
    'l12': ('roadmap', {'*': T('road')}, None), 'l13': ('test', {'*': T('test')}, None), 'l14': ('release', {'*': T('release')}, None), 'l14b': gs_tasks,
    'l15': ('ready', {'*': T('ready')}, None), 'l16': ('new-request', {}, None), 'l17': gs_loop },
 'why-simple': {
    'a01': ws_builder, 'a02': ws_castle, 'a03': ws_wall, 'a04': ws_clipboard, 'a05': ws_type, 'a06': ('choice-making', {}, 'LIKE THIS, THIS, OR THIS?'), 'a07': ws_coffee,
    'a08': ('test-preview', {}, 'DOES THIS LOOK RIGHT?'), 'a09': ws_ok, 'a10': ws_tasks, 'a11': ws_never,
    'a12': end_card([(1, 'YOU DECIDE.', 70, 'cream'), (2, 'CLAUDE BUILDS.', 70, 'amber'), (3, 'FREE. FOR MAC. STEERIFY.DEV', 40, 'green')]) },
 'why-pro': {
    'b01': wp_hook, 'b02': wp_state, 'b03': wp_board, 'b04': ('new-request', {}, 'FIX / REFINEMENT / FEATURE / QUESTION'), 'b05': ([(0, 'choices'), (1, 'choice-making')], {0: T('choices')}, 'SUGGESTED. BLEND. NOTE.'),
    'b06': ('requirements', {'*': T('reqs')}, 'YOUR OK ON A DELIVERY MARKS THEM BUILT'), 'b07': wp_sessions, 'b08': wp_git,
    'b09': ([(0, 'test'), (4, 'test-preview')], {0: T('test')}, 'THE LINK MUST OPEN THE FEATURE ITSELF'), 'b10': wp_release, 'b11': wp_tasks, 'b12': wp_next,
    'b13': ('ready', {1: [((180, 610, 1290, 400), 'WHERE YOU LEFT OFF', 'amber')], 2: [((180, 610, 1290, 400), 'WHERE YOU LEFT OFF', 'amber')], 3: [((180, 610, 1290, 400), 'COMMAND J: THE NEXT THING', 'amber')]}, None),
    'b14': wp_end },
}
VIEW = VIEWS[NAME]
# Expression per sentence (default: brow up on a question, smirk on the last line, plain otherwise). 4 = smirk that ends in a grin.
MOODS = {
 'getting-started': {'l01': [3, 4, 2, 0, 1, 4], 'l02': [0, 0, 3, 4], 'l03': [0, 0, 2, 0, 0, 4], 'l04': [0, 0, 2], 'l05': [0, 1, 3, 4], 'l06': [1, 0, 4, 0, 3, 0, 0, 3],
    'l07': [1, 4, 0, 0, 0, 3], 'l08': [1, 3, 0, 4], 'l09': [0, 0, 4], 'l10': [0, 0, 3, 3], 'l13': [0, 0, 1, 3, 2, 3], 'l14': [0, 0, 4], 'l14b': [3, 0, 0, 0, 4], 'l15': [3, 0, 4],
    'l16': [1, 0, 3], 'l17': [0, 0, 0, 3, 0, 3, 1, 0, 3, 4]},
 'why-simple': {'a01': [1, 3, 2, 4], 'a02': [0, 3, 0, 2, 4], 'a03': [1, 0, 2, 4], 'a04': [3, 0, 1, 4], 'a05': [3, 0, 0, 4], 'a06': [0, 2, 3, 1, 4], 'a07': [0, 3, 4],
    'a08': [0, 1, 3], 'a09': [3, 4], 'a10': [0, 3, 4, 4], 'a11': [2, 2, 0, 3, 4], 'a12': [3, 0, 3, 4]},
 'why-pro': {'b01': [2, 3, 4], 'b02': [0, 0, 2, 2, 1, 3], 'b05': [0, 0, 3], 'b06': [0, 0, 0, 4], 'b07': [0, 0, 3, 1, 4], 'b09': [0, 0, 2, 3], 'b11': [3, 0, 0, 0, 0, 0, 0, 4],
    'b13': [2, 0, 0, 3], 'b14': [1, 2, 4, 3, 4]},
}
MOOD = MOODS.get(NAME, {})
def mood(i, k):
    s = sentences(SL[i]['text']); m = MOOD.get(SL[i]['id'])
    if m and k < len(m): return m[k]
    return 1 if s[k].endswith('?') else 3 if k == len(s) - 1 else 0
def face(i, k, t, st, T_):  # (expression, mouth) at time t of slide i
    m = mood(i, k); talk = loud(i, t); end = st[k + 1] if k + 1 < len(st) else T_ - GAP + 0.15
    if t - st[k] < 0.3 and k > 0 and m == 0: m = 1                      # a little brow pop at the start of a plain sentence
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
    d.text((116, 50), 'STEERIFY', font=PB(30), fill=C['cream'], anchor='lm'); d.text((330, 51), doc.get('label', '').upper(), font=PR(22), fill=C['mute'], anchor='lm')
    d.text((W - 48, 50), f"{i + 1:02d} / {len(SL)}   {s['chapter'].upper()}", font=PB(26), fill=C['amber'], anchor='rm')
    seg = (W - 96) / len(SL)
    for j in range(len(SL)): d.rectangle([48 + j * seg, 92, 48 + (j + 1) * seg - 6, 97], fill=C['green'] if j < i else C['amber'] if j == i else C['line'])
    # stage
    v = VIEW[s['id']]
    if callable(v): v(d, im, k)
    else:
        name, hl, tag = v
        if not isinstance(name, str): name = [n for at, n in name if k >= at][-1]
        pic, sc = shot(name); x, y, w, h = STAGE; px, py = x + (w - pic.width) // 2, y + (h - pic.height) // 2
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
    os.makedirs(OUT, exist_ok=True); T_, st = times(i); out = os.path.join(OUT, f'seg-{i + 1:02d}.mp4')
    ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
                           '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'veryfast', '-g', str(FPS * 2), out], stdin=subprocess.PIPE)
    cache = {}
    for f in range(round(T_ * FPS)):
        t = f / FPS; k = max(j for j, x in enumerate(st) if x <= t or j == 0); who = face(i, k, t, st, T_); key = (k, int(t * 2) % 2, who)
        if key not in cache: cache[key] = frame(i, k, key[1], who).tobytes()
        ff.stdin.write(cache[key])
    ff.stdin.close(); ff.wait(); return T_

def main():
    args = sys.argv[2:]
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
        inputs += ['-i', VOICE(i)]; ms = int((starts[i] + 0.15) * 1000); filt.append(f'[{i + 1}:a]adelay={ms}|{ms}[a{i}]')
    filt.append(''.join(f'[a{i}]' for i in range(len(SL))) + f'amix=inputs={len(SL)}:normalize=0,loudnorm=I=-16,apad[a]')
    dest = os.path.join(ROOT, 'site', 'videos', NAME + '.mp4')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', silent, *inputs, '-filter_complex', ';'.join(filt), '-map', '0:v', '-map', '[a]', '-c:v', 'copy',
                    '-c:a', 'aac', '-b:a', '160k', '-shortest', '-movflags', '+faststart', dest], check=True)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-ss', '4', '-i', dest, '-frames:v', '1', '-vf', 'scale=1280:-2', '-q:v', '3', os.path.join(ROOT, 'site', 'videos', 'posters', NAME + '.jpg')], check=True)
    chapters = [dict(id=s['id'], t=round(starts[i], 2), label=s['chapter']) for i, s in enumerate(SL)]
    json.dump(dict(title=doc['title'], seconds=round(sum(lens), 1), chapters=chapters), open(os.path.join(ROOT, 'site', 'tutorial', NAME + '.json'), 'w'), indent=1)
    print('total', round(sum(lens), 1), '->', dest)

if __name__ == '__main__': main()
