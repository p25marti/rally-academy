-- Characterisation tests for the GE extension as imported from the starter
-- scaffold. They pin current behaviour so refactors are safe; when behaviour
-- changes on purpose, change the test in the same commit.

local stubs = require('beamng_stubs')
local T = {}

local function eq(actual, expected, msg)
  if actual ~= expected then
    error(('%s: expected %s, got %s'):format(msg or 'mismatch', tostring(expected), tostring(actual)), 2)
  end
end

local function setup()
  local h = stubs.install()
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  return h, M
end

-- Drives the sim forward `seconds` in 0.1 s steps at the vehicle's current velocity.
local function drive(h, M, seconds, vel)
  if vel then h.vehicle.vel = stubs.vec3(vel) end
  local steps = math.floor(seconds / 0.1 + 0.5)
  for _ = 1, steps do
    h.vehicle.pos = h.vehicle.pos + stubs.vec3(h.vehicle.vel.x * 0.1, h.vehicle.vel.y * 0.1, h.vehicle.vel.z * 0.1)
    M.onUpdate(0.1, 0.1)
  end
end

function T.loads_all_48_drills()
  local h = setup()
  local s = h.lastState()
  eq(s.phase, 'idle', 'initial phase')
  eq(#s.lessons, 48, 'lesson count')
  eq(s.lessons[1].id, 'A01', 'first lesson')
end

function T.select_enters_setup_and_ignores_unknown_ids()
  local h, M = setup()
  M.select('ZZZ')
  eq(h.lastState().phase, 'idle', 'unknown id ignored')
  M.select('B01')
  local s = h.lastState()
  eq(s.phase, 'setup', 'phase')
  eq(s.selected, 'B01', 'selected')
  eq(s.target, 10, 'target attempts from drill data')
end

function T.retry_requires_a_marked_start()
  local h, M = setup()
  M.select('A01')
  M.retry()
  eq(h.lastState().phase, 'setup', 'still in setup')
  eq(#h.vehicle.teleports, 0, 'no teleport')
end

function T.retry_teleports_to_marked_start()
  local h, M = setup()
  M.select('A01')
  h.vehicle.pos = stubs.vec3(10, 20, 30)
  M.markStart()
  h.vehicle.pos = stubs.vec3(500, 0, 0)
  M.retry()
  eq(#h.vehicle.teleports, 1, 'teleported once')
  eq(h.vehicle.teleports[1].x, 10, 'x restored')
  eq(h.vehicle.teleports[1].z, 30, 'z restored')
  eq(h.lastState().phase, 'ready', 'phase ready')
end

-- Known issue (docs/ROADMAP.md, P0): retry does not zero velocity or repair.
-- This test documents today's behaviour; flip it when the fix lands.
function T.known_issue_retry_keeps_velocity()
  local h, M = setup()
  M.select('A01')
  M.markStart()
  h.vehicle.vel = stubs.vec3(0, 25, 0)
  M.retry()
  eq(h.vehicle.vel.y, 25, 'velocity untouched by retry (bug)')
end

function T.run_starts_when_moving_and_times_with_sim_dt()
  local h, M = setup()
  M.select('A04')
  M.markStart()
  M.retry()
  drive(h, M, 2.0, {x = 0, y = 10, z = 0})
  M.publish() -- HUD updates are throttled to 4 Hz; force a fresh snapshot
  local s = h.lastState()
  eq(s.phase, 'running', 'phase')
  assert(math.abs(s.elapsed - 2.0) < 1e-6, 'elapsed 2.0 s, got ' .. tostring(s.elapsed))
end

function T.paused_physics_does_not_add_time()
  local h, M = setup()
  M.select('A04')
  M.markStart()
  M.retry()
  drive(h, M, 1.0, {x = 0, y = 10, z = 0})
  M.publish()
  local before = h.lastState().elapsed
  for _ = 1, 50 do M.onUpdate(0.1, 0) end -- dtSim = 0 while paused
  M.publish()
  eq(h.lastState().elapsed, before, 'elapsed frozen while paused')
end

function T.finish_gate_stops_timer_and_requests_review()
  local h, M = setup()
  M.select('B01')
  h.vehicle.pos = stubs.vec3(0, 0, 0)
  M.markStart()
  h.vehicle.pos = stubs.vec3(0, 100, 0)
  M.markFinish()
  M.retry()
  h.vehicle.pos = stubs.vec3(0, 0, 0)
  drive(h, M, 12.0, {x = 0, y = 20, z = 0})
  local s = h.lastState()
  eq(s.phase, 'review', 'phase')
  assert(s.lastTime and s.lastTime > 4 and s.lastTime < 5.5, 'finish time ~4.8 s, got ' .. tostring(s.lastTime))
end

function T.record_attempt_persists_progress()
  local h, M = setup()
  M.select('A01')
  M.markStart()
  M.retry()
  M.recordAttempt(true)
  M.retry()
  M.recordAttempt(false)
  local s = h.lastState()
  eq(s.attempts, 2, 'attempts')
  eq(s.successes, 1, 'successes')
  local saved = jsonReadFile('settings/rallyAcademyProgress.json')
  eq(saved.lessons.A01.totalAttempts, 2, 'saved attempts')
  eq(saved.lessons.A01.totalPasses, 1, 'saved passes')
end

return T
