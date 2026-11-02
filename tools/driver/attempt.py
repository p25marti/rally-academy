"""One attempt at a drill by the skill runner (docs/DRIVER.md, build plan step 2), from a controlled start.

    python tools/driver/attempt.py C08 [--surface gravel|asphalt|snow|all] [-n 10] [--fast] [--vary] [--card-dials]
    python tools/driver/attempt.py restore   # after a crashed or interrupted run (also tune.py's)
    python tools/driver/attempt.py line C08  # the line the card ships for the drill, worked out again (lines.py)

The runner (the mod's vehicle extension rallyAcademy/driver, which Watch AI also uses: ADR 0015) drives the technique
card's phases inside the car; this sets up each attempt the way tape.py does (physics stopped, Retry, runner loaded,
physics resumed), waits for the grade and prints it with the runner's report. Attempts count as the drill's attempts;
the drill's progress is put back afterwards, as in the scenarios. The game needs the mod linked (dev.py link).

The card, its line and the tuned dials ship with the mod (mod/gameplay/rallyAcademy/techniques/). The dials are the
card's starting values, replaced by the tuned ones in <card>-<surface>.json when tune.py has written them
(--card-dials ignores those). --vary starts each attempt differently: the approach speed within 5 km/h
of its dial and the car up to 1 m to either side of the venue start (VARY), as stage 1 tunes and is accepted.
"""
import argparse
import contextlib
import json
import math
import random
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "ingame"))
sys.path.insert(0, str(HERE))
sys.stdout.reconfigure(encoding="utf-8")

TECHNIQUES = HERE.parent.parent / "mod" / "gameplay" / "rallyAcademy" / "techniques"
CARDS = DIALS = TECHNIQUES
VARY = {"kmh": 5.0, "side": 1.0}  # the spread of varied starts (docs/DRIVER.md, Training)
TIERS = {"bronze": 1, "silver": 2, "gold": 3}
SURFACES = ("gravel", "asphalt", "snow")

# The drills the runner can drive, and their technique card (which holds the line it follows, in the course frame).
DRILLS = {"C08": "scandinavian_flick"}


def card(name):
    return json.loads((CARDS / f"{name}.json").read_text(encoding="utf-8"))


def dial_specs(c):
    """{name: [min, max, start]} for every dial on the card."""
    return {name: spec for phase in c["phases"] for name, spec in phase.get("dials", {}).items()}


def tuned_path(c, surface):
    return DIALS / f"{c['id']}-{surface}.json"


def dials(c, surface="gravel", overrides=None, tuned=True, from_file=None):
    """The card's starting dial values, with the surface's adjustments, then the tuned values (if any, or those in
    `from_file`), then `overrides`."""
    out = {name: spec[2] for name, spec in dial_specs(c).items()}
    out.update(c.get("surfaces", {}).get(surface, {}))
    path = Path(from_file) if from_file else tuned_path(c, surface)
    if (tuned or from_file) and path.exists():
        out.update(json.loads(path.read_text(encoding="utf-8"))["dials"])
    out.update(overrides or {})
    return out


def varied_start(rng, spread=VARY):
    """A start offset: approach speed (km/h) and sideways (m, + to the right)."""
    return {"kmh": round(rng.uniform(-spread["kmh"], spread["kmh"]), 2),
            "side": round(rng.uniform(-spread["side"], spread["side"]), 2)}


def score(graded, report):
    """One number for the optimiser: the medal (0 for a miss, 1-3), plus two margins worth up to 0.45 each, so they
    never add up to a medal: how far the rear slide got towards 20 degrees, and the exit speed towards 50 km/h. A spin
    costs a point."""
    medal = TIERS.get(graded.get("tier"), 1) if graded.get("passed") else 0
    slip = max(0.0, min(report.get("maxSlip") or 0.0, 20.0)) / 20.0
    exit_kmh = max(0.0, min(report.get("exitKmh") or 0.0, 50.0)) / 50.0
    return round(medal + 0.45 * slip + 0.45 * exit_kmh - (1.0 if report.get("spun") else 0.0), 3)


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


def tuned_line(base):
    """The line the dials were tuned on, worked out from the scenarios' corner line (as scenarios._flick_run): what
    the card ships as lines.<drill>."""
    import lines as L  # noqa: PLC0415
    import scenarios as S  # noqa: PLC0415
    assert base == "C08", base
    return [[round(x, 2), round(y, 2)] for x, y in L.bmp_left({**S.C02_LINE, "DR1181_3": 0.5})]


def course(drill_id):
    """World path for the runner (the card's line for the drill), and the distances along it of the Flick and Exit
    gates. The mod lays it out the same way (technique.lua's config)."""
    import academy as A  # noqa: PLC0415
    base = drill_id.split("-")[0]
    local = card(DRILLS[base])["lines"][base]
    path = resample(A.course_points(drill_id, local))
    gates = A.drill(drill_id)["assessment"]["course"]["gates"]
    flick, exit_ = A.course_points(drill_id, [(gates[0]["x"], gates[0]["y"]), (gates[-1]["x"], gates[-1]["y"])])
    return [list(map(lambda c: round(c, 3), p)) for p in path], along(path, flick), along(path, exit_)


def runner_code(cfg):
    """Load the mod's runner afresh (unloading first picks up edits) and configure it."""
    return ("extensions.unload('rallyAcademy_driver') extensions.load('rallyAcademy/driver') "
            f"extensions.rallyAcademy_driver.configure({lua_literal(cfg)})")


# Switch the runner off and let go of the controls.
_STOP = ("if extensions.rallyAcademy_driver then extensions.rallyAcademy_driver.stop() end "
         "for _, n in ipairs({'throttle', 'brake', 'steering', 'parkingbrake'}) do input.event(n, 0, 2) end")


def drill_id_for(base, surface):
    return base if surface == "gravel" else f"{base}-{surface}"


def car(code):
    """Queue Lua in the player's car: one round trip and no reply (game.vlua waits 1.2 s to read one). Commands run on
    the car's next frames in the order sent, also while physics is stopped."""
    from game import lua  # noqa: PLC0415
    assert "]==]" not in code
    lua(f"be:getPlayerVehicle(0):queueLuaCommand([==[{code}]==]) return 1")


# Move the car `side` m to its right, keeping its heading, the way Retry places it (spawn.safeTeleport, with a repair).
_SIDESTEP = ("local v = be:getPlayerVehicle(0) local p = v:getPosition() "
             "local f = vec3(v:getDirectionVector()):normalized() local u = vec3(v:getDirectionVectorUp()):normalized() "
             "spawn.safeTeleport(v, p + f:cross(u) * %.3f, quatFromDir(f, u), nil, nil, nil, nil, true) return 1")


def attempt(drill_id, cfg, start=None, timeout=60):
    """One graded attempt with the runner configured by `cfg`, from the venue start offset by `start` (see
    varied_start). Returns (graded, report). The runner hands its report to GE Lua (raDriverReport) when it has
    stopped the car, so nothing waits on the car's slow replies."""
    import academy as A  # noqa: PLC0415
    from game import lua  # noqa: PLC0415

    car(_STOP)
    lua("raDriverReport = nil be:setPhysicsRunning(false) return 1")
    try:
        A.click("Retry")
        time.sleep(0.8)
        if start and start.get("side"):
            lua(_SIDESTEP % start["side"])
            time.sleep(0.3)
        if start and start.get("kmh"):
            cfg = {**cfg, "dials": {**cfg["dials"], "approachKmh": cfg["dials"]["approachKmh"] + start["kmh"]}}
        car(runner_code(cfg))
        time.sleep(0.2)
    finally:
        lua("be:setPhysicsRunning(true) return 1")
    t0, report = time.time(), None
    while time.time() - t0 < timeout:
        time.sleep(0.25)
        out = lua("return raDriverReport or ''")
        if out:
            report = json.loads(out)
            break
    graded = A.debug_state()
    t1 = time.time()
    while graded.get("phase") not in ("scored", "review") and time.time() - t1 < 5:
        time.sleep(0.2)
        graded = A.debug_state()
    car(_STOP)
    if report is None:
        report = {"timedOut": True}
    return ({"passed": graded.get("passed") is True, "tier": graded.get("tier"), "reason": graded.get("reason"),
             "time": round(graded.get("lastTime") or 0, 2)}, report)


# A drill session saves the drill's progress first, so `attempt.py restore` can put it back after a crashed run.
SESSIONS = HERE / "logs"


@contextlib.contextmanager
def session(drill_id):
    """academy.drill_session ... end_session, with the progress from before kept in logs/session-<drill>.json until
    the session ends cleanly."""
    import academy as A  # noqa: PLC0415
    A.drill_session(drill_id)
    SESSIONS.mkdir(exist_ok=True)
    saved = SESSIONS / f"session-{drill_id}.json"
    if not saved.exists():  # an earlier crashed session's file holds the older, true progress: keep it
        saved.write_text(json.dumps({"drill": drill_id, "progress": (A._FOUND or {}).get(drill_id)}), encoding="utf-8")
    try:
        yield
    finally:
        A.end_session(drill_id)
        saved.unlink(missing_ok=True)


def restore():
    """After a crashed run: normal mode, the runner off, and every unfinished session's drill progress and settings
    put back."""
    import academy as A  # noqa: PLC0415
    import fast  # noqa: PLC0415
    from game import lua  # noqa: PLC0415
    fast.restore()
    lua("be:setPhysicsRunning(true) return 1")
    car(_STOP)
    for saved in sorted(SESSIONS.glob("session-*.json")):
        s = json.loads(saved.read_text(encoding="utf-8"))
        lua(f"return tostring(extensions.rallyAcademy.devSetProgress({json.dumps(s['drill'])}, "
            f"{A.lua_value(s['progress'])}))")
        print(f"put back {s['drill']}'s progress")
        saved.unlink()
    lua("extensions.rallyAcademy.setAutoRetry(true) extensions.rallyAcademy.devKeepRunsPaused(false) return 1")
    A.realistic()
    print("restored: normal mode, runner off, session settings and progress put back")


def config(c, drill_id, surface, overrides=None, tuned=True, from_file=None):
    """The runner's configuration for one drill and surface (needs the drill selected: course() reads the game)."""
    path, flick_s, exit_s = course(drill_id)
    return {"dials": dials(c, surface, overrides, tuned, from_file), "limits": c["humanLimits"], "path": path,
            "flickS": round(flick_s, 2), "exitS": round(exit_s, 2)}


def line(drill_id, i, n, graded, report, start=None):
    verdict = graded["tier"] or ("pass" if graded["passed"] else "MISS")
    at = f" start {start['kmh']:+.1f} km/h {start['side']:+.2f} m" if start else ""
    return (f"  {drill_id} {i}/{n}:{at} {verdict:6s} score {score(graded, report):5.2f}  slip {report.get('maxSlip')} "
            f"exit {report.get('exitKmh')} km/h  {phase_times(report)}  {'' if graded['passed'] else graded['reason']}")


def run(base, surfaces, n, fast_mode=False, overrides=None, vary=False, tuned=True, seed=None, from_file=None,
        spread=VARY):
    import fast  # noqa: PLC0415
    c = card(DRILLS[base])
    rng = random.Random(seed)
    results = {}
    for surface in surfaces:
        drill_id = drill_id_for(base, surface)
        with session(drill_id):
            cfg = config(c, drill_id, surface, overrides, tuned, from_file)
            source = from_file or ("tuned" if tuned and tuned_path(c, surface).exists() else "card")
            print(f"{drill_id}: {source} dials", flush=True)
            passes = 0
            with fast.fast() if fast_mode else contextlib.nullcontext():
                for i in range(n):
                    start = varied_start(rng, spread) if vary else None
                    graded, report = attempt(drill_id, cfg, start)
                    passes += graded["passed"]
                    print(line(drill_id, i + 1, n, graded, report, start), flush=True)
            results[drill_id] = passes
            print(f"{drill_id}: {passes}/{n} passed{' (fast)' if fast_mode else ''}{' (varied starts)' if vary else ''}",
                  flush=True)
    return results


def main():
    if sys.argv[1:] == ["restore"]:
        restore()
        return
    if sys.argv[1:2] == ["line"]:
        print(json.dumps(tuned_line(sys.argv[2])))
        return
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("drill", choices=sorted(DRILLS))
    ap.add_argument("--surface", default="gravel", choices=[*SURFACES, "all"])
    ap.add_argument("-n", type=int, default=5, help="attempts per surface")
    ap.add_argument("--fast", action="store_true", help="deterministic mode at ~5x (fast.py)")
    ap.add_argument("--dial", action="append", default=[], metavar="NAME=VALUE", help="override a dial")
    ap.add_argument("--vary", action="store_true", help="varied starts (5 km/h and 1 m sideways either way)")
    ap.add_argument("--card-dials", action="store_true", help="the card's starting dials, not the tuned ones")
    ap.add_argument("--seed", type=int, default=None, help="for --vary: the same seed gives the same starts")
    ap.add_argument("--spread", default=f"{VARY['kmh']:g},{VARY['side']:g}", metavar="KMH,M",
                    help="for --vary: the most the start varies (default %(default)s)")
    ap.add_argument("--dials", metavar="FILE", help="dials from a JSON file ({\"dials\": {...}}), e.g. to compare")
    args = ap.parse_args()
    overrides = {k: float(v) for k, v in (d.split("=", 1) for d in args.dial)}
    surfaces = SURFACES if args.surface == "all" else (args.surface,)
    kmh, side = (float(v) for v in args.spread.split(","))
    run(args.drill, surfaces, args.n, args.fast, overrides, args.vary, not args.card_dials, args.seed, args.dials,
        {"kmh": kmh, "side": side})


if __name__ == "__main__":
    main()
