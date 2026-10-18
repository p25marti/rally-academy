"""Whole-map surface scan: python tools/ingame/scan.py [--level NAME] [--step M] [--aerial N] [--surfaces dirt,gravel,...]

Reads the loaded map's terrain on a grid from inside the game (the terrain's own material map and heights,
one call per band of rows, no car placement), finds flat, smooth ground on the chosen surfaces, and writes
venue-reports/<map>/scan/ (scan-<surfaces>/ for other surfaces):
  index.html  (self-contained) the map coloured by surface with the candidates marked, a surface summary, and a card per
              candidate (size, slope, surface, what's on top, an aerial view, a --at pose for survey.py fit)
  surface.png the map image on its own
  scan.json   the candidates and the map's surface summary
Terrain only (rivers aren't masked, only water planes and water blocks): roads and buildings are meshes on top, so each candidate is also checked for objects over it
(the surface under a ray from above sitting higher than the terrain) and for room around it. --level loads the
map first if another one is loaded (40-130 s). --aerial 0 skips the camera, which otherwise moves.
"""
import argparse
import base64
import html
import json
import math
import struct
import sys
import time
import zlib
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8")

import academy as A  # noqa: E402
import catalog  # noqa: E402
import survey  # noqa: E402
from game import call, lua, lua_json  # noqa: E402

LOOSE = ("gravel", "dirt", "sand", "mud")
CLEAR_ROOM = 20  # m from the centre to the nearest object (tree, wall, building) in every direction to call a spot clear
# Map colours (RGB) per surface family; flat ground on a chosen surface is drawn brighter.
COLOURS = {"tarmac": (70, 70, 78), "gravel": (176, 150, 110), "dirt": (150, 110, 70), "sand": (222, 200, 140),
           "mud": (100, 80, 55), "grass": (80, 130, 60), "snow": (235, 238, 245), "ice": (190, 220, 240),
           "rock": (125, 120, 115), "other": (110, 120, 100), "water": (60, 100, 160), "none": (20, 20, 20)}
# Terrain material names that don't carry a ground model name we know, matched by name.
NAME_HINTS = (("gravel", "gravel"), ("sand", "sand"), ("mud", "mud"), ("dirt", "dirt"), ("rock", "rock"),
              ("grass", "grass"), ("forest", "grass"), ("asphalt", "tarmac"), ("road", "tarmac"), ("snow", "snow"),
              ("ice", "ice"), ("concrete", "tarmac"))

TERRAIN = "(core_terrain and core_terrain.getTerrain and core_terrain.getTerrain()) or " \
          "scenetree.findObject((scenetree.findClassObjects('TerrainBlock') or {})[1] or '')"


def family_of(material, groundmodel):
    fam = catalog.FAMILY.get((groundmodel or "").upper())
    if fam:
        return fam
    low = f"{material} {groundmodel}".lower()
    for hint, f in NAME_HINTS:
        if hint in low:
            return f
    return "other"


def terrain_info():
    return lua_json(f"""local t = {TERRAIN}
if not t then return {{}} end
local b = t:getWorldBox()
local mats = {{}}
for i = 0, t:getMaterialCount() - 1 do
  local m = t:getMaterial(i)
  mats[#mats + 1] = {{name = tostring(t:getMaterialName(i)), gm = tostring(m and m.getGroundmodelName and m:getGroundmodelName() or '')}}
end
local water = nil
for _, n in ipairs(scenetree.findClassObjects('WaterPlane') or {{}}) do
  local w = scenetree.findObject(n) if w then water = math.max(water or -1e9, w:getPosition().z) end
end
local blocks = {{}}
for _, n in ipairs(scenetree.findClassObjects('WaterBlock') or {{}}) do
  local w = scenetree.findObject(n)
  if w then local wb = w:getWorldBox() blocks[#blocks + 1] = {{wb.minExtents.x, wb.minExtents.y, wb.maxExtents.x, wb.maxExtents.y, wb.maxExtents.z}} end
end
return {{x0 = b.minExtents.x, y0 = b.minExtents.y, x1 = b.maxExtents.x, y1 = b.maxExtents.y, mats = mats, waterBlocks = blocks,
        water = water or false, level = tostring((getCurrentLevelIdentifier()))}}""")


def fetch(info, step):
    """Material index and height (m) per cell, rows south to north: (mats[j][i], heights[j][i])."""
    nx, ny = int((info["x1"] - info["x0"]) // step), int((info["y1"] - info["y0"]) // step)
    rows_per_call = max(1, 40000 // nx)
    mats, hs = [], []
    for j0 in range(0, ny, rows_per_call):
        j1 = min(ny, j0 + rows_per_call) - 1
        text = lua(f"""local t = {TERRAIN}
local x0, y0, s = {info['x0']}, {info['y0']}, {step}
local out = {{}}
for j = {j0}, {j1} do
  local y = y0 + (j + 0.5) * s
  local m, h = {{}}, {{}}
  for i = 0, {nx - 1} do
    local p = vec3(x0 + (i + 0.5) * s, y, 0)
    local z = core_terrain.getTerrainHeight(p)
    if z then
      p.z = z
      local idx = t:getMaterialIdxWs(p)
      m[#m + 1] = string.char(65 + math.max(-1, math.min(57, idx or -1)))  -- '@' none, 'A'.. (never ';' or '|')
      h[#h + 1] = math.floor(z * 100 + 0.5)
    else
      m[#m + 1] = '@'
      h[#h + 1] = -999999
    end
  end
  out[#out + 1] = table.concat(m) .. '|' .. table.concat(h, ',')
end
return table.concat(out, ';')""")
        for row in str(text).split(";"):
            m, h = row.split("|")
            mats.append([ord(c) - 65 for c in m])
            hs.append([int(v) / 100 for v in h.split(",")])
        print(f"  rows {j1 + 1}/{ny}", end="\r", flush=True)
    print()
    return mats, hs, nx, ny


def analyse(info, mats, hs, nx, ny, step, surfaces, max_slope, max_rough, min_side, min_share=0.7):
    fams = [family_of(m["name"], m["gm"]) for m in info["mats"]]
    water = info.get("water")
    blocks = info.get("waterBlocks") or []  # lakes and ponds: boxes whose top is the water's surface

    def fam(i, j):
        idx = mats[j][i]
        if idx < 0 or hs[j][i] < -9000:
            return "none"
        if water is not False and water is not None and hs[j][i] < water:
            return "water"
        x, y = info["x0"] + (i + 0.5) * step, info["y0"] + (j + 0.5) * step
        for bx0, by0, bx1, by1, top in blocks:
            if bx0 <= x <= bx1 and by0 <= y <= by1 and hs[j][i] < top:
                return "water"
        return fams[idx] if idx < len(fams) else "other"

    F = [[fam(i, j) for i in range(nx)] for j in range(ny)]
    # Flat at a car's scale, not the texture's: slope across about 20 m (cells 10 m either side), and bumps as the
    # height's departure from the mean over about 18 m (a summed-area table of heights). Small undulations of
    # 10-20 cm, which a car rolls over, don't count.
    k = max(1, round(10 / step))
    r = max(1, round(9 / step))
    slope = [[99.0] * nx for _ in range(ny)]
    rough = [[9.0] * nx for _ in range(ny)]
    for j in range(k, ny - k):
        hj, up, dn = hs[j], hs[j + k], hs[j - k]
        for i in range(k, nx - k):
            slope[j][i] = max(abs(hj[i + k] - hj[i - k]), abs(up[i] - dn[i])) / (2 * k * step) * 100
    H = [[0.0] * (nx + 1) for _ in range(ny + 1)]
    for j in range(ny):
        acc, row, prev, hj = 0.0, H[j + 1], H[j], hs[j]
        for i in range(nx):
            acc += hj[i] if hj[i] > -9000 else 0.0
            row[i + 1] = prev[i + 1] + acc
    n = (2 * r + 1) ** 2
    for j in range(r, ny - r):
        for i in range(r, nx - r):
            tot = H[j + r + 1][i + r + 1] - H[j - r][i + r + 1] - H[j + r + 1][i - r] + H[j - r][i - r]
            rough[j][i] = abs(hs[j][i] - tot / n)
    # Terrain textures are often a patchwork (dirt with grass patches): a cell counts when most of the ground
    # within about 5 m of it is on the chosen surfaces (a summed-area table over the loose mask).
    w = max(1, round(5 / step))
    S = [[0] * (nx + 1) for _ in range(ny + 1)]
    for j in range(ny):
        acc, row, prev = 0, S[j + 1], S[j]
        for i in range(nx):
            acc += 1 if F[j][i] in surfaces else 0
            row[i + 1] = prev[i + 1] + acc

    def share(i, j):
        a0, a1, b0, b1 = max(0, i - w), min(nx, i + w + 1), max(0, j - w), min(ny, j + w + 1)
        return (S[b1][a1] - S[b0][a1] - S[b1][a0] + S[b0][a0]) / ((a1 - a0) * (b1 - b0))
    ok = [[F[j][i] not in ("water", "tarmac", "none") and slope[j][i] <= max_slope and rough[j][i] <= max_rough
           and share(i, j) >= min_share for i in range(nx)] for j in range(ny)]
    # Largest flat square ending at each cell (dynamic programming over the grid).
    sq = [[0] * nx for _ in range(ny)]
    for j in range(ny):
        for i in range(nx):
            if ok[j][i]:
                sq[j][i] = 1 if i == 0 or j == 0 else 1 + min(sq[j - 1][i], sq[j][i - 1], sq[j - 1][i - 1])
    # Connected patches; each patch's biggest square is its candidate.
    seen = [[False] * nx for _ in range(ny)]
    cands = []
    for j in range(ny):
        for i in range(nx):
            if not ok[j][i] or seen[j][i]:
                continue
            stack, cells, best = [(i, j)], 0, (0, i, j)
            seen[j][i] = True
            while stack:
                a, b = stack.pop()
                cells += 1
                if sq[b][a] > best[0]:
                    best = (sq[b][a], a, b)
                for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    c, d = a + da, b + db
                    if 0 <= c < nx and 0 <= d < ny and ok[d][c] and not seen[d][c]:
                        seen[d][c] = True
                        stack.append((c, d))
            side = best[0] * step
            if side < min_side:
                continue
            n, a1, b1 = best
            a0, b0 = a1 - n + 1, b1 - n + 1
            block = [(a, b) for b in range(b0, b1 + 1) for a in range(a0, a1 + 1)]
            zs = [hs[b][a] for a, b in block]
            counts = {}
            for a, b in block:
                counts[F[b][a]] = counts.get(F[b][a], 0) + 1
            cx, cy = info["x0"] + (a0 + a1 + 1) / 2 * step, info["y0"] + (b0 + b1 + 1) / 2 * step
            cands.append({"pos": {"x": round(cx, 1), "y": round(cy, 1), "z": round(sum(zs) / len(zs), 1)},
                          "squareM": side, "patchM2": cells * step * step, "riseM": round(max(zs) - min(zs), 2),
                          "slopePct": round(sum(slope[b][a] for a, b in block) / len(block), 1),
                          "roughM": round(max(rough[b][a] for a, b in block), 2),
                          "surface": max((f for f in counts if f in surfaces), key=counts.get, default=max(counts, key=counts.get)),
                          "loosePct": round(sum(v for f, v in counts.items() if f in surfaces) / len(block) * 100),
                          "cells": [a0, b0, a1, b1]})
    cands.sort(key=lambda c: (-c["squareM"], -c["patchM2"]))
    summary = {}
    for row in F:
        for f in row:
            summary[f] = summary.get(f, 0) + 1
    return F, ok, cands, {f: round(c * step * step / 1e4, 1) for f, c in sorted(summary.items(), key=lambda kv: -kv[1])}


def check_on_site(c):
    """What's on top of the terrain over the square (roads, buildings, rocks), and the room around its centre."""
    half = c["squareM"] / 2
    res = lua_json(f"""local cx, cy, h = {c['pos']['x']}, {c['pos']['y']}, {half}
local covered, total = 0, 0
for a = -2, 2 do for b = -2, 2 do
  local x, y = cx + a * h / 2.5, cy + b * h / 2.5
  local tz = core_terrain.getTerrainHeight(vec3(x, y, 0)) or 0
  local sz = be:getSurfaceHeightBelow(vec3(x, y, tz + 60))
  total = total + 1
  if sz and sz > tz + 0.4 then covered = covered + 1 end
end end
local tz = (core_terrain.getTerrainHeight(vec3(cx, cy, 0)) or 0) + 1.0
local room = {{}}
for k = 0, 15 do
  local a = k * math.pi / 8
  room[#room + 1] = math.floor(castRayStatic(vec3(cx, cy, tz), vec3(math.cos(a), math.sin(a), 0), 150) + 0.5)
end
return {{covered = covered / total, room = room}}""")
    c["coveredPct"] = round(res["covered"] * 100)
    c["room"] = res["room"]
    c["clearM"] = min(res["room"])
    return c


def png(path, F, ok, cands, nx, ny):
    """The map coloured by surface (north up), flat ground on the chosen surfaces brighter, candidates outlined."""
    marks = {}
    for k, c in enumerate(cands):
        a0, b0, a1, b1 = c["cells"]
        for a in range(a0, a1 + 1):
            marks[(a, b0)] = marks[(a, b1)] = True
        for b in range(b0, b1 + 1):
            marks[(a0, b)] = marks[(a1, b)] = True
    raw = bytearray()
    for j in range(ny - 1, -1, -1):
        raw.append(0)
        for i in range(nx):
            if (i, j) in marks:
                r, g, b = 255, 40, 40
            else:
                r, g, b = COLOURS.get(F[j][i], COLOURS["other"])
                if not ok[j][i]:
                    r, g, b = int(r * 0.45), int(g * 0.45), int(b * 0.45)
            raw += bytes((r, g, b))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", nx, ny, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Surface scan: {map}</title><style>
:root {{ --bg:#16181d; --fg:#e8e8ec; --mute:#9aa0aa; --card:#22252c; --line:#353a44; }}
@media (prefers-color-scheme: light) {{ :root:not([data-theme=dark]) {{ --bg:#f5f5f7; --fg:#1d1d22; --mute:#60646c; --card:#fff; --line:#d8dae0; }} }}
body {{ background:var(--bg); color:var(--fg); font:15px/1.45 system-ui,sans-serif; margin:0; padding:16px; }}
h1 {{ font-size:22px; margin:0 0 4px; }} h2 {{ font-size:18px; margin:24px 0 8px; }} .mute {{ color:var(--mute); }}
.map {{ position:relative; max-width:900px; }} .map img {{ width:100%; image-rendering:pixelated; border-radius:6px; display:block; }}
.pin {{ position:absolute; transform:translate(-50%,-50%); background:#ff2828; color:#fff; font:700 12px system-ui;
        border-radius:10px; padding:1px 6px; border:1px solid #fff; }}
.legend span {{ display:inline-block; margin:0 10px 4px 0; }} .sw {{ display:inline-block; width:12px; height:12px; border-radius:2px; vertical-align:-1px; margin-right:4px; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(300px,1fr)); gap:12px; }}
.card {{ background:var(--card); border:1px solid var(--line); border-radius:8px; overflow:hidden; }}
.card img {{ width:100%; display:block; }} .card div {{ padding:10px 12px; }} code {{ font-size:12px; word-break:break-all; }}
</style></head><body><h1>Surface scan: {map}</h1>
<p class="mute">{when} · terrain grid every {step:g} m · flat (slope ≤ {slope:g} % across 20 m, bumps ≤ {rough:g} m) on {surfaces} ·
squares of {minside:g} m or more. Terrain only: check "on top" and the aerial view for roads, buildings and trees.</p>
<div class="map"><img src="data:image/png;base64,{mapimg}" alt="surface map">{pins}</div>
<p class="legend">{legend}</p>
<h2>Candidates ({count})</h2><div class="grid">{cards}</div></body></html>"""


def card(k, c, img):
    image = (f'<img src="data:image/jpeg;base64,{base64.b64encode(img.read_bytes()).decode()}" alt="aerial view">'
             if img and img.exists() else "")
    on_top = "" if "coveredPct" not in c else (f" · on top: {c['coveredPct']} % covered · room {c['clearM']} m+"
                                               + ("" if c["clearM"] >= CLEAR_ROOM else " <b>(cluttered: trees or objects close by)</b>"))
    return (f'<div class="card">{image}<div><b>{k}. {c["surface"]}</b>, {c["squareM"]:g} × {c["squareM"]:g} m square '
            f'(patch {c["patchM2"] / 1e4:.2f} ha, {c["loosePct"]} % {c["surface"]})<br><span class="mute">rise {c["riseM"]} m · slope {c["slopePct"]} % · '
            f'bumps {c["roughM"]} m{on_top}</span><br><code>survey.py fit DRILL --at={c["pos"]["x"]},{c["pos"]["y"]},'
            f'{c["pos"]["z"]},0,1</code></div></div>')


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--level", help="map to scan (loads it if another is loaded)")
    p.add_argument("--step", type=float, default=0, help="grid spacing, m (default: about 900 cells across the map)")
    p.add_argument("--surfaces", default=",".join(LOOSE), help="families counted as usable (default: loose ones)")
    p.add_argument("--max-slope", type=float, default=5.0, help="%% across 20 m (default 5)")
    p.add_argument("--max-rough", type=float, default=0.25, help="m a point may stand off the mean height within 9 m (default 0.25)")
    p.add_argument("--min-share", type=float, default=0.7, help="share of the ground within 5 m on the surfaces (default 0.7)")
    p.add_argument("--min-side", type=float, default=25.0, help="smallest flat square worth listing, m (default 25)")
    p.add_argument("--top", type=int, default=24, help="candidates to list (default 24)")
    p.add_argument("--aerial", type=int, default=12, help="aerial views of the best N (default 12; 0: camera untouched)")
    a = p.parse_args(argv)
    if a.level and str(lua("local l = getCurrentLevelIdentifier() return tostring(l)")).lower() != a.level.lower():
        print(f"loading {a.level} ...", flush=True)
        path = lua(f"for _, l in ipairs(core_levels.getList()) do if string.lower(l.levelName) == '{a.level.lower()}' "
                   "then return l.misFilePath end end return ''")
        if not path:
            print(f"no map called {a.level}; try survey.py levels")
            return 2
        lua(f"freeroam_freeroam.startFreeroam('{path}') return 1")
        if not A.wait_level(a.level, timeout=300):
            print("the map didn't finish loading")
            return 1
    info = terrain_info()
    if not info.get("mats"):
        print("no terrain on this map (or no map loaded)")
        return 2
    lvl = info["level"]
    size = max(info["x1"] - info["x0"], info["y1"] - info["y0"])
    step = a.step or max(2.0, round(size / 900))
    surfaces = tuple(s.strip() for s in a.surfaces.split(",") if s.strip())
    print(f"{lvl}: terrain {info['x1'] - info['x0']:.0f} × {info['y1'] - info['y0']:.0f} m, {len(info['mats'])} materials, "
          f"grid every {step:g} m", flush=True)
    t0 = time.time()
    mats, hs, nx, ny = fetch(info, step)
    print(f"  read {nx * ny} cells in {time.time() - t0:.0f} s", flush=True)
    F, ok, cands, summary = analyse(info, mats, hs, nx, ny, step, surfaces, a.max_slope, a.max_rough, a.min_side, a.min_share)
    cands = cands[:a.top]
    out = survey.REPORTS / lvl / ("scan" if surfaces == LOOSE else "scan-" + "-".join(surfaces))
    out.mkdir(parents=True, exist_ok=True)
    for c in cands:
        try:
            check_on_site(c)
        except Exception as e:  # noqa: BLE001 - a bad spot shouldn't stop the scan
            print(f"  couldn't check ({c['pos']['x']:.0f}, {c['pos']['y']:.0f}): {e}")
    # Trees are objects on top of grass terrain, invisible to the terrain scan and between the "covered" probes;
    # the horizontal rays find them. Candidates with room all round come first.
    cands.sort(key=lambda c: (c.get("clearM", 0) < CLEAR_ROOM, -c["squareM"], -c["patchM2"]))
    png(out / "surface.png", F, ok, cands, nx, ny)
    imgs = {}
    if a.aerial and cands:
        started = time.time()
        lua("extensions.ui_visibility.setCef(false) return 1")
        try:
            for k, c in enumerate(cands[:a.aerial], 1):
                img = out / f"{k:02d}.jpg"
                try:
                    survey.aerial(img, c["pos"], {"x": 0, "y": 1}, height=max(60, c["squareM"] * 1.1), back=c["squareM"] * 0.6)
                    imgs[k] = img
                except Exception as e:  # noqa: BLE001
                    print(f"  no aerial view {k}: {e}")
        finally:
            lua("extensions.ui_visibility.setCef(true) return 1")
            call("set_camera", {"name": "orbit"})
            survey.tidy_game_copies(started, out)
    total = sum(summary.values()) or 1
    legend = "".join(f'<span><i class="sw" style="background:rgb{COLOURS.get(f, COLOURS["other"])}"></i>{html.escape(f)} '
                     f'{ha:g} ha ({ha / total * 100:.0f} %)</span>' for f, ha in summary.items())
    pins = "".join(f'<span class="pin" style="left:{(c["cells"][0] + c["cells"][2] + 1) / 2 / nx * 100:.2f}%;'
                   f'top:{100 - (c["cells"][1] + c["cells"][3] + 1) / 2 / ny * 100:.2f}%">{k}</span>'
                   for k, c in enumerate(cands, 1))
    (out / "index.html").write_text(PAGE.format(
        map=html.escape(lvl), mapimg=base64.b64encode((out / "surface.png").read_bytes()).decode(),
        when=datetime.now().strftime("%Y-%m-%d %H:%M"), step=step, slope=a.max_slope, rough=a.max_rough,
        surfaces=html.escape(", ".join(surfaces)), minside=a.min_side, pins=pins, legend=legend, count=len(cands),
        cards="".join(card(k, c, imgs.get(k)) for k, c in enumerate(cands, 1))), encoding="utf-8")
    (out / "scan.json").write_text(json.dumps({"level": lvl, "step": step, "surfaces": surfaces, "summaryHa": summary,
                                               "materials": info["mats"], "candidates": cands}, indent=1), encoding="utf-8")
    print(f"\n{len(cands)} candidates; surfaces (ha): " + ", ".join(f"{f} {v:g}" for f, v in summary.items()))
    for k, c in enumerate(cands[:12], 1):
        print(f"  {k:2}. {c['surface']:6} {c['squareM']:4.0f} m square at ({c['pos']['x']:.0f}, {c['pos']['y']:.0f}, "
              f"{c['pos']['z']:.0f})  rise {c['riseM']} m, slope {c['slopePct']} %, bumps {c['roughM']} m"
              + (f", {c['coveredPct']} % covered, room {c['clearM']} m" + ("" if c["clearM"] >= CLEAR_ROOM else " CLUTTERED")
                 if "coveredPct" in c else ""))
    print(f"report: {out / 'index.html'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
