-- Telemetry sampling and per-attempt run records.
local H = require('ra_helpers')
local eq = H.eq
local setup = H.setup
local markStartAndFinish = H.markStartAndFinish
local has = H.has
local driveWithTelemetry = H.driveWithTelemetry
local commandsMatching = H.commandsMatching
local T = {}

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
  M.onTelemetry({id = h.vehicle.id, t = H.simT + 1, air = 0, w = {}})
  eq(#run.samples, n, 'no samples after the run closed')
  assert(has(h.logText('rallyAcademy'), 'B04: run record finished'), 'summary logged')
end

function T.samples_are_ignored_outside_a_run_and_from_other_cars()
  local h, M = setup()
  M.onTelemetry({id = h.vehicle.id, t = 1, w = {}}) -- no run yet: must not error
  markStartAndFinish(h, M, 'B04')
  M.retry()
  M.onTelemetry({id = 999, t = H.simT + 0.5, w = {}})
  eq(#M.getLastRun().samples, 0, 'other car ignored')
  M.onTelemetry({id = h.vehicle.id, t = H.simT + 0.6, w = {}})
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

return T
