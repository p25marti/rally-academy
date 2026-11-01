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
  markStartAndFinish(h, M, 'T02')
  M.retry()
  eq(commandsMatching(h, "extensions.load('rallyAcademy/telemetry')"), 1, 'sampler loaded')
  eq(commandsMatching(h, "rallyAcademy_telemetry.start(60, 'rallyAcademy')"), 1, 'sampler started at 60 Hz')
  local run = M.getLastRun()
  eq(run.meta.drill, 'T02', 'record for the drill')
  eq(run.meta.level, 'driver_training', 'record knows the map')
end

function T.run_is_recorded_and_closed_at_the_finish()
  local h, M = setup()
  markStartAndFinish(h, M, 'T02')      -- start (10,20), finish (10,120)
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
  assert(has(h.logText('rallyAcademy'), 'T02: run record finished'), 'summary logged')
end

function T.samples_are_ignored_outside_a_run_and_from_other_cars()
  local h, M = setup()
  M.onTelemetry({id = h.vehicle.id, t = 1, w = {}}) -- no run yet: must not error
  markStartAndFinish(h, M, 'T02')
  M.retry()
  M.onTelemetry({id = 999, t = H.simT + 0.5, w = {}})
  eq(#M.getLastRun().samples, 0, 'other car ignored')
  M.onTelemetry({id = h.vehicle.id, t = H.simT + 0.6, w = {}})
  eq(#M.getLastRun().samples, 1, 'own car recorded')
end

function T.vehicle_switch_closes_the_record_as_abandoned()
  local h, M = setup()
  markStartAndFinish(h, M, 'T02')
  M.retry()
  driveWithTelemetry(h, M, 1.0, {x = 0, y = 10, z = 0})
  M.onVehicleSwitched(1, 2, 0)
  eq(M.getLastRun().outcome, 'abandoned', 'abandoned')
end

function T.retry_mid_run_restarts_with_a_new_record()
  local h, M = setup()
  markStartAndFinish(h, M, 'T02')
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
  markStartAndFinish(h, M, 'T02')
  M.retry()
  driveWithTelemetry(h, M, 8.0, {x = 0, y = 20, z = 0})
  M.recordAttempt(true)
  local run = M.getLastRun()
  eq(run.score.passed, true, 'pass recorded on the run')
  assert(run.score.time and run.score.time > 4, 'time recorded on the run')
end

function T.miss_mid_run_closes_the_record_as_abandoned()
  local h, M = setup()
  markStartAndFinish(h, M, 'T02')
  M.retry()
  driveWithTelemetry(h, M, 1.0, {x = 0, y = 10, z = 0})
  M.recordAttempt(false)
  local run = M.getLastRun()
  eq(run.outcome, 'abandoned', 'abandoned')
  eq(run.score.passed, false, 'miss recorded')
end

local function keptRuns(h)
  local paths = {}
  for path in pairs(h.files) do
    if path:find('^settings/rallyAcademy/runs/') then paths[#paths + 1] = path end
  end
  table.sort(paths)
  return paths
end

local function scoreARun(h, M)
  M.retry()
  driveWithTelemetry(h, M, 8.0, {x = 0, y = 20, z = 0})
  M.recordAttempt(true)
end

function T.scored_attempts_are_kept_on_disk_unless_the_player_turns_it_off()
  local h, M = setup()
  markStartAndFinish(h, M, 'T02')
  eq(h.lastState().keepRuns, true, 'on by default')
  scoreARun(h, M)
  local paths = keptRuns(h)
  eq(#paths, 1, 'one attempt kept')
  assert(paths[1]:find('^settings/rallyAcademy/runs/T02/%d+%-%d+%.json$'), 'kept by drill and time: ' .. paths[1])
  local kept = jsonReadFile(paths[1])
  eq(kept.meta.drill, 'T02', 'its drill')
  assert(kept.meta.recordedAt, 'when it was driven')
  eq(kept.score.passed, true, 'its score')
  eq(#kept.samples, #M.getLastRun().samples, 'all its samples')
  M.setKeepRuns(false)
  eq(jsonReadFile('settings/rallyAcademy/prefs.json').keepRuns, false, 'preference saved')
  for path in pairs(h.files) do if path:find('^settings/rallyAcademy/runs/') then h.files[path] = nil end end
  scoreARun(h, M)
  eq(#keptRuns(h), 0, 'turned off: nothing kept')
  local M2 = H.reloadExtension()
  M2.select('T02')
  eq(h.lastState().keepRuns, false, 'remembered after a reload')
  eq(M2.getMenuData().info.keepRuns, false, 'and shown on the About page')
end

function T.scripted_runs_are_not_kept_while_paused()
  local h, M = setup()
  markStartAndFinish(h, M, 'T02')
  M.devKeepRunsPaused(true)
  scoreARun(h, M)
  eq(#keptRuns(h), 0, 'paused: nothing kept')
  M.devKeepRunsPaused(false)
  scoreARun(h, M)
  eq(#keptRuns(h), 1, 'kept again')
end

function T.only_the_newest_runs_are_kept()
  local h = setup()
  local Store = require('ge/extensions/rallyAcademy/store')
  for _, stamp in ipairs({'20261101-100000', '20261101-090000', '20261102-080000'}) do
    h.files['settings/rallyAcademy/runs/C08/' .. stamp .. '.json'] = '{}'
  end
  h.files['settings/rallyAcademy/runs/B01/20261101-120000.json'] = '{}'
  local removed = {}
  _G.FS = {
    findFiles = function(_, dir, pattern)
      eq(dir, '/settings/rallyAcademy/runs/', 'searches the runs folder')
      eq(pattern, '*.json', 'for run files')
      local out = {}
      for path in pairs(h.files) do
        if path:find('^settings/rallyAcademy/runs/') then out[#out + 1] = '/' .. path end
      end
      return out
    end,
    removeFile = function(_, path) removed[#removed + 1] = path; h.files[path:sub(2)] = nil end,
  }
  eq(Store.pruneRuns(10), 0, 'under the limit: nothing removed')
  eq(Store.pruneRuns(2), 2, 'two over')
  table.sort(removed)
  eq(removed[1], '/settings/rallyAcademy/runs/C08/20261101-090000.json', 'the oldest went')
  eq(removed[2], '/settings/rallyAcademy/runs/C08/20261101-100000.json', 'then the next oldest, across drills')
  _G.FS = nil
end

function T.save_last_run_writes_json()
  local h, M = setup()
  eq(M.saveLastRun(), nil, 'nothing to save yet')
  markStartAndFinish(h, M, 'T02')
  M.retry()
  driveWithTelemetry(h, M, 1.0, {x = 0, y = 10, z = 0})
  local path = M.saveLastRun()
  eq(path, 'settings/rallyAcademy/lastRun.json', 'default path')
  local saved = jsonReadFile(path)
  eq(saved.meta.drill, 'T02', 'saved meta')
  eq(#saved.samples, #M.getLastRun().samples, 'saved samples')
end

return T
