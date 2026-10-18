"""In-game scenarios: `python tools/dev.py ingame <name>` with BeamNG running and the mod
linked (dev.py link). Each scenario drives the real game through its MCP server, prints
what happened and returns the problems it found (empty = all as expected).

Braking scenarios use the BMP start straight on West Coast USA in the Covet Student
Driver (B01's venue spot). They record attempts, then remove them from your progress.
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
    """Mark the start at B01's spawn (the BMP run-up); needs West Coast USA loaded."""
    sp = A.drill("B01")["environment"]["spawn"]
    if A.debug_state().get("level") != "west_coast_usa":
        raise RuntimeError("load West Coast USA first (e.g. Go to drill on B01)")
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
    opts = A.wait_for(lambda: ui("return document.querySelectorAll('.dropdown-option-label').length"), len(A.drills()))
    expect(p, "drop-down opens on a click and lists every drill", opts == len(A.drills()), opts)
    ui("var o=Array.from(document.querySelectorAll('.dropdown-option-label')).find(function(e){return e.textContent.indexOf('B01 ')===0});"
       "if(o) (o.closest('[bng-nav-item]')||o.parentElement).setAttribute('data-ra-pick','1'); return 1")
    call("ui_click", {"selector": "[data-ra-pick]"})
    picked = A.wait_for(lambda: A.debug_state().get("selected"), "B01")
    expect(p, "picking B01 in the drop-down selects it", picked == "B01", picked)
    # Found by the demo run: a drill with no rules ({} from Lua, not []) crashed the Vue panel.
    A.choose("A06")
    title = A.wait_for(lambda: ui(f"var p=document.querySelector('{A.PANEL} .ra-instructions'); return p ? 'shown' : 'missing'"), "shown")
    expect(p, "panel renders a drill without grading rules (A06)", title == "shown", title)
    A.choose("A04")
    expect(p, "selecting A04 shows the gate button", "Gate" in str(ui(f"return document.querySelector('{A.PANEL}').innerText")))
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
    """Authored course at the BMP dirt arena: laid out with no marking; a medal run, the wrong
    side of the cone, a clipped gate post; auto-retry. Needs West Coast USA loaded."""
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
    """B01 on its course (BMP run-up, stop zone 30 m past the start line): threshold braking from 72
    km/h into the zone earns a medal; braking too hard overshoots and misses; full brake locks and misses."""
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
    """A04 on its course (BMP run-up, three gates 25 m apart): a steady 30 km/h earns a medal; 40 km/h at
    gate 3 misses. Needs West Coast USA."""
    p = []
    A.drill_session("A04")
    expect(p, "three gates laid out at the venue", A.debug_state().get("gateCount") == 3, A.debug_state().get("reason"))

    def hold(target_of_d):
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

    s = hold(lambda d: 30)
    expect(p, "steady 30 km/h passes with a medal", s.get("passed") is True and s.get("tier") in ("gold", "silver", "bronze"),
           f"{s.get('tier')}: {A.grade_lines()}")
    s = hold(lambda d: 30 if d < 60 else 40)
    expect(p, "too fast at gate 3 misses", s.get("passed") is False, A.grade_lines())
    A.end_session("A04")
    return p


@scenario
def stops():
    """A05 on its course (BMP dirt arena, stop line 60 m ahead) and B02 on its course (BMP run-up, a
    40 m stop area): one PASS and one MISS each."""
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
    """A02 on its course (BMP start straight, from the venue start): a flat-out launch through the
    40 km/h gate earns a medal (the run ends at the gate); 34 km/h at the gate misses. Needs West Coast USA."""
    p = []
    A.drill_session("A02")
    s = A.debug_state()
    expect(p, "the course is laid out at the venue", s.get("hasCourse") and s.get("usingVenueStart"), s.get("reason"))
    line = [(0, 0), (0, 80)]  # down the straight's centre line; the run ends at the gate (60 m)
    s = A.course_run("A02", line, kmh=48, decel=3.0, max_throttle=1.0)
    expect(p, "a flat-out launch passes with a medal", s.get("passed") is True and s.get("tier") in ("gold", "silver"),
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
    """A03 on its course (BMP run-up): up to 3rd and 60 km/h, then down to 2nd one gear at a time into
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


@scenario
def corners():
    """A07 and A08 on the BMP downhill left (Covet Gravel Rally, scripted racing line from lines.py):
    a clean line earns a medal on each; A07 clipping the exit post and A08 weaving after the exit miss.
    Swaps to the drill car with Go to drill (same map)."""
    import lines as L
    p = []
    A.drill_session("A07")
    kw = dict(decel=2.5, max_throttle=0.9, stop_within=0.5)
    s = A.course_run("A07", L.bmp_left(), kmh=50, **kw)
    expect(p, "A07 racing line earns a medal", s.get("passed") is True and s.get("tier") in ("gold", "silver"),
           f"{s.get('tier')}: {s.get('reason')}")
    s = A.course_run("A07", L.bmp_left({"DR1181_11": -0.5, "DR1181_12": -3.3}), kmh=45, **kw)
    expect(p, "A07 clipping the exit post misses", s.get("passed") is False and "Clipped" in str(s.get("reason")), s.get("reason"))
    lua("extensions.rallyAcademy.select('A08') extensions.rallyAcademy.useVenueStart() return 1")
    s = A.course_run("A08", L.bmp_left(), kmh=46, **kw)
    expect(p, "A08 late apex and steady exit earns a medal", s.get("passed") is True and s.get("tier") in ("gold", "silver"),
           f"{s.get('tier')}: {s.get('reason')}")
    s = A.course_run("A08", L.bmp_left({"DR1181_13": -0.5, "DR1181_14": -4.2, "DR1181_15": -0.5}), kmh=44, **kw)
    expect(p, "A08 weaving after the exit misses", s.get("passed") is False and "steering correction" in str(s.get("reason")),
           s.get("reason"))
    A.end_session("A07", "A08")
    return p


@scenario
def trail():
    """B04 on the BMP downhill left (Covet Gravel Rally): braking from the marker and easing off into the
    turn earns a medal; braking only in a straight line before turning in misses."""
    import lines as L
    p = []
    A.drill_session("B04")
    apex = 118.7  # metres along lines.bmp_left() to the apex gate

    def trail_pedals(_kmh, trav):
        if trav < 50:
            return None
        if trav < apex - 3:
            return (0.0, max(0.0, 0.35 * (1 - (trav - 50) / (apex - 53))))
        return (0.6, 0.0)

    def straight_pedals(_kmh, trav):
        if trav < 45:
            return None
        return (0.0, 0.45) if trav < 62 else (0.25, 0.0)
    kw = dict(kmh=60, decel=2.5, max_throttle=1.0, stop_within=0.5)
    s = A.course_run("B04", L.bmp_left(), pedals=trail_pedals, **kw)
    expect(p, "trail braking into the corner earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = A.course_run("B04", L.bmp_left(), pedals=straight_pedals, **kw)
    expect(p, "braking only before turn-in misses", s.get("passed") is False and "into the corner" in str(s.get("reason")),
           s.get("reason"))
    A.end_session("B04")
    return p


def _ring_run(kmh, dab_every=25.0, brake=0.25, dab_m=3.0, lift=False):
    """Two-plus laps of the B05 ring in 2nd (sequential), throttle held, brake dabs every `dab_every` m."""
    ring = [(-15 + 15 * math.cos(a), 15 * math.sin(a)) for a in (i * 0.02 for i in range(int(2.3 * 2 * math.pi / 0.02)))]
    shifted = []

    def on_tick(_kmh, _to_go):
        if not shifted:
            shifted.append(1)
            return A.shift_to(2)

    def pedals(v, trav):
        thr = max(0.15, min(0.6, 0.25 + (min(kmh, 12 + trav * 0.8) - v) * 0.05))
        if trav > 20 and trav % dab_every < dab_m:
            return (0.0 if lift else thr, brake)
        return (thr, 0.0)
    return A.course_run("B05", ring, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=kmh + 10,
                        max_throttle=1.0, timeout=60, stop_within=0.5)


@scenario
def circle():
    """B05 on the BMP dirt circle (Covet Gravel Rally): two laps of the 15 m ring on steady throttle with
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
    shifted = []

    def on_tick(_kmh, _to_go):
        if not shifted:
            shifted.append(1)
            return A.shift_to(2)

    def pedals(v, trav):
        if trav < 24:
            return (max(0.0, min(0.8, 0.3 + (kmh - v) * 0.08)), 0.0)
        return (0.0, brake) if trav < 24 + brake_m else (0.3, 0.0)
    return A.course_run("B07", path, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=kmh + 15,
                        max_throttle=1.0, timeout=40, stop_within=0.5, max_steer=max_steer)


@scenario
def oversteer():
    """B07 on the BMP dirt circle (Covet Gravel Rally): a hard brake at turn-in steps the rear out, the
    slide is caught and settled down the exit lane for a medal; a gentle turn-in with no slide misses."""
    p = []
    A.drill_session("B07")
    s = _arc_run(60, 6)
    expect(p, "a caught slide earns a medal", s.get("passed") is True and s.get("tier") in ("silver", "gold"),
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
    shifted = []

    def on_tick(_kmh, _to_go):
        if not shifted:
            shifted.append(1)
            return A.shift_to(2)

    def pedals(v, trav):
        def hold(target):
            return (max(0.08, min(1.0, 0.3 + (target - v) * 0.1)), 0.0)
        if trav < lift_at:
            return hold(kmh)
        return (0.0, 0.0) if trav < lift_at + lift_m else hold(then_kmh)
    return A.course_run("B06", path, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=kmh + 15,
                        max_throttle=1.0, timeout=40, stop_within=0.5)


@scenario
def understeer():
    """B06 on the BMP dirt circle (Covet Gravel Rally): turning in too fast pushes the front wide and a
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
    """The BMP downhill left in 2nd (sequential): hold `kmh`, a full-brake pulse of `pulse_m` metres from
    `pulse_at` metres, then hold `then_kmh`, along lines.bmp_left(offsets)."""
    import lines as L
    shifted = []

    def on_tick(_kmh, _to_go):
        if not shifted:
            shifted.append(1)
            return A.shift_to(2)

    def pedals(v, trav):
        def hold(target):
            return (max(0.05, min(1.0, 0.3 + (target - v) * 0.1)), 0.0)
        if trav < pulse_at:
            return hold(kmh)
        return (0.0, 1.0) if trav < pulse_at + pulse_m else hold(then_kmh)
    return A.course_run(drill, L.bmp_left(offsets), gearbox="sequential", on_tick=on_tick, pedals=pedals,
                        kmh=kmh + 15, max_throttle=1.0, timeout=40, stop_within=0.5)


C02_LINE = {"DR1181_7": 1.8, "DR1181_8": 2.2, "DR1181_9": 2.2}  # inside: the rotated car tightens the line


@scenario
def rotation():
    """C02 on the BMP downhill left (Covet Gravel Rally): a brake pulse after turn-in rotates the car for a
    medal (scripted rotations vary a lot, so up to three tries); a gentle pulse at lower speed doesn't rotate it."""
    p = []
    A.drill_session("C02")
    for _ in range(3):
        s = _corner_pulse_run("C02", 65, 73, 7, 46, C02_LINE)
        if s.get("passed"):
            break
    expect(p, "a brake pulse after turn-in rotates the car for a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _corner_pulse_run("C02", 55, 78, 5, 40, C02_LINE)
    expect(p, "no rotation misses", s.get("passed") is False and "lift or brake harder" in str(s.get("reason")), s.get("reason"))
    A.end_session("C02")
    return p


def _flick_run(kmh=62, at=54, away=0.5, away_m=8, into=-0.8, into_m=8, brake=0.8):
    """C08: hold `kmh`, then from `at` metres lift and steer `away` (right) for `away_m`, then `into` (left)
    with `brake` for `into_m`, then the pursuit holds 45 km/h."""
    import lines as L
    shifted = []

    def on_tick(_kmh, _to_go):
        if not shifted:
            shifted.append(1)
            return A.shift_to(2)

    def hold(v, target):
        return (max(0.05, min(1.0, 0.3 + (target - v) * 0.1)), 0.0)

    def pedals(v, trav):
        if trav < at:
            return hold(v, kmh)
        if trav < at + away_m:
            return (0.0, 0.0)
        return (0.0, brake) if trav < at + away_m + into_m else hold(v, 45)

    def steer(_v, trav):
        if at <= trav < at + away_m:
            return away
        return into if at + away_m <= trav < at + away_m + into_m else None
    return A.course_run("C08", L.bmp_left(C02_LINE), gearbox="sequential", on_tick=on_tick, pedals=pedals,
                        steer=steer, kmh=kmh + 15, max_throttle=1.0, timeout=40, stop_within=0.5)


@scenario
def flick():
    """C08 on the BMP downhill left (Covet Gravel Rally): a lift-and-flick with a touch of brake swings the
    rear for a pass (scripted flicks pass a third to half the time: up to five tries); turning in without
    flicking misses."""
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


def _hairpin_run(pull_m=6, entry_kmh=45, lock=-0.3, exit_kmh=30):
    """C04: 50 km/h, brake to `entry_kmh` before the pivot cone, the handbrake for `pull_m` metres from 45 m
    at `lock` steering, then hold `exit_kmh` round a 4.5 m turn and back out."""
    path = ([(0, y) for y in range(0, 44)]
            + [(-4.5 + 4.5 * math.cos(a), 44 + 4.5 * math.sin(a)) for a in (i * math.pi / 30 for i in range(31))]
            + [(-9, 44 - y) for y in range(1, 30)])
    shifted = []

    def on_tick(_kmh, _to_go):
        if not shifted:
            shifted.append(1)
            return A.shift_to(2)

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
    return A.course_run("C04", path, gearbox="sequential", on_tick=on_tick, pedals=pedals, steer=steer, kmh=65,
                        max_throttle=1.0, timeout=40, stop_within=0.5)


@scenario
def hairpin():
    """C04 on the BMP dirt arena (Covet Gravel Rally): one firm handbrake pull swings the car round the pivot
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
    shifted = []

    def on_tick(_kmh, _to_go):
        if not shifted:
            shifted.append(1)
            return A.shift_to(2)

    def pedals(v, _trav):
        return (max(0.05, min(1.0, 0.3 + (kmh - v) * 0.08)), 0.0)
    return A.course_run("C07", path, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=kmh + 10,
                        max_throttle=1.0, timeout=60, stop_within=0.5)


@scenario
def figure8():
    """C07 on the BMP dirt arena (Covet Gravel Rally): a figure-eight round both cones at 28 km/h earns a
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


def _liftoff_run(entry_kmh=61, lift_at=70):
    """C01: 65 km/h, braked to `entry_kmh` before the Turn in gate, 0.5 throttle, a 15 m lift from
    `lift_at` metres, then hold 45 km/h, on a line ~3 m inside through the apex."""
    import lines as L
    shifted = []

    def on_tick(_kmh, _to_go):
        if not shifted:
            shifted.append(1)
            return A.shift_to(2)

    def hold(v, target):
        return (max(0.05, min(1.0, 0.3 + (target - v) * 0.1)), 0.0)

    def pedals(v, trav):
        if trav < 52:
            return hold(v, 65)
        if trav < 66:
            return (0.0, 0.6) if v > entry_kmh else (0.5, 0.0)
        if trav < lift_at:
            return (0.5, 0.0)
        return (0.0, 0.0) if trav < lift_at + 15 else hold(v, 45)
    line = L.bmp_left({"DR1181_6": 1.0, "DR1181_7": 3.2, "DR1181_8": 3.6, "DR1181_9": 3.0})
    return A.course_run("C01", line, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=80, max_throttle=1.0,
                        timeout=40, stop_within=0.5)


@scenario
def liftoff():
    """C01 on the BMP downhill left (Covet Gravel Rally): lifting off at turn-in from 61 km/h rotates the car for
    a pass (scripted lifts pass only a third to half the time, so up to five tries); from 54 km/h it doesn't."""
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
    shifted = []

    def on_tick(_kmh, _to_go):
        if not shifted:
            shifted.append(1)
            return A.shift_to(2)

    def pedals(v, _trav):
        return (max(0.05, min(1.0, 0.3 + (kmh - v) * 0.08)), 0.0)
    return A.course_run("D01", path, gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=kmh + 10,
                        max_throttle=1.0, timeout=40, stop_within=0.5)


@scenario
def slalom():
    """D01 on the BMP dirt arena (Covet Gravel Rally): a clean weave through six cones earns a medal; too fast
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
    """D08: 62 km/h up the run-up, across the tarmac patch onto gravel and 2.5-3 m left, stopping on the zone
    centre at `decel` m/s2 (arcade gearbox); or a full brake from `full_brake_at` metres."""
    path = ([(0, y) for y in range(0, 123)] + [(-2.5 * (y - 122) / 24, y) for y in range(123, 147)]
            + [(-2.5 - 0.5 * (y - 146) / 16, y) for y in range(147, 163)])

    def pedals(_v, trav):
        return (0.0, 1.0) if full_brake_at is not None and trav >= full_brake_at else None
    return A.course_run("D08", path, pedals=pedals, kmh=62, decel=decel, max_throttle=1.0, timeout=40, stop_within=0.3)


@scenario
def surface():
    """D08 on the BMP run-up (Covet Gravel Rally): braking from 62 km/h across the tarmac patch onto gravel and
    stopping in the zone earns a medal; a full brake from the tarmac locks the wheels and misses."""
    p = []
    A.drill_session("D08")
    s = _surface_stop_run(4)
    expect(p, "a controlled stop across the surface change earns a medal", s.get("passed") is True and s.get("tier") is not None,
           f"{s.get('tier')}: {s.get('reason')}")
    s = _surface_stop_run(4, full_brake_at=125)
    expect(p, "a locked-wheel stop misses", s.get("passed") is False, s.get("reason"))
    A.end_session("D08")
    return p


def _fwd_exit_run(throttle_at=110, throttle=0.6):
    """E02: 64 km/h, a 7 m full-brake pulse from 73 m, 0.12 throttle, then `throttle` from `throttle_at` metres
    (None: hold 46 km/h instead, barely touching the throttle), on C02's line."""
    import lines as L
    shifted = []

    def on_tick(_kmh, _to_go):
        if not shifted:
            shifted.append(1)
            return A.shift_to(2)

    def pedals(v, trav):
        if trav < 73:
            return (max(0.0, min(1.0, 0.3 + (64 - v) * 0.1)), 0.0)
        if trav < 80:
            return (0.0, 1.0)
        if throttle_at is None:
            return (max(0.05, min(1.0, 0.3 + (46 - v) * 0.1)), 0.0)
        return (0.12, 0.0) if trav < throttle_at else (throttle, 0.0)
    return A.course_run("E02", L.bmp_left(C02_LINE), gearbox="sequential", on_tick=on_tick, pedals=pedals, kmh=80,
                        max_throttle=1.0, timeout=40, stop_within=0.5)


@scenario
def fwdexit():
    """E02 on the BMP downhill left (Covet Gravel Rally): a brake pulse to rotate, then throttle from the apex
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
    page = A.wait_for(lambda: ui("return document.querySelectorAll('.ra-pause-page .ra-card').length"), len(A.drills()))
    expect(p, "Exercises lists every drill", page == len(A.drills()), page)
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
    """Car events on the BMP straight: a handbrake spin, a grass excursion and a puncture are detected."""
    p = []
    A.reload_mod(ui_too=False)
    A.fresh_sampler()
    A.choose("B02")  # ends when the car stops; checks spin and staying on the road
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

    # Steering off the road depends on the car's path; start the run on the verge instead
    # (survey.py surfaces: grass 8 m left of the road, 20 m along from B01's spot).
    sp = A.drill("B01")["environment"]["spawn"]
    A.place(sp["pos"], sp["dir"], ahead=20, side=-8)
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
    A.realistic()
    lua("extensions.rallyAcademy.useVenueStart() return 1")  # forget the starts this marked (one on the verge)
    A.clear_progress("B02")
    return p


@scenario
def goto():
    """Go to drill: E08 loads Utah in the gravel Covet; B01 then brings back West Coast USA (slow: 2 map loads)."""
    p = []
    A.choose("E08")
    lua("extensions.rallyAcademy.goToDrill() return 1")
    expect(p, "E08 loads Utah with the Covet Gravel Rally", A.wait_level("utah", "rally_gravel"))
    s = A.debug_state()
    expect(p, "E08 is selected and the car placed", s.get("selected") == "E08", s.get("reason"))
    A.choose("B01")
    lua("extensions.rallyAcademy.goToDrill() return 1")
    expect(p, "B01 brings back West Coast USA with the Student Driver", A.wait_level("west_coast_usa", "student_driver"))
    return p


@scenario
def mainmenu():
    """From the main menu: More... > Rally Academy > A04 > Start drill lands in the drill (slow: map load).
    Leaves West Coast USA loaded, so the driving scenarios can follow."""
    p = []
    if A.debug_state().get("level") != "unknown":
        lua("returnToMainMenu() return 1")
        t0 = time.time()
        while time.time() - t0 < 120 and (str(A.safe(lua, "return tostring(getCurrentLevelIdentifier())")) not in ("nil", "<GameError>")
                                          or A.safe(ui, "return location.hash") != "#/menu"):
            time.sleep(3)
        time.sleep(3)
    lua("ui_router.navigate('menu.rallyAcademy') return 1")
    cards = A.wait_for(lambda: ui("return document.querySelectorAll('.ra-card').length"), len(A.drills()), timeout=20)
    expect(p, "Academy screen opens from the main menu", cards == len(A.drills()), cards)
    ui("var c=Array.from(document.querySelectorAll('.ra-card')).find(function(x){return x.innerText.indexOf('A04')===0}); c.click(); return 1")
    time.sleep(1)
    ui("var b=Array.from(document.querySelectorAll('.ra-details button')).find(function(x){return /Start drill/.test(x.textContent)}); b.click(); return 1")
    expect(p, "Start drill loads West Coast USA in the drill car", A.wait_level("west_coast_usa", "student_driver"))
    route = A.wait_for(lambda: ui("return location.hash"), "#/play")
    expect(p, "the menu gets out of the way (game view)", route == "#/play", route)
    expect(p, "the HUD panel is up", A.wait_panel())
    return p


@scenario
def fit():
    """Venue fit test: B01 fits its straight, not facing the barrier; B05 fits the BMP dirt arena."""
    import fit as F
    p = []
    sp = A.drill("B01")["environment"]["spawn"]
    r = F.fit("B01", sp["pos"], sp["dir"])
    expect(p, "B01 fits its own straight", r["fits"], r["problems"] or r["notes"])
    sideways = {"x": sp["dir"]["y"], "y": -sp["dir"]["x"]}  # turned to face the barrier ~8 m away
    r = F.fit("B01", sp["pos"], sideways)
    expect(p, "B01 facing the barrier does not fit", not r["fits"], r["problems"])
    arena = A.drill("A01")["environment"]["spawn"]  # BMP dirt arena
    r = F.fit("B05", arena["pos"], arena["dir"])
    expect(p, "B05's circle fits the dirt arena", r["fits"], r["problems"] or r["notes"])
    return p

