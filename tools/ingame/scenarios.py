"""In-game scenarios: `python tools/dev.py ingame <name>` with BeamNG running and the mod
linked (dev.py link). Each scenario drives the real game through its MCP server, prints
what happened and returns the problems it found (empty = all as expected).

Braking scenarios use the BMP start straight on West Coast USA in the Covet Student
Driver (B01's venue spot). They record attempts, then remove them from your progress.
"""
import json
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
    """Mark the start at B01's spawn (BMP start straight); needs West Coast USA loaded."""
    sp = A.drill("B01")["environment"]["spawn"]
    if A.debug_state().get("level") != "west_coast_usa":
        raise RuntimeError("load West Coast USA first (e.g. Go to drill on B01)")
    A.place(sp["pos"], sp["dir"])
    A.click("Mark start")
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
    A.reload_mod(ui_too=False)
    A.fresh_sampler()
    A.choose("A01")
    if A.debug_state().get("level") != "west_coast_usa":
        raise RuntimeError("load West Coast USA first (e.g. Go to drill on A01)")
    lua("extensions.rallyAcademy.useVenueStart() extensions.rallyAcademy.setAutoRetry(false) return 1")
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
    """Threshold braking into a stop zone: clean PASS, late-braking MISS, full-brake MISS."""
    p = []
    A.reload_mod(ui_too=False)
    A.fresh_sampler()
    A.choose("B01")
    on_straight()
    A.braking_run(70, lambda k, t: A.eased_brake(k))  # calibration: where a clean stop ends
    A.click("Mark stop zone")
    s = precise(lambda: A.braking_run(70, lambda k, t: A.eased_brake(k)))
    expect(p, "clean stop passes", s.get("passed") is True, A.grade_lines())
    s = A.braking_run(70, lambda k, t: 0 if t < 0.9 else A.eased_brake(k))
    expect(p, "braking 0.9 s late misses", s.get("passed") is False, A.grade_lines())
    s = A.braking_run(70, lambda k, t: 1.0)
    expect(p, "full brake misses (lockup)", s.get("passed") is False, A.grade_lines())
    A.realistic()
    A.clear_progress("B01")
    return p


@scenario
def a04():
    """A04 on its course (BMP run-up, three gates 25 m apart): a steady 30 km/h earns a medal; 40 km/h at
    gate 3 misses. Needs West Coast USA."""
    p = []
    A.reload_mod(ui_too=False)
    A.fresh_sampler()
    A.choose("A04")
    if A.debug_state().get("level") != "west_coast_usa":
        raise RuntimeError("load West Coast USA first (e.g. Go to drill on A04)")
    lua("extensions.rallyAcademy.useVenueStart() extensions.rallyAcademy.setAutoRetry(false) return 1")
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
    lua("extensions.rallyAcademy.setAutoRetry(true) return 1")
    A.realistic()
    A.clear_progress("A04")
    return p


@scenario
def stops():
    """A05 on its course (BMP dirt arena, stop line 60 m ahead) and B02 lockup recovery (BMP run-up):
    one PASS and one MISS each."""
    p = []
    A.reload_mod(ui_too=False)
    A.fresh_sampler()
    A.choose("A05")
    if A.debug_state().get("level") != "west_coast_usa":
        raise RuntimeError("load West Coast USA first (e.g. Go to drill on A05)")
    lua("extensions.rallyAcademy.useVenueStart() extensions.rallyAcademy.setAutoRetry(false) return 1")
    front = 1.81  # Covet: front bumper ahead of the car's position (catalogued footprint)

    def line_run(before_m):
        return A.course_run("A05", [(0, 0), (0, 60 - front - before_m)], kmh=44, decel=3.5, max_throttle=0.7)
    s = precise(lambda: line_run(1.0))
    expect(p, "A05 stop just before the line passes", s.get("passed") is True, A.grade_lines())
    expect(p, "A05 stop past the line misses", line_run(-1.0).get("passed") is False, A.grade_lines())
    lua("extensions.rallyAcademy.setAutoRetry(true) return 1")
    A.choose("B02")
    on_straight()
    s = A.braking_run(62, lambda k, t: 1.0 if t < 0.6 else A.eased_brake(k))
    expect(p, "B02 lock then release passes", s.get("passed") is True, A.grade_lines())
    s = A.braking_run(62, lambda k, t: 1.0)
    expect(p, "B02 held lock misses", s.get("passed") is False, A.grade_lines())
    A.realistic()
    A.clear_progress("A05", "B02")
    return p


@scenario
def launch():
    """A02 on its course (BMP start straight, from the venue start): a flat-out launch through the
    40 km/h gate earns a medal (the run ends at the gate); 34 km/h at the gate misses. Needs West Coast USA."""
    p = []
    A.reload_mod(ui_too=False)
    A.fresh_sampler()
    A.choose("A02")
    if A.debug_state().get("level") != "west_coast_usa":
        raise RuntimeError("load West Coast USA first (e.g. Go to drill on A02)")
    lua("extensions.rallyAcademy.useVenueStart() extensions.rallyAcademy.setAutoRetry(false) return 1")
    s = A.debug_state()
    expect(p, "the course is laid out at the venue", s.get("hasCourse") and s.get("usingVenueStart"), s.get("reason"))
    line = [(0, 0), (0, 80)]  # down the straight's centre line; the run ends at the gate (60 m)
    s = A.course_run("A02", line, kmh=48, decel=3.0, max_throttle=1.0)
    expect(p, "a flat-out launch passes with a medal", s.get("passed") is True and s.get("tier") in ("gold", "silver"),
           f"{s.get('tier')}: {s.get('reason')} {s.get('nextTier') or ''}")
    s = A.course_run("A02", line, kmh=34, decel=3.0, max_throttle=0.6)
    expect(p, "34 km/h at the 40 km/h gate misses", s.get("passed") is False and "too slow" in str(s.get("reason")),
           s.get("reason"))
    lua("extensions.rallyAcademy.setAutoRetry(true) return 1")
    A.realistic()
    A.clear_progress("A02")
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
    A.reload_mod(ui_too=False)
    A.fresh_sampler()
    A.choose("A03")
    if A.debug_state().get("level") != "west_coast_usa":
        raise RuntimeError("load West Coast USA first (e.g. Go to drill on A03)")
    lua("extensions.rallyAcademy.useVenueStart() extensions.rallyAcademy.setAutoRetry(false) return 1")
    line = [(0, 0), (0, 155)]
    kw = dict(gearbox="sequential", kmh=62, decel=2.2, max_throttle=0.9)
    s = A.course_run("A03", line, on_tick=_gear_plan(2), **kw)
    expect(p, "3rd to 2nd into the box passes with a medal", s.get("passed") is True and s.get("tier") in ("gold", "silver"),
           f"{s.get('tier')}: {s.get('reason')} {s.get('nextTier') or ''}")
    s = A.course_run("A03", line, on_tick=_gear_plan(1), **kw)
    expect(p, "3rd straight to 1st misses", s.get("passed") is False and "Skipped from 3rd to 1st" in str(s.get("reason")),
           s.get("reason"))
    lua("extensions.rallyAcademy.setAutoRetry(true) return 1")
    A.realistic()
    A.clear_progress("A03")
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
    A.click("Mark start")
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

