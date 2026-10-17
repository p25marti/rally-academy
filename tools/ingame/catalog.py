"""Venue catalogue: every usable practice spot on a map, by kind and by the surface you'd
actually drive on, kept in the repo so the knowledge outlives a session (docs/VENUES.md).
Built for drills that will let you pick a surface (a handbrake turn on tarmac, dirt or snow).

  python tools/ingame/catalog.py scan [--per-kind 15] [--fits 2] [--no-open] [--community]
      survey the loaded map: road finders + open-ground scan, then place the car at each
      spot to measure the surface under the wheels, room and slope, then fit-test the best
      `--fits` spots of each kind on each surface. Results go to docs/venue-catalog.json
      (this map's entry is replaced) and docs/VENUE_CATALOG.md is regenerated.
  python tools/ingame/catalog.py render
      regenerate docs/VENUE_CATALOG.md from docs/venue-catalog.json (no game needed)

Run with the map loaded and a car in it (the car is put back where it was).
"""
import argparse
import datetime
import json
import math
import os
import sys
import time
from pathlib import Path

import academy as A
import roads
import survey as S
from game import vlua

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "docs" / "venue-catalog.json"
DOC = ROOT / "docs" / "VENUE_CATALOG.md"

KINDS = ["open", "straight", "corner", "hairpin", "hill", "crest"]
KIND_TITLES = {"open": "Open ground", "straight": "Straights", "corner": "Corners", "hairpin": "Hairpins",
               "hill": "Hills", "crest": "Crests"}
# Wheel surfaces (R.SURFACES names) -> the families a player would choose between.
FAMILY = {"ASPHALT": "tarmac", "ASPHALT_WET": "tarmac", "COBBLESTONE": "tarmac", "RUMBLE_STRIP": "tarmac",
          "GRAVEL": "gravel", "DIRT": "dirt", "DIRT_DUSTY": "dirt", "SANDY_ROAD": "dirt", "SAND": "sand",
          "MUD": "mud", "GRASS": "grass", "SNOW": "snow", "ICE": "ice", "ROCK": "rock"}
FAMILIES = ["tarmac", "gravel", "dirt", "sand", "mud", "grass", "snow", "ice", "rock", "mixed", "other"]
# Each family's wheel surfaces, for the fit test's on-surface check.
SURFACES_OF = {}
for _name, _fam in FAMILY.items():
    SURFACES_OF.setdefault(_fam, []).append(_name)
# The drill whose kind of run tests each kind of place (fit.py): a circle, threshold braking,
# the AI through the section.
FIT_DRILL = {"open": "B05", "open_small": "A01", "straight": "B01", "straight_short": "A05",
             "corner": "D05", "hairpin": "C04", "hill": "D06", "crest": "E05"}
PAD_WIDTH = 16  # m: road-network nodes this wide are candidate pads (car parks, paved areas)
CLEAR_M = 40  # m: an open spot is "clear" with this much room along each axis (both ways added up)


def is_clear(room):
    """Room in eight directions (ahead, ahead-right, right, ... ahead-left) -> is there CLEAR_M
    along each axis and diagonal? A car placed near one fence of a 64 m arena reads short on that
    side, so opposite directions are added up."""
    return all(room[i] + room[i + 4] >= CLEAR_M for i in range(4))


def log(msg):
    print(msg, flush=True)


def family(names):
    """Wheel surface names (one per wheel) -> family: the majority, or 'mixed'."""
    counts = {}
    for n in names:
        if n in ("-1", "none", "?"):
            continue  # a wheel in the air
        f = FAMILY.get(n, "other")
        counts[f] = counts.get(f, 0) + 1
    if not counts:
        return "other"
    top = max(counts.values())
    best = [f for f, c in counts.items() if c == top]
    return best[0] if len(best) == 1 else "mixed"


def wheels():
    """Surface under each wheel: ['DIRT_DUSTY', 'DIRT_DUSTY', 'GRASS', 'DIRT_DUSTY']."""
    return [kv.split("=", 1)[1] for kv in str(vlua(S.WHEEL_SURFACES)).split() if "=" in kv]


def measure_at(pos, direction):
    A.place(pos, direction, lift=1.0)
    p = S.pose()
    w = wheels()
    return {"wheels": w, "room": p["room"], "slopeDeg": round(math.degrees(math.acos(min(1, p["upZ"]))), 1)}


def venue_candidates(lvl):
    """The named venues on this map (venues.json), as the kind of place their drills use."""
    out = {}
    drills = A.drills()
    for v in json.loads(A.VENUES.read_text(encoding="utf-8"))["venues"]:
        if str(v["levelId"]).lower() != str(lvl).lower():
            continue
        kinds = [d["environment"]["venueNeeds"]["kind"] for d in drills if d["environment"].get("venue") == v["id"]]
        kind = max(set(kinds), key=kinds.count) if kinds else "open"
        kind = {"route": "corner"}.get(kind, kind)
        out.setdefault(kind, []).append({"kind": kind, "pos": v["spawn"]["pos"],
                                         "dir": {"x": v["spawn"]["dir"]["x"], "y": v["spawn"]["dir"]["y"]},
                                         "spanM": "venue " + v["id"], "venue": v["id"]})
    return out


def candidates(per_kind, with_open, open_step, lvl):
    """Places from the road network, the terrain and our named venues, `per_kind` of each
    kind, best first."""
    nodes, adj = S.road_network()
    out = {}
    corners = roads.dedupe(roads.corners(nodes, adj, max_radius=80.0))
    out["hairpin"] = [c for c in corners if c.get("shape") == "hairpin"][:per_kind]
    out["corner"] = [c for c in corners if c.get("shape") != "hairpin"][:per_kind * 2]
    out["straight"] = sorted(roads.dedupe(roads.straights(nodes, adj, min_length=80.0)), key=lambda s: -s["length"])[:per_kind]
    out["hill"] = roads.dedupe(roads.hills(nodes, adj))[:per_kind]
    out["crest"] = roads.dedupe(roads.crests(nodes, adj))[:per_kind]
    out["open"] = S.open_areas(open_step, surfaces=None)[:per_kind] if with_open else []
    # Car parks and paved pads are meshes the terrain scan can't see; the road network marks
    # them as very wide nodes. The room measurement then weeds out plain wide junctions.
    pads = [{"kind": "pad", "pos": {"x": x, "y": y, "z": z}, "dir": {"x": 0.0, "y": 1.0},
             "spanM": f"road node {2 * r:.0f} m wide", "width": 2 * r} for x, y, z, r in nodes.values() if 2 * r >= PAD_WIDTH]
    pads.sort(key=lambda p: -p["width"])
    out["open"] += roads.dedupe(pads, radius=40.0)[:per_kind]
    for kind, items in venue_candidates(lvl).items():
        out[kind] = items + out.get(kind, [])
    for kind, items in out.items():
        for c in items:
            c["catalogKind"] = kind
    return nodes, out


def mid_pos(nodes, section):
    names = section.get("nodes") or []
    if len(names) < 3:
        return None
    x, y, z, _ = nodes[names[len(names) // 2]]
    return {"x": x, "y": y, "z": z}


def metrics(c):
    keep = ("length", "width", "drivability", "turnDeg", "direction", "minRadius", "entryRadius", "exitRadius",
            "shape", "gradePct", "riseM", "spanM", "areaM2", "terrain")
    return {k: c[k] for k in keep if k in c}


LOCK = ROOT / "venue-reports" / ".catalog-scan.lock"  # one scan at a time: two would fight over the car


def _running(pid):
    """Is process `pid` alive? (On Windows, os.kill(pid, 0) would terminate it, so ask the OS.)"""
    if os.name == "nt":
        import ctypes
        k = ctypes.windll.kernel32
        h = k.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not h:
            return False
        code = ctypes.c_ulong()
        ok = k.GetExitCodeProcess(h, ctypes.byref(code))
        k.CloseHandle(h)
        return bool(ok) and code.value == 259  # STILL_ACTIVE
    try:
        os.kill(pid, 0)  # POSIX: signal 0 only checks
        return True
    except OSError:
        return False


def scan(args):
    LOCK.parent.mkdir(exist_ok=True)
    if LOCK.exists():
        try:
            pid = int(LOCK.read_text())
        except ValueError:
            pid = 0
        if pid and _running(pid):
            sys.exit(f"another catalogue scan is running (pid {pid}); two would move the same car")
    LOCK.write_text(str(os.getpid()))
    try:
        _scan(args)
    finally:
        LOCK.unlink(missing_ok=True)


def _scan(args):
    lvl = S.level()
    if not lvl or lvl == "unknown":
        sys.exit("load a map with a car first")
    home = S.pose()
    log(f"cataloguing {lvl}: finding candidates...")
    nodes, cands = candidates(args.per_kind, not args.no_open, args.open_step, lvl)
    if args.kinds:
        cands = {k: v for k, v in cands.items() if k in args.kinds}
    total = sum(len(v) for v in cands.values())
    log("  " + ", ".join(f"{len(v)} {k}" for k, v in cands.items()) + f" ({total} places to measure)")
    spots, n = [], 0
    try:
        for kind in KINDS:
            for c in roads.dedupe(cands.get(kind, [])):
                n += 1
                m = measure_at(c["pos"], c["dir"])
                samples = list(m["wheels"])
                mid = mid_pos(nodes, c) if kind != "open" else None
                if mid:
                    samples += measure_at(mid, c["dir"])["wheels"]
                fam = family(samples)
                spot = {"kind": kind, "pos": {k: round(c["pos"][k], 2) for k in "xyz"},
                        "dir": {k: round(c["dir"][k], 4) for k in "xy"}, "to": (c.get("nodes") or [None])[-1],
                        "metrics": metrics(c), "family": fam, "surfaces": sorted(set(samples)),
                        "room": m["room"], "slopeDeg": m["slopeDeg"]}
                if c.get("venue"):
                    spot["venue"] = c["venue"]
                if kind == "open":
                    spot["clear"] = is_clear(m["room"])
                spots.append(spot)
                log(f"  [{n}/{total}] {kind:<8} ({c['pos']['x']:.0f}, {c['pos']['y']:.0f})  {fam:<7} "
                    f"{'/'.join(spot['surfaces'])}" + ("" if kind != "open" else ("  clear" if spot["clear"] else "  cluttered")))
        if args.fits:
            run_fits(spots, args.fits)
    finally:
        A.place(home["pos"], home["dir"], lift=0.5)
    save(lvl, spots, args)


def run_fits(spots, per_group):
    """Fit-test the best `per_group` of each (kind, family), on the place's own surface."""
    import fit as F
    groups = {}
    for s in spots:
        if s["family"] in ("other", "mixed") or (s["kind"] == "open" and not s.get("clear")):
            continue
        groups.setdefault((s["kind"], s["family"]), []).append(s)
    todo = [s for g in groups.values() for s in g[:per_group]]
    log(f"fit tests: {len(todo)} places")
    for i, s in enumerate(todo, 1):
        kind = s["kind"]
        drill = FIT_DRILL[kind]
        if kind == "straight" and s["metrics"].get("length", 0) < 150:
            drill = FIT_DRILL["straight_short"]
        surfaces = SURFACES_OF.get(s["family"])
        r = F.fit(drill, s["pos"], s["dir"], to_node=s.get("to") if kind != "straight" else None, surfaces=surfaces)
        if kind == "open" and not r["fits"]:
            small = F.fit(FIT_DRILL["open_small"], s["pos"], s["dir"], surfaces=surfaces)
            if small["fits"]:
                r = dict(small, notes=small["notes"] + ["too small for B05's 50 m circle"])
        s["fit"] = {"drill": r["drill"], "fits": r["fits"], "problems": r["problems"],
                    "notes": [x for x in r["notes"] if not x.startswith("check by eye")]}
        log(f"  [{i}/{len(todo)}] {kind:<8} {s['family']:<7} ({s['pos']['x']:.0f}, {s['pos']['y']:.0f})  "
            f"{r['drill']}: {'FITS' if r['fits'] else 'does not fit: ' + '; '.join(r['problems'])}")


def load():
    if CATALOG.exists():
        return json.loads(CATALOG.read_text(encoding="utf-8"))
    return {"schemaVersion": 1, "maps": {}}


def save(lvl, spots, args):
    data = load()
    name = str(lvl)
    if args.kinds and name in data["maps"]:
        # A partial re-scan replaces only the kinds it covered.
        spots = [s for s in data["maps"][name]["spots"] if s["kind"] not in args.kinds] + spots
    data["maps"][name] = {"level": name, "community": bool(args.community), "surveyed": datetime.date.today().isoformat(),
                          "game": args.game, "spots": spots}
    CATALOG.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    log(f"saved {len(spots)} spots for {name} to docs/{CATALOG.name}")
    render()


def where(s):
    p, d = s["pos"], s["dir"]
    return f"({p['x']:.0f}, {p['y']:.0f})", f"--at={p['x']},{p['y']},{p['z']},{d['x']},{d['y']}"


def describe(s):
    m = s["metrics"]
    if s.get("venue"):
        return f"our venue `{s['venue']}`"
    if s["kind"] == "open":
        return f"{m.get('spanM', '?')} m"
    if s["kind"] == "straight":
        return f"{m.get('length', 0):.0f} m long, {m.get('width', 0):g} m wide, {m.get('gradePct', 0):+.1f}%"
    if s["kind"] in ("corner", "hairpin"):
        return (f"{abs(m.get('turnDeg', 0)):.0f}° {m.get('direction', '')}, r {m.get('minRadius', 0):g} m, "
                f"{m.get('shape', '')}, {m.get('width', 0):g} m wide")
    if s["kind"] == "hill":
        return f"{m.get('gradePct', 0):+.1f}% over {m.get('length', 0):.0f} m, {m.get('width', 0):g} m wide"
    return f"{m.get('spanM', m.get('length', 0)):.0f} m over the top, {m.get('width', 0):g} m wide"


def verdict(s):
    f = s.get("fit")
    if not f:
        return ""
    return f"**{f['drill']} fits**" if f["fits"] else f"{f['drill']}: no ({'; '.join(f['problems'])[:80]})"


def usable(s):
    return s["family"] not in ("other",) and (s["kind"] != "open" or s.get("clear"))


def render():
    data = load()
    maps = data["maps"]
    lines = ["# Venue catalogue", "",
             "Practice spots on the surveyed maps, by **surface you drive on** and kind of place, measured",
             "in-game by `tools/ingame/catalog.py` (data: [venue-catalog.json](venue-catalog.json); this page",
             "is generated, don't edit it). For drills that let you pick a surface, and for finding venues",
             "([VENUES](VENUES.md)). The surface family is what the car's wheels reported at the spot",
             "(start and middle of a road section); \"fits\" is a venue fit test on that surface",
             "(open: B05's 50 m circle or A01's 30 m; straights: B01/A05 braking; corners and hills: the",
             "game's AI at 35–45 km/h). Open ground is listed only when clear in at least six of eight",
             "directions (trees and walls further than 20 m).", ""]
    lines += ["| Map | Surveyed | Spots | Notes |", "| --- | --- | --- | --- |"]
    for name, mp in sorted(maps.items()):
        note = "community map: needs installing" if mp.get("community") else "stock"
        lines.append(f"| `{name}` | {mp['surveyed']} ({mp.get('game', '?')}) | {len(mp['spots'])} | {note} |")
    lines.append("")
    # Coverage matrix: usable spots per family x kind.
    cover = {}
    for name, mp in maps.items():
        for s in mp["spots"]:
            if usable(s):
                cover.setdefault(s["family"], {}).setdefault(s["kind"], set()).add(name)
    lines += ["## What's available", "", "Maps with at least one usable spot, per surface and kind:", "",
              "| Surface | " + " | ".join(KIND_TITLES[k] for k in KINDS) + " |",
              "| --- |" + " --- |" * len(KINDS)]
    for fam in FAMILIES:
        if fam not in cover:
            continue
        lines.append(f"| {fam} | " + " | ".join(", ".join(f"`{m}`" for m in sorted(cover[fam].get(k, []))) or "–"
                                               for k in KINDS) + " |")
    lines.append("")
    for fam in FAMILIES:
        rows = [(name, s) for name, mp in maps.items() for s in mp["spots"] if s["family"] == fam and usable(s)]
        if not rows:
            continue
        lines += [f"## {fam.capitalize()}", ""]
        for kind in KINDS:
            krows = [(n, s) for n, s in rows if s["kind"] == kind]
            if not krows:
                continue
            krows.sort(key=lambda r: (not (r[1].get("fit") or {}).get("fits"), r[0]))
            lines += [f"### {KIND_TITLES[kind]}", "", "| Map | Where | What | Fit test | Go there |", "| --- | --- | --- | --- | --- |"]
            for n, s in krows:
                pos, at = where(s)
                lines.append(f"| `{n}` | {pos} | {describe(s)} | {verdict(s)} | `{at}` |")
            lines.append("")
    DOC.write_text("\n".join(lines), encoding="utf-8")
    log(f"wrote docs/{DOC.name}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("scan")
    p.add_argument("--per-kind", type=int, default=15, help="places of each kind to measure (corners: twice this)")
    p.add_argument("--fits", type=int, default=2, help="fit-test the best N of each kind on each surface (0 = none)")
    p.add_argument("--no-open", action="store_true", help="skip the (slow) terrain scan for open ground")
    p.add_argument("--open-step", type=float, default=16.0)
    p.add_argument("--community", action="store_true", help="the map isn't stock (players must install it)")
    p.add_argument("--kinds", nargs="+", choices=KINDS, help="only these kinds (replaces just those in the data)")
    p.add_argument("--game", default="0.39.4", help="game version, recorded with the results")
    p.set_defaults(func=scan)
    sub.add_parser("render").set_defaults(func=lambda _a: render())
    args = ap.parse_args()
    t0 = time.time()
    args.func(args)
    if args.cmd == "scan":
        log(f"done in {(time.time() - t0) / 60:.0f} min")


if __name__ == "__main__":
    main()
