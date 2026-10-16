-- Saved starts/finishes per map and drill, and car or map changes mid-run.
local H = require('ra_helpers')
local stubs = H.stubs
local eq = H.eq
local setup = H.setup
local drive = H.drive
local SETUPS = H.SETUPS
local markStartAndFinish = H.markStartAndFinish
local reloadExtension = H.reloadExtension
local startRun = H.startRun
local T = {}

function T.marks_are_saved_per_map_and_drill()
  local h, M = setup()
  markStartAndFinish(h, M, 'A03')
  local saved = jsonReadFile(SETUPS).levels.driver_training.A03
  eq(saved.start.pos.y, 20, 'start saved')
  eq(saved.finish.pos.y, 120, 'finish saved')
  eq(saved.start.vehicleId, nil, 'vehicle id not saved')
end

function T.saved_setup_is_restored_after_reload()
  local h, M = setup()
  markStartAndFinish(h, M, 'A03')
  M = reloadExtension()
  M.select('A03')
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
  markStartAndFinish(h, M, 'A03')
  h.level = 'west_coast_usa'
  M.select('A03')
  eq(h.lastState().hasStart, false, 'no start on the other map')
  h.level = 'driver_training'
  M.select('A03')
  eq(h.lastState().hasStart, true, 'back on the first map, start is there')
end

-- Vehicle ids change every session; a saved start must work with today's car.
function T.retry_uses_the_current_car()
  local h, M = setup()
  markStartAndFinish(h, M, 'A03')
  M = reloadExtension()
  h.vehicle.id = 42
  M.select('A03')
  M.retry()
  eq(h.lastState().phase, 'ready', 'retry accepted with a different vehicle id')
  drive(h, M, 1.0, {x = 0, y = 10, z = 0})
  eq(h.lastState().phase, 'running', 'run tracks the current car')
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
  markStartAndFinish(h, M, 'A03')
  local before = #h.events
  M.onVehicleSwitched(1, 2, 0)
  eq(#h.events, before, 'no state change published')
  eq(h.lastState().phase, 'setup', 'still setup')
end

function T.map_change_swaps_in_that_maps_setup()
  local h, M = setup()
  markStartAndFinish(h, M, 'A03')           -- saved on driver_training
  M.onClientEndMission('/levels/driver_training/')
  local s = h.lastState()
  eq(s.hasStart, false, 'old map start dropped on unload')
  eq(s.selected, 'A03', 'drill stays selected')
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
