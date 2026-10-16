-- Shared helpers for the extension tests (tests/lua/test_*.lua): a fresh extension on the
-- BeamNG stubs, driving the stub car, scripted runs that feed telemetry, and asserts.
local stubs = require('beamng_stubs')
local H = {stubs = stubs}

-- Sim clock shared by the scripted runs (telemetry timestamps must keep increasing).
H.simT = 100

function H.near(actual, expected, tol, msg)
  if type(actual) ~= 'number' or math.abs(actual - expected) > tol then
    error(('%s: expected %s +/- %s, got %s'):format(msg or 'mismatch', expected, tol, tostring(actual)), 2)
  end
end

function H.eq(actual, expected, msg)
  if actual ~= expected then
    error(('%s: expected %s, got %s'):format(msg or 'mismatch', tostring(expected), tostring(actual)), 2)
  end
end

function H.setup()
  local h = stubs.install()
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  return h, M
end

-- Drives the sim forward `seconds` in 0.1 s steps at the vehicle's current velocity.
function H.drive(h, M, seconds, vel)
  if vel then h.vehicle.vel = stubs.vec3(vel) end
  local steps = math.floor(seconds / 0.1 + 0.5)
  for _ = 1, steps do
    h.vehicle.pos = h.vehicle.pos + stubs.vec3(h.vehicle.vel.x * 0.1, h.vehicle.vel.y * 0.1, h.vehicle.vel.z * 0.1)
    M.onUpdate(0.1, 0.1)
  end
end

-- Start/finish persistence: settings/rallyAcademySetups.json, per map then drill.
H.SETUPS = 'settings/rallyAcademySetups.json'

function H.markStartAndFinish(h, M, id)
  M.select(id)
  h.vehicle.pos = stubs.vec3(10, 20, 30)
  M.markStart()
  h.vehicle.pos = stubs.vec3(10, 120, 30)
  M.markFinish()
end

-- Simulates an extension reload / game restart: fresh module, same files on disk.
function H.reloadExtension()
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  return M
end

function H.startRun(h, M)
  H.markStartAndFinish(h, M, 'A03')
  M.retry()
  H.drive(h, M, 1.0, {x = 0, y = 10, z = 0})
  H.eq(h.lastState().phase, 'running', 'precondition: running')
end


function H.driveWithTelemetry(h, M, seconds, vel)
  if vel then h.vehicle.vel = stubs.vec3(vel) end
  local steps = math.floor(seconds / 0.1 + 0.5)
  for _ = 1, steps do
    h.vehicle.pos = h.vehicle.pos + stubs.vec3(h.vehicle.vel.x * 0.1, h.vehicle.vel.y * 0.1, h.vehicle.vel.z * 0.1)
    H.simT = H.simT + 0.1
    M.onTelemetry({id = h.vehicle.id, t = H.simT, air = h.vehicle.vel:length(), brk = 0, w = {}})
    M.onUpdate(0.1, 0.1)
  end
end

function H.commandsMatching(h, needle)
  local n = 0
  for _, c in ipairs(h.vehicle.luaCommands) do if c:find(needle, 1, true) then n = n + 1 end end
  return n
end

-- Drills by id with each venue filled in (levelId, mapDisplayName, spawn), as the mod loads them.
function H.drills()
  local venues, byId = {}, {}
  for _, v in ipairs(jsonReadFile('gameplay/rallyAcademy/venues.json').venues) do venues[v.id] = v end
  for _, e in ipairs(jsonReadFile('gameplay/rallyAcademy/exercises.json').exercises) do
    local v = venues[e.environment.venue]
    if v then e.environment.levelId, e.environment.mapDisplayName, e.environment.spawn = v.levelId, v.name, v.spawn end
    byId[e.id] = e
  end
  return byId
end

function H.spawnOf(id)
  for _, e in ipairs(jsonReadFile('gameplay/rallyAcademy/exercises.json').exercises) do
    if e.id == id then
      for _, v in ipairs(jsonReadFile('gameplay/rallyAcademy/venues.json').venues) do
        if v.id == e.environment.venue then return v.spawn.pos end
      end
    end
  end
end

function H.tick(M, seconds)
  for _ = 1, math.floor(seconds / 0.1 + 0.5) do M.onUpdate(0.1, 0.1) end
end

-- Retry, accelerate along +y to `kmh`, brake at `brakeAtY` with `decel` m/s2 until the car
-- stops, then stand still; the car's sampler reports every step (with position).
function H.brakingRun(h, M, opts)
  local dt, v, braking, lockedT = 0.05, 0, false, 0
  local vmax = (opts.kmh or 70) / 3.6
  M.retry()
  local stoppedFor = 0
  for _ = 1, 2000 do
    if not braking and h.vehicle.pos.y >= (opts.brakeAtY or 80) then braking = true end
    if braking then v = math.max(0, v - (opts.decel or 7) * dt) else v = math.min(vmax, v + 4 * dt) end
    h.vehicle.vel = stubs.vec3(0, v, 0)
    h.vehicle.pos = h.vehicle.pos + stubs.vec3(0, v * dt, 0)
    H.simT = H.simT + dt
    local lock = braking and opts.lockFor and lockedT < opts.lockFor and v > 0
    if lock then lockedT = lockedT + dt end
    local fs = lock and 0 or v
    M.onTelemetry({id = h.vehicle.id, t = H.simT, x = h.vehicle.pos.x, y = h.vehicle.pos.y, z = 0, air = v,
      brk = braking and 0.8 or 0, w = {{n = 'FL', s = fs}, {n = 'FR', s = fs}, {n = 'RL', s = v}, {n = 'RR', s = v}}})
    M.onUpdate(dt, dt)
    if braking and v == 0 then stoppedFor = stoppedFor + dt end
    if h.lastState().phase == 'scored' or stoppedFor > 3 then break end
  end
  return h.lastState()
end

-- Start at the origin facing +y; stop zone centred at `zoneY`.
function H.setupB01(zoneY)
  local h, M = H.setup()
  M.select('B01')
  h.vehicle.pos, h.vehicle.dir = stubs.vec3(0, 0, 0), stubs.vec3(0, 1, 0)
  M.markStart()
  h.vehicle.pos = stubs.vec3(0, zoneY, 0)
  M.markFinish()
  return h, M
end

-- A04 with its start at y = 0 and gates at y = 40, 65, 90, all facing north (+y).
function H.setupA04()
  local h, M = H.setup()
  M.select('A04')
  h.vehicle.pos, h.vehicle.dir = stubs.vec3(0, 0, 0), stubs.vec3(0, 1, 0)
  M.markStart()
  for _, y in ipairs({40, 65, 90}) do
    h.vehicle.pos = stubs.vec3(0, y, 0)
    M.addGate()
  end
  return h, M
end

-- Retry, then drive north at kmhAt(y) km/h (brake pressed where brakeAt(y)) until the run is scored.
function H.gateRun(h, M, opts)
  local dt, pending = 0.05, nil
  M.retry()
  M.onUpdate(0.1, 0.1) -- settle after the teleport
  for _ = 1, 4000 do
    local v = (opts.kmhAt and opts.kmhAt(h.vehicle.pos.y) or 30) / 3.6
    h.vehicle.vel = stubs.vec3(0, v, 0)
    h.vehicle.pos = h.vehicle.pos + stubs.vec3(0, v * dt, 0)
    H.simT = H.simT + dt
    local brk = opts.brakeAt and opts.brakeAt(h.vehicle.pos.y) and 0.6 or 0
    local sample = {id = h.vehicle.id, t = H.simT, x = h.vehicle.pos.x, y = h.vehicle.pos.y, z = 0, air = v, brk = brk, w = {}}
    if opts.lag then
      -- In-game the car's sample arrives about a frame after GE sees the car move.
      M.onUpdate(dt, dt)
      if pending then M.onTelemetry(pending) end
      pending = sample
    else
      M.onTelemetry(sample)
      M.onUpdate(dt, dt)
    end
    if h.lastState().phase ~= 'ready' and h.lastState().phase ~= 'running' then break end
    if h.vehicle.pos.y > (opts.giveUpAtY or 200) then break end
  end
  return h.lastState()
end

-- Assert `needle` is in `text` (returns true, so `assert(H.has(...))` also reads well).
function H.has(text, needle)
  if not tostring(text):find(needle, 1, true) then
    error(('expected %q in %q'):format(needle, tostring(text)), 2)
  end
  return true
end

return H
