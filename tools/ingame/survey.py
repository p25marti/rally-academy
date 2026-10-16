"""Venue surveys through the game's MCP server: what's under the wheels, how much room
there is, what the terrain is, which cars and maps exist. For authoring drills (MAPS.md,
on_surface rules, venue spawns). Run with the game loaded on the map you're surveying:

  python tools/ingame/survey.py here                 room around the car, surface under each wheel
  python tools/ingame/survey.py surfaces [--along=0,40,80] [--side=-12,-8,-5,0,5,8,12]
                                                      wheel surfaces on a grid ahead/across of the car
  python tools/ingame/survey.py terrain X Y [X Y ...] terrain ground model at points (no road meshes)
  python tools/ingame/survey.py configs [MODEL]       config keys for a car model (default: current car)
  python tools/ingame/survey.py levels                installed maps

`surfaces` teleports the car around and puts it back. Surface names come from the car's own
material table (the same list as R.SURFACES in rules.lua).
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8")

from game import call, lua, vlua  # noqa: E402
import academy as A  # noqa: E402

WHEEL_SURFACES = ("local mats = particles.getMaterialsParticlesTable() local out = {} "
                  "for i = 0, wheels.wheelRotatorCount - 1 do local wd = wheels.wheelRotators[i] "
                  "local m = particles.getMaterialByID(mats, wd.contactMaterialID1) "
                  "out[#out+1] = wd.name .. '=' .. (m and m.name or tostring(wd.contactMaterialID1)) end "
                  "return table.concat(out, ' ')")

# Distance to the nearest static object in 8 directions (castRayStatic), up vector, position.
ROOM = """
local v = be:getPlayerVehicle(0)
local p = v:getPosition()
local fwd = vec3(v:getDirectionVector()):normalized()
local right = fwd:cross(vec3(0, 0, 1)):normalized()
local d = {}
for _, deg in ipairs({0, 45, 90, 135, 180, -135, -90, -45}) do
  local r = math.rad(deg)
  local dir = (fwd * math.cos(r) + right * math.sin(r)):normalized()
  d[#d + 1] = math.floor(castRayStatic(p + vec3(0, 0, 0.6), dir, 150) or 150)
end
local h = vec3(v:getDirectionVector())
return jsonEncode({room = d, upZ = vec3(v:getDirectionVectorUp()).z, pos = {x = p.x, y = p.y, z = p.z},
                   dir = {x = h.x, y = h.y, z = h.z}})"""


def pose():
    return json.loads(lua(ROOM))


def here(_args):
    s = pose()
    names = ["ahead", "ahead-right", "right", "behind-right", "behind", "behind-left", "left", "ahead-left"]
    print("car at ({x:.1f}, {y:.1f}, {z:.1f})".format(**s["pos"]), f"upright {s['upZ']:.3f} (1 = flat)")
    print("room (m, up to 150):", ", ".join(f"{n} {d}" for n, d in zip(names, s["room"])))
    print("wheels:", vlua(WHEEL_SURFACES))


def surfaces(args):
    start = pose()
    along = [float(v) for v in args.along.split(",")]
    side = [float(v) for v in args.side.split(",")]
    print(f"wheel surfaces; rows = metres ahead, columns = metres to the right ({', '.join(map(str, side))})")
    for a in along:
        row = []
        for s in side:
            A.place(start["pos"], start["dir"], ahead=a, side=s, lift=2.0)
            names = {kv.split("=")[1] for kv in str(vlua(WHEEL_SURFACES)).split() if "=" in kv}
            row.append("/".join(sorted(names)) or "?")
        print(f"  {a:>5.0f} m: " + " | ".join(row))
    A.place(start["pos"], start["dir"], lift=0.5)


def terrain(args):
    if len(args.points) % 2:
        sys.exit("give X Y pairs")
    pts = ",".join(f"{{{args.points[i]},{args.points[i + 1]}}}" for i in range(0, len(args.points), 2))
    print(lua(f"""
local t = core_terrain.getTerrain()
local out = {{}}
for _, q in ipairs({{{pts}}}) do
  local p = vec3(q[1], q[2], 0)
  p.z = core_terrain.getTerrainHeight(p) or 0
  local m = t:getMaterial(t:getMaterialIdxWs(p))
  out[#out + 1] = string.format('(%.1f, %.1f): %s', q[1], q[2], (m and m.getGroundmodelName and m:getGroundmodelName()) or '?')
end
return table.concat(out, '; ')"""))


def configs(args):
    model = args.model or json.loads(call("get_vehicle")).get("jbeam")
    print(model + ":", call("get_configs", {"model": model}) if model else "no car")


def levels(_args):
    print(lua("local o = {} for _, l in ipairs(core_levels.getList()) do o[#o+1] = l.levelName end table.sort(o) return table.concat(o, ', ')"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("here").set_defaults(func=here)
    p = sub.add_parser("surfaces")
    p.add_argument("--along", default="20,60,100")
    p.add_argument("--side", default="-12,-8,-5,0,5,8,12")
    p.set_defaults(func=surfaces)
    p = sub.add_parser("terrain")
    p.add_argument("points", nargs="+", type=float)
    p.set_defaults(func=terrain)
    p = sub.add_parser("configs")
    p.add_argument("model", nargs="?")
    p.set_defaults(func=configs)
    sub.add_parser("levels").set_defaults(func=levels)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
