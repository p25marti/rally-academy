"""Road centre lines from straights and arcs, for authoring roads in proving_ground.json (the camber, jump, rough and
ford roads were made this way, ADR 0010) and for tests. Stdlib only.

    pts, bank, zs = road([("S", 50), ("L", 35, 90, {"bank": -0.16}), ("S", 40)], heading_deg=90)

A segment is ("S", metres) or ("L" / "R", radius, degrees), optionally ending in a dict of attributes: "bank" (the
road's slope across, + left, for every point of the segment) and "z" ((from, to) metres above the ground, linear
along the segment). Points start at (0, 0); a road's "origin" moves them into place.
"""
import math


def road(segments, heading_deg=0.0, step=4.0):
    """(points [(x, y)], bank per point, z per point) along the segments, a point every ~`step` m."""
    x, y, h = 0.0, 0.0, math.radians(heading_deg)
    pts, bank, zs = [(0.0, 0.0)], [0.0], [0.0]
    z = 0.0
    for seg in segments:
        attrs = seg[-1] if isinstance(seg[-1], dict) else {}
        if seg[0] == "S":
            n = max(1, int(round(seg[1] / step)))
            moves = [(seg[1] / n, 0.0)] * n
        else:
            r, total = seg[1], math.radians(seg[2])
            n = max(2, int(round(r * total / step)))
            sgn = 1 if seg[0] == "L" else -1
            moves = [(2 * r * math.sin(total / n / 2), sgn * total / n)] * n  # chords of the arc
        z0, z1 = attrs.get("z", (z, z))
        for i, (c, dh) in enumerate(moves):
            x += math.cos(h + dh / 2) * c
            y += math.sin(h + dh / 2) * c
            h += dh
            pts.append((round(x, 2), round(y, 2)))
            bank.append(attrs.get("bank", 0.0))
            zs.append(round(z0 + (z1 - z0) * (i + 1) / len(moves), 3))
        z = z1
    return pts, bank, zs
