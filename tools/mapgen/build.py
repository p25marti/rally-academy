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
import json
import os
import struct
import sys
import uuid
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "mod"
DEFAULT_LAYOUT = Path(__file__).with_name("proving_ground.json")
STEAM_GUESSES = [r"C:\Program Files (x86)\Steam\steamapps\common\BeamNG.drive",
                 r"D:\SteamLibrary\steamapps\common\BeamNG.drive",
                 r"E:\SteamLibrary\steamapps\common\BeamNG.drive"]


def game_dir(arg):
    for d in [arg, os.environ.get("BEAMNG_GAME")] + STEAM_GUESSES:
        if d and (Path(d) / "content" / "levels" / "template.zip").exists():
            return Path(d)
    sys.exit("BeamNG install not found: pass --game or set BEAMNG_GAME")


def pid(name, key):
    """Stable persistent ids, so rebuilding doesn't churn every file."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"rally-academy/{name}/{key}"))


def grey_png(size, row):
    """A size x size 8-bit greyscale PNG whose every row is `row`."""
    def chunk(typ, data):
        return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ + data))
    body = zlib.compress((b"\0" + row) * size, 9)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", body) + chunk(b"IEND", b""))


def jsonl(objs):
    return "".join(json.dumps(o, separators=(",", ":")) + "\n" for o in objs)


def build(layout, game):
    name, size = layout["name"], layout["size"]
    t = layout["terrain"]
    out = MOD / "levels" / name
    lv = f"/levels/{name}"
    tpl = zipfile.ZipFile(game / "content" / "levels" / "template.zip")

    # Terrain materials: the template's definitions for the ones we use (filler first = layer 0).
    tmats = json.loads(tpl.read("levels/template/art/terrains/main.materials.json"))
    by_name = {v.get("internalName"): (k, v) for k, v in tmats.items() if v.get("class") == "TerrainMaterial"}
    wanted = [layout["filler"]] + [p["material"] for p in layout["pads"] if p["material"] != layout["filler"]]
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
    layer = bytearray(size * size)  # 0 = filler
    index = {m: i for i, m in enumerate(wanted)}
    for p in layout["pads"]:
        x0, x1 = int(p["x"][0] + half), int(p["x"][1] + half)
        y0, y1 = int(p["y"][0] + half), int(p["y"][1] + half)
        for gy in range(max(0, y0), min(size, y1)):
            row = gy * size
            for gx in range(max(0, x0), min(size, x1)):
                layer[row + gx] = index[p["material"]]
    names = b"".join(bytes([len(ours[m])]) + ours[m].encode() for m in wanted)
    ter = (bytes([9]) + struct.pack("<I", size) + struct.pack("<H", raw) * (size * size) + bytes(layer)
           + struct.pack("<I", len(wanted)) + names)

    files = {
        "info.json": json.dumps({
            "title": layout["title"], "description": layout["description"], "size": [size, size],
            "authors": "Rally Academy", "isAuxiliary": False, "supportsTraffic": False, "supportsTimeOfDay": True,
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
            {"name": "sky_and_sun", "class": "SimGroup", "persistentId": pid(name, "sky"), "__parent": "level_objects"}]),
        "main/MissionGroup/level_objects/terrain/items.level.json": jsonl([
            {"name": "theTerrain", "class": "TerrainBlock", "persistentId": pid(name, "terrain"), "__parent": "terrain",
             "position": [-half, -half, t["baseZ"]], "materialTextureSet": texset, "maxHeight": t["maxHeight"],
             "terrainFile": f"{lv}/theTerrain.ter"}]),
        "main/MissionGroup/level_objects/sky_and_sun/items.level.json":
            tpl.read("levels/template/main/MissionGroup/level_objects/sky_and_sun/items.level.json").decode(),
    }
    spawn = next(p for p in layout["pads"] if p["id"] == layout.get("spawn", layout["pads"][0]["id"]))
    sx, sy = sum(spawn["x"]) / 2, spawn["y"][0] + 20
    files["main/MissionGroup/PlayerDropPoints/items.level.json"] = jsonl([
        {"class": "SpawnSphere", "name": "spawn_default", "persistentId": pid(name, "spawn"), "__parent": "PlayerDropPoints",
         "position": [sx, sy, t["groundZ"] + 1], "dataBlock": "SpawnSphereMarker", "enabled": "1", "radius": 1}])

    out.mkdir(parents=True, exist_ok=True)
    for rel, text in files.items():
        f = out / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(text, encoding="utf-8", newline="\n")
    (out / "theTerrain.ter").write_bytes(ter)
    # Fluid depth map next to the terrain (8-bit greyscale, all zero like the template's). Without it the log
    # warns that fluids are disabled as a ground type (0.40.0).
    (out / "theTerrain.ter.depth.png").write_bytes(grey_png(size, bytes(size)))
    print(f"wrote {out.relative_to(ROOT)}: {size} x {size} m terrain at z {t['groundZ']} m, "
          f"{len(layout['pads'])} pads ({', '.join(p['id'] + '=' + p['material'] for p in layout['pads'])}), "
          f"{len(ter) / 1e6:.1f} MB terrain")
    return out


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("layout", nargs="?", default=str(DEFAULT_LAYOUT))
    p.add_argument("--game", help="BeamNG install folder (default: $BEAMNG_GAME or the usual Steam paths)")
    a = p.parse_args(argv)
    build(json.loads(Path(a.layout).read_text(encoding="utf-8")), game_dir(a.game))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
