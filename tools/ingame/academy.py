"""Rally Academy helpers on top of game.py: the HUD panel, drills, scripted runs."""
import json
import math
import time
from pathlib import Path

from game import call, inp, lua, lua_json, safe, state, ui, vlua

ROOT = Path(__file__).resolve().parents[2]
EXERCISES = ROOT / "mod" / "gameplay" / "rallyAcademy" / "exercises.json"
PANEL = ".rally-academy-app"


VENUES = ROOT / "mod" / "gameplay" / "rallyAcademy" / "venues.json"


def drills():
    """The drills with each venue filled in (levelId, mapDisplayName, spawn), as the mod loads them, surface
    variants included (A01-snow, after their base drill)."""
    import variants
    venues = {v["id"]: v for v in json.loads(VENUES.read_text(encoding="utf-8"))["venues"]}
    out = variants.all_drills(json.loads(EXERCISES.read_text(encoding="utf-8"))["exercises"])
    for d in out:
        v = venues.get(d["environment"].get("venue"))
        if v:
            d["environment"].update(levelId=v["levelId"], mapDisplayName=v["name"], spawn=v["spawn"])
    return out


def catalogue():
    """The drills the HUD and the Academy screen list: base drills only (surface variants are picked on them)."""
    return [d for d in drills() if not d.get("variantOf")]


def drill(drill_id):
    return next(e for e in drills() if e["id"] == drill_id)


def wait_for(fn, want, timeout=12):
    """Poll fn() until it returns `want` (the HUD remounts for a moment after UI changes)."""
    t0, got = time.time(), None
    while time.time() - t0 < timeout:
        got = safe(fn)
        if got == want:
            break
        time.sleep(0.5)
    return got


def debug_state():
    return lua_json("return extensions.rallyAcademy.debugState()")


def reload_mod(ui_too=True):
    """Re-read the extension (and its pure modules) and, optionally, the whole UI."""
    lua("extensions.reload('rallyAcademy') return 1")
    if ui_too:
        safe(call, "reload_ui")
        time.sleep(3)
    lua("ui_router.navigate('play') simTimeAuthority.pause(false) return 1")
    wait_panel()


def fresh_sampler():
    """Unload the telemetry sampler from the car so Retry loads the current file."""
    vlua("extensions.unload('rallyAcademy_telemetry') return 1")


def wait_panel(timeout=40):
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(1.5)
        n = safe(ui, f"return document.querySelectorAll('{PANEL} .ra-select').length")
        if isinstance(n, int) and n > 0:
            return True
    return False


def hud():
    return ui(f"var p=document.querySelector('{PANEL}'); if(!p) return 'NO PANEL'; "
              "return Array.from(p.querySelectorAll('.ra-grade div, .ra-reason')).map(function(e){return e.textContent.trim()}).join(' | ')")


def failed_checks():
    """The texts of the last graded run's failed checks, from the run record (the HUD panel leaves the checks to the
    Coach when it's up)."""
    got = lua_json("local r = extensions.rallyAcademy.getLastRun() local out = {} "
                   "for _, c in ipairs(r and r.grade and r.grade.checks or {}) do "
                   "if not c.ok then out[#out + 1] = c.text end end return out")
    return got if isinstance(got, list) else []


def grade_lines():
    return ui(f"return Array.from(document.querySelectorAll('{PANEL} .ra-grade div')).map(function(d){{return d.textContent.trim()}})")


# Every drill's progress as this process first found it: clear_progress puts it back, so a scenario's runs come out
# of the player's progress without taking the player's own attempts and medals with them.
_FOUND = None


def keep_progress():
    global _FOUND
    if _FOUND is None:
        found = lua_json("return extensions.rallyAcademy.devGetProgress()")
        _FOUND = found if isinstance(found, dict) else {}


def choose(drill_id):
    keep_progress()
    lua(f"extensions.rallyAcademy.select({json.dumps(drill_id)}) return 1")
    time.sleep(1.0)


def click(label):
    """Click a HUD panel button whose text contains `label`."""
    pressed = ui(f"var b=Array.from(document.querySelectorAll('{PANEL} button')).filter(function(x){{"
                 f"return x.textContent.indexOf({json.dumps(label)})>=0}})[0]; if(!b) return 'NOT FOUND'; b.click(); return b.textContent.trim()")
    time.sleep(0.6)
    if pressed == "NOT FOUND":
        # The HUD only sends commands; with the panel off screen (a game update can reset the HUD layout),
        # send the same command from Lua so driving checks don't depend on the layout.
        if label in LUA_BUTTONS:
            global _warned_no_panel
            if not _warned_no_panel:
                print("  (no HUD panel on screen: sending panel commands from Lua; switch to the Rally Academy HUD layout "
                      "for the HUD checks)", flush=True)
                _warned_no_panel = True
            lua(f"extensions.rallyAcademy.{LUA_BUTTONS[label]} return 1")
            time.sleep(0.6)
            return label
        raise RuntimeError(f"no panel button {label!r}")
    return pressed


# HUD buttons and the extension commands they send (app.vue), for when the panel isn't on screen.
LUA_BUTTONS = {"Retry": "retry()", "Pass": "recordAttempt(true)", "Miss": "recordAttempt(false)",
               "Move course here": "markStart()", "Use venue start": "useVenueStart()"}
_warned_no_panel = False


def place(pos, direction, ahead=0.0, side=0.0, lift=0.3):
    """Teleport the car to `pos` facing `direction` ({x, y}), optionally offset along/across it."""
    n = (direction["x"] ** 2 + direction["y"] ** 2) ** 0.5
    dx, dy = direction["x"] / n, direction["y"] / n
    q = lua(f"local q = quatFromDir(vec3({dx}, {dy}, 0), vec3(0,0,1)) "
            "return string.format('%.6f,%.6f,%.6f,%.6f', q.x, q.y, q.z, q.w)")
    rot = dict(zip("xyzw", map(float, q.split(","))))
    target = {"x": pos["x"] + dx * ahead + dy * side, "y": pos["y"] + dy * ahead - dx * side, "z": pos["z"] + lift}
    call("set_position", {"pos": target, "rot": rot})
    time.sleep(2.5)


def arcade():
    """Scripts drive with the arcade gearbox; Retry's repair restores the player's own."""
    vlua('controller.mainController.setGearboxMode("arcade") return 1')


def realistic():
    vlua('controller.mainController.setGearboxMode("realistic") return 1')


def eased_brake(kmh):
    """Threshold braking: ease off as speed falls (constant pressure locks late in the stop)."""
    return 0.45 if kmh > 35 else (0.30 if kmh > 15 else 0.18)


# Problems noticed along the way that no scenario asked about (the HUD panel overflowing after a
# graded run); run.py reports them with the scenario that was running.
SIDE_PROBLEMS = []


def hud_overflow():
    """Pixels of HUD panel content below its visible height (0 = it all fits), or None if no panel."""
    dims = safe(ui, f"var p=document.querySelector('{PANEL}'); return p ? [p.scrollHeight, p.clientHeight] : null")
    if not isinstance(dims, list):
        return None
    return max(0, dims[0] - dims[1] - 1)  # a pixel of rounding


def wait_graded(timeout=20):
    """Wait for the run to be graded; also checks the HUD still fits its panel (390 x 340)."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(0.25)
        s = safe(debug_state)
        if isinstance(s, dict) and s.get("phase") in ("scored", "review"):
            break
    time.sleep(0.8)
    s = debug_state()
    over = hud_overflow()
    if over:
        SIDE_PROBLEMS.append(f"HUD panel overflows by {over} px after a {s.get('selected')} run ({s.get('reason')})")
        print(f"  FAIL HUD panel overflows by {over} px after a {s.get('selected')} run", flush=True)
    return s


def braking_run(target_kmh, brake, throttle=1.0, max_s=25, brake_after_m=None):
    """Retry, accelerate to `target_kmh` (and, with `brake_after_m`, hold it until that far from the
    start), then brake with brake(kmh, seconds_since_braking). Below 4 km/h the brake is released for
    the handbrake (arcade reverses on a held brake)."""
    click("Retry")
    time.sleep(1.0)
    arcade()
    inp("parkingbrake", 0)
    inp("brake", 0)
    start = state()[0]
    t0 = time.time()
    while time.time() - t0 < 40:
        pos, spd = state()
        travelled = math.dist(pos[:2], start[:2])
        if spd * 3.6 >= target_kmh and (brake_after_m is None or travelled >= brake_after_m):
            break
        if brake_after_m is not None and spd * 3.6 >= target_kmh - 1:
            inp("throttle", max(0.0, min(1.0, 0.25 + 0.08 * (target_kmh + 1 - spd * 3.6))))
        else:
            inp("throttle", throttle)
        time.sleep(0.05)
    inp("throttle", 0)
    tb = time.time()
    while time.time() - tb < max_s:
        _, spd = state()
        if spd * 3.6 < 4:
            inp("brake", 0)
            inp("parkingbrake", 1)
            break
        inp("brake", brake(spd * 3.6, time.time() - tb))
        time.sleep(0.04)
    return wait_graded()


def course_points(drill_id, local_points):
    """Course-frame points (x right, y ahead of the venue start, metres) -> world (x, y)."""
    sp = drill(drill_id)["environment"]["spawn"]
    n = math.hypot(sp["dir"]["x"], sp["dir"]["y"])
    fx, fy = sp["dir"]["x"] / n, sp["dir"]["y"] / n
    rx, ry = fy, -fx
    return [(sp["pos"]["x"] + rx * x + fx * y, sp["pos"]["y"] + ry * x + fy * y) for x, y in local_points]


def _resample(points, step=0.25):
    out = [points[0]]
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        n = max(1, int(math.dist((ax, ay), (bx, by)) / step))
        out += [(ax + (bx - ax) * k / n, ay + (by - ay) * k / n) for k in range(1, n + 1)]
    return out


# One round trip per tick: apply the driver's inputs in the car, read back its pose.
_DRIVE_TICK = ("local v = be:getPlayerVehicle(0) "
               "v:queueLuaCommand(\"input.event('steering', {s:.3f}, 2) input.event('throttle', {t:.3f}, 2) "
               "input.event('brake', {b:.3f}, 2) input.event('parkingbrake', {p:.0f}, 2)\") "
               "local q, d, w = v:getPosition(), v:getDirectionVector(), v:getVelocity() "
               "return string.format('%.3f,%.3f,%.4f,%.4f,%.3f', q.x, q.y, d.x, d.y, w:length())")


def follow_path(points, kmh=16, decel=2.0, stop_within=0.35, wheelbase=2.45, max_steer=0.55, timeout=40, max_throttle=0.6,
                on_tick=None, pedals=None, steer=None):
    """Drive the player's car along world points (x, y) with pure pursuit and stop with its
    position on the last point: steady `kmh`, then braking at `decel` m/s2 to arrive slowly,
    and the handbrake for the last few centimetres (arcade reverses on a held brake). Use the
    arcade gearbox. `on_tick(kmh, to_go)` may return vehicle Lua to run in the car that tick (e.g. a
    scripted gear change). `pedals(kmh, travelled_m)` may return (throttle, brake[, handbrake]) to override the
    speed control that tick (e.g. trail braking). `steer(kmh, travelled_m)` may return a steering input
    (-1 left .. 1 right) to override the pursuit that tick (e.g. a Scandinavian flick). Returns the distance
    from the last point when the car stopped."""
    path = _resample(points)
    remaining = [0.0] * len(path)
    for i in range(len(path) - 2, -1, -1):
        remaining[i] = remaining[i + 1] + math.dist(path[i], path[i + 1])
    s = t = b = p = 0.0
    idx, t0, stopped_at = 0, time.time(), None
    while time.time() - t0 < timeout:
        x, y, hx, hy, v = (float(f) for f in lua(_DRIVE_TICK.format(s=s, t=t, b=b, p=p)).split(","))
        if on_tick:
            extra = on_tick(v * 3.6, remaining[idx])
            if extra:
                lua(f"be:getPlayerVehicle(0):queueLuaCommand({json.dumps(extra)}) return 1")
        # Closest path point ahead of the last one (never go back along the path).
        best = min(range(idx, min(idx + 80, len(path))), key=lambda i: math.dist((x, y), path[i]))
        idx = best
        to_go = remaining[idx] + 0.0
        if idx == len(path) - 1:
            # Past the end of the path: signed distance along the heading to the last point.
            ex, ey = path[-1]
            to_go = (ex - x) * hx + (ey - y) * hy
        look = max(2.5, 0.9 * v)
        j = idx
        while j < len(path) - 1 and math.dist((x, y), path[j]) < look:
            j += 1
        lx, ly = path[j]
        hn = math.hypot(hx, hy) or 1
        hx, hy = hx / hn, hy / hn
        dx, dy = lx - x, ly - y
        dist = math.hypot(dx, dy) or 1
        sin_a = (hx * dy - hy * dx) / dist  # + when the point is to the left
        steer_angle = math.atan(2 * wheelbase * sin_a / max(dist, 1.0))
        s = max(-1.0, min(1.0, -steer_angle / max_steer)) if to_go > 0.8 else s * 0.5
        want = min(kmh / 3.6, math.sqrt(max(0.0, 2 * decel * max(0.0, to_go - stop_within))) + 0.6)
        if to_go <= stop_within or (to_go < 1.5 and v < 0.3):
            t, b, p = 0.0, 0.0, 1.0
            if v < 0.05:
                stopped_at = to_go
                break
        elif v > want + 0.3:
            t, b, p = 0.0, min(0.6, 0.15 + (v - want) * 0.4), 0.0
            if v < 1.2:  # arcade turns a held brake at low speed into reverse
                b, p = 0.0, 0.0
        else:
            t, b, p = min(max_throttle, max(0.08, (want - v) * 0.5 + 0.12)), 0.0, 0.0
        if pedals and p == 0.0:
            override = pedals(v * 3.6, remaining[0] - remaining[idx])
            if override:
                t, b = override[0], override[1]
                if len(override) > 2:
                    p = override[2]
        if steer:
            forced = steer(v * 3.6, remaining[0] - remaining[idx])
            if forced is not None:
                s = forced
        time.sleep(0.02)
    lua(_DRIVE_TICK.format(s=0, t=0, b=0, p=1))
    return stopped_at


def sequential():
    """Sequential gearbox with an automatic clutch: scripts choose gears with shiftToGearIndex."""
    vlua('controller.mainController.setGearboxMode("sequential") return 1')


def shift_to(gear):
    """Vehicle Lua for an on_tick hook: select a gear (sequential mode)."""
    return f"controller.mainController.shiftToGearIndex({gear})"


def course_run(drill_id, local_points, gearbox="arcade", start=None, **kw):
    """Retry the drill and drive course-frame points (see course_points); returns the graded state.
    gearbox: 'arcade' (shifts itself) or 'sequential' (shift with on_tick returning shift_to(n)).
    start(gearbox) replaces the Retry and sets the gearbox (tape.py: a Retry from stopped physics, for a
    repeatable start)."""
    if start:
        start(gearbox)
    else:
        click("Retry")
        time.sleep(1.0)
        sequential() if gearbox == "sequential" else arcade()
    inp("parkingbrake", 0)
    follow_path(course_points(drill_id, local_points), **kw)
    return wait_graded()


def current_config():
    return lua("local v = be:getPlayerVehicle(0) return tostring(v and v.partConfig)")


def drill_session(drill_id, level=None):
    """The usual start of a drill scenario: reload the mod (and the car's sampler), select the drill
    with its course at the venue start, auto-retry off, and the drill's own car (Go to drill swaps it
    when the car differs). `level` defaults to the drill's venue map; when another map is loaded, Go to
    drill loads it (a few seconds for the proving ground, a minute or more for stock maps). Pair with
    end_session."""
    level = level or drill(drill_id)["environment"]["levelId"]
    reload_mod(ui_too=False)
    fresh_sampler()
    choose(drill_id)
    if debug_state().get("level") != level:
        lua("extensions.rallyAcademy.goToDrill() return 1")
        if not wait_level(level, drill(drill_id)["vehicle"]["configPath"]):
            raise RuntimeError(f"{level} didn't load for {drill_id}")
        reload_mod(ui_too=False)
        fresh_sampler()
        choose(drill_id)
    lua("extensions.rallyAcademy.useVenueStart() extensions.rallyAcademy.setAutoRetry(false) "
        "extensions.rallyAcademy.devKeepRunsPaused(true) return 1")  # scripted runs aren't the player's driving
    want = drill(drill_id)["vehicle"]["configPath"]
    if want not in current_config():
        # The config reads as the new car the moment the swap is asked for; wait until the mod has
        # placed the finished car ("... in the drill car ..."), or a gearbox switch can land on a
        # half-built car (seen: a suite's first launch run stayed in 1st).
        lua("extensions.rallyAcademy.goToDrill() return 1")
        wait_for(lambda: want in current_config() and "in the drill car" in str(debug_state().get("reason")), True,
                 timeout=30)
        time.sleep(1.5)
        lua("extensions.rallyAcademy.useVenueStart() return 1")
    return debug_state()


def end_session(*drill_ids):
    """Undo what a drill scenario changed: auto-retry back on, the realistic gearbox, and the drills' progress
    back as it was before the scenarios ran; the player's runs are kept again."""
    lua("extensions.rallyAcademy.setAutoRetry(true) extensions.rallyAcademy.devKeepRunsPaused(false) return 1")
    realistic()
    clear_progress(*drill_ids)


def save_fixture(name):
    """Save the last run record to <user folder>/settings/rallyAcademy/fixtures/<name>.json."""
    return lua(f"return tostring(extensions.rallyAcademy.saveLastRun('settings/rallyAcademy/fixtures/{name}.json'))")


def lua_value(v):
    """A JSON-like Python value as a Lua expression."""
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, dict):
        return "{" + ", ".join(f"[{json.dumps(str(k))}] = {lua_value(x)}" for k, x in v.items()) + "}"
    return "{" + ", ".join(lua_value(x) for x in v) + "}"


def clear_progress(*drill_ids):
    """Put each drill's progress back as it was before the scenarios ran (keep_progress), dropping their attempts."""
    keep_progress()
    for d in drill_ids:
        lua(f"return tostring(extensions.rallyAcademy.devSetProgress({json.dumps(d)}, {lua_value(_FOUND.get(d))}))")


def rule_check(rule):
    """Evaluate one grading rule (a dict) against the last run record, in the game."""
    return lua_json(
        "local R = require('ge/extensions/rallyAcademy/rules') "
        f"return R.evaluate({{jsonDecode({json.dumps(json.dumps(rule))})}}, extensions.rallyAcademy.getLastRun()).checks[1]")


def wait_level(name, car_config=None, timeout=240):
    """Wait for a map (and optionally a car config) to finish loading; the server drops meanwhile."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(4)
        lvl = safe(lua, "return tostring(getCurrentLevelIdentifier())")
        cfg = safe(lua, "local v = be:getPlayerVehicle(0) return tostring(v and v.partConfig)")
        if str(lvl).lower() == name.lower() and (car_config is None or car_config in str(cfg)):
            time.sleep(6)
            return True
    return False

