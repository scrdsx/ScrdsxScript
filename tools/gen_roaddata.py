"""Turns the map export (tools/map_export.lua -> mapexport/*.csv) into src/roaddata.lua: the footprints of every "Road" part (4 corners + height)
and the road cells blocked by solid things standing on the road (hedges, pumps, canopies, bases...). src/roadplan.lua plans on this data.
usage: python gen_roaddata.py [mapexport folder] [output file]
"""
import csv, glob, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import roadnet as rn

folder = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\vared\Downloads\Download\workspace\ScrdsxScript\mapexport"
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "roaddata.lua")


def key(i, j, l):
    return ((l + 16) * 1024 + (i + 640)) * 2048 + (j + 640)


parts = rn.load_roads(folder)
grid = rn.RoadGrid(parts)
print(len(parts), "road parts,", len(grid.cells), "cells")

obs = []
for f in sorted(glob.glob(os.path.join(folder, "obstacles_*.csv"))):
    obs += list(csv.DictReader(open(f, encoding="utf8")))

# big solid things that sit INSIDE the Roads folder (roundabout statue bases, concrete barriers, bridge walls) are not in the obstacle files, because the
# exporter skips everything under Workspace.Roads. They are in roads_*.csv: take the big, tall, collidable ones as obstacles too.
SKIP_PARENTS = {"Streetlamp", "Sidewalks", "Track", "Train Tracks Straight", "Train Tracks Curve", "Hydrant", "Guide Post", "MiniLight"}
extra = 0
for f in sorted(glob.glob(os.path.join(folder, "roads_*.csv"))):
    for r in csv.DictReader(open(f, encoding="utf8")):
        if r["name"] in ("Road", "Curb", "Sidewalk", "Shoulder") or r["parent"] in SKIP_PARENTS or r["collide"] != "1":
            continue
        sx, sy, sz = float(r["sx"]), float(r["sy"]), float(r["sz"])
        barrier = "safety barrier" in r["parent"].lower() or "barrier" in r["name"].lower()
        narrowing = "narrowing" in r["parent"].lower() or "concretebar" in r["name"].lower() # road narrowings have low concrete bars the car cannot climb
        if barrier or narrowing or (sy >= 2.5 and max(sx, sz) >= 4 and min(sx, sz) >= 2):
            r = dict(r); r["_extra"] = True
            obs.append(r); extra += 1
print(extra, "solid parts from the Roads folder added as obstacles")

blocked = set()
for r in obs:
    x, y, z = float(r["x"]), float(r["y"]), float(r["z"])
    sx, sy, sz = float(r["sx"]), float(r["sy"]), float(r["sz"])
    R = rn.rot_matrix(math.radians(float(r["rx"])), math.radians(float(r["ry"])), math.radians(float(r["rz"])))
    corners = []
    for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        lx, lz = a * sx / 2, b * sz / 2
        corners.append((x + R[0][0] * lx + R[0][2] * lz, z + R[2][0] * lx + R[2][2] * lz, y))
    xs = [c[0] for c in corners]; zs = [c[1] for c in corners]
    ext = abs(R[1][0]) * sx / 2 + abs(R[1][1]) * sy / 2 + abs(R[1][2]) * sz / 2
    ymin, ymax = y - ext, y + ext
    for i in range(int(min(xs) // 4), int(max(xs) // 4) + 1):
        for j in range(int(min(zs) // 4), int(max(zs) // 4) + 1):
            if not rn.inside_quad(i * 4 + 2, j * 4 + 2, corners):
                continue
            for l in range(-20, 21):
                k = (i, j, l)
                cy = grid.cells.get(k)
                # the car body occupies roughly 1 .. 4.5 studs above the road surface
                if cy is not None and ymax > cy + 1.0 and ymin < cy + 4.5:
                    blocked.add(k)
# barriers (boom gates, retractable bollards, ...): a barrier closes the whole road, so every road cell within ~22 studs of one is blocked.
# These are the places only police can pass; the autopilot must not route through them.
barrier_cells = set()
barriers = []
for r in obs:
    if r.get("_extra"): continue # (these are solid things, not gates that close a road)
    nm = (r["name"] + " " + r["parent"]).lower()
    if ("gate" in nm and "gate base" not in nm and "gated" not in nm) or "gate base" in nm or ("bollard" in nm and r["name"] == "Main") or "roadblock" in nm or "barrier" in nm:
        x, z = float(r["x"]), float(r["z"])
        barriers.append((x, z, r["parent"], r["name"]))
RAD = 22.0
for (x, z, par, nm) in barriers:
    hit = 0
    for i in range(int((x - RAD) // 4), int((x + RAD) // 4) + 1):
        for j in range(int((z - RAD) // 4), int((z + RAD) // 4) + 1):
            if math.hypot(i * 4 + 2 - x, j * 4 + 2 - z) <= RAD:
                for l in range(-20, 21):
                    if (i, j, l) in grid.cells:
                        barrier_cells.add((i, j, l)); hit += 1
    if hit:
        print("  barrier %-14s %-12s at (%.0f,%.0f): %d road cells closed" % (par[:14], nm[:12], x, z, hit))
blocked |= barrier_cells

# roundabouts: the four quadrant "Road" parts of every Roundabout module give its centre. The middle (statue base + island) is closed for cars,
# so routes have to go AROUND it; the planner also gets the rings so it can prefer the right direction of travel.
rb = []
for f in sorted(glob.glob(os.path.join(folder, "roads_*.csv"))):
    for r in csv.DictReader(open(f, encoding="utf8")):
        if r["name"] == "Road" and "roundabout" in r["parent"].lower():
            rb.append((float(r["x"]), float(r["z"])))
centres = []
for (x, z) in rb:
    for c in centres:
        if math.hypot(c[0] / c[2] - x, c[1] / c[2] - z) < 260:
            c[0] += x; c[1] += z; c[2] += 1
            break
    else:
        centres.append([x, z, 1])
rings = [(c[0] / c[2], c[1] / c[2]) for c in centres]
ISLAND, RING_OUT = 58.0, 80.0 # the island (statue, sidewalk, curb) is a disc of radius ~57; the lane is the ring around it; street lamps stand just outside it on the diagonals
for (cx, cz) in rings:
    for i in range(int((cx - ISLAND) // 4), int((cx + ISLAND) // 4) + 1):
        for j in range(int((cz - ISLAND) // 4), int((cz + ISLAND) // 4) + 1):
            if math.hypot(i * 4 + 2 - cx, j * 4 + 2 - cz) <= ISLAND:
                for l in range(-20, 21):
                    if (i, j, l) in grid.cells:
                        blocked.add((i, j, l))
# the four corners of the module outside the ring (sidewalk, street lamps, trees) are not for cars either; the arms (+-22 studs round the axes) stay open
for (cx, cz) in rings:
    for i in range(int((cx - 92) // 4), int((cx + 92) // 4) + 1):
        for j in range(int((cz - 92) // 4), int((cz + 92) // 4) + 1):
            dx, dz = i * 4 + 2 - cx, j * 4 + 2 - cz
            if math.hypot(dx, dz) > RING_OUT and abs(dx) > 22 and abs(dz) > 22:
                for l in range(-20, 21):
                    if (i, j, l) in grid.cells:
                        blocked.add((i, j, l))
print(len(rings), "roundabouts (island radius %d + corners closed)" % ISLAND)
# inflate by one cell (the car is 6 wide)
infl = set(blocked)
for (i, j, l) in blocked:
    for di in (-1, 0, 1):
        for dj in (-1, 0, 1):
            if (i + di, j + dj, l) in grid.cells:
                infl.add((i + di, j + dj, l))
print(len(blocked), "cells blocked,", len(infl), "with a 1-cell margin")

lines = ["-- GENERATED by tools/gen_roaddata.py from the map export. Do not edit by hand.",
         "-- quads: 9 numbers per Road part: x1,z1,x2,z2,x3,z3,x4,z4,y (footprint corners). blocked: road cells with a solid thing on them.",
         "return {", "quads = {"]
for p in parts:
    c = p["c"]
    lines.append("%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f," % (c[0][0], c[0][1], c[1][0], c[1][1], c[2][0], c[2][1], c[3][0], c[3][1], sum(q[2] for q in c) / 4))
lines.append("},")
lines.append("blocked = {")
ks = sorted(key(*k) for k in infl)
for i in range(0, len(ks), 20):
    lines.append(",".join(str(k) for k in ks[i:i + 20]) + ",")
lines.append("},")
lines.append("rings = {")
for (cx, cz) in rings:
    lines.append("%.1f,%.1f,%.1f,%.1f," % (cx, cz, ISLAND, RING_OUT))
lines.append("},")
lines.append("}")
open(out, "w", encoding="utf8").write("\n".join(lines) + "\n")
print("wrote", os.path.abspath(out), os.path.getsize(out) // 1024, "KB")
