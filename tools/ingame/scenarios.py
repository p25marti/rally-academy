"""In-game scenarios: `python tools/dev.py ingame <name>` with BeamNG running and the mod
linked (dev.py link). Each scenario drives the real game through its MCP server, prints
what happened and returns the problems it found (empty = all as expected).

Most drill scenarios run on our own map, the proving ground (ADR 0008), which loads in seconds; road-feature
drills stay on West Coast USA. drill_session loads the drill's map. They record attempts, then remove them from
your progress.
"""
import json
import math
import time

import academy as A
from game import call, inp, lua, state, ui

SCENARIOS = {}


def scenario(fn):
    SCENARIOS[fn.__name__] = fn
    return fn


def expect(problems, label, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'} {label}{(': ' + str(detail)) if detail else ''}", flush=True)
    if not ok:
        problems.append(f"{label}: {detail}")


def _in_gear(gear):
    """An `on_tick` for academy.course_run that shifts the sequential box into `gear` once, on the first tick."""
    done = []

    def on_tick(_kmh, _to_go):
        if not done:
            done.append(1)
            return A.shift_to(gear)
    return on_tick


def _hold(v, target, gain=0.1, floor=0.05, ceiling=1.0):
    """Pedals (throttle, brake) that hold `target` km/h at speed `v`: throttle only, from `floor` to `ceiling`."""
    return (max(floor, min(ceiling, 0.3 + (target - v) * gain)), 0.0)


def precise(run, tries=2):
    """A precision stop (stop zone, stop line) gets a second try: the script's control loop
    round-trips through the MCP server (~50 ms, ~0.7 m at 45 km/h), so where braking starts
    jitters by about a metre. Returns the first passing state, or the last one."""
    for _ in range(tries):
        s = run()
        if s.get("passed") is True:
            return s
    return s


def on_straight():
    """Mark the start at B01's spawn (the proving ground's dirt strip); needs B01's map loaded."""
    sp = A.drill("B01")["environment"]["spawn"]
    level = A.drill("B01")["environment"]["levelId"]
    if A.debug_state().get("level") != level:
        raise RuntimeError(f"load {level} first (e.g. Go to drill on B01)")
    A.place(sp["pos"], sp["dir"])
    lua("extensions.rallyAcademy.markStart() return 1")  # the button reads "Move course here" on course drills
    return sp


@scenario
def smoke():
    """Reload the mod and UI; panel, drill switching, menu open/close and pause handling."""
    p = []
    A.reload_mod()
    n = A.wait_for(lambda: ui(f"return document.querySelectorAll('{A.PANEL}').length"), 1)
    expect(p, "one HUD panel after a UI reload", n == 1, n)
    # The drill drop-down must open on a real click (a native <select> never did) and pick.
    call("ui_click", {"selector": f"{A.PANEL} .ra-select"})
    opts = A.wait_for(lambda: ui("return document.querySelectorAll('.dropdown-option-label').length"), len(A.catalogue()))
    expect(p, "drop-down opens on a click and lists every drill", opts == len(A.catalogue()), opts)
    ui("var o=Array.from(document.querySelectorAll('.dropdown-option-label')).find(function(e){return e.textContent.indexOf('B01 ')===0});"
       "if(o) (o.closest('[bng-nav-item]')||o.parentElement).setAttribute('data-ra-pick','1'); return 1")
    call("ui_click", {"selector": "[data-ra-pick]"})
    picked = A.wait_for(lambda: A.debug_state().get("selected"), "B01")
    expect(p, "picking B01 in the drop-down selects it", picked == "B01", picked)
    # Found by the demo run: a drill with no rules ({} from Lua, not []) crashed the Vue panel.
    A.choose("A06")
    title = A.wait_for(lambda: ui(f"var p=document.querySelector('{A.PANEL} .ra-instructions'); return p ? 'shown' : 'missing'"), "shown")
    expect(p, "panel renders a drill without grading rules (A06)", title == "shown", title)
    # a course drill with gates on the loaded map (off its map the panel offers Go to drill instead)
    level = A.debug_state().get("level")
    gated = next((d["id"] for d in A.drills() if d["environment"].get("levelId") == level
                  and (d["assessment"].get("course") or {}).get("gates")), None)
    if gated:
        A.choose(gated)
        text = A.wait_for(lambda: "Gate" in str(ui(f"return document.querySelector('{A.PANEL}').innerText")), True)
        expect(p, f"selecting {gated} shows its gates", text is True)
    if A.debug_state().get("level") != "unknown":
        lua("extensions.rallyAcademy.toggleMenu() return 1")
        time.sleep(4)
        expect(p, "menu opens with physics paused", lua("return tostring(simTimeAuthority.getPause())") == "true")
        expect(p, "Academy screen shows drill cards", (ui("return document.querySelectorAll('.ra-card').length") or 0) > 30)
        lua("extensions.rallyAcademy.toggleMenu() return 1")
        time.sleep(3)
        expect(p, "menu closes and physics resume", lua("return tostring(simTimeAuthority.getPause())") == "false")
    return p


# A01 lines in course coordinates (x right, y ahead of the venue start; car position, which
# sits 0.11 m ahead and 0.325 m right of the Covet's body centre, so -1.175 centres it in the box).
A01_GOLD = [(0, 0), (0, 10), (1.8, 16), (1.8, 21), (-1.175, 27.5), (-1.175, 33.11)]
A01_WRONG_SIDE = [(0, 0), (0, 10), (-1.8, 16), (-1.8, 21), (-1.175, 27.5), (-1.175, 33.11)]
A01_POST = [(0, 0), (0.95, 4), (0.95, 11), (1.8, 16), (1.8, 21), (-1.175, 27.5), (-1.175, 33.11)]


@scenario
def a01():
    """Authored course on the proving ground's dirt strip: laid out with no marking; a medal run, the wrong
    side of the cone, a clipped gate post; auto-retry."""
    p = []
    A.drill_session("A01")
    s = A.debug_state()
    expect(p, "the course is laid out at the venue with no marking", s.get("hasCourse") and s.get("usingVenueStart"), s.get("reason"))
    steps = A.wait_for(lambda: ui(f"var c=document.querySelector('{A.PANEL} .ra-course'); return c ? c.innerText.indexOf('Box') >= 0 : false"), True)
    expect(p, "the HUD shows the gate / cone / box checklist", steps is True, steps)
    best = None
    for _ in range(3):  # the script's line jitters by ~0.1 m; gold needs ~0.2 m to spare
        s = A.course_run("A01", A01_GOLD, kmh=14)
        if s.get("passed") and (best is None or s.get("tier") == "gold"):
            best = s
        if s.get("tier") == "gold":
            break
    best = best or s
    expect(p, "a clean centred run passes with a medal", best.get("passed") is True and best.get("tier") in ("gold", "silver"),
           f"{best.get('tier')}: {best.get('reason')} {best.get('nextTier') or ''}")
    s = A.course_run("A01", A01_WRONG_SIDE, kmh=14)
    expect(p, "the wrong side of the cone misses", s.get("passed") is False and "wrong side of the cone" in str(s.get("reason")),
           s.get("reason"))
    s = A.course_run("A01", A01_POST, kmh=14)
    expect(p, "clipping a gate post misses", s.get("passed") is False and "Clipped the right post" in str(s.get("reason")),
           s.get("reason"))
    lua("extensions.rallyAcademy.setAutoRetry(true) return 1")
    s = A.course_run("A01", A01_GOLD, kmh=14)
    expect(p, "after a graded run the next attempt counts down", bool(s.get("autoRetryIn")), s.get("reason"))
    ready = A.wait_for(lambda: A.debug_state().get("phase"), "ready", timeout=8)
    expect(p, "auto-retry resets the car for the next attempt", ready == "ready", ready)
    A.realistic()
    A.clear_progress("A01")
    return p


@scenario
def b01():
    """B01 on its course (the proving ground's dirt strip, stop zone 150 m ahead): threshold braking
    from 72 km/h into the zone earns a medal; braking too hard overshoots and misses; full brake locks and misses."""
    p = []
    A.drill_session("B01")
    line = [(0, 0), (0, 150)]
    s = precise(lambda: A.course_run("B01", line, kmh=72, decel=5.0, max_throttle=1.0, stop_within=0.4))
    expect(p, "threshold stop in the zone earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {A.grade_lines()}")
    s = A.course_run("B01", line, kmh=72, decel=7.5, max_throttle=1.0, stop_within=0.4)
    expect(p, "braking too hard overshoots and misses", s.get("passed") is False, A.grade_lines())
    s = A.braking_run(70, lambda k, t: 1.0, brake_after_m=110)
    expect(p, "full brake misses (lockup)", s.get("passed") is False, A.grade_lines())
    A.end_session("B01")
    return p


@scenario
def a04():
    """A04 on its course (the proving ground's dirt strip, three gates 25 m apart): a steady 30 km/h earns a
    medal; 40 km/h at gate 3 misses."""
    p = []
    A.drill_session("A04")
    expect(p, "three gates laid out at the venue", A.debug_state().get("gateCount") == 3, A.debug_state().get("reason"))
    s = _hold_run(lambda d: 30)
    expect(p, "steady 30 km/h passes with a medal", s.get("passed") is True and s.get("tier") in ("gold", "silver", "bronze"),
           f"{s.get('tier')}: {A.grade_lines()}")
    s = _hold_run(lambda d: 30 if d < 60 else 40)
    expect(p, "too fast at gate 3 misses", s.get("passed") is False, A.grade_lines())
    A.end_session("A04")
    return p


def _hold_run(target_of_d):
    """A04-style run of the selected drill: Retry, then hold target_of_d(metres from the start) km/h on the
    throttle alone (arcade gearbox), then stop."""
    A.click("Retry")
    time.sleep(1.0)
    A.arcade()
    inp("parkingbrake", 0)
    start, t0 = state()[0], time.time()
    while time.time() - t0 < 40 and A.debug_state().get("phase") not in ("scored", "review"):
        pos, spd = state()
        d = ((pos[0] - start[0]) ** 2 + (pos[1] - start[1]) ** 2) ** 0.5
        inp("throttle", max(0.0, min(1.0, 0.12 + 0.06 * (target_of_d(d) - spd * 3.6))))
        time.sleep(0.05)
    inp("throttle", 0)
    s = A.wait_graded()
    t0 = time.time()
    while state()[1] > 1 and time.time() - t0 < 15:
        inp("brake", 0.5)
        time.sleep(0.2)
    inp("brake", 0)
    inp("parkingbrake", 1)
    return s


@scenario
def stops():
    """A05 on its course (stop line 60 m ahead) and B02 on its course (a 40 m stop area), both on the proving
    ground's dirt strip: one PASS and one MISS each."""
    p = []
    A.drill_session("A05")
    front = 1.81  # Covet: front bumper ahead of the car's position (catalogued footprint)

    def line_run(before_m):
        return A.course_run("A05", [(0, 0), (0, 60 - front - before_m)], kmh=44, decel=3.5, max_throttle=0.7)
    s = precise(lambda: line_run(1.0))
    expect(p, "A05 stop just before the line passes", s.get("passed") is True, A.grade_lines())
    expect(p, "A05 stop past the line misses", line_run(-1.0).get("passed") is False, A.grade_lines())
    lua("extensions.rallyAcademy.setAutoRetry(true) return 1")
    A.choose("B02")
    lua("extensions.rallyAcademy.useVenueStart() extensions.rallyAcademy.setAutoRetry(false) return 1")
    s = A.braking_run(62, lambda k, t: 1.0 if t < 0.6 else A.eased_brake(k), brake_after_m=115)
    expect(p, "B02 lock then release passes", s.get("passed") is True, A.grade_lines())
    s = A.braking_run(62, lambda k, t: 1.0, brake_after_m=115)
    expect(p, "B02 held lock misses", s.get("passed") is False, A.grade_lines())
    A.realistic()
    A.clear_progress("A05", "B02")
    return p


@scenario
def launch():
    """A02 on its course (the proving ground's dirt strip, from the venue start): a flat-out launch through the
    40 km/h gate earns a medal (the run ends at the gate); 34 km/h at the gate misses."""
    p = []
    A.drill_session("A02")
    s = A.debug_state()
    expect(p, "the course is laid out at the venue", s.get("hasCourse") and s.get("usingVenueStart"), s.get("reason"))
    line = [(0, 0), (0, 80)]  # down the strip; the run ends at the gate (60 m)
    s = _launch_run("A02")
    expect(p, "a launch that feeds the throttle in passes with a medal", s.get("passed") is True and s.get("tier") in ("gold", "silver"),
           f"{s.get('tier')}: {s.get('reason')} {s.get('nextTier') or ''}")
    s = A.course_run("A02", line, kmh=34, decel=3.0, max_throttle=0.6)
    expect(p, "34 km/h at the 40 km/h gate misses", s.get("passed") is False and "too slow" in str(s.get("reason")),
           s.get("reason"))
    A.end_session("A02")
    return p


def _gear_plan(down_to):
    """on_tick hook for A03: 1st, 2nd at 25 km/h, 3rd at 45; after 58 km/h, `down_to` below 40 km/h."""
    st = {"g": 0, "peak": 0}

    def plan(kmh, _to_go):
        st["peak"] = max(st["peak"], kmh)
        if st["peak"] < 58:
            want = 1 if kmh < 25 else (2 if kmh < 45 else 3)
        else:
            want = 3 if kmh >= 40 else down_to
        if want != st["g"]:
            st["g"] = want
            return A.shift_to(want)
    return plan


@scenario
def gears():
    """A03 on its course (the proving ground's dirt strip): up to 3rd and 60 km/h, then down to 2nd one gear at a time into
    the stop box passes with a medal; 3rd straight to 1st misses. Sequential gearbox, scripted gears."""
    p = []
    A.drill_session("A03")
    line = [(0, 0), (0, 155)]
    kw = dict(gearbox="sequential", kmh=62, decel=2.2, max_throttle=0.9)
    s = A.course_run("A03", line, on_tick=_gear_plan(2), **kw)
    expect(p, "3rd to 2nd into the box passes with a medal", s.get("passed") is True and s.get("tier") in ("gold", "silver"),
           f"{s.get('tier')}: {s.get('reason')} {s.get('nextTier') or ''}")
    s = A.course_run("A03", line, on_tick=_gear_plan(1), **kw)
    expect(p, "3rd straight to 1st misses", s.get("passed") is False and "Skipped from 3rd to 1st" in str(s.get("reason")),
           s.get("reason"))
    A.end_session("A03")
    return p


A08_LATE = {"DR1181_9": 2.2, "DR1181_10": 1.5, "DR1181_13": -3.0, "DR1181_14": -2.0, "DR1181_15": -1.5}
CORNER_KW = dict(decel=2.5, max_throttle=0.9, stop_within=0.5)


@scenario
def corners():
    """A07 and A08 on the proving ground's flat copy of the BMP left (Covet Gravel Rally, scripted racing
    lines from lines.py): a clean line earns a medal on each; A07 clipping the exit post and A08 weaving
    after the exit miss."""
    import lines as L
    p = []
    A.drill_session("A07")
    kw = dict(decel=2.5, max_throttle=0.9, stop_within=0.5)
    s = A.course_run("A07", L.bmp_left(), kmh=55, **kw)
    expect(p, "A07 racing line earns a medal", s.get("passed") is True and s.get("tier") in ("gold", "silver"),
           f"{s.get('tier')}: {s.get('reason')}")
    s = A.course_run("A07", L.bmp_left({"DR1181_12": -2.5, "DR1181_13": -2.5}), kmh=48, **kw)
    expect(p, "A07 clipping the exit post misses", s.get("passed") is False and "Clipped" in str(s.get("reason")), s.get("reason"))
    lua("extensions.rallyAcademy.select('A08') extensions.rallyAcademy.useVenueStart() return 1")
    # a later apex than A07's, unwinding from the exit gate to the finish (the road keeps turning past it)
    late = A08_LATE
    for _ in range(3):  # the line passes ~0.1 m from the exit post and one correction comes and goes: silver or bronze
        s = A.course_run("A08", L.bmp_left(late, tail=60), kmh=41, **kw)
        if s.get("tier") in ("gold", "silver"):
            break
    expect(p, "A08 late apex and steady exit earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    for _ in range(3):  # sometimes the weave clips the exit post first
        s = A.course_run("A08", L.bmp_left(dict(late, DR1181_13=-1.5, DR1181_14=-4.2, DR1181_15=-0.5), tail=60), kmh=41, **kw)
        if "steering correction" in str(s.get("reason")):
            break
    expect(p, "A08 weaving after the exit misses", s.get("passed") is False and "steering correction" in str(s.get("reason")),
           s.get("reason"))
    A.end_session("A07", "A08")
    return p


def _trail_run(drill, kmh=65, brake=0.2, throttle=0.0, exit_throttle=0.6):
    """B04: `kmh`, then braking lightly from the marker (`brake`, eased off towards the apex, with `throttle` held
    under it so the arcade box doesn't drop to 1st and stall the car) and back on the throttle at the apex, through
    the middle of the exit gate (`exit_throttle` from the apex)."""
    import lines as L
    apex = 118.7  # metres along lines.bmp_left() to the apex gate

    def trail_pedals(_kmh, trav):
        if trav < 50:
            return None
        if trav < apex - 3:
            return (throttle, max(0.0, brake * (1 - (trav - 50) / (apex - 53))))
        return (exit_throttle, 0.0)
    return A.course_run(drill, L.bmp_left({"DR1181_12": -1.5, "DR1181_13": -1.5}), pedals=trail_pedals, kmh=kmh,
                        decel=2.5, max_throttle=1.0, stop_within=0.5)


@scenario
def trail():
    """B04 on the proving ground's flat copy of the BMP left (Covet Gravel Rally): braking lightly from the
    marker and easing off into the turn earns a medal; braking only in a straight line before turning in
    misses. On the flat, light braking with the throttle closed stops the car quickly (engine braking in a
    low gear), so the trail brake is gentle and the entry faster than on the stock downhill."""
    import lines as L
    p = []
    A.drill_session("B04")

    def straight_pedals(_kmh, trav):
        if trav < 45:
            return None
        return (0.0, 0.7) if trav < 58 else (0.1, 0.0)
    kw = dict(kmh=65, decel=2.5, max_throttle=1.0, stop_within=0.5)
    line = L.bmp_left({"DR1181_12": -1.5, "DR1181_13": -1.5})  # through the middle of the 8 m exit gate
    s = _trail_run("B04")
    expect(p, "trail braking into the corner earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = A.course_run("B04", line, pedals=straight_pedals, **kw)
    expect(p, "braking only before turn-in misses", s.get("passed") is False and "into the corner" in str(s.get("reason")),
           s.get("reason"))
    A.end_session("B04")
    return p


def _ring_run(kmh, dab_every=25.0, brake=0.25, dab_m=3.0, lift=False):
    """Two-plus laps of the B05 ring in 2nd (sequential), throttle held, brake dabs every `dab_every` m."""
    ring = [(-15 + 15 * math.cos(a), 15 * math.sin(a)) for a in (i * 0.02 for i in range(int(2.3 * 2 * math.pi / 0.02)))]
    on_tick = _in_gear(2)

    def pedals(v, trav):
        thr = max(0.15, min(0.6, 0.25 + (min(kmh, 12 + trav * 0.8) - v) * 0.05))
        if trav > 20 and trav % dab_every < dab_m:
            return (0.0 if lift else thr, brake)
        return (thr, 0.0)
    return A.course_run("B05", ring, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=kmh + 10,
                        max_throttle=1.0, timeout=60, stop_within=0.5)


@scenario
def circle():
    """B05 on the proving ground's dirt ring (Covet Gravel Rally): two laps of the 15 m ring on steady throttle with
    left-foot brake dabs earn gold; no dabs, or lifting off to brake, miss."""
    p = []
    A.drill_session("B05")
    s = _ring_run(32)
    expect(p, "laps on the throttle with brake dabs earn gold", s.get("passed") is True and s.get("tier") == "gold",
           f"{s.get('tier')}: {s.get('reason')}")
    s = _ring_run(34, dab_every=1e9)
    expect(p, "no brake dabs misses", s.get("passed") is False and "brake dabs" in str(s.get("reason")), s.get("reason"))
    s = _ring_run(34, brake=0.3, dab_m=4, lift=True)
    expect(p, "lifting off to brake misses", s.get("passed") is False, s.get("reason"))
    A.end_session("B05")
    return p


def _arc_run(kmh, brake_m, brake=1.0, max_steer=0.25):
    """B07: approach at `kmh` in 2nd (sequential), full brake for `brake_m` metres at the turn-in gate,
    then 0.3 throttle round a left quarter of the 15 m ring and down the exit lane. The pure pursuit
    countersteers by itself when the rear steps out."""
    path = ([(0, y) for y in range(0, 25)]
            + [(-15 + 15 * math.cos(a), 25 + 15 * math.sin(a)) for a in (i * math.pi / 80 for i in range(41))]
            + [(-15 - x, 40) for x in range(1, 30)])
    on_tick = _in_gear(2)

    def pedals(v, trav):
        if trav < 24:
            return _hold(v, kmh, gain=0.08, floor=0.0, ceiling=0.8)
        return (0.0, brake) if trav < 24 + brake_m else (0.3, 0.0)
    return A.course_run("B07", path, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=kmh + 15,
                        max_throttle=1.0, timeout=40, stop_within=0.5, max_steer=max_steer)


@scenario
def oversteer():
    """B07 on the proving ground's dirt arc (Covet Gravel Rally): a hard brake at turn-in steps the rear out, the
    slide is caught and settled down the exit lane for a medal; a gentle turn-in with no slide misses."""
    p = []
    A.drill_session("B07")
    for _ in range(3):  # scripted slides vary: bronze to silver on the proving ground's dirt
        s = _arc_run(60, 6)
        if s.get("passed"):
            break
    expect(p, "a caught slide earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _arc_run(35, 6, brake=0.5, max_steer=0.55)
    expect(p, "no slide misses", s.get("passed") is False and "lift or brake harder" in str(s.get("reason")),
           s.get("reason"))
    A.end_session("B07")
    return p


def _push_run(kmh, lift_at, lift_m, then_kmh):
    """B06: hold `kmh` from the start into a left half of the 15 m ring in 2nd (sequential), lift off for
    `lift_m` metres at `lift_at` metres from the start, then hold `then_kmh`."""
    path = ([(0, y) for y in range(0, 25)]
            + [(-15 + 15 * math.cos(a), 25 + 15 * math.sin(a)) for a in (i * math.pi / 80 for i in range(81))]
            + [(-30, 25 - y) for y in range(1, 15)])
    on_tick = _in_gear(2)

    def pedals(v, trav):
        if trav < lift_at:
            return _hold(v, kmh, floor=0.08)
        return (0.0, 0.0) if trav < lift_at + lift_m else _hold(v, then_kmh, floor=0.08)
    return A.course_run("B06", path, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=kmh + 15,
                        max_throttle=1.0, timeout=40, stop_within=0.5)


@scenario
def understeer():
    """B06 on the proving ground's dirt arc (Covet Gravel Rally): turning in too fast pushes the front wide and a
    lift brings it back onto the line for a medal; too slow to push misses, and no lift runs far wide."""
    p = []
    A.drill_session("B06")
    s = _push_run(40, 35, 10, 26)
    expect(p, "a push corrected by lifting earns a medal", s.get("passed") is True and s.get("tier") in ("silver", "gold"),
           f"{s.get('tier')}: {s.get('reason')}")
    s = _push_run(30, 1000, 0, 30)
    expect(p, "no push misses", s.get("passed") is False and "carry more speed" in str(s.get("reason")), s.get("reason"))
    s = _push_run(46, 1000, 0, 46)
    expect(p, "no lift runs wide and misses", s.get("passed") is False, s.get("reason"))
    A.end_session("B06")
    return p


def _corner_pulse_run(drill, kmh, pulse_at, pulse_m, then_kmh, offsets=None):
    """The BMP left (or its flat copy) in 2nd (sequential): hold `kmh`, a full-brake pulse of `pulse_m` metres from
    `pulse_at` metres, then hold `then_kmh`, along lines.bmp_left(offsets)."""
    import lines as L
    on_tick = _in_gear(2)

    def pedals(v, trav):
        if trav < pulse_at:
            return _hold(v, kmh)
        return (0.0, 1.0) if trav < pulse_at + pulse_m else _hold(v, then_kmh)
    return A.course_run(drill, L.bmp_left(offsets), gearbox="sequential", on_tick=on_tick, pedals=pedals,
                        kmh=kmh + 15, max_throttle=1.0, timeout=40, stop_within=0.5)


C02_LINE = {"DR1181_7": 1.8, "DR1181_8": 2.2, "DR1181_9": 2.2}  # inside: the rotated car tightens the line


@scenario
def rotation():
    """C02 on the proving ground's flat copy of the BMP left (Covet Gravel Rally): a brake pulse after turn-in
    rotates the car for a medal (scripted rotations vary a lot, so up to three tries); a short pulse at lower
    speed doesn't rotate it (about 6 degrees; a 5 m pulse at 55 km/h reaches the 8 degree target on the flat)."""
    p = []
    A.drill_session("C02")
    for _ in range(3):
        s = _corner_pulse_run("C02", 65, 73, 7, 46, C02_LINE)
        if s.get("passed"):
            break
    expect(p, "a brake pulse after turn-in rotates the car for a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _corner_pulse_run("C02", 55, 78, 4, 40, C02_LINE)
    expect(p, "no rotation misses", s.get("passed") is False and "lift or brake harder" in str(s.get("reason")), s.get("reason"))
    A.end_session("C02")
    return p


def _flick_run(kmh=66, at=54, away=0.5, away_m=8, into=-1.0, into_m=8, brake=1.0, offsets=None, drill="C08"):
    """C08: hold `kmh`, then from `at` metres lift and steer `away` (right) for `away_m`, then `into` (left)
    with `brake` for `into_m`, then the pursuit holds 45 km/h."""
    import lines as L
    on_tick = _in_gear(2)

    def pedals(v, trav):
        if trav < at:
            return _hold(v, kmh)
        if trav < at + away_m:
            return (0.0, 0.0)
        return (0.0, brake) if trav < at + away_m + into_m else _hold(v, 45)

    def steer(_v, trav):
        if at <= trav < at + away_m:
            return away
        return into if at + away_m <= trav < at + away_m + into_m else None
    # the approach nearer the middle than C02's outside line: the flick itself swings the car out
    line = L.bmp_left({**C02_LINE, "DR1181_3": 0.5, **(offsets or {})})
    return A.course_run(drill, line, gearbox="sequential", on_tick=on_tick, pedals=pedals,
                        steer=steer, kmh=kmh + 15, max_throttle=1.0, timeout=40, stop_within=0.5)


@scenario
def flick():
    """C08 on the proving ground's flat copy of the BMP left (Covet Gravel Rally): a lift-and-flick with a
    stab of brake swings the rear for a pass (scripted flicks vary: up to five tries); turning in without
    flicking misses. The flat corner needs a harder flick than the stock downhill (full brake, 66 km/h)."""
    p = []
    A.drill_session("C08")
    for _ in range(5):
        s = _flick_run()
        if s.get("passed"):
            break
    expect(p, "a flick that swings the rear passes", s.get("passed") is True, f"{s.get('tier')}: {s.get('reason')}")
    s = _flick_run(away=0.0)
    expect(p, "no flick misses", s.get("passed") is False and "No flick" in str(s.get("reason")), s.get("reason"))
    A.end_session("C08")
    return p


def _hairpin_run(pull_m=6, entry_kmh=45, lock=-0.3, exit_kmh=30, drill="C04"):
    """C04: 50 km/h, brake to `entry_kmh` before the pivot cone, the handbrake for `pull_m` metres from 45 m
    at `lock` steering, then hold `exit_kmh` round a 4.5 m turn and back out."""
    path = ([(0, y) for y in range(0, 44)]
            + [(-4.5 + 4.5 * math.cos(a), 44 + 4.5 * math.sin(a)) for a in (i * math.pi / 30 for i in range(31))]
            + [(-9, 44 - y) for y in range(1, 30)])
    on_tick = _in_gear(2)

    def pedals(v, trav):
        if trav < 38:
            return (max(0.0, min(1.0, 0.3 + (50 - v) * 0.1)), 0.0, 0.0)
        if trav < 45:
            return (0.0, 0.6 if v > entry_kmh else 0.0, 0.0)
        if trav < 45 + pull_m:
            return (0.0, 0.0, 1.0)
        return (max(0.1, min(1.0, 0.3 + (exit_kmh - v) * 0.1)), 0.0, 0.0)

    def steer(_v, trav):
        return lock if 45 <= trav < 45 + pull_m else None
    return A.course_run(drill, path, gearbox="sequential", on_tick=on_tick, pedals=pedals, steer=steer, kmh=65,
                        max_throttle=1.0, timeout=40, stop_within=0.5)


@scenario
def hairpin():
    """C04 on the proving ground's dirt strip (Covet Gravel Rally): one firm handbrake pull swings the car round the pivot
    cone for a medal; no handbrake misses."""
    p = []
    A.drill_session("C04")
    s = _hairpin_run()
    expect(p, "one handbrake pull round the cone earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _hairpin_run(pull_m=0)
    expect(p, "no handbrake misses", s.get("passed") is False, s.get("reason"))
    A.end_session("C04")
    return p


def _figure8_run(kmh):
    """C07: up to the crossing, then 10 m circles clockwise round the right cone and anticlockwise round the
    left one at a steady `kmh` in 2nd (sequential)."""
    n = 60
    path = ([(0, y) for y in range(0, 35)]
            + [(10 + 10 * math.cos(math.pi - i * 2 * math.pi / n), 35 + 10 * math.sin(math.pi - i * 2 * math.pi / n))
               for i in range(1, n + 1)]
            + [(-10 + 10 * math.cos(i * 2 * math.pi / n), 35 + 10 * math.sin(i * 2 * math.pi / n)) for i in range(1, n + 1)]
            + [(0, 35 + y) for y in range(1, 8)])
    on_tick = _in_gear(2)

    def pedals(v, _trav):
        return _hold(v, kmh, gain=0.08)
    return A.course_run("C07", path, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=kmh + 10,
                        max_throttle=1.0, timeout=60, stop_within=0.5)


@scenario
def figure8():
    """C07 on the proving ground's dirt strip (Covet Gravel Rally): a figure-eight round both cones at 28 km/h earns a
    medal; 32 km/h runs wide of the right-hand lobe and misses."""
    p = []
    A.drill_session("C07")
    s = _figure8_run(28)
    expect(p, "a clean figure-eight earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _figure8_run(32)
    expect(p, "too fast runs wide and misses", s.get("passed") is False, s.get("reason"))
    A.end_session("C07")
    return p


def _liftoff_run(entry_kmh=61, lift_at=70, offsets=None, drill="C01", approach_kmh=65):
    """C01: `approach_kmh`, braked to `entry_kmh` before the Turn in gate, 0.5 throttle, a 15 m lift from
    `lift_at` metres, then hold 45 km/h, on a line ~3 m inside through the apex."""
    import lines as L
    on_tick = _in_gear(2)

    def pedals(v, trav):
        if trav < 52:
            return _hold(v, approach_kmh)
        if trav < 66:
            return (0.0, 0.6) if v > entry_kmh else (0.5, 0.0)
        if trav < lift_at:
            return (0.5, 0.0)
        return (0.0, 0.0) if trav < lift_at + 15 else _hold(v, 45)
    line = L.bmp_left(dict({"DR1181_6": 1.0, "DR1181_7": 3.2, "DR1181_8": 3.6, "DR1181_9": 3.0}, **(offsets or {})))
    return A.course_run(drill, line, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=max(80, approach_kmh + 15),
                        max_throttle=1.0, timeout=40, stop_within=0.5)


@scenario
def liftoff():
    """C01 on the proving ground's flat copy of the BMP left (Covet Gravel Rally): lifting off at turn-in from
    61 km/h rotates the car for a pass (4-5 degrees on the flat; up to five tries); from 54 km/h it doesn't."""
    p = []
    A.drill_session("C01")
    for _ in range(5):
        s = _liftoff_run()
        if s.get("passed"):
            break
    expect(p, "a lift at turn-in rotates the car for a pass", s.get("passed") is True, f"{s.get('tier')}: {s.get('reason')}")
    s = _liftoff_run(entry_kmh=54, lift_at=72)
    expect(p, "too slow to rotate misses", s.get("passed") is False, s.get("reason"))
    A.end_session("C01")
    return p


def _slalom_run(kmh, amp):
    """D01: a cosine weave, `amp` metres either side at each cone (15 m apart), at a steady `kmh` in 2nd."""
    path = ([(0, y) for y in range(0, 18)]
            + [(-amp * math.cos(math.pi * (y - 25) / 15), y) for y in (17.5 + 0.5 * i for i in range(1, 196))]
            + [(0, y) for y in range(118, 135)])
    on_tick = _in_gear(2)

    def pedals(v, _trav):
        return _hold(v, kmh, gain=0.08)
    return A.course_run("D01", path, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=kmh + 10,
                        max_throttle=1.0, timeout=40, stop_within=0.5)


@scenario
def slalom():
    """D01 on the proving ground's dirt strip (Covet Gravel Rally): a clean weave through six cones earns a medal; too fast
    clips a cone and misses."""
    p = []
    A.drill_session("D01")
    s = _slalom_run(30, 3)
    expect(p, "a clean slalom earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _slalom_run(38, 3)
    expect(p, "too fast clips a cone and misses", s.get("passed") is False, s.get("reason"))
    A.end_session("D01")
    return p


def _surface_stop_run(decel, full_brake_at=None):
    """D08: 62 km/h up the straight, across the tarmac patch onto gravel and 2.5-3 m left, stopping on the zone
    centre at `decel` m/s2 (arcade gearbox); or a full brake from `full_brake_at` metres."""
    path = ([(0, y) for y in range(0, 123)] + [(-2.5 * (y - 122) / 24, y) for y in range(123, 147)]
            + [(-2.5 - 0.5 * (y - 146) / 16, y) for y in range(147, 163)])

    def pedals(_v, trav):
        return (0.0, 1.0) if full_brake_at is not None and trav >= full_brake_at else None
    return A.course_run("D08", path, pedals=pedals, kmh=62, decel=decel, max_throttle=1.0, timeout=40, stop_within=0.3)


@scenario
def surface():
    """D08 on the proving ground's surface-change straight (Covet Gravel Rally): braking from 62 km/h across the tarmac
    patch onto gravel and stopping in the zone earns a medal; a full brake from the tarmac locks the wheels and misses."""
    p = []
    A.drill_session("D08")
    s = _surface_stop_run(4)
    expect(p, "a controlled stop across the surface change earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _surface_stop_run(4, full_brake_at=125)
    expect(p, "a locked-wheel stop misses", s.get("passed") is False, s.get("reason"))
    A.end_session("D08")
    return p


def _fwd_exit_run(throttle_at=110, throttle=0.6, drill="E02"):
    """E02: 64 km/h, a 7 m full-brake pulse from 73 m, 0.12 throttle, then `throttle` from `throttle_at` metres
    (None: hold 46 km/h instead, barely touching the throttle), on C02's line."""
    import lines as L
    on_tick = _in_gear(2)

    def pedals(v, trav):
        if trav < 73:
            return _hold(v, 64, floor=0.0)
        if trav < 80:
            return (0.0, 1.0)
        if throttle_at is None:
            return _hold(v, 46)
        return (0.12, 0.0) if trav < throttle_at else (throttle, 0.0)
    return A.course_run(drill, L.bmp_left(C02_LINE), gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=80,
                        max_throttle=1.0, timeout=40, stop_within=0.5)


@scenario
def fwdexit():
    """E02 on the proving ground's flat copy of the BMP left (Covet Gravel Rally): a brake pulse to rotate, then throttle from the apex
    pulls the car out for a pass (up to three tries: rotations vary); no throttle after the apex misses."""
    p = []
    A.drill_session("E02")
    for _ in range(3):
        s = _fwd_exit_run()
        if s.get("passed"):
            break
    expect(p, "rotate, then throttle out, passes", s.get("passed") is True, f"{s.get('tier')}: {s.get('reason')}")
    s = _fwd_exit_run(throttle_at=None)
    expect(p, "no throttle after the apex misses", s.get("passed") is False, s.get("reason"))
    A.end_session("E02")
    return p


# The corner drills' scripted medal technique (drill id -> state), for corner_surfaces. `adapt` holds what a driver
# changes per surface (speeds, mostly), keyed by drill then variant.
CORNER_ADAPT = {
    "B04": {"snow": {"kmh": 60, "brake": 0.25, "throttle": 0.15, "exit_throttle": 0.3}},  # gentler exit on snow
    "C01": {"snow": {"entry_kmh": 54, "lift_at": 72},  # snow rotates from a slower entry
            "asphalt": {"approach_kmh": 80, "entry_kmh": 76, "lift_at": 68, "offsets": {"DR1181_9": 3.8, "DR1181_10": 2.5}}},
    "C02": {"snow": {"kmh": 58, "then_kmh": 42}, "asphalt": {"kmh": 72, "pulse_m": 9}},  # tarmac needs a harder pulse
    "C08": {"asphalt": {"kmh": 72, "away": 0.7, "away_m": 10}},
}


def _corner_runs():
    import lines as L

    def a(base, d):
        return CORNER_ADAPT.get(base, {}).get(d.split("-")[1] if "-" in d else "gravel", {})
    return {
        "A07": lambda d: A.course_run(d, L.bmp_left(), kmh=a("A07", d).get("kmh", 55), **CORNER_KW),
        "A08": lambda d: A.course_run(d, L.bmp_left(A08_LATE, tail=60), kmh=a("A08", d).get("kmh", 41), **CORNER_KW),
        "B04": lambda d: _trail_run(d, **a("B04", d)),
        "C01": lambda d: _liftoff_run(drill=d, **a("C01", d)),
        "C02": lambda d: _corner_pulse_run(d, **{**dict(kmh=65, pulse_at=73, pulse_m=7, then_kmh=46, offsets=C02_LINE),
                                                **a("C02", d)}),
        "C08": lambda d: _flick_run(drill=d, **a("C08", d)),
        "E02": lambda d: _fwd_exit_run(drill=d, **a("E02", d)),
    }


@scenario
def corner_surfaces():
    """The graded corner drills (A07, A08, B04, C01, C02, C08, E02) on the gravel corner and its asphalt and snow twins
    (ADR 0009): each drill's scripted medal technique, adapted per surface where a driver would adapt it, passes on
    every variant (up to three tries: rotations vary). Prints a table. RA_SURFACES=A07,C02 limits it to some drills."""
    return _surface_suite(_corner_runs(), tries=3)


def _surface_suite(runs, tries=1):
    """Each drill of `runs` (base id -> technique(drill id) -> state) on each of its surfaces, up to `tries` runs
    until one passes; expects a pass on every surface and prints a table of verdicts. RA_SURFACES=A07,C02 limits
    it to some drills."""
    import os
    p, table = [], []
    only = os.environ.get("RA_SURFACES")
    for base in [b for b in runs if not only or b in only.split(",")]:
        for sf in A.drill(base).get("surfaces") or [{"id": base, "name": "Standard"}]:
            d = sf["id"]
            A.drill_session(d)
            for _ in range(tries):
                s = runs[base](d)
                if s.get("passed"):
                    break
            table.append((d, s.get("tier") or ("pass" if s.get("passed") else "MISS"), A.grade_lines()))
            expect(p, f"{d} ({sf['name']}): the medal technique passes", s.get("passed") is True,
                   f"{s.get('tier')}: {s.get('reason')}")
            A.end_session(d)
    for d, verdict, lines in table:
        print(f"  {d:12} {verdict:7} " + " | ".join(str(x) for x in (lines or [])[:7]))
    return p


def _circuit_run(drill, a, b, kmh, then_kmh=None, then_at=1e9):
    """A run along the Off-Road Circuit's centre line, or the proving ground's copy (tools/ingame/circuit.py: metres a to b from dirttrack_1) in 2nd
    (sequential), holding `kmh`, then `then_kmh` from `then_at` metres into the run."""
    import circuit
    venue = A.drill(drill)["environment"]["spawn"]
    on_tick = _in_gear(2)

    def pedals(v, trav):
        target = then_kmh if then_kmh is not None and trav >= then_at else kmh
        if v > target + 4:
            return (0.0, min(0.7, 0.2 + (v - target) * 0.05))
        return _hold(v, target)
    return A.course_run(drill, circuit.line(venue, a, b), gearbox="sequential", on_tick=on_tick, pedals=pedals,
                        kmh=max(kmh, then_kmh or 0) + 15, max_throttle=1.0, timeout=90, stop_within=0.5)


@scenario
def blind():
    """D05 on the proving ground's copy of the Off-Road Circuit (Covet Gravel Rally): a steady 37 km/h into the blind crest hairpin earns a medal;
    55 km/h is too fast for a corner you can't see."""
    p = []
    A.drill_session("D05")
    s = _circuit_run("D05", 420, 600, 37)
    expect(p, "a conservative approach earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _circuit_run("D05", 420, 600, 55)
    # whichever check fails first: the speed check, the wall at the crest, or running wide of the gate after it
    expect(p, "too fast into the blind corner misses", s.get("passed") is False
           and any(k in str(s.get("reason")) for k in ("too fast", "Hit something", "Missed gate")), s.get("reason"))
    A.end_session("D05")
    return p


@scenario
def hills():
    """D06 on the proving ground's copy of the Off-Road Circuit (Covet Gravel Rally): the uphill and downhill corners at 45/40 km/h earn a medal;
    55 km/h hits the uphill corner's wall."""
    p = []
    A.drill_session("D06")
    s = _circuit_run("D06", 0, 320, 45, 40, 240)
    expect(p, "clean uphill and downhill corners earn a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    for _ in range(2):  # the car can jam against the wall and never finish the run: retry, as a driver would
        s = _circuit_run("D06", 0, 320, 55, 45, 230)
        if s.get("passed") is not None:
            break
    expect(p, "too fast hits the wall and misses", s.get("passed") is False, s.get("reason"))
    A.end_session("D06")
    return p


@scenario
def crest():
    """E05 on the proving ground's copy of the Off-Road Circuit (Covet Gravel Rally): 45 km/h through the banked left
    after the descent, then about 56 km/h over the kicker keeps the wheels down for a medal; flat out takes off and
    lands hard. (On the stock circuit 55 km/h through the left was fine: its wall is continuous, the copy's barriers
    are separate blocks.)"""
    p = []
    A.drill_session("E05")
    s = _circuit_run("E05", 236, 420, 45, 56, 60)
    expect(p, "a planted crest earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _circuit_run("E05", 236, 420, 55, 75, 50)
    expect(p, "flat out over the crest misses", s.get("passed") is False, s.get("reason"))
    A.end_session("E05")
    return p


def _lane_run(drill, n0, n1, a, b, kmh, then_kmh=None, then_at=1e9, throttle_at=None, throttle_max=0.45, ramp=0.005):
    """A run along gravel lane DR825 or its proving-ground copy (nodes n0 to n1, metres a to b) in 2nd (sequential): hold `kmh` (a gentle launch),
    then `then_kmh` from `then_at` metres, or a throttle ramp from 0.25 up to `throttle_max` from `throttle_at`."""
    import lanes
    line = lanes.line(A.drill(drill)["environment"]["spawn"], n0, n1, a, b)
    on_tick = _in_gear(2)

    def pedals(v, trav):
        if throttle_at is not None and trav >= throttle_at:
            return (min(throttle_max, 0.25 + (trav - throttle_at) * ramp), 0.0)
        target = then_kmh if then_kmh is not None and trav >= then_at else kmh
        if v > target + 3:
            return (0.0, min(0.7, 0.2 + (v - target) * 0.06))
        return _hold(v, target, ceiling=0.45 if v < 20 else 1.0)
    return A.course_run(drill, line, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=80, max_throttle=1.0,
                        timeout=60, stop_within=0.5)


@scenario
def tighten():
    """D03 on the proving ground's flat copy of gravel lane DR825 (Covet Gravel Rally): easing off as the right-hander
    tightens earns a medal; 55 km/h in runs wide where it closes (the flat copy carries more speed than the stock
    lane's crest did)."""
    p = []
    A.drill_session("D03")
    s = _lane_run("D03", 2, 13, 2, 118, 45, 30, 50)
    expect(p, "easing off into the tightening corner earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _lane_run("D03", 2, 13, 2, 118, 55, 40, 50)
    expect(p, "too fast in runs wide and misses", s.get("passed") is False, s.get("reason"))
    A.end_session("D03")
    return p


@scenario
def opening():
    """D04 on the proving ground's flat copy of gravel lane DR825 (Covet Gravel Rally): a progressive throttle out of
    the opening left-hander earns a medal; too much spins the front and runs wide."""
    p = []
    A.drill_session("D04")
    s = _lane_run("D04", 13, 2, 2, 100, 25, throttle_at=36, throttle_max=0.45, ramp=0.005)
    expect(p, "a progressive throttle earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _lane_run("D04", 13, 2, 2, 100, 25, throttle_at=32, throttle_max=0.6, ramp=0.01)
    expect(p, "too much throttle misses", s.get("passed") is False, s.get("reason"))
    A.end_session("D04")
    return p


@scenario
def pause():
    """Esc menu: the Rally Academy tab and its four pages render, and the menu still works after."""
    p = []
    lua("ui_router.navigate('play') return 1")
    time.sleep(1)

    def click_text(selector, text):
        tagged = ui(f"var e=Array.from(document.querySelectorAll({json.dumps(selector)})).find(function(x){{"
                    f"var r=x.getBoundingClientRect(); return r.width>0 && x.textContent.trim().indexOf({json.dumps(text)})>=0}});"
                    "if(!e) return 'missing'; document.querySelectorAll('[data-ra-click]').forEach(function(x){x.removeAttribute('data-ra-click')});"
                    "e.setAttribute('data-ra-click','1'); return 'ok'")
        if tagged == "ok":
            call("ui_click", {"selector": "[data-ra-click]"})
            time.sleep(2.5)
        return tagged

    lua("ui_router.navigate('pause') return 1")
    time.sleep(4)
    expect(p, "Rally Academy tab in the pause menu", click_text(".tab-item", "Rally Academy") == "ok")
    # Found by hand: rail buttons without an icon crashed the whole Vue UI on this click.
    click_text("[class*=rail] button, [class*=rail-button]", "Exercises")  # the menu reopens on the last page
    page = A.wait_for(lambda: ui("return document.querySelectorAll('.ra-pause-page .ra-card').length"), len(A.catalogue()))
    expect(p, "Exercises lists every drill", page == len(A.catalogue()), page)
    click_text(".ra-pause-page .ra-card", "A04")
    expect(p, "picking a drill shows its details", "Throttle modulation" in str(ui(
        "var d=document.querySelector('.ra-pause-page .ra-details'); return d ? d.innerText : ''")))
    for label, marker in (("Analysis", ".ra-metric"), ("About", ".ra-panel"), ("Credits", ".ra-big")):
        click_text("[class*=rail] button, [class*=rail-button]", label)
        n = A.wait_for(lambda: ui(f"return document.querySelectorAll('.ra-pause-page {marker}').length > 0"), True)
        expect(p, f"{label} page renders", n is True, n)
    lua("ui_router.navigate('play') return 1")
    time.sleep(2)
    lua("ui_router.navigate('pause') return 1")
    time.sleep(4)
    native = ui("return Array.from(document.querySelectorAll('.tab-item')).filter(function(e){return e.getBoundingClientRect().width>0}).map(function(e){return e.textContent.trim()})")
    has_vehicle = isinstance(native, list) and any("Vehicle" in t for t in native)  # names start with an icon glyph
    expect(p, "reopened pause menu still has the game's own tabs", has_vehicle, len(native) if isinstance(native, list) else native)
    lua("ui_router.navigate('play') return 1")
    time.sleep(1)
    return p


@scenario
def events():
    """Car events on the proving ground's dirt strip: a handbrake spin, a grass excursion and a puncture are detected."""
    p = []
    A.drill_session("B02")
    # B02 ends when the car stops; checks spin and staying on the road
    on_straight()

    def drive(target_kmh, during, max_s=20):
        A.click("Retry")
        time.sleep(1.0)
        A.arcade()
        inp("parkingbrake", 0)
        inp("steering", 0)
        t0 = time.time()
        while time.time() - t0 < 25 and state()[1] * 3.6 < target_kmh:
            inp("throttle", 1.0)
            time.sleep(0.05)
        inp("throttle", 0)
        tb = time.time()
        while time.time() - tb < max_s:
            if state()[1] * 3.6 < 3 and time.time() - tb > 1:
                break
            during(time.time() - tb)
            time.sleep(0.04)
        for event, value in (("brake", 0), ("steering", 0), ("parkingbrake", 1)):
            inp(event, value)
        A.wait_graded()

    def spin(t):
        inp("parkingbrake", 1 if t < 1.0 else 0)
        inp("steering", 1.0 if t < 1.0 else 0.0)
        inp("brake", 0.0 if t < 1.2 else 0.5)
    drive(60, spin)
    c = A.rule_check({"type": "no_spin"})
    expect(p, "handbrake spin is a spin", not c["ok"], c["text"])
    c = A.rule_check({"type": "no_handbrake"})
    expect(p, "handbrake use is seen", not c["ok"], c["text"])

    # Steering off the road depends on the car's path; start the run on the verge instead: grass 63 m left of
    # B01's spot, just past the west edge of the proving ground's 120 m dirt strip (the guardrail is 10 m out).
    sp = A.drill("B01")["environment"]["spawn"]
    A.place(sp["pos"], sp["dir"], ahead=20, side=-63)
    lua("extensions.rallyAcademy.markStart() return 1")
    drive(20, lambda t: inp("brake", 0.0 if t < 1.0 else 0.5))
    c = A.rule_check({"type": "on_surface", "surfaces": ["ASPHALT", "GRAVEL"], "maxWheelsOff": 2, "maxSeconds": 0.5})
    expect(p, "driving onto the grass leaves the road", not c["ok"], c["text"])

    on_straight()  # back to the road for the puncture
    flat = {"done": False}
    def puncture(t):
        if not flat["done"]:
            call("run_lua_vehicle", {"code": "beamstate.deflateRandomTire() return 1"})
            flat["done"] = True
        inp("brake", 0.0 if t < 1.5 else 0.35)
    drive(45, puncture)
    c = A.rule_check({"type": "no_puncture"})
    expect(p, "deflated tyre is a puncture", not c["ok"], c["text"])
    c = A.rule_check({"type": "no_damage"})
    expect(p, "a puncture is not contact", c["ok"], c["text"])
    lua("extensions.rallyAcademy.useVenueStart() return 1")  # forget the starts this marked (one on the verge)
    A.end_session("B02")
    return p


@scenario
def goto():
    """Go to drill: from another map (West Coast USA, loaded first: slow), E08 loads the proving ground in the gravel
    Covet; B01 on the same map then swaps the car for the Student Driver without a reload."""
    p = []
    if A.debug_state().get("level") != "west_coast_usa":
        lua("freeroam_freeroam.startFreeroam('levels/west_coast_usa/info.json') return 1")
        A.wait_level("west_coast_usa")
    A.reload_mod(ui_too=False)
    A.choose("E08")
    lua("extensions.rallyAcademy.goToDrill() return 1")
    expect(p, "E08 loads the proving ground with the Covet Gravel Rally", A.wait_level("ra_proving_ground", "rally_gravel"))
    s = A.debug_state()
    expect(p, "E08 is selected", s.get("selected") == "E08", s.get("reason"))
    A.choose("B01")
    lua("extensions.rallyAcademy.goToDrill() return 1")
    swapped = A.wait_for(lambda: "student_driver" in A.current_config() and "in the drill car" in str(A.debug_state().get("reason")),
                         True, timeout=30)
    expect(p, "B01 swaps in the Student Driver on the same map", swapped, A.debug_state().get("reason"))
    return p


@scenario
def mainmenu():
    """From the main menu: More... > Rally Academy > A04 > Start drill lands in the drill (a map load).
    Leaves the proving ground loaded, so the driving scenarios can follow."""
    p = []
    if A.debug_state().get("level") != "unknown":
        lua("returnToMainMenu() return 1")
        t0 = time.time()
        while time.time() - t0 < 120 and (str(A.safe(lua, "return tostring(getCurrentLevelIdentifier())")) not in ("nil", "<GameError>")
                                          or A.safe(ui, "return location.hash") != "#/menu"):
            time.sleep(3)
        time.sleep(3)
    lua("ui_router.navigate('menu.rallyAcademy') return 1")
    cards = A.wait_for(lambda: ui("return document.querySelectorAll('.ra-card').length"), len(A.catalogue()), timeout=20)
    expect(p, "Academy screen opens from the main menu", cards == len(A.catalogue()), cards)
    ui("var c=Array.from(document.querySelectorAll('.ra-card')).find(function(x){return x.innerText.indexOf('A04')===0}); c.click(); return 1")
    time.sleep(1)
    ui("var b=Array.from(document.querySelectorAll('.ra-details button')).find(function(x){return /Start drill/.test(x.textContent)}); b.click(); return 1")
    expect(p, "Start drill loads the proving ground in the drill car", A.wait_level("ra_proving_ground", "student_driver"))
    route = A.wait_for(lambda: ui("return location.hash"), "#/play")
    expect(p, "the menu gets out of the way (game view)", route == "#/play", route)
    expect(p, "the HUD panel is up", A.wait_panel())
    return p


@scenario
def fit():
    """Venue fit test on West Coast USA (it needs obstacles): B01 fits the BMP dirt arena's long straight, not
    facing the barrier; B05 fits the dirt arena. Needs West Coast USA loaded."""
    import fit as F
    p = []
    # the BMP dirt arena's long straight and its centre (the old venues bmp-dirt-arena-long, bmp-dirt-arena)
    sp = {"pos": {"x": 386.59, "y": 145.57, "z": 127.05}, "dir": {"x": -0.7051, "y": -0.7046, "z": 0.0}}
    r = F.fit("B01", sp["pos"], sp["dir"])
    expect(p, "B01 fits the long straight", r["fits"], r["problems"] or r["notes"])
    sideways = {"x": sp["dir"]["y"], "y": -sp["dir"]["x"]}  # turned to face the barrier ~8 m away
    r = F.fit("B01", sp["pos"], sideways)
    expect(p, "B01 facing the barrier does not fit", not r["fits"], r["problems"])
    arena = {"pos": {"x": 337.07, "y": 96.09, "z": 127.26}, "dir": {"x": -0.7051, "y": -0.7046, "z": 0.0793}}
    r = F.fit("B05", arena["pos"], arena["dir"])
    expect(p, "B05's circle fits the dirt arena", r["fits"], r["problems"] or r["notes"])
    return p


# Module A's scripted medal technique per drill (drill id -> state), for the surfaces scenario. Surface variants run
# the same technique: the targets, not the driving, are what change per surface (ADR 0009).
def _module_a_runs(kmh_scale=1.0):
    front = 1.81  # Covet: front bumper ahead of the car's position

    def a01(d):
        best = None
        for _ in range(3):  # the line jitters by ~0.1 m; gold needs ~0.2 m to spare
            s = A.course_run(d, A01_GOLD, kmh=14)
            if s.get("passed") and (best is None or s.get("tier") == "gold"):
                best = s
            if s.get("tier") == "gold":
                break
        return best or s
    return {
        "A01": a01,
        "A02": lambda d: _launch_run(d, A.drill(d).get("surface", "Dirt")),
        "A03": lambda d: A.course_run(d, [(0, 0), (0, 155)], on_tick=_gear_plan(2), gearbox="sequential", kmh=62,
                                      decel=2.2, max_throttle=0.9),
        "A04": lambda d: _hold_run(lambda m: 30),
        "A05": lambda d: precise(lambda: A.course_run(d, [(0, 0), (0, 60 - front - 0.5)], kmh=44, decel=3.5,
                                                      max_throttle=0.7)),
        # B01: brake earlier and gentler on snow (4.6 m/s2 locks the wheels there; 3 m/s2 doesn't)
        "B01": lambda d: precise(lambda: A.course_run(d, [(0, 0), (0, 150)], kmh=72, max_throttle=1.0, stop_within=0.4,
                                                      decel=3.0 if A.drill(d).get("surface") == "Snow" else 4.6)),
        # C04: less lock on asphalt (the grippy front cuts into the cone), a slower entry on snow (it swings 50 deg)
        "C04": lambda d: _c04_run(d),
    }


def _c04_run(d, tries=3):
    surface = A.drill(d).get("surface")
    kw = {"Asphalt": {"lock": -0.2}, "Snow": {"entry_kmh": 40, "exit_kmh": 25}}.get(surface, {})
    for _ in range(tries):  # scripted handbrake swings vary
        s = _hairpin_run(drill=d, **kw)
        if s.get("passed"):
            break
    return s


def _launch_run(drill, surface="Dirt"):
    """A02: the throttle fed in as the car gathers speed (a flat-out start spins the wheels on loose ground and the
    arcade box then stays in 1st): from 25 % at rest to full at 45 km/h; on snow from 15 % to full at 80 km/h."""
    start, full = (0.15, 80.0) if surface == "Snow" else (0.25, 45.0)

    def pedals(v, trav):
        return (min(1.0, start + max(0.0, v) / full * (1 - start)), 0.0) if trav < 75 else None
    return A.course_run(drill, [(0, 0), (0, 80)], kmh=48, decel=3.0, max_throttle=1.0, pedals=pedals)


@scenario
def surfaces():
    """A01-A05, B01 and C04 on every surface (the proving ground's dirt, gravel, asphalt and snow strips, ADR 0009):
    the drill's scripted medal technique, adapted per surface where a driver would adapt it, passes on each variant.
    Prints a table of verdicts and the numbers behind them. RA_SURFACES=B01,C04 limits it to some drills."""
    return _surface_suite(_module_a_runs())
