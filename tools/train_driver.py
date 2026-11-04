"""Offline trainer for the autopilot.

Input : a drive recording made with tools/drive_record.lua (ScrdsxScript/driverec_latest.csv) = a human driving on the real roads.
It does:
  1. measures the car (wheelbase, steering limits, acceleration, braking) and how hard the human corners,
  2. turns the good stretches of the recording into routes (the human stayed on the road, so the line is a valid road line),
  3. simulates the autopilot's controller (same pure pursuit / speed planner as src/autodrive.lua) on those routes with the game's real
     steering behaviour (wheel moves 1.5/s toward the key, 4.5/s back, steering angle shrinks with speed),
  4. searches the controller settings (kp, kd, look-ahead, cornering grip, speed) that follow the road best and fastest,
  5. writes them into drivetune.json.
usage: python train_driver.py [driverec.csv] [drivetune.json]
"""
import csv, json, math, random, sys, os

REC = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\vared\Downloads\Download\workspace\ScrdsxScript\driverec_latest.csv"
OUT = sys.argv[2] if len(sys.argv) > 2 else r"C:\Users\vared\Downloads\Download\workspace\ScrdsxScript\drivetune.json"

# ---- measured car (from driverec_latest.csv analysis)
WHEELBASE = 10.6
MAXANG = 26.0                 # degrees at low speed, shrinks as 1/max(1, v/35)
GRIP = 95.0                   # lateral acceleration the car can hold (studs/s^2)
ACCEL = [(0, 9.1), (20, 9.1), (40, 7.8), (60, 7.3), (90, 5.0), (120, 2.1), (150, 1.0)]
BRAKE, COAST = 17.6, 1.7
VCAP = 80.0                   # the autopilot never plans faster than this (st/s), times speedMul
BRAKE_PLAN = 14.0             # deceleration the planner counts on (below the real 17.6 to keep a margin)


def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def accel_at(v):
    for (v0, a0), (v1, a1) in zip(ACCEL, ACCEL[1:]):
        if v <= v1:
            return a0 + (a1 - a0) * (v - v0) / max(v1 - v0, 1e-9)
    return ACCEL[-1][1]


# ------------------------------------------------------------------ routes from the recording
def load_routes(path):
    rows = list(csv.DictReader(open(path)))
    X = [float(r["x"]) for r in rows]; Z = [float(r["z"]) for r in rows]
    fs = [float(r["fwdSpeed"]) for r in rows]; on = [int(r["onRoad"]) for r in rows]
    n = len(rows)
    # smooth (moving average +-3 samples)
    sx = [sum(X[max(0, i - 3):i + 4]) / len(X[max(0, i - 3):i + 4]) for i in range(n)]
    sz = [sum(Z[max(0, i - 3):i + 4]) / len(Z[max(0, i - 3):i + 4]) for i in range(n)]
    good = [fs[i] > 8 and on[i] == 1 for i in range(n)]
    segs, cur = [], []
    for i in range(n):
        if good[i]:
            cur.append((sx[i], sz[i]))
        else:
            if len(cur) > 40: segs.append(cur)
            cur = []
    if len(cur) > 40: segs.append(cur)
    routes = []
    for seg in segs:
        # resample every 12 studs
        pts = [seg[0]]
        acc = 0.0
        for a, b in zip(seg, seg[1:]):
            acc += math.hypot(b[0] - a[0], b[1] - a[1])
            if acc >= 12:
                pts.append(b); acc = 0.0
        # cut into chunks of ~45 points (540 studs)
        for k in range(0, len(pts) - 12, 40):
            chunk = pts[k:k + 45]
            if len(chunk) >= 15:
                routes.append(chunk)
    return routes


# ------------------------------------------------------------------ simulation of the autopilot
class Params:
    def __init__(self, kp, kd, lookBase, lookGain, latAcc, speedMul):
        self.kp, self.kd, self.lookBase, self.lookGain, self.latAcc, self.speedMul = kp, kd, lookBase, lookGain, latAcc, speedMul

    def as_dict(self):
        return dict(kp=self.kp, kd=self.kd, lookBase=self.lookBase, lookGain=self.lookGain, latAcc=self.latAcc, speedMul=self.speedMul)


def simulate(P, route, var, dt=1 / 30):
    wb = WHEELBASE * var["wb"]; ang = MAXANG * var["ang"]; acc_scale = var["acc"]
    path = [(route[0][0] - 12 * math.sin(0), route[0][1])] + route  # start slightly behind the first point, like the car
    # initial heading along the route
    h0 = math.atan2(route[1][0] - route[0][0], route[1][1] - route[0][1])
    path[0] = (route[0][0] - 6 * math.sin(h0) + var["off"] * math.cos(h0), route[0][1] - 6 * math.cos(h0) - var["off"] * math.sin(h0))
    seglen = [math.hypot(path[i + 1][0] - path[i][0], path[i + 1][1] - path[i][1]) for i in range(len(path) - 1)]
    total = sum(seglen)

    def remaining(i, t):
        r = seglen[i] * (1 - t)
        return r + sum(seglen[i + 1:])

    def point_ahead(i, t, dist):
        ax, az = path[i]; bx, bz = path[i + 1]
        px, pz = ax + (bx - ax) * t, az + (bz - az) * t
        left = seglen[i] * (1 - t)
        cur = i
        while dist > left and cur < len(path) - 2:
            dist -= left
            cur += 1
            px, pz = path[cur]
            left = seglen[cur]
        if cur >= len(path) - 2 and dist > left:
            return path[-1]
        a2, b2 = path[cur], path[cur + 1]
        if seglen[cur] < 0.01:
            return b2
        ux, uz = (b2[0] - a2[0]) / seglen[cur], (b2[1] - a2[1]) / seglen[cur]
        d = min(dist, left)
        return (px + ux * d, pz + uz * d)

    x, z = path[0]
    yaw = h0 + var["yaw0"]
    v = 6.0
    uW = 0.0                       # wheel position (attribute space)
    thr = 0.0                      # current throttle command (-1, 0, 1)
    keyq = [0, 0]                  # latency queue for the steering key (1 frame) and throttle
    thrq = [0, 0]
    yawRate = 0.0
    seg = 0
    t_end = total / 8 + 40
    t = 0.0
    sum_cte = 0.0; n = 0; off = 0; maxcte = 0.0; spin = 0
    steer_sign = -1
    while t < t_end:
        t += dt
        # nearest point on the route (window like the Lua)
        bestd, bi, bt = 1e9, seg, 0.0
        for i in range(max(seg - 1, 0), min(len(path) - 2, seg + 6) + 1):
            ax, az = path[i]; bx, bz = path[i + 1]
            abx, abz = bx - ax, bz - az
            l2 = abx * abx + abz * abz
            tt = max(0.0, min(1.0, ((x - ax) * abx + (z - az) * abz) / l2)) if l2 > 0.01 else 0.0
            d = math.hypot(x - (ax + abx * tt), z - (az + abz * tt))
            if d < bestd:
                bestd, bi, bt = d, i, tt
        seg = max(seg, bi)
        rem = remaining(bi, bt)
        if rem < 10:
            break
        sum_cte += bestd; n += 1; maxcte = max(maxcte, bestd)
        if bestd > 6.0: off += 1

        # controller (port of autodrive.lua)
        look = max(12.0, min(50.0, P.lookBase + v * P.lookGain))
        ax, az = point_ahead(bi, bt, look)
        e = wrap(math.atan2(ax - x, az - z) - yaw)
        kp = P.kp / (1 + v / 40)
        steer_cmd = max(-1.0, min(1.0, e * kp - yawRate * P.kd)) * steer_sign
        steer_cmd = round(steer_cmd * 50) / 50

        # speed planner
        allowed = min(VCAP, VCAP) * P.speedMul
        p_prev = point_ahead(bi, bt, 4); h_prev = None
        for k in range(1, 9):
            d = 4 + k * 14
            pt = point_ahead(bi, bt, d)
            h = math.atan2(pt[0] - p_prev[0], pt[1] - p_prev[1])
            if h_prev is not None:
                kappa = abs(wrap(h - h_prev)) / 14
                vk = math.sqrt(P.latAcc / max(kappa, 0.0004))
                allowed = min(allowed, math.sqrt(vk * vk + 2 * BRAKE_PLAN * max(d - 14, 0)))
            p_prev, h_prev = pt, h
        corner = 1 - max(0.0, min(0.5, abs(e) / 1.5))
        target = min(allowed * corner, math.sqrt(2 * 10 * max(rem - 22, 0)) + 8)
        target = max(target, 14)
        if v < target - 3: thr_cmd = 1
        elif v > target + 8: thr_cmd = -1
        elif v > target + 2: thr_cmd = 0
        else: thr_cmd = thr
        thr = thr_cmd

        # actuator: choose the key that puts the (modelled) wheel closest to the wanted angle on the next frame
        bestk, beste = 0, 1e9
        for a in (0, 1, -1):
            rate = 4.5 if uW * a <= 0 else 1.5
            nxt = uW + max(-rate * dt, min(rate * dt, a - uW))
            er = abs(nxt - steer_cmd)
            if er < beste - 1e-6:
                bestk, beste = a, er
        keyq.append(bestk); thrq.append(thr_cmd)
        key_now = keyq.pop(0); thr_now = thrq.pop(0)

        # the car
        rate = 4.5 if uW * key_now <= 0 else 1.5
        uW += max(-rate * dt, min(rate * dt, key_now - uW))
        delta = math.radians(ang / max(1.0, v / 35.0) * uW)
        om = -(v / wb) * math.tan(delta)
        if v > 1 and abs(v * om) > GRIP:
            om = math.copysign(GRIP / v, om)
            spin += 1
        yaw += om * dt
        yawRate = yawRate * 0.6 + om * 0.4
        if thr_now > 0: a_long = accel_at(v) * acc_scale
        elif thr_now < 0: a_long = -BRAKE
        else: a_long = -COAST
        v = max(0.0, v + a_long * dt)
        x += v * math.sin(yaw) * dt
        z += v * math.cos(yaw) * dt
    done = rem < 10
    dist = total - rem
    mean_cte = sum_cte / max(n, 1)
    speed = dist / max(t, 1e-6)
    cost = mean_cte * 3 + 25 * (off / max(n, 1)) + max(0.0, maxcte - 8) * 1.5 + 100 * (spin / max(n, 1)) + (0 if done else 80) + (100 / max(speed, 5)) * 8
    return cost, dict(cte=mean_cte, max=maxcte, off=off / max(n, 1), speed=speed, done=done, slide=spin / max(n, 1))


def evaluate(P, routes, variants):
    tot = 0.0; stats = []
    for r in routes:
        for var in variants:
            c, s = simulate(P, r, var)
            tot += c; stats.append(s)
    k = len(routes) * len(variants)
    return tot / k, dict(
        cte=sum(s["cte"] for s in stats) / k, max=max(s["max"] for s in stats), off=sum(s["off"] for s in stats) / k,
        speed=sum(s["speed"] for s in stats) / k, done=sum(1 for s in stats if s["done"]) / k, slide=sum(s["slide"] for s in stats) / k)


def main():
    routes = load_routes(REC)
    print(f"{len(routes)} route chunks from {REC}", flush=True)
    if not routes:
        sys.exit("no usable driving in the recording")
    random.seed(7)
    pick = routes if len(routes) <= 6 else random.sample(routes, 6)
    variants = [
        dict(wb=1.0, ang=1.0, acc=1.0, off=0.0, yaw0=0.0),
        dict(wb=1.12, ang=0.9, acc=0.85, off=3.0, yaw0=0.15),
        dict(wb=0.92, ang=1.1, acc=1.15, off=-3.0, yaw0=-0.15),
    ]
    old = Params(1.74, 0.22, 11.2, 0.53, 16.0, 1.1)
    base, bs = evaluate(old, pick, variants)
    print(f"current settings : cost {base:.1f}  cte {bs['cte']:.2f} studs  max {bs['max']:.1f}  off-lane {bs['off']*100:.1f}%  speed {bs['speed']:.1f}  finished {bs['done']*100:.0f}%  sliding {bs['slide']*100:.1f}%")

    rng = {"kp": (0.6, 4.0), "kd": (0.02, 0.7), "lookBase": (5, 25), "lookGain": (0.1, 1.2), "latAcc": (15, 90), "speedMul": (0.6, 1.2)}
    best, bestc, beststats = old, base, bs
    # coarse random search, then local perturbation
    for it in range(150):
        cand = Params(*[random.uniform(*rng[k]) for k in ("kp", "kd", "lookBase", "lookGain", "latAcc", "speedMul")])
        c, s = evaluate(cand, pick, variants)
        if c < bestc:
            best, bestc, beststats = cand, c, s
            print(f"  random {it:3d}: cost {bestc:.1f}  cte {s['cte']:.2f}  speed {s['speed']:.1f}  finished {s['done']*100:.0f}%", flush=True)
    print(f"after random search: cost {bestc:.1f}")
    for it in range(450):
        d = best.as_dict()
        k = random.choice(list(d))
        d[k] = min(rng[k][1], max(rng[k][0], d[k] * (1 + random.gauss(0, 0.12))))
        cand = Params(**d)
        c, s = evaluate(cand, pick, variants)
        if c < bestc:
            best, bestc, beststats = cand, c, s
            print(f"  refine {it:3d}: cost {bestc:.1f}  cte {s['cte']:.2f}  speed {s['speed']:.1f}  kp {best.kp:.2f} kd {best.kd:.2f} look {best.lookBase:.1f}+{best.lookGain:.2f}v grip {best.latAcc:.0f} x{best.speedMul:.2f}", flush=True)
    # check on ALL routes (not only the 8 used for training)
    allc, alls = evaluate(best, routes, variants)
    oldc, olds = evaluate(old, routes, variants)
    print("\nbest settings:", {k: round(v, 3) for k, v in best.as_dict().items()})
    print(f"on all {len(routes)} routes: cost {allc:.1f} (current settings {oldc:.1f})")
    print(f"  cte {alls['cte']:.2f} (was {olds['cte']:.2f})   max {alls['max']:.1f} (was {olds['max']:.1f})   off-lane {alls['off']*100:.1f}% (was {olds['off']*100:.1f}%)")
    print(f"  speed {alls['speed']:.1f} (was {olds['speed']:.1f})   finished {alls['done']*100:.0f}% (was {olds['done']*100:.0f}%)")

    try:
        data = json.load(open(OUT)) if os.path.exists(OUT) else {}
    except Exception:
        data = {}
    data.setdefault("p", {}).update({k: round(v, 4) for k, v in best.as_dict().items()})
    data["p"].setdefault("bendDiv", 1.4)
    data["cost"] = None
    data["trips"] = 0
    data.setdefault("pieces", {})
    json.dump(data, open(OUT, "w"))
    print("written to", OUT)


if __name__ == "__main__":
    main()
