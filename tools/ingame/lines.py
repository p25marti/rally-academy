"""Scripted driving lines for course drills, in course coordinates (x right, y ahead of the venue
start), for academy.course_run. Measured on West Coast USA, 0.39.4."""
import json
import math
from pathlib import Path

VENUES = Path(__file__).resolve().parents[2] / "mod" / "gameplay" / "rallyAcademy" / "venues.json"

# The BMP downhill left (venue bmp-gravel-corner, road network DR1181): centre-line nodes.
BMP_LEFT = [["DR1181_3", 150.93, 301.35], ["DR1181_5", 147.01, 283.01], ["DR1181_6", 147.34, 273.58], ["DR1181_7", 150.45, 264.49], ["DR1181_8", 155.71, 256.47], ["DR1181_9", 162.73, 249.86], ["DR1181_10", 169.6, 245.62], ["DR1181_11", 177.29, 242.49], ["DR1181_12", 185.81, 240.14], ["DR1181_13", 195.34, 239.74], ["DR1181_14", 203.37, 241.55], ["DR1181_15", 212.31, 245.11]]

# Lateral offset to the LEFT of the centre line at each node (the inside of this left turn):
# outside on entry, a late apex at node 9 (the A08 apex gate), the track-out at node 12 (the exit
# gate), then a straight line on. Tuned so the pure-pursuit follower (which cuts a little inside)
# clears the 3 m gates' posts in the Covet Gravel Rally.
BMP_LEFT_RACING = {"DR1181_3": -2.5, "DR1181_5": -2.0, "DR1181_6": -1.0, "DR1181_7": 0.5, "DR1181_8": 1.2,
                   "DR1181_9": 1.5, "DR1181_10": 1.0, "DR1181_11": -1.2, "DR1181_12": -3.5, "DR1181_13": -3.2,
                   "DR1181_14": -3.2, "DR1181_15": -3.2}


def _frame(venue_id):
    v = next(x for x in json.loads(VENUES.read_text(encoding="utf-8"))["venues"] if x["id"] == venue_id)
    p, d = v["spawn"]["pos"], v["spawn"]["dir"]
    n = math.hypot(d["x"], d["y"])
    fx, fy = d["x"] / n, d["y"] / n
    return p["x"], p["y"], fx, fy, fy, -fx


def bmp_left(offsets=None, tail=25):
    """Racing line through the BMP left (stock, downhill) or its flat copy on the proving ground (venue
    pg-corner-left, same course frame); `offsets` overrides BMP_LEFT_RACING per node, `tail` is how far the
    line runs on past the last node (the follower brakes to a stop over the end of it)."""
    sx, sy, fx, fy, rx, ry = _frame("bmp-gravel-corner")
    left = dict(BMP_LEFT_RACING, **(offsets or {}))
    names = [n for n, _, _ in BMP_LEFT]
    pts = {n: (x, y) for n, x, y in BMP_LEFT}

    def local(x, y):
        dx, dy = x - sx, y - sy
        return round(dx * rx + dy * ry, 2), round(dx * fx + dy * fy, 2)

    out = [(0.0, 0.0), (1.5, 40.0)]
    for i, nm in enumerate(names):
        a, b = names[max(0, i - 1)], names[min(len(names) - 1, i + 1)]
        th = math.atan2(pts[b][1] - pts[a][1], pts[b][0] - pts[a][0])
        off = left.get(nm, 0.0)
        out.append(local(pts[nm][0] + math.cos(th + math.pi / 2) * off, pts[nm][1] + math.sin(th + math.pi / 2) * off))
    last, prev = pts[names[-1]], pts[names[-2]]
    th = math.atan2(last[1] - prev[1], last[0] - prev[0])
    off = left.get(names[-1], 0.0)
    out.append(local(last[0] + math.cos(th) * tail + math.cos(th + math.pi / 2) * off,
                     last[1] + math.sin(th) * tail + math.sin(th + math.pi / 2) * off))
    return out
