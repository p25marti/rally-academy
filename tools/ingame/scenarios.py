"""In-game scenarios: `python tools/dev.py ingame <name>` with BeamNG running and the mod
linked (dev.py link). Each scenario drives the real game through its MCP server, prints
what happened and returns the problems it found (empty = all as expected).

Braking scenarios use the BMP start straight on West Coast USA in the Covet Student
Driver (B01's venue spot). They record attempts, then remove them from your progress.
"""
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
    A.choose("A01")
    title = A.wait_for(lambda: ui(f"var p=document.querySelector('{A.PANEL} .ra-instructions'); return p ? 'shown' : 'missing'"), "shown")
    expect(p, "panel renders a drill without grading rules (A01)", title == "shown", title)
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
    """Gates: mark three gates down the straight, then 30 km/h PASS and 38 km/h MISS."""
    p = []
    A.reload_mod(ui_too=False)
    A.fresh_sampler()
    A.choose("A04")
    sp = on_straight()
    if A.debug_state().get("gateCount"):
        A.click("Clear gates")
    for d in (30, 55, 80):
        A.place(sp["pos"], sp["dir"], ahead=d)
        A.click("+ Gate")
    expect(p, "three gates marked", A.debug_state().get("gateCount") == 3)

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
    expect(p, "steady 30 km/h passes", s.get("passed") is True, A.grade_lines())
    s = hold(lambda d: 30 if d < 60 else 40)
    expect(p, "too fast at gate 3 misses", s.get("passed") is False, A.grade_lines())
    A.realistic()
    A.clear_progress("A04")
    return p


@scenario
def stops():
    """A05 stop line and B02 lockup recovery: one PASS and one MISS each."""
    p = []
    A.reload_mod(ui_too=False)
    A.fresh_sampler()
    A.choose("A05")
    sp = on_straight()
    A.braking_run(42, lambda k, t: A.eased_brake(k))
    pos, _ = state()
    A.place({"x": pos[0], "y": pos[1], "z": pos[2]}, sp["dir"], ahead=1.0)  # line 1 m past the stop
    A.click("Mark stop line")
    s = precise(lambda: A.braking_run(42, lambda k, t: A.eased_brake(k)))
    expect(p, "A05 eased stop passes", s.get("passed") is True, A.grade_lines())
    expect(p, "A05 late braking misses", A.braking_run(42, lambda k, t: 0 if t < 0.5 else A.eased_brake(k)).get("passed") is False, A.grade_lines())
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
    """A02: a 60% throttle launch to 42 km/h with an (arcade) 1-2 shift passes."""
    p = []
    A.reload_mod(ui_too=False)
    A.fresh_sampler()
    A.choose("A02")
    on_straight()
    s = A.braking_run(42, lambda k, t: A.eased_brake(k), throttle=0.6)
    expect(p, "clean launch passes", s.get("passed") is True, A.grade_lines())
    A.realistic()
    A.clear_progress("A02")
    return p
