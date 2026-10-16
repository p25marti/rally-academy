"""Find drill-shaped road sections in a map's AI road network (map.getMap() in GE Lua).

Pure Python (no game needed), so it's unit-tested (tests/python/test_roads.py). survey.py
fetches the network from the running game and calls these.

The network is nodes {name: (x, y, z, radius)} and links (a, b, drivability, speedLimit).
`radius` is half the road width. Drivability is a road class, not a surface: the asphalt
BMP straight on West Coast USA is 0.5 (survey.py checks surfaces separately).
"""
import math
from collections import defaultdict


def build(nodes, links):
    """Adjacency {name: {neighbour: link}} from links; ignores links to unknown nodes."""
    adj = defaultdict(dict)
    for a, b, drivability, speed in links:
        if a in nodes and b in nodes and a != b:
            link = {"drivability": drivability, "speed": speed}
            adj[a][b] = link
            adj[b][a] = link
    return adj


def chains(nodes, adj):
    """Split the network into polylines that run between junctions or dead ends (degree != 2).
    Returns lists of node names; loops without junctions come back once, closed."""
    seen_edges, out = set(), []

    def walk(start, nxt):
        path, prev, cur = [start], start, nxt
        while True:
            seen_edges.add(frozenset((prev, cur)))
            path.append(cur)
            if len(adj[cur]) != 2 or cur == start:
                return path
            prev, cur = cur, next(n for n in adj[cur] if n != prev)

    for n in adj:
        if len(adj[n]) != 2:
            for m in adj[n]:
                if frozenset((n, m)) not in seen_edges:
                    out.append(walk(n, m))
    for n in adj:  # pure loops (every node degree 2)
        for m in adj[n]:
            if frozenset((n, m)) not in seen_edges:
                out.append(walk(n, m))
    return out


def _xy(nodes, name):
    return nodes[name][0], nodes[name][1]


def _dist(nodes, a, b):
    (ax, ay), (bx, by) = _xy(nodes, a), _xy(nodes, b)
    return math.hypot(bx - ax, by - ay)


def _heading(nodes, a, b):
    (ax, ay), (bx, by) = _xy(nodes, a), _xy(nodes, b)
    return math.atan2(by - ay, bx - ax)


def _wrap(angle):
    return (angle + math.pi) % (2 * math.pi) - math.pi


def _width(nodes, names):
    return 2 * min(nodes[n][3] for n in names)


def _drivability(adj, names):
    vals = [adj[a][b]["drivability"] for a, b in zip(names, names[1:]) if b in adj[a]]
    return round(min(vals), 2) if vals else None


def _section(nodes, adj, names, kind, **extra):
    """A candidate: start pose (position, unit direction), length, width, drivability."""
    a, b = names[0], names[1]
    h = _heading(nodes, a, b)
    x, y, z, _ = nodes[a]
    length = sum(_dist(nodes, p, q) for p, q in zip(names, names[1:]))
    return {"kind": kind, "pos": {"x": round(x, 2), "y": round(y, 2), "z": round(z, 2)},
            "dir": {"x": round(math.cos(h), 4), "y": round(math.sin(h), 4)},
            "length": round(length, 1), "width": round(_width(nodes, names), 1),
            "drivability": _drivability(adj, names), "nodes": [names[0], names[-1]], **extra}


def _off_line(nodes, names, i, j):
    """Largest distance of the points between i and j from the straight line i -> j."""
    (ax, ay), (bx, by) = _xy(nodes, names[i]), _xy(nodes, names[j])
    L = math.hypot(bx - ax, by - ay) or 1e-9
    worst = 0.0
    for k in range(i + 1, j):
        px, py = _xy(nodes, names[k])
        worst = max(worst, abs((bx - ax) * (ay - py) - (ax - px) * (by - ay)) / L)
    return worst


def straights(nodes, adj, min_length=100.0, tolerance=1.5):
    """Sections that stay within `tolerance` metres of a straight line for at least `min_length`."""
    out = []
    for names in chains(nodes, adj):
        i = 0
        while i < len(names) - 1:
            j = i + 1
            while j + 1 < len(names) and _off_line(nodes, names, i, j + 1) <= tolerance:
                j += 1
            seg = names[i:j + 1]
            if len(seg) >= 2 and _dist(nodes, seg[0], seg[-1]) >= min_length:
                grade = (nodes[seg[-1]][2] - nodes[seg[0]][2]) / _dist(nodes, seg[0], seg[-1])
                out.append(_section(nodes, adj, seg, "straight", gradePct=round(100 * grade, 1)))
            i = j
    return sorted(out, key=lambda s: -s["length"])


def _circumradius(p, q, r):
    """Radius of the circle through three points (inf when they're in line), and turn sign."""
    a, b, c = math.dist(p, q), math.dist(q, r), math.dist(p, r)
    cross = (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    if abs(cross) < 1e-9:
        return math.inf, 0
    return a * b * c / (2 * abs(cross)), (1 if cross > 0 else -1)


def corners(nodes, adj, max_radius=80.0, min_turn_deg=30.0, min_radius=8.0):
    """Runs of nodes curving the same way tighter than `max_radius`, turning at least
    `min_turn_deg` in total. Labels: hairpin (>= 150 deg), decreasing/increasing radius
    (exit radius < 0.7x or > 1.4x the entry radius), else constant. Bends tighter than
    `min_radius` are skipped: on real maps those are junction and car-park artefacts."""
    out = []
    for names in chains(nodes, adj):
        pts = [_xy(nodes, n) for n in names]
        bends = [(None, 0)] + [_circumradius(pts[k - 1], pts[k], pts[k + 1]) for k in range(1, len(pts) - 1)] + [(None, 0)]
        k = 1
        while k < len(names) - 1:
            r, sign = bends[k]
            if not (r and r <= max_radius):
                k += 1
                continue
            start = k
            while k + 1 < len(names) - 1 and bends[k + 1][0] and bends[k + 1][0] <= max_radius and bends[k + 1][1] == sign:
                k += 1
            seg = names[start - 1:k + 2]
            turn = sum(_wrap(_heading(nodes, seg[m + 1], seg[m + 2]) - _heading(nodes, seg[m], seg[m + 1]))
                       for m in range(len(seg) - 2))
            radii = [bends[m][0] for m in range(start, k + 1)]
            if abs(math.degrees(turn)) >= min_turn_deg and min(radii) >= min_radius:
                entry, exit_ = radii[0], radii[-1]
                shape = ("hairpin" if abs(math.degrees(turn)) >= 150 else
                         "decreasing" if exit_ < 0.7 * entry else
                         "increasing" if exit_ > 1.4 * entry else "constant")
                out.append(_section(nodes, adj, seg, "corner", turnDeg=round(math.degrees(turn)),
                                    direction="left" if sign > 0 else "right", minRadius=round(min(radii), 1),
                                    entryRadius=round(entry, 1), exitRadius=round(exit_, 1), shape=shape))
            k += 1
    return sorted(out, key=lambda s: -abs(s["turnDeg"]))


def hills(nodes, adj, min_grade_pct=6.0, min_length=60.0):
    """Climbs or descents steeper than `min_grade_pct` for at least `min_length`."""
    out = []
    for names in chains(nodes, adj):
        grades = []
        for a, b in zip(names, names[1:]):
            d = _dist(nodes, a, b)
            grades.append(100 * (nodes[b][2] - nodes[a][2]) / d if d > 0 else 0)
        k = 0
        while k < len(grades):
            if abs(grades[k]) < min_grade_pct:
                k += 1
                continue
            sign, start = (1 if grades[k] > 0 else -1), k
            while k + 1 < len(grades) and abs(grades[k + 1]) >= min_grade_pct and (grades[k + 1] > 0) == (sign > 0):
                k += 1
            seg = names[start:k + 2]
            length = sum(_dist(nodes, p, q) for p, q in zip(seg, seg[1:]))
            if length >= min_length:
                rise = nodes[seg[-1]][2] - nodes[seg[0]][2]
                out.append(_section(nodes, adj, seg, "uphill" if sign > 0 else "downhill",
                                    gradePct=round(100 * rise / length, 1), riseM=round(rise, 1)))
            k += 1
    return sorted(out, key=lambda s: -abs(s["gradePct"]))


def crests(nodes, adj, min_grade_pct=4.0, max_span=60.0):
    """A climb of at least `min_grade_pct` turning into a descent of at least that within
    `max_span` metres: a crest (jumps, E05)."""
    out = []
    for names in chains(nodes, adj):
        for k in range(1, len(names) - 1):
            a, m = names[k - 1], names[k]
            d1 = _dist(nodes, a, m)
            if d1 <= 0 or 100 * (nodes[m][2] - nodes[a][2]) / d1 < min_grade_pct:
                continue
            span = d1
            for j in range(k + 1, len(names)):
                span += _dist(nodes, names[j - 1], names[j])
                if span > max_span:
                    break
                d2 = _dist(nodes, names[j - 1], names[j])
                if d2 > 0 and 100 * (nodes[names[j]][2] - nodes[names[j - 1]][2]) / d2 <= -min_grade_pct:
                    out.append(_section(nodes, adj, names[k - 1:j + 1], "crest", spanM=round(span, 1)))
                    break
    return out


def dedupe(sections, radius=25.0):
    """Drop sections that start within `radius` metres of a better one (input order = preference)."""
    kept = []
    for s in sections:
        if all(math.dist((s["pos"]["x"], s["pos"]["y"]), (k["pos"]["x"], k["pos"]["y"])) > radius for k in kept):
            kept.append(s)
    return kept


def nearest(nodes, x, y):
    """Name of the road node closest to (x, y)."""
    return min(nodes, key=lambda n: (nodes[n][0] - x) ** 2 + (nodes[n][1] - y) ** 2)


def follow(nodes, adj, start, heading, length):
    """Walk the road from node `start` for `length` metres, setting off in `heading`
    (radians) and at each node taking the link that turns least. -> list of node names."""
    path, prev, cur, dist, h = [start], None, start, 0.0, heading
    while dist < length:
        options = [n for n in adj.get(cur, {}) if n != prev]
        if not options:
            break
        nxt = min(options, key=lambda n: abs(_wrap(_heading(nodes, cur, n) - h)))
        if prev is None and abs(_wrap(_heading(nodes, cur, nxt) - h)) > math.radians(100):
            break  # nothing goes the way we're facing
        dist += _dist(nodes, cur, nxt)
        h = _heading(nodes, cur, nxt)
        prev, cur = cur, nxt
        path.append(cur)
    return path

