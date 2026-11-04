"""Road network from the real road geometry (tools/map_export.lua -> mapexport/roads_*.csv).
Rasterises every "Road" part (oriented rectangle, any slope) into 4-stud cells and plans on them with A*, with a preference for the
middle of the road. The Lua planner in src/autodrive.lua does exactly the same thing on the live Workspace.Roads parts, so this file is
the offline test bench for it: python roadnet.py [mapexport folder] -> writes route pictures.
"""
import csv, glob, math, heapq, os, sys

CELL = 4.0


def rot_matrix(rx, ry, rz):
    """CFrame.fromEulerAnglesYXZ(rx, ry, rz) = Ry * Rx * Rz (radians) as 3x3 rows."""
    cx, sx = math.cos(rx), math.sin(rx); cy, sy = math.cos(ry), math.sin(ry); cz, sz = math.cos(rz), math.sin(rz)
    Rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    Ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    Rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    def mul(A, B): return [[sum(A[i][k] * B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mul(mul(Ry, Rx), Rz)


def load_roads(folder):
    parts = []
    for f in sorted(glob.glob(os.path.join(folder, "roads_*.csv"))):
        for r in csv.DictReader(open(f, encoding="utf8")):
            if "Road" not in r["name"]:
                continue
            x, y, z = float(r["x"]), float(r["y"]), float(r["z"])
            sx, sy, sz = float(r["sx"]), float(r["sy"]), float(r["sz"])
            R = rot_matrix(math.radians(float(r["rx"])), math.radians(float(r["ry"])), math.radians(float(r["rz"])))
            corners = []
            for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                lx, lz = a * sx / 2, b * sz / 2
                corners.append((x + R[0][0] * lx + R[0][2] * lz, z + R[2][0] * lx + R[2][2] * lz, y + R[1][0] * lx + R[1][2] * lz))
            parts.append(dict(name=r["name"], parent=r["parent"], c=corners, y=y))
    return parts


def inside_quad(px, pz, q):
    s = 0
    for i in range(4):
        ax, az, _ = q[i]; bx, bz, _ = q[(i + 1) % 4]
        cr = (bx - ax) * (pz - az) - (bz - az) * (px - ax)
        if cr > 0: s |= 1
        elif cr < 0: s |= 2
    return s != 3


class RoadGrid:
    def __init__(self, parts):
        self.cells = {}   # (i, j, level) -> y
        for p in parts:
            xs = [c[0] for c in p["c"]]; zs = [c[1] for c in p["c"]]
            i0, i1 = int(min(xs) // CELL), int(max(xs) // CELL)
            j0, j1 = int(min(zs) // CELL), int(max(zs) // CELL)
            for i in range(i0, i1 + 1):
                for j in range(j0, j1 + 1):
                    cx, cz = i * CELL + CELL / 2, j * CELL + CELL / 2
                    if inside_quad(cx, cz, p["c"]):
                        y = sum(c[2] for c in p["c"]) / 4
                        self.cells[(i, j, round(y / 6))] = y
        # distance to the road edge (in cells) by multi-source BFS from boundary cells
        self.edge = {}
        from collections import deque
        dq = deque()
        for k in self.cells:
            i, j, l = k
            if any(self.find(i + di, j + dj, l) is None for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                self.edge[k] = 0; dq.append(k)
        while dq:
            k = dq.popleft()
            i, j, l = k
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = self.find(i + di, j + dj, l)
                if n is not None and n not in self.edge:
                    self.edge[n] = self.edge[k] + 1; dq.append(n)

    def find(self, i, j, l):
        for dl in (0, -1, 1):
            if (i, j, l + dl) in self.cells:
                return (i, j, l + dl)
        return None

    def snap(self, x, z, y=None, radius=60):
        i, j = int(x // CELL), int(z // CELL)
        best, bd = None, None
        r = int(radius / CELL)
        for di in range(-r, r + 1):
            for dj in range(-r, r + 1):
                for dl in range(-3, 4):
                    pass
        # cheap: scan the cell dict near the point
        for (ci, cj, cl), cy in self.cells.items():
            if abs(ci - i) <= r and abs(cj - j) <= r and self.edge.get((ci, cj, cl), 0) >= 1:
                d = (ci - i) ** 2 + (cj - j) ** 2 + (0 if y is None else ((cy - y) / CELL) ** 2 * 0.2)
                if bd is None or d < bd: best, bd = (ci, cj, cl), d
        return best

    def center(self, k):
        return (k[0] * CELL + CELL / 2, k[1] * CELL + CELL / 2, self.cells[k])

    def plan(self, a, b, blocked=None, want=6):
        """A* from (x, z, y) a to b. cost prefers cells >= want cells... (4 studs each) from the edge."""
        s = self.snap(a[0], a[1], a[2] if len(a) > 2 else None)
        g = self.snap(b[0], b[1], b[2] if len(b) > 2 else None)
        if not s or not g: return None, "no road near the start or the goal"
        gx, gz, _ = self.center(g)
        openh = [(0, 0, s)]
        gs, parent, closed = {s: 0}, {}, set()
        while openh:
            f, gcost, k = heapq.heappop(openh)
            if k in closed: continue
            if k == g: break
            closed.add(k)
            i, j, l = k
            for di in (-1, 0, 1):
                for dj in (-1, 0, 1):
                    if di == 0 and dj == 0: continue
                    n = self.find(i + di, j + dj, l)
                    if n is None or n in closed: continue
                    e = self.edge.get(n, 0)
                    if e < 1: continue
                    if di and dj and (self.find(i + di, j, l) is None or self.find(i, j + dj, l) is None): continue
                    cx, cz, _ = self.center(n)
                    if blocked and blocked(cx, cz): continue
                    step = 1.4142 if di and dj else 1.0
                    pen = 1 + 0.35 * max(0, want - e)
                    ng = gcost + step * pen
                    if ng < gs.get(n, 1e18):
                        gs[n], parent[n] = ng, k
                        h = math.hypot(cx - gx, cz - gz) / CELL
                        heapq.heappush(openh, (ng + h, ng, n))
        if g not in parent and s != g: return None, "no road connection"
        path, k = [], g
        while k is not None:
            path.append(self.center(k)); k = parent.get(k)
        path.reverse()
        return path, "ok"


def smooth(path, grid, step=10):
    """string pulling (line of sight over cells at least 2 cells from the edge), then resample every `step` studs."""
    def ok(a, b):
        n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / (CELL * 0.5)))
        for t in range(1, n):
            x = a[0] + (b[0] - a[0]) * t / n; z = a[1] + (b[1] - a[1]) * t / n
            i, j = int(x // CELL), int(z // CELL)
            f = grid.find(i, j, round(a[2] / 6))
            if f is None or grid.edge.get(f, 0) < 2: return False
        return True
    out = [path[0]]; i = 0
    while i < len(path) - 1:
        j = len(path) - 1
        while j > i + 1 and not ok(path[i], path[j]): j -= 1
        out.append(path[j]); i = j
    dense = [out[0]]
    for a, b in zip(out, out[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1]); n = max(1, round(L / step))
        for t in range(1, n + 1):
            dense.append((a[0] + (b[0] - a[0]) * t / n, a[1] + (b[1] - a[1]) * t / n, a[2] + (b[2] - a[2]) * t / n))
    return dense


if __name__ == "__main__":
    folder = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\vared\Downloads\Download\workspace\ScrdsxScript\mapexport"
    parts = load_roads(folder)
    print(len(parts), "road parts")
    g = RoadGrid(parts)
    print(len(g.cells), "road cells")
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    tests = [((-1246, 3283), (-1488, 3782)), ((-1246, 3283), (-1190, 3640)), ((-1880, 1865), (-1880, 1034))]
    fig, ax = plt.subplots(figsize=(11, 11))
    xs = [c[0] * CELL + 2 for c in g.cells]; zs = [c[1] * CELL + 2 for c in g.cells]
    ax.scatter(xs, zs, s=1, c="#bbbbbb")
    cols = ["red", "blue", "green"]
    for (a, b), col in zip(tests, cols):
        path, why = g.plan(a, b)
        print(a, "->", b, why, len(path) if path else "")
        if path:
            d = smooth(path, g)
            ax.plot([p[0] for p in d], [p[1] for p in d], color=col, lw=1.5)
            ax.plot(*a, "o", color=col); ax.plot(*b, "s", color=col)
    ax.set_aspect("equal")
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "roadnet_test.png")
    fig.savefig(out, dpi=90)
    print("picture:", out)
