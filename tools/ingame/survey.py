"""Venue surveys through the game's MCP server: finding and checking places for drills.
Run with the game loaded on the map you're surveying (docs/TESTING.md, "Finding a venue").

  survey.py here                          room around the car, surface under each wheel
  survey.py surfaces [--along=..] [--side=..]   wheel surfaces on a grid ahead of / across the car
  survey.py terrain X Y [X Y ...]         terrain ground model at points (no road meshes)
  survey.py configs [MODEL]               config keys for a car model (default: current car)
  survey.py levels                        installed maps

  survey.py spots [--all]                 spots saved with "Rally Academy: Save spot" (this map)
  survey.py goto ID | --at X,Y,Z,DX,DY    put the car on a saved spot or a pose
  survey.py straights|corners|hills|crests   road sections from the map's AI road network
  survey.py open [--step=16]              open, flat, loose-surface areas from a terrain scan (slow)
  survey.py fits DRILL [--measure N]      places on this map that suit a drill's venueNeeds
  survey.py fit DRILL (--spot ID | --at X,Y,Z,DX,DY) [--to NODE]
                                          drive the drill's kind of run there: does it work?
  survey.py report [--quick] [--open]     HTML page: saved spots + the finders' best, with aerial
                                          views and measured surfaces, in venue-reports/<map>/

Commands that place the car or the camera put them back afterwards.
"""
import argparse
import base64
import html
import json
import math
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
sys.stdout.reconfigure(encoding="utf-8")

from game import call, lua, screenshot, vlua  # noqa: E402
import academy as A  # noqa: E402
import roads  # noqa: E402
import venues  # noqa: E402

ROOT = HERE.parents[1]
REPORTS = ROOT / "venue-reports"

WHEEL_SURFACES = ("local mats = particles.getMaterialsParticlesTable() local out = {} "
                  "for i = 0, wheels.wheelRotatorCount - 1 do local wd = wheels.wheelRotators[i] "
                  "local m = particles.getMaterialByID(mats, wd.contactMaterialID1) "
                  "out[#out+1] = wd.name .. '=' .. (m and m.name or tostring(wd.contactMaterialID1)) end "
                  "return table.concat(out, ' ')")

# Distance to the nearest static object in 8 directions (castRayStatic), up vector, position.
ROOM = """
local v = be:getPlayerVehicle(0)
local p = v:getPosition()
local fwd = vec3(v:getDirectionVector()):normalized()
local right = fwd:cross(vec3(0, 0, 1)):normalized()
local d = {}
for _, deg in ipairs({0, 45, 90, 135, 180, -135, -90, -45}) do
  local r = math.rad(deg)
  local dir = (fwd * math.cos(r) + right * math.sin(r)):normalized()
  d[#d + 1] = math.floor(castRayStatic(p + vec3(0, 0, 0.6), dir, 150) or 150)
end
local h = vec3(v:getDirectionVector())
return jsonEncode({room = d, upZ = vec3(v:getDirectionVectorUp()).z, pos = {x = p.x, y = p.y, z = p.z},
                   dir = {x = h.x, y = h.y, z = h.z}})"""

ROAD_NETWORK = """
local m = map.getMap()
local nodes, links = {}, {}
for name, n in pairs(m.nodes) do
  nodes[#nodes + 1] = {name, math.floor(n.pos.x * 100 + 0.5) / 100, math.floor(n.pos.y * 100 + 0.5) / 100,
                       math.floor(n.pos.z * 100 + 0.5) / 100, n.radius or 0}
  for other, l in pairs(n.links or {}) do
    links[#links + 1] = {name, other, l.drivability or 1, l.speedLimit or 0}
  end
end
return jsonEncode({nodes = nodes, links = links})"""

ROOM_NAMES = ["ahead", "ahead-right", "right", "behind-right", "behind", "behind-left", "left", "ahead-left"]


def pose():
    return json.loads(lua(ROOM))


def wheel_surfaces():
    return sorted({kv.split("=")[1] for kv in str(vlua(WHEEL_SURFACES)).split() if "=" in kv})


def level():
    return A.debug_state().get("level")


def road_network():
    data = json.loads(lua(ROAD_NETWORK))
    nodes = {n[0]: (n[1], n[2], n[3], n[4]) for n in data["nodes"]}
    return nodes, roads.build(nodes, data["links"])


def saved_spots(all_maps=False):
    data = json.loads(lua("return jsonEncode(jsonReadFile('settings/rallyAcademy/spots.json') or {spots = {}})"))
    spots = data.get("spots") or []
    if isinstance(spots, dict):  # an empty Lua table arrives as {}
        spots = []
    lvl = level()
    return [s for s in spots if all_maps or str(s.get("level", "")).lower() == str(lvl).lower()]


# --------------------------------------------------------------------------- simple commands

def here(_args):
    s = pose()
    print("car at ({x:.1f}, {y:.1f}, {z:.1f})".format(**s["pos"]), f"upright {s['upZ']:.3f} (1 = flat)")
    print("room (m, up to 150):", ", ".join(f"{n} {d}" for n, d in zip(ROOM_NAMES, s["room"])))
    print("wheels:", vlua(WHEEL_SURFACES))


def surfaces(args):
    start = pose()
    along = [float(v) for v in args.along.split(",")]
    side = [float(v) for v in args.side.split(",")]
    print(f"wheel surfaces; rows = metres ahead, columns = metres to the right ({', '.join(map(str, side))})")
    for a in along:
        row = []
        for s in side:
            A.place(start["pos"], start["dir"], ahead=a, side=s, lift=2.0)
            row.append("/".join(wheel_surfaces()) or "?")
        print(f"  {a:>5.0f} m: " + " | ".join(row))
    A.place(start["pos"], start["dir"], lift=0.5)


def terrain(args):
    if len(args.points) % 2:
        sys.exit("give X Y pairs")
    pts = ",".join(f"{{{args.points[i]},{args.points[i + 1]}}}" for i in range(0, len(args.points), 2))
    print(lua(f"""
local t = core_terrain.getTerrain()
local out = {{}}
for _, q in ipairs({{{pts}}}) do
  local p = vec3(q[1], q[2], 0)
  p.z = core_terrain.getTerrainHeight(p) or 0
  local m = t:getMaterial(t:getMaterialIdxWs(p))
  out[#out + 1] = string.format('(%.1f, %.1f): %s', q[1], q[2], (m and m.getGroundmodelName and m:getGroundmodelName()) or '?')
end
return table.concat(out, '; ')"""))


def configs(args):
    model = args.model or json.loads(call("get_vehicle")).get("jbeam")
    print(f"{model}:", call("get_configs", {"model": model}) if model else "no car")


def levels(_args):
    print(lua("local o = {} for _, l in ipairs(core_levels.getList()) do o[#o+1] = l.levelName end table.sort(o) return table.concat(o, ', ')"))


def spots(args):
    found = saved_spots(args.all)
    if not found:
        print("no saved spots" + ("" if args.all else f" on {level()}") + ": bind and press 'Rally Academy: Save spot'")
    for s in found:
        road = s.get("road") or {}
        print(f"  #{s['id']:<3} {s.get('level')}  ({s['pos']['x']:.1f}, {s['pos']['y']:.1f})  room ahead {s['room'][0]} m, "
              f"behind {s['room'][4]} m  road {road.get('width', '-')} m  slope {s.get('slopeDeg')}°  "
              f"{'/'.join(sorted(set((s.get('surfaces') or {}).values())))}  {s.get('note') or ''}")


def goto(args):
    if args.at:
        x, y, z, dx, dy = (float(v) for v in args.at.split(","))
        A.place({"x": x, "y": y, "z": z}, {"x": dx, "y": dy}, lift=0.5)
        return print("placed")
    spot = next((s for s in saved_spots(all_maps=True) if s["id"] == args.id), None)
    if not spot:
        sys.exit(f"no spot #{args.id}")
    if str(spot["level"]).lower() != str(level()).lower():
        sys.exit(f"spot #{args.id} is on {spot['level']}; load that map first")
    A.place(spot["pos"], spot["dir"], lift=0.5)
    print(f"placed at spot #{args.id}")


# --------------------------------------------------------------------------- finders

def show(sections, limit):
    for s in roads.dedupe(sections)[:limit]:
        extra = {k: v for k, v in s.items() if k not in ("kind", "pos", "dir", "nodes")}
        print(f"  {s['kind']:<9} at ({s['pos']['x']:.1f}, {s['pos']['y']:.1f})  " + ", ".join(f"{k} {v}" for k, v in extra.items()))
        print(f"            --at={s['pos']['x']},{s['pos']['y']},{s['pos']['z']},{s['dir']['x']},{s['dir']['y']}  --to {s['nodes'][-1]}"
              if "nodes" in s else f"            --at={s['pos']['x']},{s['pos']['y']},{s['pos']['z']},{s['dir']['x']},{s['dir']['y']}")


def find(args):
    nodes, adj = road_network()
    fn = {"straights": lambda: roads.straights(nodes, adj, min_length=args.min_length),
          "corners": lambda: roads.corners(nodes, adj, max_radius=args.max_radius),
          "hills": lambda: roads.hills(nodes, adj),
          "crests": lambda: roads.crests(nodes, adj)}[args.cmd]
    print(f"{args.cmd} on {level()} ({len(nodes)} road nodes):")
    show(fn(), args.limit)


LOOSE = ("DIRT", "GRAVEL", "SAND", "MUD")


def terrain_grid(step):
    """(x, y, z, groundmodel, normal_z) on a grid over the whole terrain."""
    x0, y0, x1, y1 = (float(v) for v in lua(
        "local b = core_terrain.getTerrain():getWorldBox() "
        "return string.format('%.1f,%.1f,%.1f,%.1f', b.minExtents.x, b.minExtents.y, b.maxExtents.x, b.maxExtents.y)").split(","))
    rows, band, y = [], step * 40, y0
    while y < y1:
        out = lua(f"""
local t = core_terrain.getTerrain()
local out, cache = {{}}, {{}}
for yy = {y + step / 2}, {min(y + band, y1)}, {step} do
  for xx = {x0 + step / 2}, {x1}, {step} do
    local p = vec3(xx, yy, 0)
    local z = core_terrain.getTerrainHeight(p)
    if z then
      p.z = z
      local idx = t:getMaterialIdxWs(p)
      local gm = cache[idx]
      if gm == nil then
        local m = t:getMaterial(idx)
        gm = (m and m.getGroundmodelName and m:getGroundmodelName()) or ''
        cache[idx] = gm
      end
      local n = core_terrain.getTerrainNormal(p)
      out[#out + 1] = string.format('%.0f,%.0f,%.1f,%s,%.3f', xx, yy, z, gm, n and n.z or 0)
    end
  end
end
return table.concat(out, ';')""")
        for c in out.split(";"):
            parts = c.split(",")
            if len(parts) == 5:
                rows.append((float(parts[0]), float(parts[1]), float(parts[2]), parts[3].upper(), float(parts[4])))
        y += band
    return rows


def open_areas(step=16.0, min_cells=12, flat=0.985, max_dz=3.0):
    """Connected loose, flat terrain cells, largest first (terrain only: roads and buildings
    on top aren't seen, so check candidates with `here`)."""
    ok = {(math.floor(x / step), math.floor(y / step)): (x, y, z, gm) for x, y, z, gm, nz in terrain_grid(step)
          if any(k in gm for k in LOOSE) and nz >= flat}
    seen, out = set(), []
    for key in ok:
        if key in seen:
            continue
        stack, cells = [key], []
        seen.add(key)
        while stack:
            k = stack.pop()
            cells.append(ok[k])
            for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (k[0] + d[0], k[1] + d[1])
                if n in ok and n not in seen and abs(ok[n][2] - ok[k][2]) < max_dz:
                    seen.add(n)
                    stack.append(n)
        if len(cells) >= min_cells:
            cx, cy = sum(c[0] for c in cells) / len(cells), sum(c[1] for c in cells) / len(cells)
            best = min(cells, key=lambda c: (c[0] - cx) ** 2 + (c[1] - cy) ** 2)  # a cell inside the patch
            surf = {}
            for c in cells:
                surf[c[3]] = surf.get(c[3], 0) + 1
            out.append({"kind": "open area", "pos": {"x": best[0], "y": best[1], "z": best[2]}, "dir": {"x": 0.0, "y": 1.0},
                        "areaM2": len(cells) * step * step,
                        "spanM": f"{max(c[0] for c in cells) - min(c[0] for c in cells) + step:.0f} x "
                                 f"{max(c[1] for c in cells) - min(c[1] for c in cells) + step:.0f}",
                        "terrain": max(surf, key=surf.get)})
    return sorted(out, key=lambda p: -p["areaM2"])


def open_cmd(args):
    print(f"open loose areas on {level()} (terrain grid every {args.step:g} m):")
    show(open_areas(args.step), args.limit)


def fits_cmd(args):
    """Search this map for places matching a drill's venueNeeds."""
    drill = A.drill(args.drill)
    needs = drill["environment"]["venueNeeds"]
    kind = needs["kind"]
    print(f"{drill['id']} {drill['title']} needs: " + ", ".join(f"{k} {v}" for k, v in needs.items() if k != "features"))
    if needs.get("features"):
        print("  and, by eye: " + "; ".join(needs["features"]))
    if kind == "open":
        found = open_areas()
    else:
        nodes, adj = road_network()
        found = {"straight": lambda: roads.straights(nodes, adj, min_length=needs.get("lengthM", 80)),
                 "corner": lambda: roads.corners(nodes, adj, max_radius=(needs.get("radiusM") or [8, 120])[1]),
                 "hill": lambda: roads.hills(nodes, adj, min_grade_pct=needs.get("gradePct", 6)),
                 "crest": lambda: roads.crests(nodes, adj),
                 "route": lambda: roads.straights(nodes, adj, min_length=needs.get("lengthM", 100)) + roads.corners(nodes, adj)}[kind]()
    matches = [c for c in roads.dedupe(found) if not venues.check(needs, c)[0]]
    if args.measure:  # place the car on the best few: real surfaces and room, then check again
        home = pose()
        try:
            for c in matches[:args.measure]:
                c["measured"] = measure(c)
        finally:
            A.place(home["pos"], home["dir"], lift=0.5)
        measured = sorted((c for c in matches[:args.measure] if not venues.check(needs, c)[0]),
                          key=lambda c: venues.surface_rank(needs, c))  # gravel before tarmac
        print(f"\n{len(measured)} of the best {min(args.measure, len(matches))} pass with measured surfaces and room:")
        matches = measured
    else:
        print(f"\n{len(matches)} candidates on {level()} (surfaces unchecked; add --measure 5 to check the best five):")
    show(matches, args.limit)


def fit_cmd(args):
    import fit
    if args.spot:
        spot = next((s for s in saved_spots(all_maps=True) if s["id"] == args.spot), None)
        if not spot:
            sys.exit(f"no spot #{args.spot}")
        pos, direction = spot["pos"], spot["dir"]
    elif args.at:
        x, y, z, dx, dy = (float(v) for v in args.at.split(","))
        pos, direction = {"x": x, "y": y, "z": z}, {"x": dx, "y": dy}
    else:
        sys.exit("give --spot ID or --at X,Y,Z,DX,DY")
    r = fit.fit(args.drill, pos, direction, to_node=args.to)
    print(f"{r['drill']} ({r['kind']}): {'FITS' if r['fits'] else 'DOES NOT FIT'}")
    for p in r["problems"]:
        print(f"  ✗ {p}")
    for n in r["notes"]:
        print(f"  · {n}")
    sys.exit(0 if r["fits"] else 1)


# --------------------------------------------------------------------------- report

def aerial(path, pos, direction, height=40.0, back=30.0):
    """Free camera behind and above `pos`, looking along `direction` and down at it."""
    n = math.hypot(direction["x"], direction["y"]) or 1
    dx, dy = direction["x"] / n, direction["y"] / n
    target = (pos["x"] + dx * 25, pos["y"] + dy * 25, pos["z"])
    cam = (pos["x"] - dx * back, pos["y"] - dy * back, pos["z"] + height)
    q = lua(f"local d = vec3({target[0] - cam[0]:.2f}, {target[1] - cam[1]:.2f}, {target[2] - cam[2]:.2f}):normalized() "
            "local q = quatFromDir(d, vec3(0, 0, 1)) return string.format('%.6f,%.6f,%.6f,%.6f', q.x, q.y, q.z, q.w)")
    rot = dict(zip("xyzw", map(float, q.split(","))))
    call("set_free_camera", {"pos": {"x": cam[0], "y": cam[1], "z": cam[2]}, "rot": rot, "fov": 70})
    time.sleep(2.5)  # let the view stream in
    return screenshot(str(path))


def measure(section):
    """Put the car at a section's start: what's under the wheels, how much room."""
    A.place(section["pos"], section["dir"], lift=1.0)
    s = pose()
    return {"surfaces": wheel_surfaces(), "room": s["room"], "slopeDeg": round(math.degrees(math.acos(min(1, s["upZ"]))), 1)}


def fmt(v):
    return f"{v:g}" if isinstance(v, float) else str(v)


def suitability(c):
    """HTML rows: drills this place fits, ones it nearly fits (and why), what to check by eye."""
    fits, maybe, near = venues.suits(A.drills(), c)
    rows = []
    if fits:
        rows.append(f"<tr><th>fits</th><td class=\"fits\">{html.escape(', '.join(d for d, _ in fits))}</td></tr>")
        eye = sorted({e for _, by_eye in fits for e in by_eye})
        if eye:
            rows.append(f"<tr><th>check by eye</th><td>{html.escape('; '.join(eye[:5]))}</td></tr>")
    if maybe:
        rows.append(f"<tr><th>maybe (by eye)</th><td>{html.escape(', '.join(d for d, _ in maybe))}</td></tr>")
    if near:
        rows.append("<tr><th>nearly</th><td>" + "<br>".join(f"{html.escape(d)}: {html.escape('; '.join(p))}"
                                                        for d, p in near[:4]) + "</td></tr>")
    return rows


def card(c, img):
    facts = {k: v for k, v in c.items() if k not in ("kind", "pos", "dir", "nodes", "id", "level", "note", "measured", "room", "road", "surfaces")}
    m = c.get("measured") or {}
    rows = [f"<tr><th>{html.escape(k)}</th><td>{html.escape(fmt(v))}</td></tr>" for k, v in facts.items()]
    if c.get("road"):
        rows.append(f"<tr><th>road</th><td>{c['road'].get('width')} m wide</td></tr>")
    surf = m.get("surfaces") or sorted(set((c.get("surfaces") or {}).values()))
    if surf:
        rows.append(f"<tr><th>surface</th><td>{html.escape(' / '.join(surf))}</td></tr>")
    room = m.get("room") or c.get("room")
    if room:
        rows.append("<tr><th>room</th><td>" + ", ".join(f"{n} {d} m" for n, d in zip(ROOM_NAMES, room) if n in ("ahead", "left", "right", "behind")) + "</td></tr>")
    rows += suitability(c)
    p, d = c["pos"], c["dir"]
    cmd = f"python tools/ingame/survey.py goto {c['id']}" if "id" in c else \
        f"python tools/ingame/survey.py goto --at={p['x']},{p['y']},{p['z']},{d['x']},{d['y']}"
    title = f"Spot #{c['id']}" + (f" · {html.escape(c['note'])}" if c.get("note") else "") if "id" in c else \
        html.escape(c["kind"].capitalize() + (f" · {c['shape']}" if c.get("shape") else ""))
    # embedded, so the page is one file you can share or open anywhere
    image = (f'<img src="data:image/jpeg;base64,{base64.b64encode(img.read_bytes()).decode()}" alt="aerial view">'
             if img and img.exists() else '<div class="noimg">no view</div>')
    return f"""<article><h3>{title}</h3>{image}<table>{''.join(rows)}</table>
<p class="at">({p['x']:.1f}, {p['y']:.1f}, {p['z']:.1f})</p><code>{html.escape(cmd)}</code></article>"""


PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Venues: {map}</title><style>
:root {{ color-scheme: dark; --bg: #111418; --card: #1b2027; --line: #2c333d; --text: #eef1f4; --muted: #9aa5b1; --accent: #ff7a1a; }}
body {{ margin: 0; padding: 24px; background: var(--bg); color: var(--text); font: 14px/1.45 system-ui, sans-serif; }}
h1 {{ margin: 0 0 4px; }} h2 {{ margin: 28px 0 10px; color: var(--accent); font-size: 16px; text-transform: uppercase; letter-spacing: .04em; }}
.sub {{ color: var(--muted); margin-bottom: 8px; }}
.grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 14px; }}
article {{ background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 12px; }}
article h3 {{ margin: 0 0 8px; font-size: 15px; }} img, .noimg {{ width: 100%; border-radius: 6px; display: block; aspect-ratio: 16/9; object-fit: cover; background: #000; }}
.noimg {{ display: grid; place-items: center; color: var(--muted); }}
table {{ width: 100%; margin-top: 8px; border-collapse: collapse; }} th {{ text-align: left; color: var(--muted); font-weight: 500; padding: 2px 8px 2px 0; width: 38%; }}
td {{ padding: 2px 0; }} td.fits {{ color: var(--accent); font-weight: 600; }} .at {{ color: var(--muted); margin: 6px 0 4px; }}
code {{ display: block; padding: 6px 8px; background: #0b0d10; border-radius: 6px; font-size: 12px; overflow-x: auto; white-space: nowrap; }}
</style></head><body><h1>Venues on {map}</h1>
<div class="sub">Generated {when} by tools/ingame/survey.py report. Surfaces and room are measured with the car at each start; road values come from the map's AI road network.</div>
{sections}</body></html>"""


def report(args):
    lvl = level()
    out = REPORTS / f"{lvl}"
    out.mkdir(parents=True, exist_ok=True)
    started = time.time()
    home = pose()
    nodes, adj = road_network()
    groups = [("Your saved spots", saved_spots())]
    found = [("Straights (braking, speed holds)", roads.dedupe(roads.straights(nodes, adj, min_length=120))[:6]),
             ("Corners", roads.dedupe(roads.corners(nodes, adj, max_radius=60))[:8]),
             ("Hills", roads.dedupe(roads.hills(nodes, adj))[:4]),
             ("Crests", roads.dedupe(roads.crests(nodes, adj))[:4])]
    if args.open:
        found.append(("Open areas (terrain scan)", open_areas()[:6]))
    groups += found
    html_groups = []
    lua("extensions.ui_visibility.setCef(false) return 1")  # no HUD in the aerial views
    try:
        build_cards(groups, out, args, html_groups)
    finally:
        lua("extensions.ui_visibility.setCef(true) return 1")
        call("set_camera", {"name": "orbit"})
        A.place(home["pos"], home["dir"], lift=0.5)
    page = out / "index.html"
    page.write_text(PAGE.format(map=html.escape(str(lvl)), when=datetime.now().strftime("%Y-%m-%d %H:%M"),
                                sections="".join(html_groups) or "<p>Nothing found.</p>"), encoding="utf-8")
    moved = tidy_game_copies(started, out)
    print(f"\nreport: {page}" + (f"  (moved the game's {moved} screenshot copies into {out.name}/game-copies)" if moved else ""))


def build_cards(groups, out, args, html_groups):
    count = 0
    for title, items in groups:
        cards = []
        for c in items:
            count += 1
            print(f"  {count:>2}. {title}: ({c['pos']['x']:.0f}, {c['pos']['y']:.0f})", flush=True)
            if not args.quick and "id" not in c:
                try:
                    c["measured"] = measure(c)
                except Exception as e:  # noqa: BLE001 - a bad spot shouldn't stop the report
                    print(f"      couldn't measure: {e}")
            img = out / f"{count:02d}.jpg"
            try:
                aerial(img, c["pos"], c["dir"])
            except Exception as e:  # noqa: BLE001
                print(f"      no aerial view: {e}")
                img = None
            cards.append(card(c, img))
        if cards:
            html_groups.append(f"<h2>{html.escape(title)} ({len(cards)})</h2><div class=\"grid\">{''.join(cards)}</div>")


def tidy_game_copies(since, out):
    """The game also saves every MCP screenshot under <user folder>/screenshots/mcp; move the
    ones this report made next to it instead of leaving them in the user folder."""
    try:
        import dev
        user = next(c for c in dev.candidate_user_folders() if c.is_dir())
    except (ImportError, StopIteration, SystemExit):
        return 0
    src = user / "screenshots" / "mcp"
    if not src.is_dir():
        return 0
    dest = out / "game-copies"
    moved = 0
    for f in src.iterdir():
        if f.is_file() and f.stat().st_mtime >= since - 1:
            dest.mkdir(exist_ok=True)
            shutil.move(str(f), dest / f.name)
            moved += 1
    return moved


# --------------------------------------------------------------------------- cli

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("here").set_defaults(func=here)
    p = sub.add_parser("surfaces")
    p.add_argument("--along", default="20,60,100")
    p.add_argument("--side", default="-12,-8,-5,0,5,8,12")
    p.set_defaults(func=surfaces)
    p = sub.add_parser("terrain")
    p.add_argument("points", nargs="+", type=float)
    p.set_defaults(func=terrain)
    p = sub.add_parser("configs")
    p.add_argument("model", nargs="?")
    p.set_defaults(func=configs)
    sub.add_parser("levels").set_defaults(func=levels)
    p = sub.add_parser("spots")
    p.add_argument("--all", action="store_true", help="every map")
    p.set_defaults(func=spots)
    p = sub.add_parser("goto")
    p.add_argument("id", nargs="?", type=int)
    p.add_argument("--at", help="X,Y,Z,DX,DY")
    p.set_defaults(func=goto)
    for name in ("straights", "corners", "hills", "crests"):
        p = sub.add_parser(name)
        p.add_argument("--limit", type=int, default=10)
        p.add_argument("--min-length", type=float, default=100.0, help="straights: metres")
        p.add_argument("--max-radius", type=float, default=80.0, help="corners: metres")
        p.set_defaults(func=find)
    p = sub.add_parser("open")
    p.add_argument("--step", type=float, default=16.0)
    p.add_argument("--limit", type=int, default=10)
    p.set_defaults(func=open_cmd)
    p = sub.add_parser("fits")
    p.add_argument("drill")
    p.add_argument("--measure", type=int, default=0, help="place the car on the best N to measure them")
    p.add_argument("--limit", type=int, default=8)
    p.set_defaults(func=fits_cmd)
    p = sub.add_parser("fit")
    p.add_argument("drill")
    p.add_argument("--spot", type=int)
    p.add_argument("--at", help="X,Y,Z,DX,DY")
    p.add_argument("--to", help="road node to drive to (corners, routes; from a finder's `nodes`)")
    p.set_defaults(func=fit_cmd)
    p = sub.add_parser("report")
    p.add_argument("--quick", action="store_true", help="skip placing the car to measure surfaces")
    p.add_argument("--open", action="store_true", help="include the (slow) terrain scan for open areas")
    p.set_defaults(func=report)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
