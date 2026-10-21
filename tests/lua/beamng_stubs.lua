-- Fake BeamNG Game Engine (GE) Lua environment for unit tests.
--
-- These stand-ins cover only what the mod calls. They encode our
-- *assumptions* about the real API; when in-game testing disproves one,
-- fix the stub first so the tests reflect reality (docs/TESTING.md).

local json = require('json')
local S = {}

local ROOT = arg[1] or '.'

-- ---------------------------------------------------------------- vec3 / quat
local vec3mt = {}
vec3mt.__index = vec3mt
local function vec3(x, y, z)
  if type(x) == 'table' then x, y, z = x.x, x.y, x.z end
  return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vec3mt)
end
function vec3mt.__sub(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
function vec3mt.__add(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
function vec3mt.__mul(a, b)
  if type(a) == 'number' then a, b = b, a end
  return vec3(a.x * b, a.y * b, a.z * b)
end
function vec3mt.__unm(a) return vec3(-a.x, -a.y, -a.z) end
function vec3mt:cross(b) return vec3(self.y * b.z - self.z * b.y, self.z * b.x - self.x * b.z, self.x * b.y - self.y * b.x) end
function vec3mt:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function vec3mt:normalized()
  local l = self:length()
  if l == 0 then return vec3(0, 0, 0) end
  return vec3(self.x / l, self.y / l, self.z / l)
end

local function quatFromDir(dir, up)
  return {x = 0, y = 0, z = 0, w = 1, _dir = dir, _up = up}
end

-- ---------------------------------------------------------------- vehicle
local function newVehicle(id)
  local v = {
    id = id or 1,
    pos = vec3(0, 0, 0),
    vel = vec3(0, 0, 0),
    dir = vec3(0, 1, 0),
    up = vec3(0, 0, 1),
    teleports = {},
    damage = 0,
    JBeam = 'covet',
    partConfig = 'vehicles/covet/student_driver.pc',
    luaCommands = {},
  }
  function v:getID() return self.id end
  function v:getPosition() return vec3(self.pos) end
  function v:getVelocity() return vec3(self.vel) end
  function v:getDirectionVector() return vec3(self.dir) end
  function v:getDirectionVectorUp() return vec3(self.up) end
  function v:setPositionRotation(x, y, z, rx, ry, rz, rw)
    table.insert(self.teleports, {x = x, y = y, z = z, rx = rx, ry = ry, rz = rz, rw = rw})
    self.pos = vec3(x, y, z)
    self.vel = vec3(0, 0, 0) -- verified 0.39.4: teleporting a moving car leaves it at rest
  end
  function v:queueLuaCommand(cmd) table.insert(self.luaCommands, cmd) end
  -- Nodes (verified 0.39.4): getNodePosition(i) is node i's offset from the car's position in
  -- world axes. The stub's body is a box measured on the Covet Student Driver: 1.85 m ahead of
  -- its position, 2.07 m behind, 1.23 m to the left, 0.58 m to the right.
  v.body = {front = 1.85, rear = 2.07, left = 1.23, right = 0.58}
  function v.getNodeCount() return 4 end
  function v:getNodePosition(i)
    local f = vec3(self.dir.x, self.dir.y, 0):normalized()
    local r = vec3(f.y, -f.x, 0)
    local a = (i < 2) and self.body.front or -self.body.rear
    local s = (i % 2 == 0) and -self.body.left or self.body.right
    return f * a + r * s
  end
  return v
end

-- ---------------------------------------------------------------- install
-- Installs fresh globals; returns a handle for inspecting side effects.
function S.install()
  local h = {events = {}, files = {}, logs = {}, vehicle = newVehicle(1), level = 'driver_training'}

  _G.vec3 = vec3
  _G.quatFromDir = quatFromDir
  _G.log = function(level, tag, msg) table.insert(h.logs, {level = level, tag = tag, msg = msg}) end
  _G.dump = function() end
  -- getSurfaceHeightBelow (verified 0.39.4): the ground under a point; h.groundZ overrides.
  _G.be = {getPlayerVehicle = function(_, idx) if idx == 0 then return h.vehicle end end,
           getSurfaceHeightBelow = function(_, p) return h.groundZ or (p.z - 3) end}
  _G.getCurrentLevelIdentifier = function() return h.level end -- verified 0.39.4
  _G.getObjectByID = function(id) if h.vehicle.id == id then return h.vehicle end end
  -- Levels and vehicle spawning (verified 0.39.4, as the game's MCP tools use them).
  h.levelsLoaded, h.spawned = {}, {}
  _G.core_levels = {
    getList = function()
      return {{levelName = 'west_coast_usa', fullfilename = '/levels/west_coast_usa/main/'},
              {levelName = 'utah', fullfilename = '/levels/utah/main/'},
              {levelName = 'driver_training', fullfilename = '/levels/driver_training/main/'},
              {levelName = 'ra_proving_ground', fullfilename = '/levels/ra_proving_ground/main/'}}
    end,
    startLevel = function(path) table.insert(h.levelsLoaded, path) end,
  }
  -- verified 0.39.4: the Freeroam menu's way in (enters freeroam mode, then startLevel)
  h.paused = false
  _G.simTimeAuthority = { -- verified 0.39.4 (photomode uses the same calls)
    pause = function(p) h.paused = p end,
    getPause = function() return h.paused end,
  }
  -- Venue bookmarks (verified 0.39.4): static ray casts, the AI road map, on-screen messages.
  h.rayDistance, h.messages = 40, {}
  _G.castRayStatic = function() return h.rayDistance end
  h.roads = {nodes = {a = {radius = 4, links = {b = {drivability = 0.5}}}, b = {radius = 3.5, links = {}}}}
  _G.map = {findClosestRoad = function() return 'a', 'b', 1.2 end, getMap = function() return h.roads end}
  _G.ui_message = function(msg) table.insert(h.messages, msg) end
  h.uiRoutes = {}
  _G.ui_router = {navigate = function(route) table.insert(h.uiRoutes, route) end} -- verified 0.39.4
  h.freeroamStarts = {}
  _G.freeroam_freeroam = {startFreeroam = function(path)
    table.insert(h.freeroamStarts, path)
    table.insert(h.levelsLoaded, path)
  end}
  _G.core_vehicles = {replaceVehicle = function(model, opt)
    table.insert(h.spawned, {model = model, config = opt and opt.config})
    h.vehicle.JBeam = model
    h.vehicle.partConfig = 'vehicles/' .. model .. '/' .. tostring(opt and opt.config) .. '.pc'
    -- verified 0.39.4: onVehicleSpawned fires synchronously inside replaceVehicle
    if h.syncSpawnHook and extensions and extensions.rallyAcademy then
      extensions.rallyAcademy.onVehicleSpawned(h.vehicle.id, h.vehicle)
    end
  end}
  -- spawn.safeTeleport(veh, pos, rot, checkOnlyStatics, visibilityPoint, removeTraffic,
  -- centeredPosition, resetVehicle): verified 0.39.4 as the game's own teleport + repair.
  _G.spawn = {safeTeleport = function(veh, pos, rot, _a, _b, _c, _d, resetVehicle)
    table.insert(veh.teleports, {x = pos.x, y = pos.y, z = pos.z, rot = rot, reset = resetVehicle})
    veh.pos = vec3(pos)
    veh.vel = vec3(0, 0, 0)
    if resetVehicle then veh.damage = 0 end
  end}
  -- Debug overlay (verified to exist 0.39.4): records what was drawn on the last frames.
  h.draws = {}
  _G.ColorF = function(r, g, b, a) return {r = r, g = g, b = b, a = a} end
  _G.Point2F = function(x, y) return {x = x, y = y} end
  _G.debugDrawer = {drawCylinder = function(_, a, b, radius, colour)
    table.insert(h.draws, {kind = 'cylinder', a = a, b = b, radius = radius, colour = colour})
  end, drawSquarePrism = function(_, a, b, sizeA, sizeB, colour)
    table.insert(h.draws, {kind = 'prism', a = a, b = b, sizeA = sizeA, sizeB = sizeB, colour = colour})
  end}
  _G.guihooks = {trigger = function(name, data) table.insert(h.events, {name = name, data = data}) end}

  -- Reads go to the in-memory store first (files the mod wrote), then the repo's mod/ folder,
  -- which mirrors BeamNG's virtual filesystem where mod files appear at the game root.
  _G.jsonReadFile = function(path)
    if h.files[path] then return json.decode(h.files[path]) end
    local f = io.open(ROOT .. '/mod/' .. path, 'r')
    if not f then return nil end
    local text = f:read('*a'); f:close()
    local data = json.decode(text)
    if path == S.EXERCISES then
      -- Test-only drills (T01-T04) go after the shipped ones, so engine tests don't depend on how
      -- any shipped drill is graded (tests/fixtures/test_drills.json).
      for _, e in ipairs(S.testDrills()) do table.insert(data.exercises, e) end
    elseif path == S.VENUES then
      -- ... and they stand on a test-only venue on another map (tests/fixtures/test_venues.json).
      for _, v in ipairs(S.testFixture('test_venues.json').venues) do table.insert(data.venues, v) end
    end
    return data
  end
  _G.jsonWriteFile = function(path, data)
    h.files[path] = json.encode(data)
    return true
  end

  function h.lastState()
    for i = #h.events, 1, -1 do
      if h.events[i].name == 'rallyAcademyState' then return h.events[i].data end
    end
  end

  -- Messages logged with the given tag, joined with newlines.
  function h.logText(tag)
    local out = {}
    for _, l in ipairs(h.logs) do if l.tag == tag then table.insert(out, l.level .. ' ' .. l.msg) end end
    return table.concat(out, '\n')
  end

  return h
end

S.EXERCISES = 'gameplay/rallyAcademy/exercises.json'
S.VENUES = 'gameplay/rallyAcademy/venues.json'

function S.testFixture(name)
  local f = assert(io.open(ROOT .. '/tests/fixtures/' .. name, 'r'))
  local text = f:read('*a'); f:close()
  return json.decode(text)
end

function S.testDrills() return S.testFixture('test_drills.json').exercises end

-- Prop vehicles for physical course markers (props.lua; verified 0.40.0 as the game's drift mode spawns
-- its poles): spawned props land in h.props, the player car's collisions are h.collisions[propId] = true,
-- and h.leftovers are props a previous load of the extension left in the scene (object names).
function S.installProps(h)
  h.props, h.collisions, h.leftovers, h.leftoversDeleted = {}, {}, {}, {}
  local nextId = 1000
  _G.sanitizeVehicleSpawnOptions = function(_model, opt) return opt end
  _G.quat = function(x, y, z, w) return {x = x, y = y, z = z, w = w} end
  _G.RESET_PHYSICS = 1
  _G.core_vehicles.spawnNewVehicle = function(model, opt)
    nextId = nextId + 1
    local v = {id = nextId, model = model, config = opt.config, pos = opt.pos, name = opt.vehicleName,
               autoEnter = opt.autoEnterVehicle, resets = 0, deleted = false}
    function v:getID() return self.id end
    function v:delete() self.deleted = true end
    function v:requestReset(kind) if kind == RESET_PHYSICS then self.resets = self.resets + 1 end end
    function v.resetBrokenFlexMesh() end
    table.insert(h.props, v)
    return v
  end
  local carById = getObjectByID
  _G.getObjectByID = function(id)
    for _, v in ipairs(h.props) do if v.id == id and not v.deleted then return v end end
    return carById(id)
  end
  local function live()
    local out = {}
    for _, v in ipairs(h.props) do if not v.deleted then out[#out + 1] = v end end
    return out
  end
  _G.scenetree = {
    findClassObjects = function(class)
      if class ~= 'BeamNGVehicle' then return {} end
      local names = {}
      for _, v in ipairs(live()) do names[#names + 1] = v.name end
      for _, n in ipairs(h.leftovers) do names[#names + 1] = n end
      return names
    end,
    findObject = function(name)
      for _, v in ipairs(live()) do if v.name == name then return v end end
      for i, n in ipairs(h.leftovers) do
        if n == name then
          return {delete = function() table.insert(h.leftoversDeleted, n); table.remove(h.leftovers, i) end}
        end
      end
    end,
  }
  _G.map.objects = {[h.vehicle.id] = {objectCollisions = h.collisions}}
end

-- Ids of the shipped drills only (the catalogue the stubs serve also holds T01-T04).
function S.isTestDrill(id) return tostring(id):match('^T%d%d$') ~= nil end

-- Loads a fresh copy of a GE extension module (bypasses require's cache).
function S.loadExtension(name)
  package.loaded['ge.extensions.' .. name] = nil
  return require('ge.extensions.' .. name)
end

S.vec3 = vec3
return S
