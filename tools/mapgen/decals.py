"""Road decals for generated levels (tools/mapgen/build.py): edge blends, wear and markings drawn over the terrain
as DecalRoad objects. Purely visual: the wheels still read the terrain material painted underneath, so grip and
grading don't change.

Layout "decals": a list of entries, each with a `material` (borrowed from the stock level named in the layout's
"decalMaterials" map), a `width` and optionally `textureLength`, `priority` (lower draws on top), `fade`:
  {"kind": "road_edges", "road": id}             both edges of a road, straddling the edge
  {"kind": "road_track", "road": id, "offset": m} a line along a road, `offset` m to the left of its centre
  {"kind": "pad_edges", "pads": [ids]}            round the outline of rectangular pads
  {"kind": "line", "points": [[x, y], ...]}       through world points
  {"kind": "circle", "center": [x, y], "radius": m, "from": deg, "to": deg}   an arc (degrees, 0 = east, anticlockwise)
"""
import math


def offset_line(line, d):
    """The polyline shifted `d` m to its left."""
    out = []
    for i, (x, y) in enumerate(line):
        a, b = line[max(0, i - 1)], line[min(len(line) - 1, i + 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        n = math.hypot(tx, ty) or 1.0
        out.append((x - ty / n * d, y + tx / n * d))
    return out


def resample(line, step):
    """Points every ~`step` m along the polyline (DecalRoads look best with nodes a few metres apart)."""
    out = [line[0]]
    acc = 0.0
    for (ax, ay), (bx, by) in zip(line, line[1:]):
        seg = math.hypot(bx - ax, by - ay)
        acc += seg
        if acc >= step:
            out.append((bx, by))
            acc = 0.0
    if out[-1] != line[-1]:
        out.append(line[-1])
    return out


def lines_for(entry, layout, road_line):
    """The polylines an entry draws, in world coordinates."""
    k = entry["kind"]
    if k in ("road_edges", "road_track"):
        r = next(r for r in layout["roads"] if r["id"] == entry["road"])
        centre = road_line(r)
        if k == "road_track":
            return [offset_line(centre, entry.get("offset", 0.0))]
        half = r["width"] / 2
        # each edge drawn with the road on the same side of the line (the right edge reversed), so a blend's
        # gradient faces the road on both sides
        return [offset_line(centre, half), list(reversed(offset_line(centre, -half)))]
    if k == "pad_edges":
        out = []
        for p in layout["pads"]:
            if p["id"] in entry["pads"]:
                (x0, x1), (y0, y1) = p["x"], p["y"]
                # clockwise seen from above, so the pad is on the right of travel
                out.append([(x0, y0), (x0, y1), (x1, y1), (x1, y0), (x0, y0)])
        return out
    if k == "line":
        return [[tuple(q) for q in entry["points"]]]
    if k == "circle":
        cx, cy = entry["center"]
        r = entry["radius"]
        a0, a1 = math.radians(entry.get("from", 0)), math.radians(entry.get("to", 360))
        n = max(8, int(abs(a1 - a0) * r / 3))
        return [[(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]]
    raise SystemExit(f"unknown decal kind {k}")


def decal_roads(layout, terrain, road_line, pid):
    """DecalRoad objects for the layout's decals."""
    base = layout["terrain"]["baseZ"]
    out = []
    for i, e in enumerate(layout.get("decals", [])):
        for j, line in enumerate(lines_for(e, layout, road_line)):
            pts = resample(line, e.get("step", 4.0)) if e["kind"] not in ("line", "circle", "pad_edges") else line
            nodes = [[round(x, 2), round(y, 2), round(base + terrain.height(x, y), 2), e["width"]] for x, y in pts]
            o = {"name": f"ra_decal_{i}_{j}", "class": "DecalRoad", "persistentId": pid(layout["name"], f"decal/{i}/{j}"),
                 "__parent": "decals", "position": nodes[0][:3], "material": e["material"], "nodes": nodes,
                 "improvedSpline": e["kind"] not in ("pad_edges",), "textureLength": e.get("textureLength", 10),
                 "renderPriority": e.get("priority", 10), "drivability": -1, "breakAngle": e.get("breakAngle", 3)}
            if e.get("fade"):
                o["startEndFade"] = e["fade"]
            out.append(o)
    return out
