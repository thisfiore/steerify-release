#!/usr/bin/env python3
# Vertical (1080x1920) cuts of the narrated tutorial videos, for Shorts / Reels / TikTok.
#   python3 scripts/tutorial/vertical.py <video> <out-name> "<TITLE>" <first-slide> <last-slide> [--still i k]
# Reuses video.py's cards and screenshots: draws the landscape frame without the face, crops the picture area,
# and lays it out tall with a big caption and the face bubble underneath.
import importlib.util, json, os, subprocess, sys
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
name, outname, TITLE, A, B = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
argv = sys.argv; sys.argv = [argv[0], name]
spec = importlib.util.spec_from_file_location('tv', os.path.join(HERE, 'video.py')); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
sys.argv = argv
C, PB, PR = m.C, m.PB, m.PR
VW, VH, FPS = 1080, 1920, 30
CROP = (60, 130, 1440, 950)          # the picture area of the landscape frame
SW, SH = 1080, round(1080 * (CROP[3] - CROP[1]) / (CROP[2] - CROP[0]))
STAGE_Y, CAP_Y, FACE_Y = 330, 1030, 1330
OUT = os.path.join(m.ROOT, 'build', 'vertical', outname); os.makedirs(OUT, exist_ok=True)
_none = Image.new('RGBA', (336, 336), (0, 0, 0, 0)); _real_bubble = m.bubble
_stage = {}
FULL = {'choice-making'}            # shots that only read whole
def _title(d, text):                 # card titles must fit the cropped picture area
    size = 54
    while d.textlength(text, font=PB(size)) > CROP[2] - 150 and size > 30: size -= 2
    d.text((110, 170), text, font=PB(size), fill=C['cream'])
m.title = _title
ZOOM = (0, 40, 1636)                 # screenshots: the board half of the window, from just under the title bar
def stage(i, k, pulse):
    key = (i, k, pulse)
    if key in _stage: return _stage[key]
    v = m.VIEW[m.SL[i]['id']]
    if not callable(v):
        name, hl, tag = v
        if not isinstance(name, str): name = [n for at, n in name if k >= at][-1]
        marks = hl.get(k, hl.get('*', []))
        fits = all(r[0] + r[2] <= ZOOM[2] + 20 for r, _, _ in marks)
        src = Image.open(m.SHOT(name)).convert('RGB'); zx, zy, zw = ZOOM if fits and name not in FULL else (0, 0, src.width); sc = SW / zw
        im = src.crop((zx, zy, zx + zw, zy + round(SH / sc))).resize((SW, SH), Image.LANCZOS); d = ImageDraw.Draw(im)
        for (rx, ry, rw, rh), label, col in marks:
            a = [(rx - zx) * sc, (ry - zy) * sc, min(SW - 3, (rx + rw - zx) * sc), min(SH - 3, (ry + rh - zy) * sc)]
            d.rectangle(a, outline=C[col], width=8 if pulse else 5)
            if label:
                f = PB(30) if d.textlength(label, font=PB(30)) + 52 <= a[2] - a[0] else PB(20)
                tw = d.textlength(label, font=f); d.rectangle([a[0] + 12, a[1] + 12, a[0] + 40 + tw, a[1] + 66], fill=C[col]); d.text((a[0] + 26, a[1] + 39), label, font=f, fill=C['ink'], anchor='lm')
        if tag:
            tw = d.textlength(tag, font=PB(30)); d.rectangle([20, SH - 80, 52 + tw, SH - 20], fill=C['amber']); d.text((36, SH - 68), tag, font=PB(30), fill=C['ink'])
        _stage[key] = im; return im
    m.bubble = lambda *a: _none
    im = m.frame(i, k, pulse, (0, 0)); m.bubble = _real_bubble
    _stage[key] = im.crop(CROP).resize((SW, SH), Image.LANCZOS)
    return _stage[key]
def vframe(i, k, pulse, who):
    s = m.SL[i]; im = Image.new('RGB', (VW, VH), C['bg']); d = ImageDraw.Draw(im)
    ic = m.ICON.resize((84, 84), Image.LANCZOS); im.paste(ic, (60, 76), ic)
    d.text((164, 104), 'STEERIFY', font=PB(58), fill=C['cream'], anchor='lm'); d.text((164, 152), 'FOR CLAUDE CODE  ·  FREE MAC APP', font=PR(24), fill=C['mute'], anchor='lm')
    ls = m.wrap(d, TITLE, PB(46), VW - 120)[:2]
    for n, ln in enumerate(ls): d.text((60, 258 + (n - (len(ls) - 1) / 2) * 56), ln, font=PB(46), fill=C['amber'], anchor='lm')
    im.paste(stage(i, k, pulse), (0, STAGE_Y)); d.rectangle([0, STAGE_Y - 3, VW, STAGE_Y - 1], fill=C['line2']); d.rectangle([0, STAGE_Y + SH, VW, STAGE_Y + SH + 2], fill=C['line2'])
    n_ = B - A + 1; seg = (VW - 120) / n_
    for j in range(n_): d.rectangle([60 + j * seg, STAGE_Y + SH + 22, 60 + (j + 1) * seg - 8, STAGE_Y + SH + 30], fill=C['green'] if j < i - A + 1 else C['amber'] if j == i - A + 1 else C['line'])
    ls = m.wrap(d, m.sentences(s['text'])[k].upper(), PR(44), VW - 120)[:5]
    for n, ln in enumerate(ls): d.text((60, CAP_Y + 140 + (n - (len(ls) - 1) / 2) * 58), ln, font=PR(44), fill=C['cream'], anchor='lm')
    b = _real_bubble(*who); im.paste(b, (44, FACE_Y), b)
    d.text((420, FACE_Y + 70), f'{i - A + 2:02d}', font=PB(100), fill=C['amber'], anchor='lm')
    for n, ln in enumerate(m.wrap(d, s['chapter'].upper(), PB(34), 600)[:2]): d.text((420, FACE_Y + 170 + n * 46), ln, font=PB(34), fill=C['cream'], anchor='lm')
    d.text((420, FACE_Y + 290), 'STEERIFY.DEV', font=PB(40), fill=C['green'], anchor='lm')
    return im
def render(i):
    T_, st = m.times(i); out = os.path.join(OUT, f'seg-{i + 1:02d}.mp4'); tmp = out + '.tmp.mp4'
    ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{VW}x{VH}', '-r', str(FPS), '-i', '-',
                           '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'veryfast', '-g', str(FPS * 2), tmp], stdin=subprocess.PIPE)
    cache = {}
    for f in range(round(T_ * FPS)):
        t = f / FPS; k = max(j for j, x in enumerate(st) if x <= t or j == 0); who = m.face(i, k, t, st, T_); key = (k, int(t * 2) % 2, who)
        if key not in cache: cache[key] = vframe(i, k, key[1], who).tobytes()
        ff.stdin.write(cache[key])
    ff.stdin.close()
    if ff.wait() == 0: os.replace(tmp, out)
    return T_
def main():
    if '--still' in argv:
        j = argv.index('--still'); i = int(argv[j + 1]) - 1; k = int(argv[j + 2]); vframe(i, k, 1, (m.mood(i, k) % 4, 2)).save(os.path.join(OUT, f'still-{i + 1:02d}-{k}.png')); return
    idx = list(range(A - 1, B)); lens = [render(i) for i in idx]; starts = [sum(lens[:n]) for n in range(len(idx))]
    lst = os.path.join(OUT, 'list.txt'); open(lst, 'w').write(''.join(f"file 'seg-{i + 1:02d}.mp4'\n" for i in idx))
    silent = os.path.join(OUT, 'silent.mp4'); subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', silent], check=True)
    inputs, filt = [], []
    for n, i in enumerate(idx):
        inputs += ['-i', m.VOICE(i)]; ms = int((starts[n] + 0.15) * 1000); filt.append(f'[{n + 1}:a]adelay={ms}|{ms}[a{n}]')
    filt.append(''.join(f'[a{n}]' for n in range(len(idx))) + f'amix=inputs={len(idx)}:normalize=0,loudnorm=I=-16,apad[a]')
    dest = os.path.join(m.ROOT, 'build', 'vertical', outname + '.mp4')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', silent, *inputs, '-filter_complex', ';'.join(filt), '-map', '0:v', '-map', '[a]', '-c:v', 'copy',
                    '-c:a', 'aac', '-b:a', '160k', '-shortest', '-movflags', '+faststart', dest], check=True)
    print(outname, round(sum(lens), 1), dest)
main()
