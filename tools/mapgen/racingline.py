"""The proving ground's drill roads as the mod's racing lines need them (tools/mapgen/build.py writes them to the level
as rallyAcademy/roads.json; ADR 0013).

The mod works out a drill's racing line itself (mod/lua/ge/extensions/rallyAcademy/racingLine.lua): the
minimum-curvature path inside the road through the drill's own gates, with a target speed at every point. What it
needs from the map is each road's centre line, a point every STEP m, with the ground's height there and how the road
tilts across (for banked and off-camber corners), plus the road's width and its surface's grip. Pure Python.
"""
import math

STEP = 3.0  # m between points
GRIP = {"gravel": 0.65, "dirt": 0.65, "asphalt": 1.0, "snow": 0.35, "mud": 0.45}  # by terrain material, lower case
TILT_REACH = 1.5  # m either side of the centre line where the tilt is measured


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


def road_samples(road, centre_line, height):
    """{id, width, grip, points: [[x, y, ground z, tilt]]}: tilt is the right side's ground above the left's, per
    metre, looking along the road's own direction."""
    pts = resample(centre_line, STEP)
    out = []
    for (x, y), (nx, ny) in zip(pts, normals(pts)):
        right = height(x - nx * TILT_REACH, y - ny * TILT_REACH)
        left = height(x + nx * TILT_REACH, y + ny * TILT_REACH)
        out.append([round(x, 2), round(y, 2), round(height(x, y), 2), round((right - left) / (2 * TILT_REACH), 3)])
    return {"id": road["id"], "width": road["width"], "grip": GRIP.get(road["material"].lower(), 0.65), "points": out}


def drill_roads(layout, terrain, road_line):
    """Every road with turn markers (the drill roads; layout "turnMarkers")."""
    roads = {r["id"]: r for r in layout.get("roads", [])}
    base = layout["terrain"]["baseZ"]

    def height(x, y):
        return base + terrain.height(x, y)
    return [road_samples(roads[m["road"]], road_line(roads[m["road"]]), height) for m in layout.get("turnMarkers", [])]
