"""Does a place suit a drill? Matches a drill's `environment.venueNeeds` against a candidate:
a road section from roads.py (optionally with surfaces measured in-game) or a spot saved
with "Rally Academy: Save spot". Pure Python, unit-tested (tests/python/test_venues.py).

venueNeeds (docs/DRILL_DATA.md): kind (straight | corner | open | hill | crest | route),
lengthM, widthM, areaM, radiusM [min, max], turnDeg, shape, gradePct, maxGradePct,
maxSlopeDeg, surfaces (allowed), features (things to check by eye).
"""

KINDS = ("straight", "corner", "open", "hill", "crest", "route")
# What each finder kind can stand in for. A route is any drivable stretch long enough.
MATCHES = {"straight": {"straight", "route"}, "corner": {"corner", "route"}, "open area": {"open"},
           "uphill": {"hill", "route"}, "downhill": {"hill", "route"}, "crest": {"crest", "route"}}
NUMERIC = ("lengthM", "widthM", "areaM", "turnDeg", "gradePct", "maxGradePct", "maxSlopeDeg")
SHAPES = ("constant", "decreasing", "increasing", "hairpin")


def validate(needs):
    """Problems with a venueNeeds block (shared with tools/dev.py validate)."""
    if not isinstance(needs, dict):
        return ["venueNeeds must be an object"]
    errors = []
    if needs.get("kind") not in KINDS:
        errors.append(f"venueNeeds.kind must be one of {list(KINDS)}")
    for k in NUMERIC:
        if k in needs and not (isinstance(needs[k], (int, float)) and needs[k] >= 0):
            errors.append(f"venueNeeds.{k} must be a number >= 0")
    r = needs.get("radiusM")
    if r is not None and not (isinstance(r, list) and len(r) == 2 and all(isinstance(x, (int, float)) for x in r) and r[0] <= r[1]):
        errors.append("venueNeeds.radiusM must be [min, max]")
    if "shape" in needs and needs["shape"] not in SHAPES:
        errors.append(f"venueNeeds.shape must be one of {list(SHAPES)}")
    for k in ("surfaces", "features"):
        if k in needs and not (isinstance(needs[k], list) and all(isinstance(x, str) for x in needs[k])):
            errors.append(f"venueNeeds.{k} must be a list of strings")
    known = {"kind", "radiusM", "shape", "surfaces", "features"} | set(NUMERIC)
    errors += [f"venueNeeds.{k} is not a known field" for k in needs if k not in known]
    return errors


def _surfaces(c):
    """Surfaces measured at a candidate (finder: measured.surfaces; spot: surfaces by wheel)."""
    m = (c.get("measured") or {}).get("surfaces")
    if m is None and isinstance(c.get("surfaces"), dict):
        m = list(c["surfaces"].values())
    return None if m is None else sorted({s for s in m if s and s != "none"})


def _room(c):
    room = (c.get("measured") or {}).get("room") or c.get("room")
    if not room or len(room) < 8:
        return None
    return {"ahead": room[0], "right": room[2], "behind": room[4], "left": room[6]}


def check(needs, c):
    """-> (problems, by_eye): what this candidate lacks, and what only a person can confirm."""
    problems, by_eye = [], list(needs.get("features") or [])
    kind, is_spot = c.get("kind"), "id" in c and "kind" not in c
    room, width = _room(c), c.get("width")
    if is_spot and c.get("road") and c["road"].get("dist", 99) <= c["road"].get("width", 0):
        width = c["road"].get("width")

    if not is_spot and needs["kind"] not in MATCHES.get(kind, set()):
        problems.append(f"is a {kind}, needs a {needs['kind']}")
    if is_spot and needs["kind"] in ("corner", "hill", "crest"):
        by_eye.insert(0, f"a {needs['kind']} here")

    if "lengthM" in needs:
        have = c.get("length") if not is_spot else None
        if kind == "open area" or (is_spot and needs["kind"] == "open"):
            have = (room["ahead"] + room["behind"]) if room else None
        elif is_spot and room:
            have = room["ahead"]
        if have is None:
            by_eye.append(f"{needs['lengthM']:g} m of usable length")
        elif have < needs["lengthM"]:
            problems.append(f"needs {needs['lengthM']:g} m long, has {have:g} m")
    if "areaM" in needs:
        if kind == "open area":
            span = [float(v) for v in str(c.get("spanM", "0 x 0")).split(" x ")]
            have = min(span)
        else:
            have = min(room["left"] + room["right"], room["ahead"] + room["behind"]) if room else None
        if have is None:
            by_eye.append(f"{needs['areaM']:g} m of open ground")
        elif have < needs["areaM"]:
            problems.append(f"needs {needs['areaM']:g} m of open ground, has {have:g} m")
    if "widthM" in needs and needs["kind"] != "open":
        if width is None:
            by_eye.append(f"road at least {needs['widthM']:g} m wide")
        elif width < needs["widthM"]:
            problems.append(f"needs {needs['widthM']:g} m wide, is {width:g} m")
    if kind == "corner":
        if "radiusM" in needs:
            lo, hi = needs["radiusM"]
            if not lo <= c.get("minRadius", 0) <= hi:
                problems.append(f"needs radius {lo:g}-{hi:g} m, is {c.get('minRadius'):g} m")
        if "turnDeg" in needs and abs(c.get("turnDeg", 0)) < needs["turnDeg"]:
            problems.append(f"needs a {needs['turnDeg']:g}° turn, turns {abs(c.get('turnDeg', 0)):g}°")
        if needs.get("shape") and c.get("shape") != needs["shape"]:
            problems.append(f"needs a {needs['shape']} corner, is {c.get('shape')}")
    if "gradePct" in needs and kind in ("uphill", "downhill") and abs(c.get("gradePct", 0)) < needs["gradePct"]:
        problems.append(f"needs a {needs['gradePct']:g}% grade, is {abs(c.get('gradePct', 0)):g}%")
    if "maxGradePct" in needs and "gradePct" in c and abs(c["gradePct"]) > needs["maxGradePct"]:
        problems.append(f"needs flatter than {needs['maxGradePct']:g}%, is {abs(c['gradePct']):g}%")
    slope = (c.get("measured") or {}).get("slopeDeg", c.get("slopeDeg"))
    if "maxSlopeDeg" in needs and slope is not None and slope > needs["maxSlopeDeg"]:
        problems.append(f"needs flatter than {needs['maxSlopeDeg']:g}°, is {slope:g}°")
    if needs.get("surfaces"):
        have = _surfaces(c)
        if have is None:
            by_eye.append("surface: " + "/".join(needs["surfaces"]))
        else:
            wrong = [s for s in have if s not in needs["surfaces"]]
            if wrong:
                problems.append(f"surface {'/'.join(wrong)} isn't allowed")
    return problems, by_eye


def surface_rank(needs, c):
    """Lower is better: the `surfaces` list is in order of preference (loose first, tarmac
    last), so a place is ranked by its least preferred measured surface. Unknown sorts last."""
    allowed, have = needs.get("surfaces") or [], _surfaces(c)
    if not allowed or not have:
        return len(allowed)
    return max(allowed.index(s) if s in allowed else len(allowed) for s in have)


UNPROVEN = ("a corner here", "a hill here", "a crest here")


def suits(drills, c, close=1):
    """Sort drills into those a candidate fits, those it might fit (a saved spot can't prove
    there's a corner, hill or crest), and those it misses by at most `close` problems.
    -> (fits [(id, by_eye)], maybe [(id, by_eye)], near [(id, problems)]). Drills without
    venueNeeds, and parked drills, are skipped."""
    fits, maybe, near = [], [], []
    for d in drills:
        needs = (d.get("environment") or {}).get("venueNeeds")
        if not needs or d.get("parked"):
            continue
        problems, by_eye = check(needs, c)
        if not problems and any(e in UNPROVEN for e in by_eye):
            maybe.append((d["id"], by_eye))
        elif not problems:
            fits.append((d["id"], by_eye))
        elif len(problems) <= close and not any(p.startswith("is a ") for p in problems):
            near.append((d["id"], problems))
    return fits, maybe, near
