# Creamy "thock" UI sounds (like a lubed linear keyboard switch bottoming out): a low body tone that drops in pitch, a soft
# muffled tick on top, heavy low-pass, a tiny room. Replaces click / hover / on / off / tab in src/core/sfx.lua.
#   python tools/gen_thock.py   (needs numpy + ffmpeg)
import numpy as np, wave, subprocess, base64, os, re, tempfile
SR = 44100
rng = np.random.default_rng(7)

def lowpass(x, a):
    y = np.zeros_like(x); p = 0.0
    for i, v in enumerate(x): p += a * (v - p); y[i] = p
    return y
def room(x, mix):
    out = x.copy()
    for d, g in ((0.011, .5), (0.019, .35), (0.029, .22), (0.043, .12)):
        k = int(d * SR); out[k:] += g * x[:-k] * mix
    return out

def thock(f0, dur=0.14, body=1.0, tick=0.35, tau=0.028, drop=1.55, bright=0.16, rm=0.5):
    n = int(SR * dur); t = np.arange(n) / SR
    f = f0 * (1 + (drop - 1) * np.exp(-t / 0.012))           # pitch falls into the note: the "th-"
    ph = 2 * np.pi * np.cumsum(f) / SR
    att = np.minimum(t / 0.0015, 1)
    s = body * (np.sin(ph) * np.exp(-t / tau) + 0.32 * np.sin(2.31 * ph) * np.exp(-t / (tau * 0.45)))
    nz = rng.standard_normal(n) * np.exp(-t / 0.0022)          # the soft "tick" of the keycap
    s = s * att + tick * lowpass(nz, 0.3)
    s = lowpass(s, bright)                                     # creamy: no highs
    s = room(s, rm)
    fade = np.ones(n); k = int(0.02 * SR); fade[-k:] = np.linspace(1, 0, k)
    return s * fade

S = {
    "on": thock(205, tick=.32),
    "off": thock(165, tick=.26, tau=.032),
    "click": thock(185, dur=.12, tick=.28, tau=.024),
    "tab": thock(230, dur=.11, tick=.22, tau=.02, bright=.18),
    "hover": thock(290, dur=.06, body=.4, tick=.12, tau=.01, bright=.12, rm=.2),
}
PEAK = { "on": .62, "off": .6, "click": .55, "tab": .5, "hover": .22 }

tmp = tempfile.mkdtemp()
out = {}
for name, x in S.items():
    x = x / (np.max(np.abs(x)) + 1e-9) * PEAK[name]
    wav = os.path.join(tmp, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype(np.int16).tobytes())
    ogg = os.path.join(tmp, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", ogg], check=True)
    out[name] = base64.b64encode(open(ogg, "rb").read()).decode()
    print(name, len(out[name]))

p = os.path.join(os.path.dirname(__file__), "..", "src", "core", "sfx.lua")
s = open(p, encoding="utf-8").read()
for name, b in out.items():
    s, n = re.subn(r'^data\.%s = "[^"]*"' % name, 'data.%s = "%s"' % (name, b), s, flags=re.M)
    assert n == 1, name
s = s.replace('"ScrdsxScript/sfx_v1_"', '"ScrdsxScript/sfx_v2_"')
open(p, "w", encoding="utf-8", newline="").write(s)
