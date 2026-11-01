"""One attempt at a drill by the skill runner (docs/DRIVER.md, build plan step 2), from a controlled start.

    python tools/driver/attempt.py C08 [--surface gravel|asphalt|snow|all] [-n 10] [--fast]

The runner (runner.lua) drives the technique card's phases inside the car; this sets up each attempt the way tape.py
does (physics stopped, Retry, runner loaded, physics resumed), waits for the grade and prints it with the runner's
report. Attempts count as the drill's attempts; the drill's progress is put back afterwards, as in the scenarios.
"""
import argparse
import contextlib
import json
import math
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "ingame"))
sys.path.insert(0, str(HERE))
sys.stdout.reconfigure(encoding="utf-8")

CARDS = HERE / "cards"
RUNNER = HERE / "runner.lua"
TIERS = {"bronze": 1, "silver": 2, "gold": 3}
SURFACES = ("gravel", "asphalt", "snow")

# The drills the runner can drive: the technique card, and the line it follows (course frame).
DRILLS = {"C08": "scandinavian_flick"}


def card(name):
    return json.loads((CARDS / f"{name}.json").read_text(encoding="utf-8"))


def dials(c, surface="gravel", overrides=None):
    """The card's starting dial values, with the surface's adjustments and then `overrides`."""
    out = {name: spec[2] for phase in c["phases"] for name, spec in phase.get("dials", {}).items()}
    out.update(c.get("surfaces", {}).get(surface, {}))
    out.update(overrides or {})
    return out


def score(graded, report):
    """One number for the optimiser: the medal (0 for a miss, 1-3), plus margins in [0, 1) each: how far the rear
    slide got towards 20 degrees, and the exit speed towards 50 km/h. A spin costs a point."""
    medal = TIERS.get(graded.get("tier"), 1) if graded.get("passed") else 0
    slip = max(0.0, min(report.get("maxSlip") or 0.0, 20.0)) / 20.0
    exit_kmh = max(0.0, min(report.get("exitKmh") or 0.0, 50.0)) / 50.0
    return round(medal + 0.5 * slip + 0.5 * exit_kmh - (1.0 if report.get("spun") else 0.0), 3)


def phase_times(report):
    """How long each phase lasted, e.g. 'feint 0.30 load_turn_in 0.25 catch 0.85'."""
    ph = report.get("phases") or []
    return " ".join(f"{a[0]} {b[1] - a[1]:.2f}" + (f" (ends: slip {b[2]:.0f}, yaw {b[3]:.0f}/s, turned {b[4]:.0f})" if len(b) > 4 else "")
                    for a, b in zip(ph, ph[1:]) if a[0] in ("feint", "load_turn_in", "catch"))


def lua_literal(v):
    """A Python value as a Lua literal (numbers, strings, bools, lists, dicts with string keys)."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(round(v, 4) if isinstance(v, float) else v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, (list, tuple)):
        return "{" + ",".join(lua_literal(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ",".join(f"[{json.dumps(k)}]={lua_literal(x)}" for k, x in v.items()) + "}"
    raise TypeError(type(v))


def resample(points, step=1.0):
    out = [points[0]]
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        n = max(1, int(math.dist((ax, ay), (bx, by)) / step))
        out += [(ax + (bx - ax) * k / n, ay + (by - ay) * k / n) for k in range(1, n + 1)]
    return out


def along(path, point):
    """Distance along `path` to the point of it nearest `point`."""
    i = min(range(len(path)), key=lambda j: math.dist(path[j], point))
    return sum(math.dist(a, b) for a, b in zip(path[:i], path[1:i + 1]))


def course(drill_id):
    """World path for the runner, and the distances along it of the Flick and Exit gates."""
    import academy as A  # noqa: PLC0415
    import lines as L  # noqa: PLC0415
    import scenarios as S  # noqa: PLC0415
    local = L.bmp_left({**S.C02_LINE, "DR1181_3": 0.5})  # as scenarios._flick_run
    path = resample(A.course_points(drill_id, local))
    gates = A.drill(drill_id)["assessment"]["course"]["gates"]
    flick, exit_ = A.course_points(drill_id, [(gates[0]["x"], gates[0]["y"]), (gates[-1]["x"], gates[-1]["y"])])
    return [list(map(lambda c: round(c, 3), p)) for p in path], along(path, flick), along(path, exit_)


def runner_code(cfg):
    src = RUNNER.read_text(encoding="utf-8")
    return ("package.loaded['raDriver'] = nil\n"
            f"package.preload['raDriver'] = function()\n{src}\nend\n"
            "extensions.unload('raDriver') extensions.load('raDriver')\n"
            f"extensions.raDriver.configure({lua_literal(cfg)})\n"
            "return 1")


_ZERO = ("extensions.unload('raDriver') for _, n in ipairs({'throttle', 'brake', 'steering', 'parkingbrake'}) do "
         "input.event(n, 0, 2) end return 1")


def drill_id_for(base, surface):
    return base if surface == "gravel" else f"{base}-{surface}"


def attempt(drill_id, cfg, timeout=60):
    """One graded attempt with the runner configured by `cfg`. Returns (graded, report)."""
    import academy as A  # noqa: PLC0415
    from game import lua, vlua  # noqa: PLC0415

    def vget(code):
        vlua(code)
        time.sleep(0.4)
        return vlua(code)

    vlua(_ZERO)
    lua("be:setPhysicsRunning(false) return 1")
    try:
        A.click("Retry")
        time.sleep(1.5)
        A.sequential()
        vlua(runner_code(cfg))
        time.sleep(0.3)
    finally:
        lua("be:setPhysicsRunning(true) return 1")
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(0.5)
        if str(vget("return extensions.raDriver and extensions.raDriver.state() or 'none'")).startswith("done"):
            break
    graded = A.wait_graded()
    report = json.loads(vget("return extensions.raDriver.report()") or "{}")
    vlua(_ZERO)
    return ({"passed": graded.get("passed") is True, "tier": graded.get("tier"), "reason": graded.get("reason"),
             "time": round(graded.get("lastTime") or 0, 2)}, report)


def run(base, surfaces, n, fast_mode=False, overrides=None):
    import academy as A  # noqa: PLC0415
    import fast  # noqa: PLC0415
    c = card(DRILLS[base])
    results = {}
    for surface in surfaces:
        drill_id = drill_id_for(base, surface)
        A.drill_session(drill_id)
        try:
            path, flick_s, exit_s = course(drill_id)
            cfg = {"dials": dials(c, surface, overrides), "limits": c["humanLimits"], "path": path,
                   "flickS": round(flick_s, 2), "exitS": round(exit_s, 2)}
            passes = 0
            with fast.fast() if fast_mode else contextlib.nullcontext():
                for i in range(n):
                    graded, report = attempt(drill_id, cfg)
                    passes += graded["passed"]
                    verdict = graded["tier"] or ("pass" if graded["passed"] else "MISS")
                    print(f"  {drill_id} {i + 1}/{n}: {verdict:6s} score {score(graded, report):5.2f}  "
                          f"slip {report.get('maxSlip')} exit {report.get('exitKmh')} km/h  {phase_times(report)}  "
                          f"{'' if graded['passed'] else graded['reason']}", flush=True)
            results[drill_id] = passes
            print(f"{drill_id}: {passes}/{n} passed{' (fast)' if fast_mode else ''}", flush=True)
        finally:
            A.end_session(drill_id)
    return results


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("drill", choices=sorted(DRILLS))
    ap.add_argument("--surface", default="gravel", choices=[*SURFACES, "all"])
    ap.add_argument("-n", type=int, default=5, help="attempts per surface")
    ap.add_argument("--fast", action="store_true", help="deterministic mode at ~5x (fast.py)")
    ap.add_argument("--dial", action="append", default=[], metavar="NAME=VALUE", help="override a dial")
    args = ap.parse_args()
    overrides = {k: float(v) for k, v in (d.split("=", 1) for d in args.dial)}
    surfaces = SURFACES if args.surface == "all" else (args.surface,)
    run(args.drill, surfaces, args.n, args.fast, overrides)


if __name__ == "__main__":
    main()
