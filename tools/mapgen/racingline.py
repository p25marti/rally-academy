"""Racing lines for the proving ground's drill roads (tools/mapgen/build.py, written to the level as
rallyAcademy/racingLines.json; the mod draws one when "Show line" is on).

A line is the minimum-curvature path inside the road: the centre line moved sideways at each point, as little bent
as the road allows while the car stays on it (a margin for half its width). It starts in the middle of the road,
where the drills start the car. Each point also carries a target speed: the fastest the corner allows on the road's
surface (its grip, with the banking or off-camber measured from the terrain), reached by accelerating out of the
corner before and braking for the next. The mod colours the line from it: red where to brake, green where to
accelerate. A guide, not a physics model: no gearing, gradient, downforce or combined grip. Pure Python.
"""
import math

STEP = 3.0  # m between the line's points
CAR_MARGIN = 1.3  # m kept between the line and each road edge: half a car and a little
G = 9.81
GRIP = {"gravel": 0.65, "dirt": 0.65, "asphalt": 1.0, "snow": 0.35, "mud": 0.45}  # by terrain material, lower case
ACCEL = 3.0  # m/s2 at most, flat out in a road car
BRAKE = 0.8  # of the grip
TOP = 140 / 3.6  # m/s
CENTRE_PULL = 1e-7  # a slight preference for the middle, so a straight with nothing to bend for stays there


def resample(line, step):
    """Points every `step` m along a polyline."""
    out, d, target = [], 0.0, 0.0
    for (ax, ay), (bx, by) in zip(line, line[1:]):
        seg = math.hypot(bx - ax, by - ay)
        while seg > 0 and target <= d + seg:
            t = (target - d) / seg
            out.append((ax + (bx - ax) * t, ay + (by - ay) * t))
            target += step
        d += seg
    return out


def normals(pts):
    """Unit vectors to the left of the way the line runs, at each point."""
    out = []
    for i in range(len(pts)):
        a, b = pts[max(0, i - 1)], pts[min(len(pts) - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dy) or 1.0
        out.append((-dy / n, dx / n))
    return out


def _solve_banded(rows, rhs):
    """Solve a symmetric positive-definite system with bandwidth 2. rows[i] = {j: value} for |i - j| <= 2."""
    n = len(rhs)
    # Gaussian elimination without pivoting keeps the band (fine for a positive-definite matrix).
    a = [dict(r) for r in rows]
    b = list(rhs)
    for i in range(n):
        piv = a[i][i]
        for k in range(i + 1, min(n, i + 3)):
            f = a[k].get(i, 0.0) / piv
            if f:
                for j in range(i, min(n, i + 3)):
                    a[k][j] = a[k].get(j, 0.0) - f * a[i].get(j, 0.0)
                b[k] -= f * b[i]
    x = [0.0] * n
    for i in range(n - 1, -1, -1):
        s = b[i] - sum(a[i].get(j, 0.0) * x[j] for j in range(i + 1, min(n, i + 3)))
        x[i] = s / a[i][i]
    return x


def min_curvature(centre, limit, fixed=2):
    """Sideways offsets (metres left of the centre line, within +-limit) that make the line as straight as possible:
    the least sum of squared second differences. The first `fixed` points stay on the centre line. Exact, by an
    active-set solve of the banded system (bounds clamped, then released while they pull the wrong way)."""
    n = len(centre)
    nv = normals(centre)
    # D_j = centre second difference + a_{j-1} n_{j-1} - 2 a_j n_j + a_{j+1} n_{j+1}, j = 1 .. n-2
    coef = (1.0, -2.0, 1.0)
    H = [dict() for _ in range(n)]
    g0 = [0.0] * n
    for j in range(1, n - 1):
        d = [centre[j - 1][k] - 2 * centre[j][k] + centre[j + 1][k] for k in (0, 1)]
        idx = (j - 1, j, j + 1)
        for p in range(3):
            i = idx[p]
            g0[i] += coef[p] * (d[0] * nv[i][0] + d[1] * nv[i][1])
            for q in range(3):
                k = idx[q]
                H[i][k] = H[i].get(k, 0.0) + coef[p] * coef[q] * (nv[i][0] * nv[k][0] + nv[i][1] * nv[k][1])
    for i in range(n):
        H[i][i] = H[i].get(i, 0.0) + CENTRE_PULL
    a = [0.0] * n
    clamped = {}  # index -> bound value
    for _ in range(200):
        free = [i for i in range(fixed, n) if i not in clamped]
        pos = {i: k for k, i in enumerate(free)}
        rows, rhs = [], []
        for i in free:
            rows.append({pos[k]: v for k, v in H[i].items() if k in pos})
            rhs.append(-g0[i] - sum(v * a[k] for k, v in H[i].items() if k not in pos))
        if free:
            for i, x in zip(free, _solve_banded(rows, rhs)):
                a[i] = x
        over = [i for i in free if abs(a[i]) > limit + 1e-9]
        for i in over:
            a[i] = math.copysign(limit, a[i])
            clamped[i] = a[i]
        released = []
        if not over:
            for i, v in list(clamped.items()):
                grad = g0[i] + sum(h * a[k] for k, h in H[i].items())
                if (v > 0 and grad > 1e-9) or (v < 0 and grad < -1e-9):  # it wants back inside the road
                    released.append(i)
            for i in released:
                del clamped[i]
        if not over and not released:
            break
    return a


def curvature(pts, i, reach=1):
    """Signed curvature (1/m, + turning left) through the points `reach` either side of i."""
    a, b, c = pts[max(0, i - reach)], pts[i], pts[min(len(pts) - 1, i + reach)]
    cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    ab, bc, ca = math.dist(a, b), math.dist(b, c), math.dist(c, a)
    return 0.0 if ab * bc * ca == 0 else 2 * cross / (ab * bc * ca)


def speeds(pts, grip, bank=None):
    """Target speed (m/s) at each point and what the driver does there: -1 brake, 1 accelerate, 0 hold the corner's
    limit. The speed is the corner's limit, then what accelerating from a standstill at the start and braking for each
    corner allow. `bank[i]`: the road's tilt across, as a slope, + leaning into the turn."""
    limit = []
    for i in range(len(pts)):
        k = abs(curvature(pts, i, reach=2))  # over 12 m: a kink in the road is no corner
        b = bank[i] if bank else 0.0
        if k < 1e-6 or 1 - grip * b <= 0:
            limit.append(TOP)
        else:
            limit.append(min(TOP, math.sqrt(max(0.0, G / k * (grip + b) / (1 - grip * b)))))
    fwd = list(limit)
    fwd[0] = 0.0
    for i in range(1, len(fwd)):
        fwd[i] = min(fwd[i], math.sqrt(fwd[i - 1] ** 2 + 2 * min(ACCEL, grip * G) * math.dist(pts[i - 1], pts[i])))
    v = list(fwd)
    for i in range(len(v) - 2, -1, -1):
        v[i] = min(v[i], math.sqrt(v[i + 1] ** 2 + 2 * BRAKE * grip * G * math.dist(pts[i], pts[i + 1])))
    # braking: held down by the next corner; accelerating: below the limit here; within 1 m/s counts as at it
    phase = [-1 if s < f - 1.0 else (1 if s < lim - 1.0 else 0) for s, f, lim in zip(v, fwd, limit)]
    return v, phase


def line_for(road, centre_line, height, reverse=False):
    """The racing line along a road the way drills drive it: [[x, y, ground z, km/h, phase]] every STEP m (phase: -1
    brake, 1 accelerate, 0 hold the corner's limit)."""
    pts = resample(list(reversed(centre_line)) if reverse else centre_line, STEP)
    off = min_curvature(pts, max(0.0, road["width"] / 2 - CAR_MARGIN))
    nv = normals(pts)
    line = [(p[0] + n[0] * a, p[1] + n[1] * a) for p, n, a in zip(pts, nv, off)]
    lnv = normals(line)
    bank = []
    for i, (p, n) in enumerate(zip(line, lnv)):
        # across the road at the line: the right side's ground above the left's, per metre; + into a left turn
        tilt = (height(p[0] - n[0] * 1.5, p[1] - n[1] * 1.5) - height(p[0] + n[0] * 1.5, p[1] + n[1] * 1.5)) / 3.0
        bank.append(tilt if curvature(line, i) >= 0 else -tilt)
    v, phase = speeds(line, GRIP.get(road["material"].lower(), 0.65), bank)
    return [[round(x, 2), round(y, 2), round(height(x, y), 2), round(s * 3.6), ph] for (x, y), s, ph in zip(line, v, phase)]


def racing_lines(layout, terrain, road_line):
    """Every turn-marked road's line, each way its drills drive it (layout "turnMarkers")."""
    roads = {r["id"]: r for r in layout.get("roads", [])}
    base = layout["terrain"]["baseZ"]

    def height(x, y):
        return base + terrain.height(x, y)
    out = []
    for m in layout.get("turnMarkers", []):
        r = roads[m["road"]]
        for way in m.get("directions", ["forward"]):
            out.append({"road": r["id"], "direction": way, "surface": r["material"],
                        "points": line_for(r, road_line(r), height, reverse=way == "reverse")})
    return out
