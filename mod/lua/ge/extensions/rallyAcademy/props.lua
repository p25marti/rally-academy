-- Physical course markers (docs/decisions/0011-physical-course-markers.md): a soft-body traffic cone or a
-- flexible delineator post stands at each of a course's markers (layout.lua: gate posts, cones, a stop line's
-- cones), so hitting one is real. Spawned as the game's prop vehicles, the way its drift mode spawns poles;
-- reset to their spots on Retry; the car's collisions say which it touched. The only module that spawns.
-- Engine calls only; with no engine (unit tests) it places nothing and grading measures instead.
local P = {}

P.MODELS = {post = {'delineator', 'vehicles/delineator/pole.pc'}, cone = {'cones', 'vehicles/cones/large.pc'}}
-- Our props' object names start with this, so a reloaded extension can find and remove the last one's.
local PREFIX = 'ra_prop_'

local placed = {} -- {{id, name, kind}} for the course laid out now
local signature = nil -- what was placed (kinds and positions), so an unchanged course isn't spawned again

local function engine()
  return core_vehicles and core_vehicles.spawnNewVehicle and sanitizeVehicleSpawnOptions and scenetree and true
end

local function find(id) return getObjectByID and getObjectByID(id) end

-- Remove every prop of ours, including any a previous load of the extension left behind.
function P.clear()
  for _, p in ipairs(placed) do
    local v = find(p.id)
    if v then v:delete() end
  end
  placed, signature = {}, nil
  if not engine() then return end
  for _, name in ipairs(scenetree.findClassObjects('BeamNGVehicle') or {}) do
    if type(name) == 'string' and name:sub(1, #PREFIX) == PREFIX then
      local v = scenetree.findObject(name)
      if v then v:delete() end
    end
  end
end

local function signatureOf(markers)
  local parts = {}
  for _, m in ipairs(markers) do parts[#parts + 1] = string.format('%s@%.2f,%.2f', m.kind or '?', m.x, m.y) end
  return table.concat(parts, ';')
end

-- Stand a prop at each marker ({x, y, name, kind = 'post' | 'cone'}); `groundZ(x, y)` gives the ground height.
-- Leaves the props alone when the same course is laid out again. Returns how many stand.
function P.place(markers, groundZ)
  if not engine() then return 0 end
  local sig = signatureOf(markers)
  if sig == signature and #placed > 0 then return #placed end
  P.clear()
  for i, m in ipairs(markers) do
    local model = P.MODELS[m.kind]
    if model then
      local opt = sanitizeVehicleSpawnOptions(model[1], {config = model[2], pos = vec3(m.x, m.y, groundZ(m.x, m.y)),
                                                        rot = quat(0, 0, 0, 1), vehicleName = PREFIX .. i})
      opt.autoEnterVehicle = false
      local v = core_vehicles.spawnNewVehicle(model[1], opt)
      if v then
        v.playerUsable = false -- not one to switch into
        placed[#placed + 1] = {id = v:getID(), name = m.name, kind = m.kind}
      end
    end
  end
  signature = sig
  return #placed
end

function P.active() return #placed > 0 end

-- Every prop back where it was spawned, upright and unbroken (Retry).
function P.reset()
  for _, p in ipairs(placed) do
    local v = find(p.id)
    if v then
      v:requestReset(RESET_PHYSICS)
      if v.resetBrokenFlexMesh then v:resetBrokenFlexMesh() end
    end
  end
end

-- Names of the props the vehicle is touching now (the game's per-vehicle collision list, as its drift mode
-- reads it).
function P.touching(vehId)
  local out = {}
  local m = map and map.objects and map.objects[vehId]
  local cols = m and m.objectCollisions
  if not cols then return out end
  for _, p in ipairs(placed) do
    if cols[p.id] then out[#out + 1] = p.name end
  end
  return out
end

return P
