"""Venue fit test: does a place actually work for a drill? Drives the drill's kind of run
there and judges it with the grading rules (no setup or progress is touched: the run is
recorded with extensions.rallyAcademy.devRecordStart/Stop).

  straight          scripted run to the drill's entry speed, then threshold braking: did it
                    stop within the drill's length, without hitting anything or leaving the
                    allowed surfaces?
  corner, hill,     the game's AI drives the section at a steady speed (drive_to): did it get
  crest, route      through cleanly?
  open              a steady circle at low speed: does it fit, on allowed ground?

Plus: was the car nudged when placed (the start spot isn't clear)? Used by `survey.py fit`.
"""
import json
import math
import time

import academy as A
import roads
from game import call, inp, lua, state

NUDGE_M = 1.0  # the game moves a car placed on something solid; more than this = start not clear


def entry_kmh(drill, default=50):
    for r in drill["assessment"].get("rules") or []:
        if r.get("type") == "entry_speed":
            return r["minKmh"] + 5
    return default


def path_length(samples):
    pts = [(s["x"], s["y"]) for s in samples if "x" in s]
    return sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))


def _straight(drill):
    target = entry_kmh(drill)
    A.arcade()
    inp("parkingbrake", 0)
    inp("brake", 0)
    t0 = time.time()
    while time.time() - t0 < 30 and state()[1] * 3.6 < target:
        inp("throttle", 1.0)
        time.sleep(0.05)
    inp("throttle", 0)
    t0 = time.time()
    while time.time() - t0 < 20:
        kmh = state()[1] * 3.6
        if kmh < 4:
            break
        inp("brake", A.eased_brake(kmh))
        time.sleep(0.04)
    inp("brake", 0)
    inp("parkingbrake", 1)
    return f"accelerated to {target} km/h and braked to a stop"


def _ai(to_node, to_pos, kmh, timeout):
    args = {"routeSpeed": kmh / 3.6, "routeSpeedMode": "limit", "aggression": 0.5, "avoidCars": "off"}
    args.update({"waypoint": to_node} if to_node else {"pos": to_pos})
    A.arcade()
    inp("parkingbrake", 0)
    call("drive_to", args)
    target = to_pos
    if to_node:
        target = json.loads(lua(f"local n = map.getMap().nodes[{json.dumps(to_node)}] "
                                "return jsonEncode(n and {x = n.pos.x, y = n.pos.y, z = n.pos.z} or {})")) or None
    t0, arrived = time.time(), False
    while time.time() - t0 < timeout:
        time.sleep(0.5)
        pos, spd = state()
        if target and math.dist(pos[:2], (target["x"], target["y"])) < 10:
            arrived = True
            break
    call("set_ai", {"mode": "disabled"})
    for _ in range(40):
        if state()[1] < 1:
            break
        inp("brake", 0.6)
        time.sleep(0.2)
    inp("brake", 0)
    inp("parkingbrake", 1)
    return arrived


def road_target(pos, direction, length):
    """The road node `length` metres along the road from pos, setting off the way we face."""
    data = json.loads(lua("""local m = map.getMap() local nodes, links = {}, {}
for name, n in pairs(m.nodes) do nodes[#nodes + 1] = {name, n.pos.x, n.pos.y, n.pos.z, n.radius or 0}
  for o, l in pairs(n.links or {}) do links[#links + 1] = {name, o, l.drivability or 1, 0} end end
return jsonEncode({nodes = nodes, links = links})"""))
    nodes = {n[0]: (n[1], n[2], n[3], n[4]) for n in data["nodes"]}
    adj = roads.build(nodes, data["links"])
    path = roads.follow(nodes, adj, roads.nearest(nodes, pos["x"], pos["y"]), math.atan2(direction["y"], direction["x"]), length)
    return path[-1] if len(path) > 1 else None


def _circle(area_m, seconds=24, kmh=20):
    A.arcade()
    inp("parkingbrake", 0)
    # 0.55 steering gave a ~17 m circle in the Covet; aim for ~80% of the drill's open area
    steer = max(0.15, min(0.6, 0.55 * 17 / (0.8 * area_m)))
    t0 = time.time()
    while time.time() - t0 < seconds:
        spd = state()[1] * 3.6
        inp("steering", steer)
        inp("throttle", max(0.0, min(0.6, 0.15 + 0.05 * (kmh - spd))))
        time.sleep(0.05)
    inp("throttle", 0)
    inp("steering", 0)
    for _ in range(30):
        if state()[1] < 1:
            break
        inp("brake", 0.6)
        time.sleep(0.2)
    inp("brake", 0)
    inp("parkingbrake", 1)


def fit(drill_id, pos, direction, to_node=None):
    """Run the fit test with the car placed at pos/direction. -> {fits, problems, notes}."""
    drill = A.drill(drill_id)
    needs = drill["environment"]["venueNeeds"]
    kind = needs["kind"]
    problems, notes = [], []
    home = json.loads(lua("local v = be:getPlayerVehicle(0) local p = v:getPosition() local d = v:getDirectionVector() "
                          "return jsonEncode({pos = {x = p.x, y = p.y, z = p.z}, dir = {x = d.x, y = d.y}})"))
    try:
        A.place(pos, direction, lift=0.5)
        time.sleep(1.5)
        moved = math.dist(state()[0][:2], (pos["x"], pos["y"]))
        if moved > NUDGE_M:
            problems.append(f"start spot isn't clear: the game moved the car {moved:.1f} m when placing it")
        lua("return tostring(extensions.rallyAcademy.devRecordStart())")
        time.sleep(1.0)  # let the sampler start
        if kind == "straight":
            notes.append(_straight(drill))
        elif kind == "open":
            _circle(needs.get("areaM", 30))
            notes.append("drove a steady circle at about 20 km/h, sized to the drill's open area")
        else:
            length = needs.get("lengthM", 120)
            kmh = {"corner": 40, "hill": 35, "crest": 45}.get(kind, 50)
            to_node = to_node or road_target(pos, direction, length)
            if not to_node:
                problems.append("no road leads away from here in the direction faced")
            elif not _ai(to_node, None, kmh, timeout=length / (kmh / 3.6) * 3 + 15):
                problems.append(f"the AI didn't get through the section at {kmh} km/h")
            notes.append(f"the game's AI drove it at up to {kmh} km/h")
        n = int(lua("return tostring(extensions.rallyAcademy.devRecordStop())"))
        run = A.lua_json("return extensions.rallyAcademy.getLastRun()")
        samples = run.get("samples") or []
        if isinstance(samples, dict) or n < 10:
            problems.append(f"too little telemetry recorded ({n} samples)")
            samples = []
        used = path_length(samples)
        notes.append(f"used {used:.0f} m")
        if kind == "straight" and needs.get("lengthM") and used > needs["lengthM"]:
            problems.append(f"needed {used:.0f} m but the drill allows {needs['lengthM']:g} m")
        if kind == "open" and samples:
            xs, ys = [s["x"] for s in samples], [s["y"] for s in samples]
            span = max(max(xs) - min(xs), max(ys) - min(ys))
            notes.append(f"circle about {span:.0f} m across")
        checks = [{"type": "no_damage"}, {"type": "no_rollover"}]
        if needs.get("surfaces"):
            checks.append({"type": "on_surface", "surfaces": needs["surfaces"], "maxWheelsOff": 2, "maxSeconds": 0.5})
        for rule in checks:
            c = A.rule_check(rule)
            (notes if c["ok"] else problems).append(c["text"])
        if needs.get("features"):
            notes.append("check by eye: " + "; ".join(needs["features"]))
    finally:
        call("set_ai", {"mode": "disabled"})
        for event in ("throttle", "brake", "steering"):
            inp(event, 0)
        A.place(home["pos"], home["dir"], lift=0.5)
        # a failed fit can wreck or roll the car: put it back repaired (the game's own reset
        # teleport, as Retry uses), then restore the player's gearbox
        lua("local v = be:getPlayerVehicle(0) spawn.safeTeleport(v, v:getPosition(), "
            "quatFromDir(vec3(v:getDirectionVector()), vec3(v:getDirectionVectorUp())), nil, nil, nil, nil, true) return 1")
        time.sleep(1.0)
        A.realistic()
    return {"drill": drill_id, "kind": kind, "fits": not problems, "problems": problems, "notes": notes}
