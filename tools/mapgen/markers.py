"""Rally corner boards for the proving ground's roads (tools/mapgen/build.py, layout "turnMarkers").

A real stage marks its corners: a direction board before each, showing which way and how sharp, and chevrons on the
outside where it turns. This finds the bends of a road from its centre line and picks the rally kit's board for each
(45 degrees, 90, or the tightest: a 135 right, a 225 hairpin left; the kit has no others) and a chevron sign for its
outside. Pure Python, no engine calls.
"""
import math

BOARDS = {  # (direction, severity) -> mesh; severity 1 = up to 65 degrees, 2 = up to 120 (left: 160), 3 = tighter
    ("left", 1): "/art/shapes/race/rally/rally_assets/s_corner_dir45_left.dae",
    ("left", 2): "/art/shapes/race/rally/rally_assets/s_corner_dir_left.dae",
    ("left", 3): "/art/shapes/race/rally/rally_assets/s_corner_dir225_left.dae",
    ("right", 1): "/art/shapes/race/rally/rally_assets/s_corner_dir45_right.dae",
    ("right", 2): "/art/shapes/race/rally/rally_assets/s_corner_dir_right.dae",
    ("right", 3): "/art/shapes/race/rally/rally_assets/s_corner_dir135_right.dae",
}


def resample(line, step=1.0):
    """Points every `step` m along a polyline, with their distance along it."""
    out, d, target = [], 0.0, 0.0
    for (ax, ay), (bx, by) in zip(line, line[1:]):
        seg = math.hypot(bx - ax, by - ay)
        while seg > 0 and target <= d + seg:
            t = (target - d) / seg
            out.append((ax + (bx - ax) * t, ay + (by - ay) * t, target))
            target += step
        d += seg
    return out


def bends(line, max_radius=120.0, min_deg=25.0, join_m=12.0):
    """The road's bends in travel order: [{"from", "to" (m along), "deg" (signed, + left)}]. A bend is a stretch
    curving tighter than `max_radius`; stretches the same way less than `join_m` apart are one bend (an S is two)."""
    pts = resample(line)
    if len(pts) < 12:
        return []
    heads = [math.atan2(b[1] - a[1], b[0] - a[0]) for a, b in zip(pts, pts[1:])]

    def turn(i, j):  # heading change from step i to step j, unwrapped
        return math.atan2(math.sin(heads[j] - heads[i]), math.cos(heads[j] - heads[i]))
    w = 4  # curvature over +-4 m smooths the polyline's joints
    curv = [turn(max(0, i - w), min(len(heads) - 1, i + w)) / (min(len(heads) - 1, i + w) - max(0, i - w))
            for i in range(len(heads))]
    runs, cur = [], None
    for i, k in enumerate(curv):
        sign = 1 if k > 0 else -1
        if abs(k) >= 1.0 / max_radius:
            if cur and cur["sign"] == sign and i - cur["to"] <= 1:
                cur["to"] = i
            else:
                cur = {"from": i, "to": i, "sign": sign}
                runs.append(cur)
    # drop blips (a wobble in a copied centre line), then join same-way stretches close together into one bend
    runs = [r for r in runs if r["to"] - r["from"] >= 5 or abs(math.degrees(turn(r["from"], r["to"]))) >= 10]
    joined = []
    for r in runs:
        if joined and joined[-1]["sign"] == r["sign"] and r["from"] - joined[-1]["to"] <= join_m:
            joined[-1]["to"] = r["to"]
        else:
            joined.append(dict(r))
    out = []
    for r in joined:
        deg = math.degrees(turn(max(0, r["from"] - 1), min(len(heads) - 1, r["to"] + 1)))
        if abs(deg) >= min_deg:
            out.append({"from": pts[r["from"]][2], "to": pts[r["to"]][2], "deg": round(deg, 1)})
    return out


CHEVRONS = {"left": "/art/shapes/objects/race_arrowsign_1_L.dae", "right": "/art/shapes/objects/race_arrowsign_1_R.dae"}


def board(deg):
    side = "left" if deg > 0 else "right"
    a = abs(deg)
    sev = 1 if a < 65 else 2 if a < (160 if side == "left" else 120) else 3
    return BOARDS[(side, sev)]


def placements(line, width, lead=25.0, gap=3.0, **kw):
    """[(x, y, travel heading in degrees, mesh, bend)] for each bend of `line` driven from its start: a board `lead` m
    before the bend begins (at least 5 m into the road), `gap` m outside the road's edge on the bend's outside."""
    pts = resample(line)
    out, prev_end = [], 0.0
    for b in bends(line, **kw):
        s = max(5.0, prev_end + 3.0, b["from"] - lead)  # never inside the bend before
        prev_end = b["to"]
        i = min(len(pts) - 2, int(s))
        (ax, ay, _), (bx, by, _) = pts[i], pts[i + 1]
        hx, hy = bx - ax, by - ay
        n = math.hypot(hx, hy) or 1.0
        hx, hy = hx / n, hy / n
        side = -1.0 if b["deg"] > 0 else 1.0  # outside of a left bend is the right (-left)
        off = side * (width / 2 + gap)
        out.append((ax - hy * off, ay + hx * off, math.degrees(math.atan2(hy, hx)), board(b["deg"]), b))
    return out


def chevrons(line, width, into=12.0, gap=7.0, **kw):
    """[(x, y, approach heading in degrees, mesh, bend)]: a chevron sign on the outside of each bend, `into` m past
    where it begins (or a third of the way round a short bend), `gap` m beyond the road's edge (behind the run-off
    barriers, so it stands clear above them), facing the way the car
    comes in (the heading 10 m before the bend), so it stands ahead of the driver as the road turns away."""
    pts = resample(line)
    out = []
    for b in bends(line, **kw):
        s = b["from"] + min(into, (b["to"] - b["from"]) / 3)
        i = min(len(pts) - 2, int(s))
        j = max(0, min(len(pts) - 2, int(b["from"] - 10)))
        (ax, ay, _), (bx, by, _) = pts[i], pts[i + 1]
        hx, hy = bx - ax, by - ay
        n = math.hypot(hx, hy) or 1.0
        hx, hy = hx / n, hy / n
        side = -1.0 if b["deg"] > 0 else 1.0
        off = side * (width / 2 + gap)
        approach = math.degrees(math.atan2(pts[j + 1][1] - pts[j][1], pts[j + 1][0] - pts[j][0]))
        out.append((ax - hy * off, ay + hx * off, approach, CHEVRONS["left" if b["deg"] > 0 else "right"], b))
    return out
