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
  M.select('B04')
  local s = h.lastState()
  eq(s.phase, 'setup', 'phase')
  eq(s.selected, 'B04', 'selected')
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
  M.onUpdate(0.1, 0.1) -- a frame at rest after Retry, as in the game (origin is captured here)
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

-- Seen in-game: the repair-teleport nudged the car ~1 m off a start next to barriers,
-- which (with the post-teleport speed spike) started the run on its own.
function T.a_nudged_start_does_not_start_the_run()
  local h, M = setup()
  M.select('A04')
  h.vehicle.pos = stubs.vec3(5, 5, 0)
  M.markStart()
  M.retry()
  M.onUpdate(0.016, 0.016)                  -- first frame: car where safeTeleport put it
  h.vehicle.pos = stubs.vec3(6.9, 5.6, 0)   -- a frame later it is nudged ~1.9 m out of an overlap
  h.vehicle.vel = stubs.vec3(0, 3, 0)       -- moving while it is shoved
  for _ = 1, 3 do M.onUpdate(0.016, 0.016) end
  h.vehicle.vel = stubs.vec3(0, 0.1, 0)     -- and settles
  for _ = 1, 30 do M.onUpdate(0.016, 0.016) end
  eq(h.lastState().phase, 'ready', 'still waiting for the driver')
  -- now the driver goes: the run starts from the settled spot
  for _ = 1, 10 do
    h.vehicle.vel = stubs.vec3(0, 5, 0)
    h.vehicle.pos = h.vehicle.pos + stubs.vec3(0, 0.1, 0)
    M.onUpdate(0.016, 0.016)
  end
  eq(h.lastState().phase, 'running', 'started once the driver moved off the settled spot')
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
  M.select('B04')
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
  M.onUpdate(0.1, 0.1) -- a frame at rest after Retry, as in the game (origin is captured here)
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
  M.select('B04')
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
  local saved = jsonReadFile('settings/rallyAcademyProgress.json').lessons.B04
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

-- Logging -------------------------------------------------------------------

local function has(text, needle) return text:find(needle, 1, true) ~= nil end

function T.key_events_are_logged_with_the_rallyAcademy_tag()
  local h, M = setup()
  markStartAndFinish(h, M, 'B04')
  M.retry()
  h.vehicle.pos = stubs.vec3(10, 20, 30)
  drive(h, M, 8.0, {x = 0, y = 20, z = 0})
  M.recordAttempt(true)
  local text = h.logText('rallyAcademy')
  for _, needle in ipairs({'loaded 48 drills on map driver_training', 'selected B04 on driver_training',
                           'start marked for B04', 'finish marked for B04', 'retry: B04',
                           'B04: run started', 'B04: finish reached in', 'B04: PASS, time'}) do
    assert(has(text, needle), 'missing log line: ' .. needle .. '\n--- got:\n' .. text)
  end
end

function T.missing_drill_file_is_logged_as_an_error()
  local h = stubs.install()
  local real = _G.jsonReadFile
  _G.jsonReadFile = function(path) if path:find('exercises') then return nil end return real(path) end
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  _G.jsonReadFile = real
  assert(has(h.logText('rallyAcademy'), 'E could not read drills'), 'error logged')
end

function T.onUpdate_does_not_log_every_frame()
  local h, M = setup()
  markStartAndFinish(h, M, 'A01')
  M.retry()
  drive(h, M, 1.0, {x = 0, y = 10, z = 0})
  local before = #h.logs
  for _ = 1, 100 do M.onUpdate(0.016, 0.016) end
  eq(#h.logs, before, 'no log spam while driving')
end

-- Telemetry and run records ----------------------------------------------------

-- Like drive(), but the car's sampler also reports each step (as obj:queueGameEngineLua would).
local simT = 100
local function driveWithTelemetry(h, M, seconds, vel)
  if vel then h.vehicle.vel = stubs.vec3(vel) end
  local steps = math.floor(seconds / 0.1 + 0.5)
  for _ = 1, steps do
    h.vehicle.pos = h.vehicle.pos + stubs.vec3(h.vehicle.vel.x * 0.1, h.vehicle.vel.y * 0.1, h.vehicle.vel.z * 0.1)
    simT = simT + 0.1
    M.onTelemetry({id = h.vehicle.id, t = simT, air = h.vehicle.vel:length(), brk = 0, w = {}})
    M.onUpdate(0.1, 0.1)
  end
end

local function commandsMatching(h, needle)
  local n = 0
  for _, c in ipairs(h.vehicle.luaCommands) do if has(c, needle) then n = n + 1 end end
  return n
end

function T.retry_loads_and_starts_the_sampler_in_the_current_car()
  local h, M = setup()
  markStartAndFinish(h, M, 'B04')
  M.retry()
  eq(commandsMatching(h, "extensions.load('rallyAcademy/telemetry')"), 1, 'sampler loaded')
  eq(commandsMatching(h, "rallyAcademy_telemetry.start(60, 'rallyAcademy')"), 1, 'sampler started at 60 Hz')
  local run = M.getLastRun()
  eq(run.meta.drill, 'B04', 'record for the drill')
  eq(run.meta.level, 'driver_training', 'record knows the map')
end

function T.run_is_recorded_and_closed_at_the_finish()
  local h, M = setup()
  markStartAndFinish(h, M, 'B04')      -- start (10,20), finish (10,120)
  M.retry()
  driveWithTelemetry(h, M, 0.3)        -- stationary at the start
  driveWithTelemetry(h, M, 8.0, {x = 0, y = 20, z = 0})
  eq(h.lastState().phase, 'review', 'precondition: finished')
  local run = M.getLastRun()
  eq(run.outcome, 'finished', 'closed as finished')
  assert(#run.samples > 40, 'samples recorded, got ' .. #run.samples)
  assert(run.runStartT and run.runStartT > run.samples[1].t, 'run start marked after the pre-roll')
  eq(commandsMatching(h, 'rallyAcademy_telemetry.stop()'), 1, 'sampler stopped')
  local n = #run.samples
  M.onTelemetry({id = h.vehicle.id, t = simT + 1, air = 0, w = {}})
  eq(#run.samples, n, 'no samples after the run closed')
  assert(has(h.logText('rallyAcademy'), 'B04: run record finished'), 'summary logged')
end

function T.samples_are_ignored_outside_a_run_and_from_other_cars()
  local h, M = setup()
  M.onTelemetry({id = h.vehicle.id, t = 1, w = {}}) -- no run yet: must not error
  markStartAndFinish(h, M, 'B04')
  M.retry()
  M.onTelemetry({id = 999, t = simT + 0.5, w = {}})
  eq(#M.getLastRun().samples, 0, 'other car ignored')
  M.onTelemetry({id = h.vehicle.id, t = simT + 0.6, w = {}})
  eq(#M.getLastRun().samples, 1, 'own car recorded')
end

function T.vehicle_switch_closes_the_record_as_abandoned()
  local h, M = setup()
  markStartAndFinish(h, M, 'B04')
  M.retry()
  driveWithTelemetry(h, M, 1.0, {x = 0, y = 10, z = 0})
  M.onVehicleSwitched(1, 2, 0)
  eq(M.getLastRun().outcome, 'abandoned', 'abandoned')
end

function T.retry_mid_run_restarts_with_a_new_record()
  local h, M = setup()
  markStartAndFinish(h, M, 'B04')
  M.retry()
  driveWithTelemetry(h, M, 1.0, {x = 0, y = 10, z = 0})
  local first = M.getLastRun()
  M.retry()
  eq(first.outcome, 'restarted', 'old record closed as restarted')
  assert(M.getLastRun() ~= first, 'fresh record')
  eq(M.getLastRun().outcome, nil, 'fresh record is open')
end

function T.score_is_attached_to_the_run_record()
  local h, M = setup()
  markStartAndFinish(h, M, 'B04')
  M.retry()
  driveWithTelemetry(h, M, 8.0, {x = 0, y = 20, z = 0})
  M.recordAttempt(true)
  local run = M.getLastRun()
  eq(run.score.passed, true, 'pass recorded on the run')
  assert(run.score.time and run.score.time > 4, 'time recorded on the run')
end

function T.miss_mid_run_closes_the_record_as_abandoned()
  local h, M = setup()
  markStartAndFinish(h, M, 'B04')
  M.retry()
  driveWithTelemetry(h, M, 1.0, {x = 0, y = 10, z = 0})
  M.recordAttempt(false)
  local run = M.getLastRun()
  eq(run.outcome, 'abandoned', 'abandoned')
  eq(run.score.passed, false, 'miss recorded')
end

function T.save_last_run_writes_json()
  local h, M = setup()
  eq(M.saveLastRun(), nil, 'nothing to save yet')
  markStartAndFinish(h, M, 'B04')
  M.retry()
  driveWithTelemetry(h, M, 1.0, {x = 0, y = 10, z = 0})
  local path = M.saveLastRun()
  eq(path, 'settings/rallyAcademy/lastRun.json', 'default path')
  local saved = jsonReadFile(path)
  eq(saved.meta.drill, 'B04', 'saved meta')
  eq(#saved.samples, #M.getLastRun().samples, 'saved samples')
end

-- FWD-first lineup (docs/VEHICLES.md, MAPS.md Option A) ------------------------

local function drills()
  local byId = {}
  for _, e in ipairs(jsonReadFile('gameplay/rallyAcademy/exercises.json').exercises) do byId[e.id] = e end
  return byId
end

function T.lineup_parks_exactly_the_drills_fwd_cannot_do()
  stubs.install()
  local parked = {}
  for id, e in pairs(drills()) do if e.parked then parked[#parked + 1] = id end end
  table.sort(parked)
  eq(table.concat(parked, ','), 'C03,C05,C06,E03,E04', 'parked drills')
end

function T.every_active_drill_pins_a_fwd_covet_and_a_map()
  stubs.install()
  for id, e in pairs(drills()) do
    assert(e.environment.levelId == 'west_coast_usa' or e.environment.levelId == 'utah', id .. ' map')
    if not e.parked then
      eq(e.vehicle.modelId, 'covet', id .. ' model')
      assert(e.vehicle.configPath == 'vehicles/covet/student_driver.pc' or e.vehicle.configPath == 'vehicles/covet/rally_gravel.pc',
        id .. ' config ' .. tostring(e.vehicle.configPath))
      assert(e.vehicle.displayName:find('FWD', 1, true), id .. ' says FWD')
    end
  end
end

function T.parked_drills_are_flagged_in_the_catalogue_and_explained_on_select()
  local h, M = setup()
  local flagged = {}
  for _, l in ipairs(h.lastState().lessons) do if l.parked then flagged[#flagged + 1] = l.id end end
  eq(#flagged, 5, 'five parked drills flagged for the HUD')
  M.select('C03')
  local s = h.lastState()
  eq(s.selected, 'C03', 'still selectable')
  assert(s.reason:find('Parked for now', 1, true), 'reason explains: ' .. s.reason)
  M.select('B04')
  assert(not h.lastState().reason:find('Parked', 1, true), 'normal drills have no parked note')
end

-- Go to drill ---------------------------------------------------------------

local function spawnOf(id)
  for _, e in ipairs(jsonReadFile('gameplay/rallyAcademy/exercises.json').exercises) do
    if e.id == id then return e.environment.spawn.pos end
  end
end

local function tick(M, seconds)
  for _ = 1, math.floor(seconds / 0.1 + 0.5) do M.onUpdate(0.1, 0.1) end
end

function T.go_to_drill_on_another_map_loads_it_then_places_the_car()
  local h, M = setup()                       -- stub starts on driver_training
  M.select('A01')                            -- venue: west_coast_usa arena, Student Driver
  M.goToDrill()
  eq(h.levelsLoaded[1], '/levels/west_coast_usa/main/', 'map load requested')
  assert(h.lastState().reason:find('Loading', 1, true), 'tells you it is loading')
  eq(#h.vehicle.teleports, 0, 'nothing placed before the map is there')

  h.level = 'west_coast_usa'                 -- the game finishes loading
  M.onClientPostStartMission('/levels/west_coast_usa/main.level.json')
  eq(#h.spawned, 0, 'already in the Student Driver: no respawn')
  local pos, want = h.vehicle.teleports[#h.vehicle.teleports], spawnOf('A01')
  eq(pos.x, want.x, 'placed at the venue spot (x)')
  eq(pos.y, want.y, 'placed at the venue spot (y)')
  local s = h.lastState()
  eq(s.phase, 'setup', 'ready to mark a start')
  assert(s.reason:find('Mark start', 1, true), 'tells you what to do next: ' .. s.reason)
end

function T.go_to_drill_on_the_same_map_swaps_the_car_then_waits_before_placing()
  local h, M = setup()
  h.level = 'west_coast_usa'
  M.select('B04')                            -- Gravel Rally drill
  M.goToDrill()
  eq(#h.levelsLoaded, 0, 'no map load on the same map')
  eq(h.spawned[1].model, 'covet', 'covet spawned')
  eq(h.spawned[1].config, 'rally_gravel', 'gravel rally config')
  eq(#h.vehicle.teleports, 0, 'waits for the new car before teleporting')
  tick(M, 1.0)
  eq(#h.vehicle.teleports, 0, 'still waiting: the respawn has not finished')
  M.onVehicleSpawned(h.vehicle.id, h.vehicle)  -- the game reports the new car
  tick(M, 0.4)
  eq(#h.vehicle.teleports, 1, 'placed shortly after the spawn event')
  eq(h.vehicle.teleports[1].y, spawnOf('B04').y, 'at the venue spot')
end

-- Seen in-game on 0.39.4: the spawn hook fires *inside* replaceVehicle; listening only
-- afterwards missed it and fell back to the 6 s timeout.
function T.go_to_drill_catches_a_spawn_event_fired_inside_replace_vehicle()
  local h, M = setup()
  h.level = 'west_coast_usa'
  h.syncSpawnHook = true
  _G.extensions = {rallyAcademy = M}
  M.select('B04')
  M.goToDrill()
  tick(M, 0.4)
  _G.extensions = nil
  eq(#h.vehicle.teleports, 1, 'placed right after the synchronous spawn event')
end

function T.choosing_another_drill_during_a_car_swap_cancels_it()
  local h, M = setup()
  h.level = 'west_coast_usa'
  M.select('B04')
  M.goToDrill()
  M.select('B05')
  tick(M, 7)
  eq(#h.vehicle.teleports, 0, 'no placement for a drill you left')
end

function T.go_to_drill_ignores_spawn_events_for_other_cars()
  local h, M = setup()
  h.level = 'west_coast_usa'
  M.select('B04')
  M.goToDrill()
  M.onVehicleSpawned(77, {partConfig = 'vehicles/pickup/whatever.pc'})
  tick(M, 0.4)
  eq(#h.vehicle.teleports, 0, 'other cars do not trigger placement')
end

function T.go_to_drill_places_the_car_anyway_if_no_spawn_event_comes()
  local h, M = setup()
  h.level = 'west_coast_usa'
  M.select('B04')
  M.goToDrill()
  tick(M, 6.5)
  eq(#h.vehicle.teleports, 1, 'placed after the timeout')
end

-- Seen in-game: core_levels.getList() names the map 'Utah', getCurrentLevelIdentifier() says 'utah'.
function T.go_to_drill_matches_map_names_case_insensitively()
  local h, M = setup()
  _G.core_levels.getList = function() return {{levelName = 'Utah', fullfilename = '/levels/utah/main/'}} end
  M.select('E08')
  M.goToDrill()
  eq(h.levelsLoaded[1], '/levels/utah/main/', 'Utah found')
  h.level = 'Utah'
  M.select('E08')
  M.goToDrill()
  eq(#h.levelsLoaded, 1, 'already there: no second load, whatever the case')
end

function T.go_to_drill_with_a_saved_start_goes_straight_into_a_run()
  local h, M = setup()
  h.level = 'west_coast_usa'
  M.select('A02')
  h.vehicle.pos = stubs.vec3(5, 6, 7)
  M.markStart()                               -- saved for A02 on west_coast_usa
  h.vehicle.pos = stubs.vec3(900, 900, 0)
  M.goToDrill()
  local s = h.lastState()
  eq(s.phase, 'ready', 'straight into a run')
  eq(h.vehicle.teleports[#h.vehicle.teleports].x, 5, 'at the saved start')
  assert(s.reason:find('saved start', 1, true), s.reason)
end

function T.go_to_drill_reports_a_missing_map()
  local h, M = setup()
  _G.core_levels.getList = function() return {} end
  M.select('A01')
  M.goToDrill()
  assert(h.lastState().reason:find('Map not installed', 1, true), 'missing map reported')
end

function T.choosing_another_drill_while_loading_cancels_the_arrival()
  local h, M = setup()
  M.select('A01')
  M.goToDrill()
  M.select('B04')                            -- changed your mind during the load
  h.level = 'west_coast_usa'
  M.onClientPostStartMission('/levels/west_coast_usa/main.level.json')
  eq(#h.vehicle.teleports, 0, 'no surprise teleport')
end

-- B01: automatic grading -----------------------------------------------------

-- Retry, accelerate along +y to `kmh`, brake at `brakeAtY` with `decel` m/s2 until the car
-- stops, then stand still; the car's sampler reports every step (with position).
local function brakingRun(h, M, opts)
  local dt, v, braking, lockedT = 0.05, 0, false, 0
  local vmax = (opts.kmh or 70) / 3.6
  M.retry()
  local stoppedFor = 0
  for _ = 1, 2000 do
    if not braking and h.vehicle.pos.y >= (opts.brakeAtY or 80) then braking = true end
    if braking then v = math.max(0, v - (opts.decel or 7) * dt) else v = math.min(vmax, v + 4 * dt) end
    h.vehicle.vel = stubs.vec3(0, v, 0)
    h.vehicle.pos = h.vehicle.pos + stubs.vec3(0, v * dt, 0)
    simT = simT + dt
    local lock = braking and opts.lockFor and lockedT < opts.lockFor and v > 0
    if lock then lockedT = lockedT + dt end
    local fs = lock and 0 or v
    M.onTelemetry({id = h.vehicle.id, t = simT, x = h.vehicle.pos.x, y = h.vehicle.pos.y, z = 0, air = v,
      brk = braking and 0.8 or 0, w = {{n = 'FL', s = fs}, {n = 'FR', s = fs}, {n = 'RL', s = v}, {n = 'RR', s = v}}})
    M.onUpdate(dt, dt)
    if braking and v == 0 then stoppedFor = stoppedFor + dt end
    if h.lastState().phase == 'scored' or stoppedFor > 3 then break end
  end
  return h.lastState()
end

-- Start at the origin facing +y; stop zone centred at `zoneY`.
local function setupB01(zoneY)
  local h, M = setup()
  M.select('B01')
  h.vehicle.pos, h.vehicle.dir = stubs.vec3(0, 0, 0), stubs.vec3(0, 1, 0)
  M.markStart()
  h.vehicle.pos = stubs.vec3(0, zoneY, 0)
  M.markFinish()
  return h, M
end

-- With these defaults (70 km/h, braking at 80 m, 7 m/s2) the car stops near y = 107.
function T.b01_clean_stop_in_the_zone_is_graded_pass()
  local h, M = setupB01(107)
  local s = brakingRun(h, M, {})
  eq(s.phase, 'scored', 'graded and recorded on its own')
  eq(s.attempts, 1, 'one attempt')
  eq(s.successes, 1, 'counted as a pass')
  eq(s.grade.passed, true, 'grade passed')
  eq(#s.grade.checks, 3, 'three checks shown')
  assert(s.reason:find('PASS', 1, true), s.reason)
  local saved = jsonReadFile('settings/rallyAcademyProgress.json').lessons.B01
  eq(saved.totalPasses, 1, 'pass saved')
  eq(M.getLastRun().grade.passed, true, 'grade kept on the run record')
end

function T.b01_overshoot_is_graded_miss_with_the_reason()
  local h, M = setupB01(95)
  local s = brakingRun(h, M, {})
  eq(s.successes, 0, 'miss')
  eq(s.attempts, 1, 'recorded')
  assert(s.reason:find('MISS: Stopped', 1, true) and s.reason:find('past the zone', 1, true), s.reason)
end

function T.b01_locked_stop_is_graded_miss_for_lockup()
  local h, M = setupB01(107)
  local s = brakingRun(h, M, {lockFor = 1.5})
  eq(s.grade.passed, false, 'failed')
  local lock = s.grade.checks[3]
  eq(lock.ok, false, 'lockup check failed')
  assert(lock.text:find('locked for', 1, true), lock.text)
end

function T.b01_marking_says_stop_zone_and_the_run_ends_on_stopping()
  local h, M = setupB01(107)
  -- (setupB01 marked the zone; check the message it left)
  assert(h.lastState().reason:find('Stop zone centre marked', 1, true), h.lastState().reason)
  M.retry()
  -- drive past the start then sit still: run should end even far from any finish circle
  for _ = 1, 20 do h.vehicle.vel = stubs.vec3(0, 10, 0); h.vehicle.pos = h.vehicle.pos + stubs.vec3(0, 0.5, 0); M.onUpdate(0.05, 0.05) end
  h.vehicle.vel = stubs.vec3(0, 0, 0)
  for _ = 1, 40 do M.onUpdate(0.05, 0.05) end
  eq(h.lastState().attempts, 1, 'ended on stopping and was graded')
end

function T.self_assessed_drills_still_wait_for_pass_or_miss()
  local h, M = setup()
  markStartAndFinish(h, M, 'B04')
  M.retry()
  for _ = 1, 100 do h.vehicle.vel = stubs.vec3(0, 20, 0); h.vehicle.pos = h.vehicle.pos + stubs.vec3(0, 2, 0); M.onUpdate(0.1, 0.1) end
  local s = h.lastState()
  eq(s.phase, 'review', 'waiting for the driver')
  eq(s.attempts, 0, 'not recorded automatically')
  eq(s.grade, nil, 'no automatic grade')
end

function T.every_rule_in_the_drill_data_is_known_with_its_parameters()
  stubs.install()
  local Rules = require('ge/extensions/rallyAcademy/rules')
  for _, e in ipairs(jsonReadFile('gameplay/rallyAcademy/exercises.json').exercises) do
    for _, rule in ipairs(e.assessment.rules or {}) do
      local params = Rules.TYPES[rule.type]
      assert(params, e.id .. ': unknown rule type ' .. tostring(rule.type))
      for _, k in ipairs(params) do assert(type(rule[k]) == 'number', e.id .. ': ' .. rule.type .. ' needs ' .. k) end
    end
  end
end

return T
