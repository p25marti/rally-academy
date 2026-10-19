"""Physics surfaces from inside the game, the way BeamNG's Groundmodel Debug panel (0.40) reads them: for any
points, how many 1 m tiles of each ground model lie around them, on the terrain and on static meshes (roads,
bridges, buildings), plus each ground model's friction. No car placement.

  debugDrawer:renderGroundModelDebug(type, name, colour, radius, tile, pos, depthScale, countOnly)  terrain tiles
  debugDrawer:renderStaticColDebug(...)                                                             mesh triangles
  core_environment.groundModels[name].cdata                                                         friction etc.

These name the physics ground model (DIRT, GRAVEL, ASPHALT), which isn't always the name wheel telemetry
reports (the BMP dirt arena and circle read DIRT here and DIRT_DUSTY on the wheels). Aliases (BEACHSAND for SAND,
DIRT_ROCKY for DIRT_DUSTY, ...) are counted under their own names, so they're folded into their parent. About 0.2 ms a call at a 10 m radius (0.40.0), so it's for checking places, not sampling whole maps.
"""
import json

from game import lua, lua_json

# Ground models that are obstacles or game props rather than something to drive a drill on.
NOT_GROUND = {"METAL", "WOOD", "PLASTIC", "METAL_TREAD", "KICKPLATE", "SHOCK_ABSORBER", "SOFT_COLLISION_GENERAL",
              "FRICTIONLESS", "SPIKE_STRIP", "LEAVES_THIN", "LEAVES_STRONG", "BRANCHES_STRONG", "VOID"}


def friction():
    """{name: {mu (static friction), slide, rough, depth (m of loose layer), strength}} for real ground models,
    plus "_aliases": {alias: parent} (terrain textures often name an alias: DIRT_ROCKY is DIRT_DUSTY, BEACHSAND is SAND)."""
    return lua_json(r"""local o, al = {}, {}
for name, gm in pairs(core_environment.groundModels) do
  if gm.isAlias then
    al[name] = tostring(gm.parent)
  else
    local c = gm.cdata
    o[name] = {mu = c.staticFrictionCoefficient, slide = c.slidingFrictionCoefficient, rough = c.roughnessCoefficient,
               depth = c.defaultDepth, strength = c.strength}
  end
end
o._aliases = al
return o""")


def counts(points, radius=5.0, statics=True):
    """For each (x, y[, z]) point, ({ground model: terrain tiles}, {ground model: mesh triangles}) within `radius` m
    (at most 60, the engine's limit). z defaults to the terrain height there."""
    out = []
    for k in range(0, len(points), 40):  # bounded calls: 40 points x ~32 ground models x 2
        chunk = points[k:k + 40]
        pts = ",".join("{%.2f,%.2f,%s}" % (p[0], p[1], ("%.2f" % p[2]) if len(p) > 2 and p[2] is not None else "nil")
                       for p in chunk)
        res = lua(f"""local P = {{{pts}}}
local names = {{}}
for name, _ in pairs(core_environment.groundModels) do if name ~= '' then names[#names + 1] = name end end  -- aliases count under their own names
local col, r = ColorF(1, 1, 1, 1), {min(60.0, radius)}
{"Engine.setStaticColDebugEnabled(true)" if statics else ""}
local ok, err = pcall(function()
  local rows = {{}}
  for i, p in ipairs(P) do
    local z = p[3] or core_terrain.getTerrainHeight(vec3(p[1], p[2], 0)) or 0
    local pos = vec3(p[1], p[2], z)
    local t, s = {{}}, {{}}
    for _, name in ipairs(names) do
      local a = debugDrawer:renderGroundModelDebug(0, name, col, r, 1, pos, 1, true) or 0
      if a > 0 then t[#t + 1] = name .. '=' .. a end
      {"local b = debugDrawer:renderStaticColDebug(0, name, col, r, 1, pos, 1, true) or 0 if b > 0 then s[#s + 1] = name .. '=' .. b end" if statics else ""}
    end
    rows[i] = table.concat(t, ' ') .. '|' .. table.concat(s, ' ')
  end
  _G.__raSurface = table.concat(rows, ';')
end)
{"Engine.setStaticColDebugEnabled(false)" if statics else ""}
if not ok then error(err) end
return _G.__raSurface""")
        for row in str(res).split(";"):
            terr, stat = (row.split("|") + [""])[:2]
            parse = lambda s: {kv.split("=")[0]: int(kv.split("=")[1]) for kv in s.split() if "=" in kv}  # noqa: E731
            out.append((parse(terr), parse(stat)))
    return out


def summary(rows, fric=None):
    """Totals over many points: shares of each ground model (terrain and driveable meshes together), the share
    covered by obstacles (meshes that aren't ground), and the mean static friction, weighted by area."""
    ground, obstacles = {}, 0
    aliases = (fric or {}).get("_aliases", {})
    for terr, stat in rows:
        for g, n in terr.items():
            g = aliases.get(g, g)
            ground[g] = ground.get(g, 0) + n
        for g, n in stat.items():
            g = aliases.get(g, g)
            if g in NOT_GROUND:
                obstacles += n
            else:
                ground[g] = ground.get(g, 0) + n
    total = sum(ground.values()) or 1
    shares = {g: round(n / total * 100) for g, n in sorted(ground.items(), key=lambda kv: -kv[1])}
    mu = None
    if fric:
        known = [(n, fric[g]["mu"]) for g, n in ground.items() if g in fric and g != "_aliases"]
        if known:
            mu = round(sum(n * m for n, m in known) / (sum(n for n, _ in known) or 1), 2)
    return {"shares": shares, "obstacleTris": obstacles, "mu": mu}


def describe(s):
    """'GRAVEL 92 %, GRASS 8 % (grip 0.67)'."""
    parts = ", ".join(f"{g} {p} %" for g, p in list(s["shares"].items())[:3] if p > 0)
    return parts + (f" (grip {s['mu']:.2f})" if s.get("mu") else "")


if __name__ == "__main__":
    print(json.dumps(friction(), indent=1))
