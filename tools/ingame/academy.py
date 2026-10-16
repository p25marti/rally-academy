"""Rally Academy helpers on top of game.py: the HUD panel, drills, scripted runs."""
import json
import time
from pathlib import Path

from game import call, inp, lua, lua_json, safe, state, ui, vlua

ROOT = Path(__file__).resolve().parents[2]
EXERCISES = ROOT / "mod" / "gameplay" / "rallyAcademy" / "exercises.json"
PANEL = ".rally-academy-app"


def drills():
    return json.loads(EXERCISES.read_text(encoding="utf-8"))["exercises"]


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
        n = safe(ui, f"return document.querySelectorAll('{PANEL} option').length")
        if isinstance(n, int) and n > 0:
            return True
    return False


def hud():
    return ui(f"var p=document.querySelector('{PANEL}'); if(!p) return 'NO PANEL'; "
              "return Array.from(p.querySelectorAll('.ra-grade div, .ra-reason')).map(function(e){return e.textContent.trim()}).join(' | ')")


def grade_lines():
    return ui(f"return Array.from(document.querySelectorAll('{PANEL} .ra-grade div')).map(function(d){{return d.textContent.trim()}})")


def choose(drill_id):
    lua(f"extensions.rallyAcademy.select({json.dumps(drill_id)}) return 1")
    time.sleep(1.0)


def click(label):
    """Click a HUD panel button whose text contains `label`."""
    pressed = ui(f"var b=Array.from(document.querySelectorAll('{PANEL} button')).filter(function(x){{"
                 f"return x.textContent.indexOf({json.dumps(label)})>=0}})[0]; if(!b) return 'NOT FOUND'; b.click(); return b.textContent.trim()")
    time.sleep(0.6)
    if pressed == "NOT FOUND":
        raise RuntimeError(f"no panel button {label!r}")
    return pressed


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


def wait_graded(timeout=20):
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(0.25)
        s = safe(debug_state)
        if isinstance(s, dict) and s.get("phase") in ("scored", "review"):
            break
    time.sleep(0.8)
    return debug_state()


def braking_run(target_kmh, brake, throttle=1.0, max_s=25):
    """Retry, accelerate to `target_kmh`, then brake with brake(kmh, seconds_since_braking).
    Below 4 km/h the brake is released for the handbrake (arcade reverses on a held brake)."""
    click("Retry")
    time.sleep(1.0)
    arcade()
    inp("parkingbrake", 0)
    inp("brake", 0)
    t0 = time.time()
    while time.time() - t0 < 25:
        _, spd = state()
        if spd * 3.6 >= target_kmh:
            break
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


def save_fixture(name):
    """Save the last run record to <user folder>/settings/rallyAcademy/fixtures/<name>.json."""
    return lua(f"return tostring(extensions.rallyAcademy.saveLastRun('settings/rallyAcademy/fixtures/{name}.json'))")


def clear_progress(*drill_ids):
    for d in drill_ids:
        lua(f"return tostring(extensions.rallyAcademy.devClearProgress({json.dumps(d)}))")
