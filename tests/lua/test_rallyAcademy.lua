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

-- spawn.safeTeleport rotates 180 degrees itself, so Retry must hand it the
-- rotation built from the plain (not negated) direction vector.
function T.retry_faces_the_marked_direction()
  local h, M = setup()
  M.select('A01')
  h.vehicle.dir = stubs.vec3(0, 1, 0)
  M.markStart()
  h.vehicle.dir = stubs.vec3(1, 0, 0) -- car turned since
  M.retry()
  eq(h.vehicle.teleports[1].rot._dir.y, 1, 'rotation from the marked forward vector')
end

function T.retry_repairs_damage()
  local h, M = setup()
  M.select('A01')
  M.markStart()
  h.vehicle.damage = 1500
  M.retry()
  eq(h.vehicle.teleports[1].reset, true, 'teleport asks for a vehicle reset')
  eq(h.vehicle.damage, 0, 'damage repaired')
end

-- Formerly known_issue_retry_keeps_velocity. In-game on 0.39.4, Retry at
-- 4.25 m/s left the car at 0.03 m/s: setPositionRotation already stops it.
-- (Damage is still not repaired; see ROADMAP.)
function T.retry_leaves_car_at_rest()
  local h, M = setup()
  M.select('A01')
  M.markStart()
  h.vehicle.vel = stubs.vec3(0, 25, 0)
  M.retry()
  eq(h.vehicle.vel:length(), 0, 'car at rest after retry')
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

-- Seen in-game on 0.39.4: the first frame after setPositionRotation reports
-- ~430 m/s while the car is sitting at the start. That must not start the run.
function T.teleport_velocity_spike_does_not_start_run()
  local h, M = setup()
  M.select('A04')
  h.vehicle.pos = stubs.vec3(5, 5, 0)
  M.markStart()
  M.retry()
  h.vehicle.vel = stubs.vec3(0, 430, 0) -- spike, but the car has not moved
  M.onUpdate(0.016, 0.016)
  h.vehicle.vel = stubs.vec3(0, 0.3, 0) -- suspension settling
  M.onUpdate(0.016, 0.016)
  eq(h.lastState().phase, 'ready', 'still waiting for the driver')
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

-- A01 has no finish gate here, so the driver ends each run with Pass/Miss.
function T.record_attempt_persists_progress()
  local h, M = setup()
  M.select('A01')
  M.markStart()
  M.retry()
  drive(h, M, 1.0, {x = 0, y = 10, z = 0})
  M.recordAttempt(true)
  M.retry()
  drive(h, M, 1.0, {x = 0, y = 10, z = 0})
  M.recordAttempt(false)
  local s = h.lastState()
  eq(s.attempts, 2, 'attempts')
  eq(s.successes, 1, 'successes')
  local saved = jsonReadFile('settings/rallyAcademyProgress.json')
  eq(saved.lessons.A01.totalAttempts, 2, 'saved attempts')
  eq(saved.lessons.A01.totalPasses, 1, 'saved passes')
end

function T.no_finish_gate_pass_records_run_time_as_best()
  local h, M = setup()
  M.select('A01')
  M.markStart()
  M.retry()
  drive(h, M, 2.0, {x = 0, y = 10, z = 0})
  M.recordAttempt(true)
  local best = jsonReadFile('settings/rallyAcademyProgress.json').lessons.A01.bestTime
  assert(best and math.abs(best - 2.0) < 1e-6, 'best 2.0 s, got ' .. tostring(best))
end

function T.scoring_before_driving_is_ignored()
  local h, M = setup()
  M.select('A01')
  M.markStart()
  M.retry()
  M.recordAttempt(true)
  M.recordAttempt(false)
  local s = h.lastState()
  eq(s.phase, 'ready', 'still ready')
  eq(s.attempts, 0, 'nothing recorded')
  eq(jsonReadFile('settings/rallyAcademyProgress.json'), nil, 'nothing saved')
end

-- With a finish gate, a run in progress can't be passed (its time is partial);
-- Miss abandons it and records no time.
function T.pass_mid_run_with_finish_gate_is_refused()
  local h, M = setup()
  M.select('B01')
  h.vehicle.pos = stubs.vec3(0, 0, 0)
  M.markStart()
  h.vehicle.pos = stubs.vec3(0, 100, 0)
  M.markFinish()
  M.retry()
  drive(h, M, 1.0, {x = 0, y = 10, z = 0})
  M.recordAttempt(true)
  local s = h.lastState()
  eq(s.phase, 'running', 'run continues')
  eq(s.attempts, 0, 'pass not recorded')
  eq(jsonReadFile('settings/rallyAcademyProgress.json'), nil, 'nothing saved')

  M.recordAttempt(false)
  s = h.lastState()
  eq(s.phase, 'scored', 'abandoned run scored as a miss')
  eq(s.attempts, 1, 'miss recorded')
  eq(s.lastTime, nil, 'no time for an abandoned run')
  local saved = jsonReadFile('settings/rallyAcademyProgress.json').lessons.B01
  eq(saved.totalAttempts, 1, 'saved attempt')
  eq(saved.bestTime, nil, 'no best time')
end

-- Start/finish persistence: settings/rallyAcademySetups.json, per map then drill.
local SETUPS = 'settings/rallyAcademySetups.json'

local function markStartAndFinish(h, M, id)
  M.select(id)
  h.vehicle.pos = stubs.vec3(10, 20, 30)
  M.markStart()
  h.vehicle.pos = stubs.vec3(10, 120, 30)
  M.markFinish()
end

-- Simulates an extension reload / game restart: fresh module, same files on disk.
local function reloadExtension()
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  return M
end

function T.marks_are_saved_per_map_and_drill()
  local h, M = setup()
  markStartAndFinish(h, M, 'A01')
  local saved = jsonReadFile(SETUPS).levels.driver_training.A01
  eq(saved.start.pos.y, 20, 'start saved')
  eq(saved.finish.pos.y, 120, 'finish saved')
  eq(saved.start.vehicleId, nil, 'vehicle id not saved')
end

function T.saved_setup_is_restored_after_reload()
  local h, M = setup()
  markStartAndFinish(h, M, 'A01')
  M = reloadExtension()
  M.select('A01')
  local s = h.lastState()
  eq(s.hasStart, true, 'start restored')
  eq(s.hasFinish, true, 'finish restored')
  h.vehicle.pos = stubs.vec3(500, 0, 0)
  M.retry()
  eq(h.lastState().phase, 'ready', 'retry works straight away')
  eq(h.vehicle.teleports[#h.vehicle.teleports].y, 20, 'teleported to the saved start')
end

function T.each_map_has_its_own_setup()
  local h, M = setup()
  markStartAndFinish(h, M, 'A01')
  h.level = 'west_coast_usa'
  M.select('A01')
  eq(h.lastState().hasStart, false, 'no start on the other map')
  h.level = 'driver_training'
  M.select('A01')
  eq(h.lastState().hasStart, true, 'back on the first map, start is there')
end

-- Vehicle ids change every session; a saved start must work with today's car.
function T.retry_uses_the_current_car()
  local h, M = setup()
  markStartAndFinish(h, M, 'A01')
  M = reloadExtension()
  h.vehicle.id = 42
  M.select('A01')
  M.retry()
  eq(h.lastState().phase, 'ready', 'retry accepted with a different vehicle id')
  drive(h, M, 1.0, {x = 0, y = 10, z = 0})
  eq(h.lastState().phase, 'running', 'run tracks the current car')
end

-- Vehicle switch / map changes ------------------------------------------------

local function startRun(h, M)
  markStartAndFinish(h, M, 'A01')
  M.retry()
  drive(h, M, 1.0, {x = 0, y = 10, z = 0})
  eq(h.lastState().phase, 'running', 'precondition: running')
end

function T.vehicle_switch_mid_run_returns_to_setup()
  local h, M = setup()
  startRun(h, M)
  M.onVehicleSwitched(1, 2, 0)
  local s = h.lastState()
  eq(s.phase, 'setup', 'run abandoned')
  eq(s.attempts, 0, 'nothing scored')
  eq(s.hasStart, true, 'start kept')
  eq(s.hasFinish, true, 'finish kept')
end

-- If the hook doesn't fire (e.g. the car is deleted), onUpdate notices instead of
-- leaving the timer frozen in 'running'.
function T.different_car_in_on_update_returns_to_setup()
  local h, M = setup()
  startRun(h, M)
  h.vehicle.id = 99
  M.onUpdate(0.1, 0.1)
  eq(h.lastState().phase, 'setup', 'run abandoned')
end

function T.vehicle_switch_while_not_running_changes_nothing()
  local h, M = setup()
  markStartAndFinish(h, M, 'A01')
  local before = #h.events
  M.onVehicleSwitched(1, 2, 0)
  eq(#h.events, before, 'no state change published')
  eq(h.lastState().phase, 'setup', 'still setup')
end

function T.map_change_swaps_in_that_maps_setup()
  local h, M = setup()
  markStartAndFinish(h, M, 'A01')           -- saved on driver_training
  M.onClientEndMission('/levels/driver_training/')
  local s = h.lastState()
  eq(s.hasStart, false, 'old map start dropped on unload')
  eq(s.selected, 'A01', 'drill stays selected')
  M.retry()
  eq(#h.vehicle.teleports, 0, 'no retry to the old map coordinates')

  h.level = 'west_coast_usa'
  M.onClientPostStartMission('/levels/west_coast_usa/')
  eq(h.lastState().hasStart, false, 'nothing saved on the new map')

  h.level = 'driver_training'
  M.onClientEndMission('/levels/west_coast_usa/')
  M.onClientPostStartMission('/levels/driver_training/')
  eq(h.lastState().hasStart, true, 'saved setup back when returning to the map')
end

return T
