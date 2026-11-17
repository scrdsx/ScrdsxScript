# Generates the UI sounds (soft sine / bell tones with a little room reverb), encodes them to ogg and prints base64 per sound.
import numpy as np, wave, subprocess, base64, os, sys, json, tempfile
SR = 44100
def t_(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.004, tau=0.06):
    t = np.arange(n) / SR
    return np.minimum(t / a, 1.0) * np.exp(-t / tau)
def bell(f, d, tau, amp=1.0, parts=((1, 1), (2.0, .22), (3.01, .07))):
    n = int(SR * d); t = np.arange(n) / SR
    s = sum(a * np.sin(2 * np.pi * f * k * t) for k, a in parts)
    return amp * s * env(n, 0.004, tau)
def glide(f0, f1, d, tau, amp=1.0):
    n = int(SR * d); t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t / (d * 0.35))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return amp * (np.sin(ph) + 0.18 * np.sin(2 * ph)) * env(n, 0.003, tau)
def place(buf, snd, at):
    i = int(at * SR); buf[i:i + len(snd)] += snd[:len(buf) - i]
def room(x, mix=0.22):
    out = x.copy()
    for d, g in ((0.031, .45), (0.047, .33), (0.071, .24), (0.097, .16)):
        k = int(d * SR); out[k:] += g * x[:-k] * mix * 2
    return out
def lowpass(x, a=0.18):
    y = np.zeros_like(x); p = 0.0
    for i, v in enumerate(x): p += a * (v - p); y[i] = p
    return y
def norm(x, peak): return x / (np.max(np.abs(x)) + 1e-9) * peak
def mk(total): return np.zeros(int(SR * total))

S = {}
b = mk(.16); place(b, glide(640, 430, .12, .05, .9), 0); S["click"] = lowpass(room(b), .35)
b = mk(.08); place(b, bell(1500, .05, .018, .6, ((1, 1), (2, .1))), 0); S["hover"] = lowpass(b, .3)
b = mk(.34); place(b, bell(587, .2, .09), 0); place(b, bell(880, .26, .12), .075); S["on"] = lowpass(room(b), .4)
b = mk(.34); place(b, bell(880, .2, .08), 0); place(b, bell(587, .26, .12), .075); S["off"] = lowpass(room(b), .4)
b = mk(.2); place(b, glide(760, 560, .1, .04, .7), 0); S["tab"] = lowpass(room(b), .35)
b = mk(1.1)
for i, f in enumerate((523.25, 659.25, 783.99)): place(b, bell(f, .8, .22, .8 - i * .12), i * .09)
S["notify"] = lowpass(room(b, .35), .45)
b = mk(.6); place(b, glide(330, 250, .18, .09, .9), 0); place(b, glide(300, 220, .22, .12, .8), .13); S["warn"] = lowpass(room(b), .3)
rng = np.random.default_rng(3)
n = int(SR * .32); t = np.arange(n) / SR
sw = np.sin(2 * np.pi * np.cumsum(260 + 520 * (t / .32) ** 1.6) / SR) * np.sin(np.pi * t / .32) ** 1.5
nz = lowpass(rng.standard_normal(n), .06) * np.sin(np.pi * t / .32) ** 2 * 1.6
S["open"] = lowpass(room(sw * .8 + nz * .5), .4)
S["close"] = S["open"][::-1].copy()
S["success"] = None
b = mk(.8); place(b, bell(659.25, .5, .16, .9), 0); place(b, bell(987.77, .6, .2, .8), .1); S["success"] = lowpass(room(b, .3), .45)

out = {}
tmp = tempfile.mkdtemp()
for name, x in S.items():
    x = norm(x, 0.55)
    wav = os.path.join(tmp, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype(np.int16).tobytes())
    ogg = os.path.join(tmp, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", ogg], check=True)
    out[name] = base64.b64encode(open(ogg, "rb").read()).decode()
    print(name, len(out[name]), file=sys.stderr)
json.dump(out, open(sys.argv[1], "w"))
