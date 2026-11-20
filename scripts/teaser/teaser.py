# Steerify teaser: pixel art at 320x180, scaled x6 (nearest) to 1920x1080, 24 fps.
# Scene lengths come from timing.json (seconds per voice line); frames are piped to ffmpeg.
import json, math, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
W, H, S, FPS = 320, 180, 6, 24
C = dict(bg=(7, 8, 10), bg2=(13, 15, 19), panel=(17, 19, 24), line=(52, 57, 68), cream=(242, 232, 207), amber=(255, 176, 32),
         mute=(74, 78, 88), green=(74, 222, 128), blue=(143, 176, 255), red=(255, 90, 54), ink=(5, 6, 7), sea=(16, 24, 40), sea2=(22, 34, 56))
F8 = ImageFont.truetype(os.path.join(HERE, 'Silkscreen-Regular.ttf'), 8)
F16 = ImageFont.truetype(os.path.join(HERE, 'Silkscreen-Bold.ttf'), 16)
F24 = ImageFont.truetype(os.path.join(HERE, 'Silkscreen-Bold.ttf'), 24)

SPR = {
    'boat': ['........c.........', '........cc........', '........ccc.......', '........cccc......', '........ccccc.....', '........cccccc....',
             '........ccccccc...', '........c.........', '.aaaaaaaaaaaaaaaa.', '..aaaaaaaaaaaaaa..', '...aaaaaaaaaaaa...'],
    'dizzy': ['...cccccc...', '..cccccccc..', '.cckckckcccc', '.ccckcckcccc'[:12], '.cckckckcccc', '.cccccccccc.', '.cccrrrrccc.', '..cccccccc..', '...cccccc...'],
    'cat': ['c.....c...', 'cc...cc...', 'ccccccc...', 'ckccckc...', 'ccccacc..c', '.ccccc...c', '.ccccc..c.', '.ccccc.c..', '.ccccccc..', '.cc.cc....'],
}
PAL = dict(c=C['cream'], a=C['amber'], k=C['ink'], r=C['red'], g=C['green'], b=C['blue'], m=C['mute'])


def wheel_cells():
    out, n, c = [], 17, 8
    for y in range(n):
        for x in range(n):
            dx, dy = x - c, y - c
            r = math.hypot(dx, dy); a = math.atan2(dy, dx)
            k = round(a / (math.pi / 4)); da = abs(a - k * math.pi / 4) * r
            col = None
            if r <= 2.2: col = 'a'
            elif 4.6 <= r <= 5.9: col = 'c'
            elif da < 0.55 and r <= 7.4: col = 'c'
            elif 7.4 < r <= 8.3 and da < 0.9: col = 'c'
            if col: out.append((x, y, col))
    return out
WHEEL = wheel_cells()


class Frame:
    def __init__(self):
        self.im = Image.new('RGB', (W, H), C['bg']); self.d = ImageDraw.Draw(self.im)
    def rect(self, x, y, w, h, col): self.d.rectangle([int(x), int(y), int(x) + int(w) - 1, int(y) + int(h) - 1], fill=col)
    def box(self, x, y, w, h, fill=C['panel'], edge=C['line']): self.rect(x, y, w, h, edge); self.rect(x + 1, y + 1, w - 2, h - 2, fill)
    def text(self, x, y, s, col=C['cream'], f=F8, anchor='la'): self.d.text((int(x), int(y)), s, font=f, fill=col, anchor=anchor)
    def spr(self, name, x, y, k=1, pal=None):
        P = dict(PAL, **(pal or {}))
        for j, row in enumerate(SPR[name]):
            for i, ch in enumerate(row):
                if ch in P: self.rect(x + i * k, y + j * k, k, k, P[ch])
    def wheel(self, x, y, k=1):
        for (cx, cy, col) in WHEEL: self.rect(x + cx * k, y + cy * k, k, k, C['amber'] if col == 'a' else C['cream'])
    def out(self): return self.im.resize((W * S, H * S), Image.NEAREST)


def ease(t): return 1 - (1 - min(max(t, 0), 1)) ** 3
def typed(s, t, cps=22): return s[:max(0, int(t * cps))]


def sea(f, t):
    for i in range(0, 12):
        x = (i * 37 + 11) % W; y = (i * 23 + 7) % 60
        if (int(t * 2) + i) % 5: f.rect(x, y, 1, 1, C['mute'])
    f.rect(0, 120, W, 60, C['sea'])
    for i in range(0, W, 12):
        off = int(3 * math.sin(t * 2 + i * 0.3))
        f.rect(i + off, 126 + (i // 12 % 3) * 14, 6, 1, C['sea2'])


def s1(f, t, T):  # nine sessions. fine, nineteen. okay, ninety-nine. three are waiting
    sea(f, t)
    t19, t99, tw, tg = T * 0.27, T * 0.44, T * 0.66, T * 0.86
    n = 9 if t < t19 else 19 if t < t99 else 99
    slots = [(30 + i * 32, 106) for i in range(9)] + [(14 + j * 30, 124) for j in range(10)]
    for y in (74, 88, 140, 152, 164):
        slots += [(6 + c * 22 + (8 if y % 4 else 0), y) for c in range(14)]
    slots += [(162 + c * 22, 60) for c in range(7)] + [(262 + c * 20, 44) for c in range(3)]
    marks = []
    for i, (x, y) in enumerate(slots[:99]):
        born = 0 if i < 9 else t19 + (i - 9) * 0.03 if i < 19 else t99 + (i - 19) * 0.012
        if t < born: continue
        bob = int(2 * math.sin(t * 2.4 + i))
        f.spr('boat', x, y + bob)
        if i in (1, 4, 7) and t > tw and int(t * 3) % 2 == 0: marks.append((x, y + bob))
    for x, y in marks:  # the three waiting on you, somewhere in the crowd
        f.rect(x + 5, y - 19, 8, 15, C['bg']); f.rect(x + 8, y - 17, 2, 7, C['amber']); f.rect(x + 8, y - 8, 2, 2, C['amber'])
    x = 16
    for old, at in (('9', t19), ('19', t99)):
        if t >= at:
            w = int(f.d.textlength(old, font=F16)); f.text(x, 14, old, (128, 132, 142), F16); f.rect(x - 1, 24, w + 2, 2, C['red']); x += w + 7
    since = t - (0.2 if n == 9 else t19 if n == 19 else t99)
    if since >= 0:
        f.text(x, 14, str(n), C['amber'] if n > 9 and since < 0.6 else C['cream'], F16); x += int(f.d.textlength(str(n), font=F16)) + 7
        f.text(x, 14, typed('SESSIONS OPEN.', t - 0.2, 30), C['cream'], F16)
    if t >= tw: f.text(16, 34, typed('3 ARE WAITING ON YOU.', t - tw, 30), C['amber'], F16)
    if t >= tg: f.text(16, 54, typed('GUESS WHICH.', t - tg, 30), C['cream'], F16)


def s2(f, t, T):  # scroll, read, scroll
    f.box(14, 12, 200, 156, C['bg2'])
    off = int(t * 70)
    for i in range(40):
        y = 18 + i * 6 - off % 6
        if 16 < y < 162:
            w = 40 + (i * 53 + off // 6 * 31) % 140
            f.rect(20, y, w, 2, C['mute'] if (i + off // 6) % 7 else C['line'])
    f.rect(206, 16 + int((t / T) * 120), 4, 24, C['line'])
    f.spr('dizzy', 248, 70 + int(3 * math.sin(t * 9)), 4)
    for k, s in enumerate(['SCROLL.', 'READ.', 'SCROLL.']):
        if t > 0.3 + k * T * 0.25: f.text(232, 120 + k * 14, s, C['amber'] if k == 1 else C['cream'], F8)
    if t > T * 0.75: f.text(232, 166, 'THE QUESTION WAS 40 MIN AGO', C['mute'], F8)


def s3(f, t, T):  # every session on its item
    a = ease(t / 0.8)
    f.wheel(18, int(-30 + 44 * a), 2)
    f.text(60, 20, typed('STEERIFY', t, 14), C['cream'], F16)
    items = [('DONE', C['green']), ('REVIEW', C['blue']), ('WAITING ON YOU', C['amber']), ('WIP', C['cream'])]
    for i, (st, col) in enumerate(items):
        y = 62 + i * 28; show = ease((t - 0.6 - i * 0.35) / 0.5)
        if show <= 0: continue
        f.box(18, y, 120, 22)
        if st == 'DONE': f.rect(24, y + 7, 8, 8, col)
        elif st == 'WAITING ON YOU' and int(t * 3) % 2 == 0: f.rect(24, y + 7, 8, 8, col)
        else: f.box(24, y + 7, 8, 8, C['panel'], col)
        f.rect(38, y + 6, 60, 2, C['cream']); f.text(38, y + 11, st, col, F8)
        bx = int(300 - (300 - 176) * show)
        for x in range(140, bx, 4): f.rect(x, y + 11, 2, 1, col)
        f.spr('boat', bx, y + 4 + int(math.sin(t * 3 + i)))
    if t > T * 0.7: f.text(160, 172, 'SUBTLE.', C['amber'], F8, 'ms')


def s4(f, t, T):  # look, pin, OK
    f.box(60, 14, 200, 120, (26, 29, 36), C['cream'])
    f.rect(61, 15, 198, 60, (29, 34, 48))
    for r in range(8):
        f.rect(215 - r, 30 + r, 2 * r + 2, 1, C['amber']); f.rect(215 - r, 46 - r, 2 * r + 2, 1, C['amber'])
    for i in range(70): h = 40 - abs(i - 35); f.rect(70 + i, 120 - h, 1, h + 10, (63, 154, 82))
    for i in range(90): h = int(30 - abs(i - 45) * 0.6); f.rect(140 + i, 120 - h, 1, h + 10, (47, 110, 61))
    f.rect(61, 122, 198, 11, (36, 65, 79))
    for k, (px, py, at) in enumerate([(98, 52, 0.7), (196, 86, 1.3)]):
        p = ease((t - at) / 0.35)
        if p > 0:
            y = int(py - 14 * (1 - p)); f.rect(px, y, 12, 12, C['amber']); f.text(px + 6, y + 10, str(k + 1), C['ink'], F8, 'ms')
    for k, s in enumerate(['LOOK.', 'PIN.', 'OK.']):
        if t > 0.3 + k * T * 0.22: f.text(20 + k * 0, 146 + 0, '', C['cream'])
    f.text(20, 152, typed('PICTURES, NOT PARAGRAPHS.', t, 20), C['cream'], F8)
    if t > T * 0.72:
        p = ease((t - T * 0.72) / 0.25); w = int(80 * (1.6 - 0.6 * p)); h = int(30 * (1.6 - 0.6 * p))
        x, y = 230 - w // 2, 140 - h // 2
        f.rect(x, y, w, h, C['green']); f.text(230, 140 + 8, 'OK', C['ink'], F16 if p > 0.7 else F24, 'ms')


def s5(f, t, T):  # it ships
    sea(f, t)
    f.rect(258, 60, 62, 60, C['panel']); f.rect(258, 60, 62, 2, C['green']); f.text(289, 74, 'SHIPPED', C['green'], F8, 'ms')
    n = 0
    for i in range(6):
        start = i * 0.45; p = ease((t - start) / 1.6)
        x = int(-20 + p * 270); bob = int(2 * math.sin(t * 3 + i))
        if p >= 1: n += 1
        f.spr('boat', x, 104 + (i % 2) * 8 + bob)
    f.text(289, 100, f'{min(11, n * 2 + (1 if n else 0)):02d}', C['cream'], F24, 'ms')
    f.text(16, 16, typed('READ LESS.', t, 16), C['cream'], F16)
    if t > T * 0.45: f.text(16, 38, typed('SHIP MORE.', t - T * 0.45, 16), C['amber'], F16)


def s6(f, t, T):  # logo
    a = ease(t / 0.6)
    f.box(84, int(40 - 10 * (1 - a)), 44, 44, (20, 22, 28), C['line']); f.wheel(90, int(46 - 10 * (1 - a)), 2)
    f.text(140, 56, typed('STEERIFY', t, 18), C['cream'], F24)
    if t > 0.9: f.text(141, 88, 'YOU DECIDE. CLAUDE BUILDS.', C['amber'], F8)
    if t > 1.6: f.text(160, 128, 'STEERIFY.DEV', C['cream'], F16, 'ms')
    if t > 2.2: f.text(160, 146, 'FREE AND OPEN SOURCE', C['mute'], F8, 'ms')
    for i, pal in enumerate([None, {'c': C['amber'], 'k': (58, 37, 8)}, {'c': (74, 78, 88), 'k': C['amber']}]):
        if t > 2.0: f.spr('cat', 252 + i * 14, 160, 1, pal)


SCENES = [s1, s2, s3, s4, s5, s6]


def main(out):
    timing = json.load(open(os.path.join(HERE, 'timing.json')))
    durs = [max(d + 0.35, 2.4) for d in timing['durations']]
    ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W*S}x{H*S}', '-r', str(FPS), '-i', '-',
                           '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'medium', out], stdin=subprocess.PIPE)
    for scene, T in zip(SCENES, durs):
        for i in range(int(T * FPS)):
            t = i / FPS; f = Frame(); scene(f, t, T)
            if t < 0.15: f.im = Image.blend(Image.new('RGB', (W, H), C['bg']), f.im, t / 0.15)
            ff.stdin.write(f.out().tobytes())
    ff.stdin.close(); ff.wait()
    print('durations', [round(d, 2) for d in durs], 'total', round(sum(durs), 2))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'teaser-silent.mp4'))
