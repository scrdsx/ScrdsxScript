import math
# Generates the tab icon sprite sheet (white line icons, 64px cells, drawn at 8x and downsampled for clean edges) and prints it as base64.
import base64, io, math, sys
from PIL import Image, ImageDraw
CELL, SS = 64, 8
S = CELL * SS
W = int(4.2 * SS)  # stroke width

def new():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)
def P(x, y): return (x * SS, y * SS)
def line(d, pts, w=W):
    pts = [P(*p) for p in pts]
    d.line(pts, fill="white", width=w, joint="curve")
    for p in (pts[0], pts[-1]):
        d.ellipse([p[0]-w/2, p[1]-w/2, p[0]+w/2, p[1]+w/2], fill="white")
def arc(d, box, a0, a1, w=W):
    d.arc([c*SS for c in box], a0, a1, fill="white", width=w)
def ring(d, cx, cy, r, w=W): d.ellipse([(cx-r)*SS, (cy-r)*SS, (cx+r)*SS, (cy+r)*SS], outline="white", width=w)
def disc(d, cx, cy, r): d.ellipse([(cx-r)*SS, (cy-r)*SS, (cx+r)*SS, (cy+r)*SS], fill="white")
def rrect(d, box, r, w=W, fill=False):
    b = [c*SS for c in box]
    if fill: d.rounded_rectangle(b, r*SS, fill="white")
    else: d.rounded_rectangle(b, r*SS, outline="white", width=w)

def car(d):
    rrect(d, (8, 28, 56, 46), 6)
    line(d, [(14, 28), (20, 16), (44, 16), (50, 28)])
    ring(d, 20, 48, 5); ring(d, 44, 48, 5)
def person(d):
    ring(d, 32, 21, 9)
    arc(d, (12, 36, 52, 76), 190, 350)
def eye(d):
    arc(d, (6, 14, 58, 70), 205, 335); arc(d, (6, -6, 58, 50), 25, 155)
    ring(d, 32, 32, 8); disc(d, 32, 32, 3)
def crosshair(d):
    ring(d, 32, 32, 15)
    for a, b in (((32, 8), (32, 21)), ((32, 43), (32, 56)), ((8, 32), (21, 32)), ((43, 32), (56, 32))): line(d, [a, b])
def pin(d):
    arc(d, (16, 8, 48, 40), 140, 400)
    line(d, [(19.5, 31), (32, 54), (44.5, 31)])
    ring(d, 32, 24, 5)
def coin(d):
    ring(d, 32, 32, 22); ring(d, 32, 32, 13, int(3.4*SS))
    line(d, [(32, 26), (32, 38)], int(3.4*SS))
def bolt(d):
    line(d, [(36, 8), (16, 36), (31, 36), (26, 56), (48, 26), (33, 26), (36, 8)])
def folder(d):
    line(d, [(8, 20), (8, 50), (56, 50), (56, 24), (30, 24), (25, 17), (8, 17), (8, 20)])
def gear(d):
    ring(d, 32, 32, 18); ring(d, 32, 32, 7)
    for i in range(8):
        a = math.radians(i * 45)
        line(d, [(32 + 21*math.cos(a), 32 + 21*math.sin(a)), (32 + 27*math.cos(a), 32 + 27*math.sin(a))], int(5.4*SS))
def shield(d):
    line(d, [(32, 7), (52, 14), (52, 32), (32, 57), (12, 32), (12, 14), (32, 7)])
    line(d, [(23, 31), (30, 38), (42, 24)])
def store(d):
    line(d, [(10, 24), (14, 10), (50, 10), (54, 24)])
    line(d, [(10, 24), (54, 24)])
    arc(d, (10, 18, 26, 30), 0, 180); arc(d, (26, 18, 42, 30), 0, 180); arc(d, (42, 18, 54, 30), 0, 180)
    line(d, [(14, 30), (14, 54), (50, 54), (50, 30)])
    rrect(d, (26, 38, 38, 54), 2)
def bomb(d):
    ring(d, 28, 38, 16)
    line(d, [(39, 26), (45, 20)])
    line(d, [(45, 20), (49, 16)], int(3.4*SS))
    for a, b in (((53, 8), (53, 14)), ((50, 11), (56, 11)), ((56, 16), (58.5, 18.5)), ((47, 6), (45, 3.5))): line(d, [a, b], int(2.6*SS))
def sparkle(d):
    line(d, [(32, 8), (36, 28), (56, 32), (36, 36), (32, 56), (28, 36), (8, 32), (28, 28), (32, 8)])
def hand(d):
    rrect(d, (16, 30, 48, 56), 8)
    for x, top in ((20, 14), (28, 10), (36, 12), (44, 18)):
        line(d, [(x, 30), (x, top)])
def bell(d):
    arc(d, (14, 10, 50, 46), 180, 360)
    line(d, [(14, 28), (14, 42), (8, 48), (56, 48), (50, 42), (50, 28)])
    arc(d, (27, 48, 37, 58), 0, 180)
def map_(d):
    line(d, [(8, 16), (22, 11), (42, 17), (56, 12), (56, 48), (42, 53), (22, 47), (8, 52), (8, 16)])
    line(d, [(22, 11), (22, 47)]); line(d, [(42, 17), (42, 53)])
def sliders(d):
    for y, x in ((16, 40), (32, 22), (48, 36)):
        line(d, [(8, y), (56, y)], int(3.2*SS)); ring(d, x, y, 5.5); 
def flag(d):
    line(d, [(14, 8), (14, 58)]); line(d, [(14, 12), (50, 12), (42, 22), (50, 32), (14, 32)])
def wifi(d):
    arc(d, (6, 8, 58, 60), 225, 315); arc(d, (16, 18, 48, 50), 225, 315); disc(d, 32, 44, 3.4)

def sun(d):
    disc(d, 32, 32, 11)
    for k in range(8):
        a = math.radians(k * 45); line(d, [(32 + 18 * math.cos(a), 32 + 18 * math.sin(a)), (32 + 26 * math.cos(a), 32 + 26 * math.sin(a))])
def grid(d):
    for x in (10, 36):
        for y in (10, 36): line(d, [(x, y), (x + 18, y), (x + 18, y + 18), (x, y + 18), (x, y)])
ICONS = [car, person, eye, crosshair, pin, coin, bolt, folder, gear, shield, store, bomb, sparkle, hand, bell, map_, sliders, flag, wifi, sun, grid]
COLS = 10
sheet = Image.new("RGBA", (CELL * COLS, CELL * ((len(ICONS) + COLS - 1) // COLS)), (0, 0, 0, 0))
for i, fn in enumerate(ICONS):
    im, d = new(); fn(d)
    sheet.paste(im.resize((CELL, CELL), Image.LANCZOS), ((i % COLS) * CELL, (i // COLS) * CELL))
buf = io.BytesIO(); sheet.save(buf, "PNG", optimize=True)
if len(sys.argv) > 1: sheet.save(sys.argv[1])
open(sys.argv[2] if len(sys.argv) > 2 else "icons_b64.txt", "w").write(base64.b64encode(buf.getvalue()).decode())
print("icons", len(ICONS), "bytes", len(buf.getvalue()))
