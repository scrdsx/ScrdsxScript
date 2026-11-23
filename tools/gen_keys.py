# Generates soft "creamy" keyboard sounds (low thock + tiny click) and embeds them into src/core/sfx.lua as data.key1..key4 / data.keyspace.
import numpy as np, wave, subprocess, base64, os, re, tempfile
SR = 44100
rng = np.random.default_rng(11)
def lowpass(x, a):
    y = np.zeros_like(x); p = 0.0
    for i, v in enumerate(x): p += a * (v - p); y[i] = p
    return y
def key(f, dur=.11, body=1.0, click=.5, seed=0):
    r = np.random.default_rng(seed)
    n = int(SR * dur); t = np.arange(n) / SR
    thock = np.sin(2 * np.pi * f * (1 + .35 * np.exp(-t / .012)) * t) * np.exp(-t / .028) * body      # low pitched body, drops a little
    ring = np.sin(2 * np.pi * f * 2.3 * t) * np.exp(-t / .012) * .18                                    # soft plastic ring
    nz = lowpass(r.standard_normal(n), .22) * np.exp(-t / .004) * click                                  # the tiny click
    x = thock + ring + nz
    x[:int(SR * .0012)] *= np.linspace(0, 1, int(SR * .0012))
    x = lowpass(x, .42)
    return x
S = {"key1": key(190, seed=1), "key2": key(215, seed=2), "key3": key(170, seed=3), "key4": key(235, seed=4, body=.9),
     "keyspace": key(130, dur=.16, body=1.15, click=.35, seed=5)}
tmp = tempfile.mkdtemp(); out = {}
for name, x in S.items():
    x = x / (np.max(np.abs(x)) + 1e-9) * .5
    wav = os.path.join(tmp, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype(np.int16).tobytes())
    ogg = os.path.join(tmp, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", ogg], check=True)
    out[name] = base64.b64encode(open(ogg, "rb").read()).decode()
p = os.path.join(os.path.dirname(__file__), "..", "src", "core", "sfx.lua")
s = open(p, encoding="utf-8").read()
s = re.sub(r'^data\.key\w* = ".*"\n', "", s, flags=re.M)
lines = "".join('data.%s = "%s"\n' % (k, v) for k, v in out.items())
s = s.replace("\nlocal function decode(s)", "\n" + lines + "\nlocal function decode(s)", 1) if "data.key1" not in s else s
open(p, "w", encoding="utf-8").write(s)
print({k: len(v) for k, v in out.items()})
