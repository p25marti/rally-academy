"""Generate a Rally Academy level from a layout file: python tools/mapgen/build.py [layout.json] [--game DIR]

Writes mod/levels/<name>/ (a complete level the game loads): a flat terrain in BeamNG's terrain format (version 9:
version byte, size, 16-bit heights, one material byte per square, material names), surface pads painted into its
material layer, the stock template level's terrain materials and sky (their textures stay in the game: nothing is
copied but small JSON definitions), and a spawn point per pad. The layout file is the source of truth: edit it and
rebuild, then reload the level in game.

The template level is read from the game install (content/levels/template.zip): --game, $BEAMNG_GAME, or the
usual Steam paths.
"""
import argparse
import hashlib
import json
import os
import struct
import sys
import uuid
import zipfile
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import borrow  # noqa: E402
import decals  # noqa: E402
import markers  # noqa: E402
import nature  # noqa: E402
import racingline  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "mod"
DEFAULT_LAYOUT = Path(__file__).with_name("proving_ground.json")
STEAM_GUESSES = [r"C:\Program Files (x86)\Steam\steamapps\common\BeamNG.drive",
                 r"D:\SteamLibrary\steamapps\common\BeamNG.drive",
                 r"E:\SteamLibrary\steamapps\common\BeamNG.drive"]


def find_game(arg=None):
    """The BeamNG install folder, or None."""
    for d in [arg, os.environ.get("BEAMNG_GAME")] + STEAM_GUESSES:
        if d and (Path(d) / "content" / "levels" / "template.zip").exists():
            return Path(d)
    return None


def game_dir(arg):
    return find_game(arg) or sys.exit("BeamNG install not found: pass --game or set BEAMNG_GAME")


def pid(name, key):
    """Stable persistent ids, so rebuilding doesn't churn every file."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"rally-academy/{name}/{key}"))


# Preview colours per template material (the map list's thumbnail is a plan of the layout).
COLOURS = {"Grass": (74, 110, 52), "gravel": (168, 152, 120), "Asphalt": (60, 60, 64), "snow": (236, 240, 245),
           "Dirt": (132, 98, 64), "Mud": (86, 66, 46), "BeachSand": (214, 196, 150), "rock": (120, 118, 112)}


def preview_png(layer, size, wanted, terrain=None, trees=(), px=512):
    """A top-down plan of the material layer, px x px, north up: hills shaded, trees as dark dots."""
    step = size // px
    half = size / 2
    cols = [COLOURS.get(m, (255, 0, 255)) for m in wanted]
    dots = {(int((t[1] + half) / step), int((t[2] + half) / step)) for t in trees}
    rows = []
    for y in range(px - 1, -1, -1):  # PNG rows run top (north) to bottom
        src = (y * step) * size
        row = bytearray()
        for x in range(px):
            r, g, b = cols[layer[src + x * step]]
            if terrain is not None and terrain.b:
                wx, wy = x * step - half, y * step - half
                shade = (terrain.height(wx + step, wy + step) - terrain.height(wx - step, wy - step)) / (2 * step)
                k = max(0.55, min(1.35, 1 + shade * 1.5))
                r, g, b = (min(255, int(c * k)) for c in (r, g, b))
            if (x, y) in dots:
                r, g, b = 34, 62, 30
            row += bytes((r, g, b))
        rows.append(b"\0" + bytes(row))

    def chunk(typ, data):
        return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", px, px, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))


def jsonl(objs):
    return "".join(json.dumps(o, separators=(",", ":")) + "\n" for o in objs)


def smooth(pts, steps=4):
    """Catmull-Rom through the points (end points kept), `steps` pieces per segment."""
    p = [pts[0]] + pts + [pts[-1]]
    out = []
    for i in range(1, len(p) - 2):
        for k in range(steps):
            t = k / steps
            out.append(tuple(0.5 * (2 * p[i][j] + (-p[i - 1][j] + p[i + 1][j]) * t
                                    + (2 * p[i - 1][j] - 5 * p[i][j] + 4 * p[i + 1][j] - p[i + 2][j]) * t * t
                                    + (-p[i - 1][j] + 3 * p[i][j] - 3 * p[i + 1][j] + p[i + 2][j]) * t ** 3) for j in (0, 1)))
    return out + [tuple(pts[-1])]


def road_line(r):
    """A road's smoothed centre line in world coordinates."""
    ox, oy = r["origin"]
    return [(ox + x, oy + y) for x, y in smooth([tuple(q) for q in r["points"]])]


def paint_road(layer, size, half, r, mat):
    """Paint every 1 m square whose centre lies within width / 2 of the road's centre line."""
    w2 = (r["width"] / 2) ** 2
    line = road_line(r)
    for (ax, ay), (bx, by) in zip(line, line[1:]):
        dx, dy = bx - ax, by - ay
        ll = dx * dx + dy * dy or 1e-9
        pad = r["width"] / 2 + 1
        for gy in range(max(0, int(min(ay, by) - pad + half)), min(size, int(max(ay, by) + pad + half) + 1)):
            cy = gy - half + 0.5
            for gx in range(max(0, int(min(ax, bx) - pad + half)), min(size, int(max(ax, bx) + pad + half) + 1)):
                cx = gx - half + 0.5
                t = max(0.0, min(1.0, ((cx - ax) * dx + (cy - ay) * dy) / ll))
                if (cx - ax - t * dx) ** 2 + (cy - ay - t * dy) ** 2 <= w2:
                    layer[gy * size + gx] = mat


def generate(layout, game):
    """Every file of the level: {path inside mod/levels/<name>/: bytes}."""
    name, size = layout["name"], layout["size"]
    t = layout["terrain"]
    lv = f"/levels/{name}"
    tpl = zipfile.ZipFile(game / "content" / "levels" / "template.zip")

    # Terrain materials: the template's definitions for the ones we use (filler first = layer 0).
    tmats = json.loads(tpl.read("levels/template/art/terrains/main.materials.json"))
    by_name = {v.get("internalName"): (k, v) for k, v in tmats.items() if v.get("class") == "TerrainMaterial"}
    wanted = [layout["filler"]] + [p["material"] for p in layout["pads"] + layout.get("roads", [])]
    if layout.get("backdrop"):
        wanted.append(layout["backdrop"].get("rockMaterial", "rock"))
    if (layout.get("forest") or {}).get("floorMaterial"):
        wanted.append(layout["forest"]["floorMaterial"])
    wanted = list(dict.fromkeys(wanted))
    missing = [m for m in wanted if m not in by_name]
    if missing:
        sys.exit(f"not template terrain materials: {missing}; choose from {sorted(by_name)}")
    # Our own internal names (ra_*): the game keeps terrain materials from the last map loaded, and a shared
    # name ("Grass") collides with them ("Internal name collision" in the log, 0.40.0).
    mats, ours = {}, {}
    for m in wanted:
        k, v = by_name[m]
        v = dict(v, internalName=f"ra_{m}", persistentId=pid(name, f"mat/{m}"))
        ours[m] = v["internalName"]
        mats[v["internalName"]] = v
    for k, v in tmats.items():
        if v.get("class") == "TerrainMaterialTextureSet":
            mats[k] = v
            texset = v["name"]

    # Heights and the material layer, row by row from the south-west corner (x fastest).
    half = size / 2
    raw = round((t["groundZ"] - t["baseZ"]) / t["maxHeight"] * 65535)
    if not 0 <= raw <= 65535:
        sys.exit("groundZ must lie between baseZ and baseZ + maxHeight")
    terrain = nature.Terrain(layout)
    terrain.check_flat(layout)
    heights = terrain.raw_heights(t["maxHeight"])
    if sys.byteorder != "little":
        heights.byteswap()
    layer = bytearray(size * size)  # 0 = filler
    index = {m: i for i, m in enumerate(wanted)}
    nature.paint_forest_floor(layout, terrain, layer, index)
    if layout.get("backdrop"):
        terrain.paint_rock(layer, index[layout["backdrop"].get("rockMaterial", "rock")])
    for p in layout["pads"]:
        x0, x1 = int(p["x"][0] + half), int(p["x"][1] + half)
        y0, y1 = int(p["y"][0] + half), int(p["y"][1] + half)
        for gy in range(max(0, y0), min(size, y1)):
            row = gy * size
            for gx in range(max(0, x0), min(size, x1)):
                layer[row + gx] = index[p["material"]]
    for r in layout.get("roads", []):
        paint_road(layer, size, half, r, index[r["material"]])
    names = b"".join(bytes([len(ours[m])]) + ours[m].encode() for m in wanted)
    ter = (bytes([9]) + struct.pack("<I", size) + heights.tobytes() + bytes(layer)
           + struct.pack("<I", len(wanted)) + names)
    trees = nature.forest(layout, terrain)

    files = {
        "info.json": json.dumps({
            "title": layout["title"], "description": layout["description"], "size": [size, size],
            "previews": ["preview.png"], "authors": "Rally Academy", "isAuxiliary": False, "supportsTraffic": False, "supportsTimeOfDay": True,
            "defaultDate": {"year": 2026, "month": 7, "day": 29}}, indent=2) + "\n",
        "theTerrain.terrain.json": json.dumps({
            "binaryFormat": "version(char), size(unsigned int), heightMap(heightMapSize * heightMapItemSize), "
                            "layerMap(layerMapSize * layerMapItemSize), materialNames",
            "datafile": f"{lv}/theTerrain.ter", "heightMapItemSize": 2, "heightMapSize": size * size,
            "layerMapItemSize": 1, "layerMapSize": size * size, "materials": [ours[m] for m in wanted], "size": size, "version": 9},
            indent=2) + "\n",
        "art/terrains/main.materials.json": json.dumps(mats, indent=2) + "\n",
        "main/items.level.json": jsonl([
            {"name": "MissionGroup", "class": "SimGroup", "persistentId": pid(name, "mission"), "enabled": "1"}]),
        "main/MissionGroup/items.level.json": jsonl([
            {"name": "level_objects", "class": "SimGroup", "__parent": "MissionGroup"},
            {"name": "PlayerDropPoints", "class": "SimGroup", "persistentId": pid(name, "drops"),
             "__parent": "MissionGroup", "enabled": "1"}]),
        "main/MissionGroup/level_objects/items.level.json": jsonl([
            {"name": "terrain", "class": "SimGroup", "__parent": "level_objects"},
            {"name": "sky_and_sun", "class": "SimGroup", "persistentId": pid(name, "sky"), "__parent": "level_objects"}]
            + ([{"name": "vegetation", "class": "SimGroup", "persistentId": pid(name, "vegetation"), "__parent": "level_objects"}]
               if trees or layout.get("groundcover") else [])
            + ([{"name": "props", "class": "SimGroup", "persistentId": pid(name, "props"), "__parent": "level_objects"}]
               if layout.get("props") else [])
            + ([{"name": "decals", "class": "SimGroup", "persistentId": pid(name, "decals"), "__parent": "level_objects"}]
               if layout.get("decals") else [])
            + ([{"name": "water", "class": "SimGroup", "persistentId": pid(name, "water"), "__parent": "level_objects"}]
               if layout.get("water") else [])),
        "main/MissionGroup/level_objects/terrain/items.level.json": jsonl([
            {"name": "theTerrain", "class": "TerrainBlock", "persistentId": pid(name, "terrain"), "__parent": "terrain",
             "position": [-half, -half, t["baseZ"]], "materialTextureSet": texset, "maxHeight": t["maxHeight"],
             "terrainFile": f"{lv}/theTerrain.ter"}]),
        "main/MissionGroup/level_objects/sky_and_sun/items.level.json": sky(layout, tpl),
    }
    spawn = next(p for p in layout["pads"] if p["id"] == layout.get("spawn", layout["pads"][0]["id"]))
    sx, sy = sum(spawn["x"]) / 2, spawn["y"][0] + 20
    files["main/MissionGroup/PlayerDropPoints/items.level.json"] = jsonl([
        {"class": "SpawnSphere", "name": "spawn_default", "persistentId": pid(name, "spawn"), "__parent": "PlayerDropPoints",
         "position": [sx, sy, t["groundZ"] + 1], "dataBlock": "SpawnSphereMarker", "enabled": "1", "radius": 1}])

    vegetation = []
    if trees:
        used = {t[0] for t in trees}
        vegetation.append({"name": "theForest", "class": "Forest", "persistentId": pid(name, "forest"), "__parent": "vegetation",
                           "lodReflectScalar": 0.15})
        files["art/forest/managedItemData.json"] = json.dumps(
            {k: v for k, v in nature.item_data(name, pid).items() if k in used}, indent=2) + "\n"
        files["art/shapes/trees/main.materials.json"] = json.dumps(nature.tree_materials(game, name, pid, layout["forest"].get("leafColours") or layout["forest"].get("leafTint")), indent=2) + "\n"
        files.update(nature.forest_files(trees))
    if layout.get("groundcover"):
        objs, mats = grass_cover(layout, game, ours, t["groundZ"])
        vegetation += objs
        files["art/groundcover/main.materials.json"] = json.dumps(mats, indent=2) + "\n"
    if vegetation:
        files["main/MissionGroup/level_objects/vegetation/items.level.json"] = jsonl(vegetation)
    if layout.get("props"):
        files["main/MissionGroup/level_objects/props/items.level.json"] = jsonl(props(layout, terrain))
    if layout.get("water"):
        files["main/MissionGroup/level_objects/water/items.level.json"] = jsonl(water(layout))
    if layout.get("decals"):
        files["main/MissionGroup/level_objects/decals/items.level.json"] = jsonl(decals.decal_roads(layout, terrain, road_line, pid))
        stock = borrow.Stock(game)
        used = sorted({e["material"] for e in layout["decals"]})
        src = layout.get("decalMaterials", {})
        missing = [m for m in used if m not in src]
        if missing:
            raise SystemExit(f"decal materials without a source level in decalMaterials: {missing}")
        files["art/decals/main.materials.json"] = json.dumps(
            # objects find materials by name, which in a stock file can differ from mapTo (skidmarks_01)
            {m: dict(stock.material(src[m], m), name=m, persistentId=pid(name, f"decalmat/{m}")) for m in used}, indent=2) + "\n"
    if layout.get("turnMarkers"):
        # the drill roads' racing lines, for the mod's "Show line" (one per line of the file)
        files["rallyAcademy/racingLines.json"] = '{"lines": [\n' + ",\n".join(
            json.dumps(e, separators=(",", ":")) for e in racingline.racing_lines(layout, terrain, road_line)) + "\n]}\n"
    out = {rel: text.replace("\r\n", "\n").encode("utf-8") for rel, text in files.items()}  # LF, as git keeps them
    out["theTerrain.ter"] = ter
    out["preview.png"] = preview_png(layer, size, wanted, terrain, trees)
    # No fluid depth map (<terrain>.ter.depth.png): the log notes "all fluids will be disabled as ground type",
    # which is what we want for now: WaterBlocks still wet the car without it. An all-zero map made every wheel sink
    # 0.2 m into the gravel and bog the car down to walking pace at full throttle (0.40.0); the template's is mostly 255.
    return out


def water(layout):
    """Water bodies (layout "water"): a WaterBlock over `center` [x, y] covering `size` [w, h] m, its surface `surface` m
    above the ground level (negative: in a dip shaped by a feature road), `depth` m deep. The box must reach past where
    the dip climbs back above the surface, or its square edge shows. Textures from core/art."""
    out = []
    ground = layout["terrain"]["groundZ"]
    for k, w in enumerate(layout["water"]):
        depth = w.get("depth", 2.0)
        out.append({"name": f"water_{w['id']}", "class": "WaterBlock", "persistentId": pid(layout["name"], f"water/{w['id']}"),
                    "__parent": "water",
                    # drawn at its position and wet from there down `depth` (its world box is centred on it, 0.40.0)
                    "position": [w["center"][0], w["center"][1], round(ground + w["surface"], 3)],
                    "scale": [w["size"][0], w["size"][1], depth],
                    "baseColor": w.get("colour", [92, 74, 46, 255]),
                    "depthGradientTex": "core/art/water/depthcolor_ramp.png", "foamTex": "core/art/water/foam.dds",
                    "rippleTex": "core/art/water/ripple.dds", "fullReflect": False, "reflectivity": 0.3,
                    "overallRippleMagnitude": 0.3, "overallWaveMagnitude": 0, "foamMaxDepth": 0.4, "overallFoamOpacity": 0.6,
                    "waterFogDensity": w.get("fog", 1.2), "waterFogDensityOffset": 0.2, "wetDarkening": 0.5, "wetDepth": 0.5,
                    "specularPower": 200,
                    "Ripples (texture animation)": [
                        {"rippleDir": [0, 1], "rippleSpeed": 0.02, "rippleTexScale": [7, 7]},
                        {"rippleDir": [0.707, 0.707], "rippleSpeed": 0.012, "rippleTexScale": [6, 12]},
                        {"rippleDir": [0.5, 0.86], "rippleSpeed": 0.004, "rippleTexScale": [30, 30]}]})
    return out


def props(layout, terrain):
    """Static props (layout "props"): each entry places `shape` (a game-wide mesh under /art/shapes/, whose
    materials the game always loads) at `at`, or `count` of them evenly along `row` [[x0, y0], [x1, y1]], turned
    `yaw` degrees anticlockwise from facing south (its default), `lift` m above the ground. None may stand on a pad
    or road (2 m margin): props are scenery, not obstacles in a drill."""
    out = []
    for k, e in enumerate(layout["props"]):
        if "along" in e:  # barriers: pieces end to end along a path (and posts at the joints)
            pieces = [(x, y, yaw, e["shape"], e.get("lift", 0)) for x, y, yaw in along(layout, e)]
            if e.get("posts"):
                joints = along(layout, dict(e, axis="-y", turn=0.0))  # piece starts
                pieces += [(x, y, 0.0, e["posts"], 0) for x, y, _ in joints]
            for j, (x, y, yaw, shape, lift) in enumerate(pieces):
                if not nature._clear_of(layout, x, y, 2.0):
                    if e.get("skipClash"):  # winding roads: drop the pieces that come near another stretch
                        continue
                    raise SystemExit(f"prop {e['shape']} at ({x:.0f}, {y:.0f}) stands on a pad or road")
                out.append(static(layout, terrain, f"prop/{k}/{j}", x, y, yaw, shape, lift=lift))
            continue
        if "row" in e:
            (x0, y0), (x1, y1) = e["row"]
            n = e["count"]
            spots = [(x0 + (x1 - x0) * i / max(1, n - 1), y0 + (y1 - y0) * i / max(1, n - 1)) for i in range(n)]
        else:
            spots = [tuple(e["at"])]
        for j, (x, y) in enumerate(spots):
            if not nature._clear_of(layout, x, y, 2.0):
                raise SystemExit(f"prop {e['shape']} at ({x:.0f}, {y:.0f}) stands on a pad or road")
            out.append(static(layout, terrain, f"prop/{k}/{j}", x, y, e.get("yaw", 0), e["shape"], e.get("scale", 1),
                              e.get("lift", 0)))
    return out + turn_boards(layout, terrain)


def static(layout, terrain, key, x, y, yaw, shape, scale=1, lift=0):
    """A TSStatic in the props group: `shape` on the ground at (x, y) (`lift` m above it), turned `yaw` degrees."""
    import math
    a = math.radians(yaw)
    c, sn = round(math.cos(a), 6), round(math.sin(a), 6)
    return {"class": "TSStatic", "persistentId": pid(layout["name"], key), "__parent": "props",
            "position": [round(x, 2), round(y, 2), round(layout["terrain"]["baseZ"] + terrain.height(x, y) + lift, 3)],
            "rotationMatrix": [c, sn, 0, -sn, c, 0, 0, 0, 1], "scale": [scale] * 3,
            "shapeName": shape, "useInstanceRenderData": True}


# Faces of the corner signs, as the heading their readable side points at yaw 0 (0.40.0): the rally kit's arrow
# flags show down their -x, the chevron signs down their -y. A sign turned to (travel heading + 180 - face) faces the
# driver. The arrow flags are small (1.3 m tall, a 0.5 m arrow) and read only from close by at their own size.
SIGNS = {"board": {"face": 180.0, "scale": 2.5}, "chevron": {"face": -90.0, "scale": 1.5}}


def turn_boards(layout, terrain):
    """Corner signs (layout "turnMarkers": [{"road": id, "directions": ["forward", "reverse"]}]) for each bend of those
    roads, facing the way the drills drive it (tools/mapgen/markers.py): a rally direction board before the bend and a
    chevron sign on its outside. A sign that would stand on another pad or road is left out."""
    out = []
    for e in layout.get("turnMarkers", []):
        r = next(r for r in layout["roads"] if r["id"] == e["road"])
        for way in e.get("directions", ["forward"]):
            line = road_line(r)
            line = line if way == "forward" else line[::-1]
            for kind, spots in (("board", markers.placements(line, r["width"])), ("chevron", markers.chevrons(line, r["width"]))):
                for j, (x, y, heading, shape, _) in enumerate(spots):
                    if not nature._clear_of(layout, x, y, 1.5):
                        continue
                    out.append(static(layout, terrain, f"{kind}/{r['id']}/{way}/{j}", x, y,
                                      heading + 180.0 - SIGNS[kind]["face"], shape, SIGNS[kind]["scale"]))
    return out


AXIS_ANGLE = {"x": 0.0, "y": 90.0, "-y": -90.0, "-x": 180.0}


def along(layout, e):
    """Positions and yaws (degrees) for pieces `length` m long laid end to end along a path: e["along"] is
    {"road": id, "offset": m to the left of its centre, "from": m, "to": m along it} or {"points": [[x, y], ...]}.
    `axis` is the mesh axis its length runs along ("x", "y", or "-y" for tapes that start at their origin and run
    down -y); centred pieces sit at the middle of their stretch, "-y" ones at its start. `turn` adds degrees to each
    piece (180 turns it round: guardrail1's beam sits on its +y side, left of its length axis, so rails on the
    left of a path turn 180 to put the beam towards the road and the posts behind it). `posts` adds that mesh at every joint."""
    import math
    path = e["along"]
    if "road" in path:
        r = next(r for r in layout["roads"] if r["id"] == path["road"])
        line = decals.offset_line(road_line(r), path.get("offset", 0.0))
    else:
        line = [tuple(q) for q in path["points"]]
    length, axis = e["length"], e.get("axis", "x")
    start, stop = path.get("from", 0.0), path.get("to", 1e9)
    phi = AXIS_ANGLE[axis]
    out, d = [], 0.0
    target = start
    for (ax, ay), (bx, by) in zip(line, line[1:]):
        seg = math.hypot(bx - ax, by - ay)
        theta = math.degrees(math.atan2(by - ay, bx - ax))
        while seg > 0 and target + length <= d + seg + 1e-6 and target + length <= stop:
            t0 = (target - d) / seg
            t = t0 if axis.startswith("-") else (target + length / 2 - d) / seg
            # the engine reads each row of rotationMatrix as a local axis: a mesh axis at angle phi ends up at
            # phi + yaw, so yaw = theta - phi lays the piece's length along the path (0.40.0)
            out.append((ax + (bx - ax) * t, ay + (by - ay) * t, theta - phi + e.get("turn", 0.0)))
            target += length + e.get("gap", 0.0)
        d += seg
    return out


def sky(layout, tpl):
    """The template's sky and sun, at the layout's time of day ("timeOfDay": BeamNG's 0..1, 0 = noon; 0.19 is a low,
    warm late-afternoon sun, 0.24 sunset, 0.29 night; 0.40.0)."""
    lines = []
    for line in tpl.read("levels/template/main/MissionGroup/level_objects/sky_and_sun/items.level.json").decode().splitlines():
        if not line.strip():
            continue
        o = json.loads(line)
        if o.get("class") == "TimeOfDay" and "timeOfDay" in layout:
            o["time"] = o["startTime"] = layout["timeOfDay"]
        lines.append(o)
    return jsonl(lines)


def grass_cover(layout, game, ours, ground_z):
    """GroundCover objects borrowed from stock levels (layout "groundcover": [{from, name, on: [materials]}]), each
    growing on our terrain materials instead of the source level's, and their materials: (objects, materials)."""
    stock = borrow.Stock(game)
    objs, mats = [], {}
    for k, g in enumerate(layout["groundcover"]):
        src = stock.objects(g["from"], "GroundCover").get(g["name"])
        if src is None:
            raise SystemExit(f"no GroundCover {g['name']} in {g['from']}")
        on = [ours[m] for m in g["on"]]
        o = dict(src, name=f"ra_grass_{k}_{g['name']}", persistentId=pid(layout["name"], f"grass/{k}"), __parent="vegetation",
                 position=[0, 0, ground_z])
        types, j = [], 0
        for ty in src.get("Types", []):
            ty = dict(ty)
            if ty.get("layer"):
                ty["layer"] = on[j % len(on)]
                j += 1
            types.append(ty)
        o["Types"] = types
        for key, v in g.get("set", {}).items():  # overrides (density, radius)
            o[key] = v
        objs.append(o)
        mats[src["material"]] = dict(stock.material(g["from"], src["material"]), name=src["material"],
                                     persistentId=pid(layout["name"], f"grassmat/{src['material']}"))
    return objs, mats


def level_dir(layout):
    return MOD / "levels" / layout["name"]


def build(layout, game):
    """Write the level into mod/levels/<name>/."""
    out = level_dir(layout)
    files = generate(layout, game)
    if out.is_dir():  # a clean slate: files the layout no longer makes (a tree type dropped) must go
        for f in sorted(out.rglob("*"), reverse=True):
            if f.is_file():
                f.unlink()
    for rel, data in files.items():
        f = out / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(data)
    man = dict(stamp(layout), files={rel: digest(data) for rel, data in sorted(files.items())})
    (out / MANIFEST).write_text(json.dumps(man, indent=1) + "\n", encoding="utf-8", newline="\n")
    t = layout["terrain"]
    print(f"wrote {out.relative_to(ROOT)}: {layout['size']} x {layout['size']} m terrain at z {t['groundZ']} m, "
          f"{len(layout['pads'])} pads, {len(layout.get('roads', []))} roads")
    return out


MANIFEST = "build.json"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def stamp(layout):
    """What a level is built from: the layout and the generator's own source."""
    src = b"".join((Path(__file__).with_name(f)).read_bytes()
                   for f in ("build.py", "nature.py", "decals.py", "markers.py", "racingline.py"))
    return {"layout": digest(json.dumps(layout, sort_keys=True).encode()), "generator": digest(src.replace(b"\r\n", b"\n"))}


def stale(layout, game=None):
    """Why mod/levels/<name>/ doesn't match its layout (empty when it does): the manifest written by the last build
    must name this layout and generator, and every file must match its recorded hash. Fast, and needs no game
    install (the template level's own files aren't re-read: rebuild after a game update)."""
    out = level_dir(layout)
    try:
        man = json.loads((out / MANIFEST).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return [f"{MANIFEST} missing"]
    problems = [f"{k} changed since the last build" for k, v in stamp(layout).items() if man.get(k) != v]
    have = {f.relative_to(out).as_posix() for f in out.rglob("*") if f.is_file()} - {MANIFEST}
    want = man.get("files", {})
    problems += [f"{rel} missing" for rel in sorted(set(want) - have)]
    problems += [f"{rel} not in the build" for rel in sorted(have - set(want))]
    problems += [f"{rel} edited" for rel in sorted(set(want) & have) if digest((out / rel).read_bytes()) != want[rel]]
    return problems


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("layout", nargs="?", default=str(DEFAULT_LAYOUT))
    p.add_argument("--game", help="BeamNG install folder (default: $BEAMNG_GAME or the usual Steam paths)")
    a = p.parse_args(argv)
    build(json.loads(Path(a.layout).read_text(encoding="utf-8")), game_dir(a.game))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
