"""Backdrop and trees for generated levels (tools/mapgen/build.py): rolling hills round a dead-flat play area, rock
on their steep faces, and forests made of the game's shared tree library (/assets/meshes/foliage/trees_library/,
always mounted, so nothing is copied into the mod).

Deterministic: the same layout (and seed) gives the same hills and the same trees, so rebuilds don't churn.
Pure Python and quick enough for a 2 km terrain: noise is evaluated on a coarse grid and interpolated.
"""
import math
import random

COARSE = 4  # metres between coarse height samples (the finest hill detail is ~60 m)


def smoothstep(a, b, x):
    if x <= a:
        return 0.0
    if x >= b:
        return 1.0
    t = (x - a) / (b - a)
    return t * t * (3 - 2 * t)


class Noise:
    """Value noise on a hashed lattice, summed over octaves (fbm), in about 0..1."""

    def __init__(self, seed, scale, octaves=3):
        self.seed, self.scale, self.octaves = seed, scale, octaves

    def _lattice(self, ix, iy, o):
        h = (ix * 374761393 + iy * 668265263 + (self.seed + o * 101) * 2147483647) & 0xFFFFFFFF
        h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
        return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0

    def __call__(self, x, y):
        total, amp, norm, freq = 0.0, 1.0, 0.0, 1.0 / self.scale
        for o in range(self.octaves):
            fx, fy = x * freq, y * freq
            ix, iy = math.floor(fx), math.floor(fy)
            tx, ty = fx - ix, fy - iy
            tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
            a, b = self._lattice(ix, iy, o), self._lattice(ix + 1, iy, o)
            c, d = self._lattice(ix, iy + 1, o), self._lattice(ix + 1, iy + 1, o)
            total += amp * (a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty)
            norm += amp
            amp *= 0.5
            freq *= 2.0
        return total / norm


def flat_zone(layout, margin):
    """The rectangle (x0, y0, x1, y1) that stays dead flat: every pad and road plus `margin` metres."""
    xs, ys = [], []
    for p in layout["pads"]:
        xs += p["x"]
        ys += p["y"]
    for r in layout.get("roads", []):
        ox, oy = r["origin"]
        xs += [ox + q[0] for q in r["points"]]
        ys += [oy + q[1] for q in r["points"]]
    return min(xs) - margin, min(ys) - margin, max(xs) + margin, max(ys) + margin


def outside(zone, x, y):
    """Distance (m) from the point to the flat zone, 0 inside it."""
    x0, y0, x1, y1 = zone
    dx = max(x0 - x, 0.0, x - x1)
    dy = max(y0 - y, 0.0, y - y1)
    return math.hypot(dx, dy)


class Terrain:
    """Heights (m above the terrain's base) for a size x size terrain centred on 0, 0."""

    def __init__(self, layout):
        t, b = layout["terrain"], layout.get("backdrop")
        self.size, self.half = layout["size"], layout["size"] / 2
        self.ground = t["groundZ"] - t["baseZ"]
        self.b = b
        if not b:
            return
        self.zone = flat_zone(layout, b["flatMarginM"])
        seed = b.get("seed", 1)
        self.hills = Noise(seed, b.get("noiseScaleM", 240))
        self.foot = Noise(seed + 7, 150, 2)  # wobbles where the hills start, so the foot isn't a rectangle
        n = self.size // COARSE + 1
        self.n = n
        self.grid = [self._coarse(i * COARSE - self.half, j * COARSE - self.half) for j in range(n) for i in range(n)]

    def _coarse(self, x, y):
        b = self.b
        d = outside(self.zone, x, y)
        if d <= 0:
            return self.ground
        d = max(0.0, d + (self.foot(x, y) - 0.5) * b.get("footWobbleM", 60))
        rise = smoothstep(0, b["rampM"], d) * b["heightM"] * (0.45 + 0.9 * self.hills(x, y))
        edge = smoothstep(self.half - b.get("edgeRampM", 350), self.half - 40, max(abs(x), abs(y))) * b.get("edgeExtraM", 0)
        return self.ground + rise + edge

    def height(self, x, y):
        """Height above the base at any point (bilinear between coarse samples; exact ground in the flat zone)."""
        if not self.b or outside(self.zone, x, y) <= 0:
            return self.ground
        fx, fy = (x + self.half) / COARSE, (y + self.half) / COARSE
        i, j = min(self.n - 2, max(0, int(fx))), min(self.n - 2, max(0, int(fy)))
        tx, ty = fx - i, fy - j
        g, n = self.grid, self.n
        a, b2, c, d = g[j * n + i], g[j * n + i + 1], g[(j + 1) * n + i], g[(j + 1) * n + i + 1]
        return a + (b2 - a) * tx + (c - a) * ty + (a - b2 - c + d) * tx * ty

    def slope(self, x, y):
        """Rise over run across 2 m."""
        return math.hypot(self.height(x + 1, y) - self.height(x - 1, y), self.height(x, y + 1) - self.height(x, y - 1)) / 2

    def raw_heights(self, max_height):
        """The u16 height map, rows from the south-west corner, x fastest (the .ter order)."""
        import array
        scale = 65535 / max_height
        size, half = self.size, self.half
        flat = round(self.ground * scale)
        out = array.array("H", [flat]) * (size * size)
        if not self.b:
            return out
        x0, y0, x1, y1 = self.zone
        for gy in range(size):
            y = gy - half
            row = gy * size
            inside_row = y0 <= y <= y1
            for gx in range(size):
                x = gx - half
                if inside_row and x0 <= x <= x1:
                    continue
                out[row + gx] = min(65535, max(0, round(self.height(x, y) * scale)))
        return out

    def paint_rock(self, layer, rock_index):
        """Rock where the hills are steep (slope from the coarse grid, dithered so the edge isn't blocky)."""
        b = self.b
        if not b or rock_index is None:
            return
        limit = b.get("rockSlope", 0.5)
        size, half, n, g = self.size, self.half, self.n, self.grid
        rnd = random.Random(b.get("seed", 1) + 3)
        steep = set()
        for j in range(n - 1):
            for i in range(n - 1):
                a = g[j * n + i]
                s = math.hypot(g[j * n + i + 1] - a, g[(j + 1) * n + i] - a) / COARSE
                if s > limit * 0.8:
                    steep.add((i, j, s))
        for i, j, s in steep:
            for gy in range(j * COARSE, min(size, (j + 1) * COARSE)):
                for gx in range(i * COARSE, min(size, (i + 1) * COARSE)):
                    if s + (rnd.random() - 0.5) * limit * 0.4 > limit:
                        layer[gy * size + gx] = rock_index


def paint_forest_floor(layout, terrain, layer, index):
    """Bare forest floor (layout forest.floorMaterial, e.g. Dirt) under the dense woods on the hills, where grass
    cover doesn't grow: the same noise mask the woods use, a little inside it, dithered at the edge. Never in the
    flat zone."""
    f = layout.get("forest") or {}
    mat = f.get("floorMaterial")
    if not mat or not terrain.b:
        return
    woods = Noise(f.get("seed", 1) + 11, f.get("woodsScaleM", 180), 3)
    rnd = random.Random(f.get("seed", 1) + 5)
    size, half, mi = terrain.size, terrain.half, index[mat]
    inset = f.get("floorInsetNoise", 0.04)  # how far inside the woods' noise edge the bare floor starts
    for gy in range(0, size, COARSE):
        for gx in range(0, size, COARSE):
            x, y = gx - half + 2, gy - half + 2
            d = outside(terrain.zone, x, y)
            if d <= 20:
                continue
            hill = smoothstep(0, terrain.b["rampM"] * 0.5, d)
            w = woods(x, y) - (f.get("woodsThreshold", 0.5) - 0.12 * hill)  # > 0 inside the woods (as forest())
            for yy in range(gy, min(size, gy + COARSE)):
                for xx in range(gx, min(size, gx + COARSE)):
                    if w + (rnd.random() - 0.5) * 0.06 > inset:
                        layer[yy * size + xx] = mi


# Trees from /assets/meshes/foliage/trees_library/ and their sway settings (BeamNG's own values for these
# models, from the Driver Training level's managedItemData.json, 0.40.0).
LIB = "/assets/meshes/foliage/trees_library/"
SWAY = {
    "large": {"branchAmp": 0.15, "dampingCoefficient": 0.3, "detailAmp": 0.2, "detailFreq": 4, "mass": 100,
              "rigidity": 80, "tightnessCoefficient": 4, "trunkBendScale": 0.01, "windScale": 0.4},
    "group": {"branchAmp": 0.2, "detailAmp": 0.2, "detailFreq": 5, "mass": 60, "radius": 1.3, "rigidity": 35,
              "tightnessCoefficient": 4, "trunkBendScale": 0.07, "windScale": 0.4},
    "small": {"branchAmp": 0.03, "detailAmp": 0.15, "detailFreq": 3, "mass": 50, "radius": 0.5, "rigidity": 30,
              "tightnessCoefficient": 4, "trunkBendScale": 0.1, "windScale": 0.4},
    "bush": {"branchAmp": 0.1, "dampingCoefficient": 3, "detailAmp": 0.5, "detailFreq": 0.5, "mass": 4, "radius": 0.5,
             "rigidity": 20, "tightnessCoefficient": 1, "trunkBendScale": 0.05, "windScale": 0.5},
}
TREES = {
    "tree_oak_large_a": ("oak/tree_oak_large_a.dae", "large"),
    "tree_oak_large_b": ("oak/tree_oak_large_b.dae", "large"),
    "tree_oak_large_c": ("oak/tree_oak_large_c.dae", "large"),
    "tree_beech_large_b": ("beech/tree_beech_large_b.dae", "large"),
    "tree_beech_large_c": ("beech/tree_beech_large_c.dae", "large"),
    "tree_aspen_large_a": ("birch/tree_aspen_large_a.dae", "small"),
    "tree_aspen_large_b": ("birch/tree_aspen_large_b.dae", "small"),
    "tree_oak_forest_group": ("oak/tree_oak_forest_group.dae", "group"),
    "tree_beech_forest_group": ("beech/tree_beech_forest_group.dae", "group"),
    "tree_aspen_forest_group": ("birch/tree_aspen_forest_group.dae", "group"),
    "tree_oak_forest_a": ("oak/tree_oak_forest_a.dae", "group"),
    "tree_beech_forest_b": ("beech/tree_beech_forest_b.dae", "group"),
    "tree_beech_small_b": ("beech/tree_beech_small_b.dae", "small"),
    "tree_beech_small_c": ("beech/tree_beech_small_c.dae", "small"),
    "tree_aspen_small_a": ("birch/tree_aspen_small_a.dae", "small"),
    "tree_aspen_small_c": ("birch/tree_aspen_small_c.dae", "small"),
    "tree_oak_sml_a": ("oak/tree_oak_sml_a.dae", "small"),
    "tree_oak_bush_a": ("oak/tree_oak_bush_a.dae", "bush"),
    "tree_oak_bush_c": ("oak/tree_oak_bush_c.dae", "bush"),
    "tree_beech_bush_c": ("beech/tree_beech_bush_c.dae", "bush"),
    "tree_aspen_bush_b": ("birch/tree_aspen_bush_b.dae", "bush"),
}


# The library's meshes name materials that no level-independent file defines: each stock level ships its own
# definitions (pointing at the shared textures in /assets/materials/tree/). We copy Driver Training's, and give
# the names only some meshes use (the m_ind_* ones, found in beamng.log as NO-MATERIAL) the nearest definition.
TREE_MATERIAL_FILES = ["levels/driver_training/art/shapes/trees/" + f + "main.materials.json"
                       for f in ("", "common/", "trees_aspen/", "trees_beech/", "trees_oak/", "trees_italy/")]
TREE_MATERIAL_KEEP = {"Birch_Bark_01", "Birch_Branch_01", "Birch_Leaves_01", "m_birch_leaves_distant", "beech_blocker",
                      "beech_branch_01", "beech_leaves", "beech_trunk", "m_beech_leaves_distant",
                      "Moss_01", "Oak_branch_01", "Oak_branch_02", "m_oak_leaves_distant",
                      "oak_leaves_01", "oak_leaves_02", "oak_leaves_03", "Oak_bark_01", "leaves_strong"}
TREE_MATERIAL_ALIASES = {"m_ind_beech_leaves": "beech_leaves", "m_ind_beech_blocker": "beech_blocker",
                         "m_ind_birch_leaves_01": "Birch_Leaves_01", "m_oak_leaves_01": "oak_leaves_01",
                         "m_oak_leaves_02": "oak_leaves_02",
                         # the beech and oak merged-foliage textures aren't in the shared pack (only Driver Training
                         # has them, inside its own zip): the distant leaves look the same from where they're used
                         "m_beech_merged_foliage": "m_beech_leaves_distant", "m_oak_merged_foliage": "m_oak_leaves_distant"}


def lenient_json(text):
    """BeamNG's JSON files allow trailing commas and // comments."""
    import json
    import re
    text = re.sub(r"(?m)^\s*//[^\n]*", "", text)
    return json.loads(re.sub(r",\s*([}\]])", r"\1", text))


def is_leaf(material):
    return any(w in material.lower() for w in ("leaves", "foliage", "blocker"))


def autumn(found, colours):
    """Autumn colours (the owner's choice, 2026-10-20): the game's own autumn birch textures, and each leaf material's
    base colour multiplied by its colour in `colours` ({material: [r, g, b]}, "default" for the rest; the leaf
    textures are green, so red goes well above 1). A list instead of a map tints every leaf material alike. Species
    and leaf textures differ between tree types, so mixed woods come out in a scatter of colours."""
    import json
    if isinstance(colours, list):
        colours = {"default": colours}
    for k, v in found.items():
        if not is_leaf(k):
            continue
        text = json.dumps(v).replace("t_birch_leaves_distant/t_birch_leaves_distant_b.color",
                                     "t_birch_leaves_autumn_distant/t_birch_leaves_autumn_distant_b.color")
        text = text.replace("t_birch_leaves/t_birch_leaves_b.color", "t_birch_leaves_autumn/t_birch_leaves_autumn_b.color")
        v = json.loads(text)
        t = colours.get(k, colours.get("default", [1.0, 1.0, 1.0]))
        for st in v.get("Stages", [])[:1]:
            if "baseColorMap" in st:
                base = st.get("baseColorFactor", [1, 1, 1, 1])
                st["baseColorFactor"] = [round(base[i] * t[i], 3) for i in range(3)] + [base[3]]
        found[k] = v


def tree_materials(game, name, pid, tint=None):
    """Material definitions for the trees: {name: definition}, from the game's Driver Training level."""
    import zipfile
    z = zipfile.ZipFile(game / "content" / "levels" / "driver_training.zip")
    found = {}
    for f in TREE_MATERIAL_FILES:
        for k, v in lenient_json(z.read(f).decode("utf-8", "replace")).items():
            m = v.get("mapTo", k)
            if m in TREE_MATERIAL_KEEP and m not in found:
                found[m] = dict(v, persistentId=pid(name, f"treemat/{m}"))
    missing = sorted((TREE_MATERIAL_KEEP | set(TREE_MATERIAL_ALIASES.values())) - set(found))
    if missing:
        raise SystemExit(f"tree materials not found in Driver Training: {missing}")
    for alias, src in TREE_MATERIAL_ALIASES.items():
        found[alias] = dict(found[src], name=alias, mapTo=alias, persistentId=pid(name, f"treemat/{alias}"))
    if tint:
        autumn(found, tint)
    # every texture must be in the shared pack (a missing one renders as the engine's orange placeholder)
    import json
    import re
    pack = {"/" + n.rsplit(".", 2)[0] for n in zipfile.ZipFile(game / "content" / "assets" / "materials" / "tree.zip").namelist()}
    bad = sorted({t for v in found.values() for t in re.findall(r'"(/assets/materials/tree/[^"]+)"', json.dumps(v))
                  if t.rsplit(".", 2)[0] not in pack})
    if bad:
        raise SystemExit(f"tree textures not in the game's shared pack: {bad}")
    return {k: found[k] for k in sorted(found)}


def item_data(name, pid):
    """ForestItemData definitions for the trees in use: {name: definition}."""
    out = {}
    for t in sorted(TREES):
        shape, kind = TREES[t]
        out[t] = dict({"name": t, "internalName": t, "class": "TSForestItemData", "persistentId": pid(name, f"tree/{t}"),
                       "shapeFile": LIB + shape}, **SWAY[kind])
    return out


def _clear_of(layout, x, y, clearance):
    """True when the point is at least `clearance` m from every pad and road (and the spawn)."""
    for p in layout["pads"]:
        dx = max(p["x"][0] - x, 0.0, x - p["x"][1])
        dy = max(p["y"][0] - y, 0.0, y - p["y"][1])
        if math.hypot(dx, dy) < clearance:
            return False
    for r in layout.get("roads", []):
        ox, oy = r["origin"]
        pts = [(ox + q[0], oy + q[1]) for q in r["points"]]
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            vx, vy = bx - ax, by - ay
            ll = vx * vx + vy * vy or 1e-9
            t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / ll))
            if math.hypot(x - ax - t * vx, y - ay - t * vy) < clearance + r["width"] / 2:
                return False
    return True


def forest(layout, terrain):
    """Tree placements [(type, x, y, z, yaw, scale)], z in world metres. Zones (layout "forest"):
    dense woods on the hills where a noise mask says so, lone trees on open hillside, and scattered trees and
    bushes on the flat grass, never nearer a pad or road than `clearanceM`."""
    f = layout.get("forest")
    if not f or not terrain.b:
        return []
    rnd = random.Random(f.get("seed", 1))
    woods = Noise(f.get("seed", 1) + 11, f.get("woodsScaleM", 180), 3)
    base = layout["terrain"]["baseZ"]
    half, zone, clearance = terrain.half, terrain.zone, f.get("clearanceM", 35)
    rampM = terrain.b["rampM"]
    dense, sparse, edge = f["woods"], f["hillside"], f["grass"]
    out = []
    cell = f.get("cellM", 10)
    steps = int((terrain.size - 20) / cell)
    for j in range(steps):
        for i in range(steps):
            x = -half + 10 + (i + rnd.random()) * cell
            y = -half + 10 + (j + rnd.random()) * cell
            d = outside(zone, x, y)
            u = rnd.random()
            if d > 0:
                hill = smoothstep(0, rampM * 0.5, d)
                if woods(x, y) > f.get("woodsThreshold", 0.5) - 0.12 * hill:
                    pick, p = dense, f.get("woodsDensity", 0.8)
                else:
                    pick, p = sparse, f.get("hillsideDensity", 0.05)
                p *= 0.3 + 0.7 * hill
            else:
                if not _clear_of(layout, x, y, clearance):
                    continue
                pick, p = edge, f.get("grassDensity", 0.05) * (1.5 if woods(x, y) > 0.55 else 0.4)
            if u >= p or terrain.slope(x, y) > f.get("maxSlope", 0.7):
                continue
            t = pick[int(rnd.random() * len(pick))]
            out.append((t, round(x, 2), round(y, 2), round(base + terrain.height(x, y) - 0.25, 2),
                        rnd.random() * 2 * math.pi, round(0.8 + 0.45 * rnd.random(), 3)))
    return out


def forest_files(trees):
    """{"forest/<type>.forest4.json": text} for the placements (BeamNG's forest format, one item per line)."""
    import json
    files = {}
    for t, x, y, z, yaw, s in trees:
        c, si = math.cos(yaw), math.sin(yaw)
        line = json.dumps({"ctxid": 0, "pos": [x, y, z], "rotationMatrix": [round(c, 5), round(-si, 5), 0, round(si, 5),
                           round(c, 5), 0, 0, 0, 1], "scale": s, "type": t}, separators=(",", ":"))
        files.setdefault(f"forest/{t}.forest4.json", []).append(line)
    return {k: "\n".join(v) + "\n" for k, v in sorted(files.items())}
