-- Core loop: drill catalogue, Retry, run timing, scoring and logging.
local H = require('ra_helpers')
local stubs = H.stubs
local eq = H.eq
local setup = H.setup
local drive = H.drive
local markStartAndFinish = H.markStartAndFinish
local has = H.has
local T = {}

function T.loads_all_42_drills()
  local h = setup()
  local s = h.lastState()
  eq(s.phase, 'idle', 'initial phase')
  eq(#s.lessons, 42 + #stubs.testDrills(), 'lesson count: 42 shipped (F01-F05, F08 cut: ADR 0006) + the test drills')
  eq(s.lessons[1].id, 'A01', 'first lesson')
end

function T.select_enters_setup_and_ignores_unknown_ids()
  local h, M = setup()
  M.select('ZZZ')
  eq(h.lastState().phase, 'idle', 'unknown id ignored')
  M.select('T02')
  local s = h.lastState()
  eq(s.phase, 'setup', 'phase')
  eq(s.selected, 'T02', 'selected')
  eq(s.target, 10, 'target attempts from drill data')
end

function T.retry_requires_a_marked_start()
  local h, M = setup()
  M.select('T01')
  M.retry()
  eq(h.lastState().phase, 'setup', 'still in setup')
  eq(#h.vehicle.teleports, 0, 'no teleport')
end

function T.retry_teleports_to_marked_start()
  local h, M = setup()
  M.select('T01')
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
  M.select('T01')
  h.vehicle.dir = stubs.vec3(0, 1, 0)
  M.markStart()
  h.vehicle.dir = stubs.vec3(1, 0, 0) -- car turned since
  M.retry()
  eq(h.vehicle.teleports[1].rot._dir.y, 1, 'rotation from the marked forward vector')
end

function T.retry_repairs_damage()
  local h, M = setup()
  M.select('T01')
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
  M.select('T01')
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
  M.select('T02')
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

-- A06 has no finish gate here, so the driver ends each run with Pass/Miss.
function T.record_attempt_persists_progress()
  local h, M = setup()
  M.select('T01')
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
  eq(saved.lessons.T01.totalAttempts, 2, 'saved attempts')
  eq(saved.lessons.T01.totalPasses, 1, 'saved passes')
end

function T.no_finish_gate_pass_records_run_time_as_best()
  local h, M = setup()
  M.select('T01')
  M.markStart()
  M.retry()
  M.onUpdate(0.1, 0.1) -- a frame at rest after Retry, as in the game (origin is captured here)
  drive(h, M, 2.0, {x = 0, y = 10, z = 0})
  M.recordAttempt(true)
  local best = jsonReadFile('settings/rallyAcademyProgress.json').lessons.T01.bestTime
  assert(best and math.abs(best - 2.0) < 1e-6, 'best 2.0 s, got ' .. tostring(best))
end

function T.scoring_before_driving_is_ignored()
  local h, M = setup()
  M.select('T01')
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
  M.select('T02')
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
  local saved = jsonReadFile('settings/rallyAcademyProgress.json').lessons.T02
  eq(saved.totalAttempts, 1, 'saved attempt')
  eq(saved.bestTime, nil, 'no best time')
end

function T.key_events_are_logged_with_the_rallyAcademy_tag()
  local h, M = setup()
  markStartAndFinish(h, M, 'T02')
  M.retry()
  h.vehicle.pos = stubs.vec3(10, 20, 30)
  drive(h, M, 8.0, {x = 0, y = 20, z = 0})
  M.recordAttempt(true)
  local text = h.logText('rallyAcademy')
  for _, needle in ipairs({'drills on map driver_training', 'selected T02 on driver_training',
                           'start marked for T02', 'finish marked for T02', 'retry: T02',
                           'T02: run started', 'T02: finish reached in', 'T02: PASS, time'}) do
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
  markStartAndFinish(h, M, 'T01')
  M.retry()
  drive(h, M, 1.0, {x = 0, y = 10, z = 0})
  local before = #h.logs
  for _ = 1, 100 do M.onUpdate(0.016, 0.016) end
  eq(#h.logs, before, 'no log spam while driving')
end

-- Key bindings (Stream Deck): step through the drills and toggle auto-retry without the HUD.
function T.next_and_previous_drill_step_through_the_curriculum_and_wrap()
  local h, M = H.setup()
  M.select('A01')
  M.selectNext()
  eq(h.lastState().selected, 'A02', 'next')
  H.has(h.messages[#h.messages], 'A02 · ')
  M.selectPrevious()
  M.selectPrevious()
  local last = M.getMenuData().lessons
  eq(h.lastState().selected, last[#last].id, 'previous from the first wraps to the last')
  M.selectNext()
  eq(h.lastState().selected, 'A01', 'and next wraps back')
end

function T.auto_retry_toggles_from_a_binding()
  local h, M = H.setup()
  M.select('A01')
  M.toggleAutoRetry()
  eq(h.lastState().autoRetry, false, 'off')
  H.has(h.messages[#h.messages], 'auto-retry off')
  M.toggleAutoRetry()
  eq(h.lastState().autoRetry, true, 'on again')
end

return T
