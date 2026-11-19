import json, subprocess, sys
T, V, out = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(f'{T}/teaser.json')); t = json.load(open(f'{V}/timing.json'))['durations']
durs = [max(x + 0.35, 2.4) for x in t]; start = 0; inputs = []; filt = []
for i, (s, dur) in enumerate(zip(d['slides'], durs)):
    inputs += ['-i', f"{T}/{s['audio']['src']}"]; ms = int((start + 0.25) * 1000)
    filt.append(f'[{i+1}:a]adelay={ms}|{ms}[a{i}]'); start += dur
filt.append(''.join(f'[a{i}]' for i in range(len(durs))) + f'amix=inputs={len(durs)}:normalize=0,loudnorm=I=-16,apad[a]')
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', f'{V}/silent.mp4', *inputs, '-filter_complex', ';'.join(filt), '-map', '0:v', '-map', '[a]',
                '-c:v', 'copy', '-c:a', 'aac', '-b:a', '160k', '-shortest', '-movflags', '+faststart', out], check=True)
