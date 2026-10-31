"""Input tapes: record a drill's scripted pass as the driver's inputs, frame by frame, and check that replaying them
passes again. python tools/ingame/tape.py record C08 [--surface asphalt|all] [--checks 5] [--tries 5]
                     python tools/ingame/tape.py check C08 [--surface ...] [--checks 5]
                     python tools/ingame/tape.py play C08 [--surface ...]

A tape replays the same run only from the same start, so recording and replaying both start alike: physics
stopped, Retry, the tape extension loaded into the car, physics resumed; the extension then holds the car still
for HOLD frames, selects the gear on frame SHIFT_AT, and from there records (or plays) throttle, brake, handbrake,
steering and gear every frame by simulation time. Run to run, replays of one tape stay within about 0.4 m through
C08's corner (IDEAS: Demo cutscenes). A recorded tape is kept only when every check replay passes too.

Tapes are written to mod/gameplay/rallyAcademy/tapes/<drill id>.json. The runs count as attempts; the drills'
progress is put back afterwards, as in the scenarios.
"""
import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8")

import academy as A  # noqa: E402
import scenarios as S  # noqa: E402
from game import lua, vlua  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
TAPES = ROOT / "mod" / "gameplay" / "rallyAcademy" / "tapes"
HOLD, SHIFT_AT = 80, 20  # frames
TAPE_VERSION = 1

# The car side: one extension that records or plays. Rows are {t, throttle, brake, handbrake, steering, gear}.
_TAPE_LUA = r'''
package.loaded['raTape'] = nil
package.preload['raTape'] = function()
  local M = {}
  local HOLD, SHIFT_AT, mode, gear = %d, %d, '%s', %d
  local rows = {%s}
  local n, t, i, out, done, lastGear = 0, 0, 1, {}, false, nil
  local function ev(k, v) input.event(k, v, 2) end
  local function inputs(thr, brk, hb, st) ev('throttle', thr) ev('brake', brk) ev('parkingbrake', hb) ev('steering', st) end
  function M.updateGFX(dt)
    if dt <= 0 or done then return end -- physics stopped
    n = n + 1
    if n <= HOLD then
      inputs(0, 0, 0, 0)
      if n == SHIFT_AT and gear > 0 then controller.mainController.shiftToGearIndex(gear) end
      return
    end
    t = t + dt
    local e = electrics.values
    if mode == 'record' then
      out[#out + 1] = string.format('[%%.4f,%%.3f,%%.3f,%%.3f,%%.4f,%%d,%%.2f]', t, e.throttle_input or 0, e.brake_input or 0,
        e.parkingbrake_input or 0, e.steering_input or 0, e.gearIndex or 0, obj:getVelocity():length())
      return
    end
    if i >= #rows then -- the tape has ended: brake to a stop, then the handbrake
      local slow = obj:getVelocity():length() < 1
      inputs(0, slow and 0 or 0.6, slow and 1 or 0, 0)
      return
    end
    while i < #rows and rows[i + 1][1] <= t do i = i + 1 end
    local r = rows[i]
    inputs(r[2], r[3], r[4], r[5])
    if r[6] > 0 and r[6] ~= lastGear and r[6] ~= (e.gearIndex or 0) then controller.mainController.shiftToGearIndex(r[6]) end
    lastGear = r[6]
  end
  function M.state() return string.format('%%d %%.2f %%d', n, t, #out) end
  function M.stop() done = true return '[' .. table.concat(out, ',') .. ']' end
  return M
end
extensions.unload('raTape') extensions.load('raTape')
return 1
'''
_ZERO = ("extensions.unload('raTape') for _, n in ipairs({'throttle', 'brake', 'steering', 'parkingbrake'}) do "
         "input.event(n, 0, 2) end return 1")


def _vget(code):
    """Vehicle Lua answers asynchronously: ask, wait, ask again."""
    vlua(code)
    time.sleep(1.0)
    return vlua(code)


def _start(mode, gear, rows=()):
    """A course_run `start`: Retry with physics stopped, load the tape extension, resume, wait out the hold."""
    code = _TAPE_LUA % (HOLD, SHIFT_AT, mode, gear, ",".join("{%s}" % ",".join(str(v) for v in r) for r in rows))

    def start(gearbox):
        vlua(_ZERO)
        lua("be:setPhysicsRunning(false) return 1")
        try:
            A.click("Retry")
            time.sleep(1.5)
            A.sequential() if gearbox == "sequential" else A.arcade()
            vlua(code)
            time.sleep(0.3)
        finally:
            lua("be:setPhysicsRunning(true) return 1")
        t0 = time.time()
        while time.time() - t0 < 15:
            time.sleep(0.5)
            if int(str(_vget("return extensions.raTape and extensions.raTape.state() or '0'")).split()[0]) > HOLD:
                return
        raise RuntimeError("the tape's hold didn't finish")
    return start


def _variant(drill_id):
    return drill_id.split("-", 1)[1] if "-" in drill_id else "gravel"


# How each drill is driven for its tape: (drill id, start) -> graded state. Uses the scenarios' medal techniques.
DRIVERS = {
    "C08": lambda d, start: S._flick_run(drill=d, start=start, **S.CORNER_ADAPT["C08"].get(_variant(d), {})),
}
GEAR = {"C08": 2}  # the gear selected during the hold (sequential box)


def _graded():
    s = A.debug_state()
    return {"passed": s.get("passed") is True, "tier": s.get("tier"), "time": round(s.get("lastTime") or 0, 2),
            "reason": s.get("reason")}


def _verdict(g):
    return f"{g['tier'] or ('pass' if g['passed'] else 'MISS')} {g['time']:.2f} s" + ("" if g["passed"] else f" ({g['reason']})")


def trim(rows, run_time, after=1.5):
    """Cut the tape `after` seconds past the drill's finish: the car's first movement plus the graded run time (the
    scripts keep driving towards their last point after that). Drops the speed column, which is only for this."""
    moving = next((r[0] for r in rows if r[6] > 0.5), 0)
    return [r[:6] for r in rows if r[0] <= moving + run_time + after]


def record_one(drill_id, base):
    """One scripted run on tape; returns (graded, rows)."""
    DRIVERS[base](drill_id, _start("record", GEAR[base]))
    g = _graded()
    rows = trim(json.loads(_vget("return extensions.raTape.stop()")), g["time"])
    vlua(_ZERO)
    return g, rows


def play_one(base, rows):
    """Replay a tape through the drill's course: the same start, then the tape drives; returns the graded state."""
    _start("play", GEAR[base], rows)("sequential")
    A.wait_graded(timeout=40)
    g = _graded()
    vlua(_ZERO)
    return g


def check(drill_id, base, rows, n):
    results = []
    for k in range(n):
        g = play_one(base, rows)
        results.append(g)
        print(f"    replay {k + 1}/{n}: {_verdict(g)}", flush=True)
    return results


def tape_path(drill_id):
    return TAPES / f"{drill_id}.json"


def save(drill_id, recorded, rows, results):
    TAPES.mkdir(parents=True, exist_ok=True)
    meta = {
        "version": TAPE_VERSION, "drill": drill_id, "game": lua("return tostring(beamng_versiond)"),
        "vehicle": A.drill(drill_id.split("-")[0])["vehicle"]["configPath"], "gearbox": "sequential",
        "hold": HOLD, "shiftAt": SHIFT_AT, "gear": GEAR[drill_id.split("-")[0]],
        "recorded": {k: recorded[k] for k in ("tier", "time")},
        "checks": [{k: g[k] for k in ("passed", "tier", "time")} for g in results],
        "columns": ["t", "throttle", "brake", "handbrake", "steering", "gear"],
    }
    body = ",\n".join("    " + json.dumps(r, separators=(",", ":")) for r in rows)
    text = json.dumps(meta, indent=2)[:-2] + ',\n  "frames": [\n' + body + "\n  ]\n}\n"
    tape_path(drill_id).write_text(text, encoding="utf-8")
    return tape_path(drill_id)


def load(drill_id):
    return json.loads(tape_path(drill_id).read_text(encoding="utf-8"))["frames"]


def surfaces(base, which):
    ids = [sf["id"] for sf in (A.drill(base).get("surfaces") or [{"id": base}])]
    if which == "all":
        return ids
    return [base if which in (None, "gravel") else f"{base}-{which}"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["record", "check", "play"])
    ap.add_argument("drill", choices=sorted(DRIVERS))
    ap.add_argument("--surface", help="a variant (asphalt, snow) or all; default the base drill")
    ap.add_argument("--checks", type=int, default=5, help="replays that must all pass (default 5)")
    ap.add_argument("--tries", type=int, default=5, help="recordings to try until one keeps (default 5)")
    a = ap.parse_args()
    ids = surfaces(a.drill, a.surface)
    failed = []
    for d in ids:
        print(f"{d}:", flush=True)
        A.drill_session(d)
        lua("extensions.rallyAcademy.setAutoRetry(false) return 1")
        try:
            if a.command == "record":
                kept = False
                for k in range(a.tries):
                    g, rows = record_one(d, a.drill)
                    print(f"  recording {k + 1}: {_verdict(g)}, {len(rows)} frames", flush=True)
                    if not g["passed"]:
                        continue
                    results = check(d, a.drill, rows, a.checks)
                    if all(r["passed"] for r in results):
                        print(f"  kept: {save(d, g, rows, results).relative_to(ROOT)}", flush=True)
                        kept = True
                        break
                if not kept:
                    failed.append(d)
            elif a.command == "check":
                if not all(r["passed"] for r in check(d, a.drill, load(d), a.checks)):
                    failed.append(d)
            else:
                print(f"  {_verdict(play_one(a.drill, load(d)))}", flush=True)
        finally:
            A.end_session(d)
    if failed:
        print(f"no passing tape: {', '.join(failed)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
