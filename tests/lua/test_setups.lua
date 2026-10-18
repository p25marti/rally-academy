-- Saved starts/finishes per map and drill, and car or map changes mid-run.
local H = require('ra_helpers')
local stubs = H.stubs
local eq, has = H.eq, H.has
local setup = H.setup
local drive = H.drive
local SETUPS = H.SETUPS
local markStartAndFinish = H.markStartAndFinish
local reloadExtension = H.reloadExtension
local startRun = H.startRun
local T = {}

function T.marks_are_saved_per_map_and_drill()
  local h, M = setup()
  markStartAndFinish(h, M, 'T01')
  local saved = jsonReadFile(SETUPS).levels.driver_training.T01
  eq(saved.start.pos.y, 20, 'start saved')
  eq(saved.finish.pos.y, 120, 'finish saved')
  eq(saved.start.vehicleId, nil, 'vehicle id not saved')
end

function T.saved_setup_is_restored_after_reload()
  local h, M = setup()
  markStartAndFinish(h, M, 'T01')
  M = reloadExtension()
  M.select('T01')
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
  markStartAndFinish(h, M, 'T01')
  h.level = 'west_coast_usa'
  M.select('T01')
  eq(h.lastState().hasStart, false, 'no start on the other map')
  h.level = 'driver_training'
  M.select('T01')
  eq(h.lastState().hasStart, true, 'back on the first map, start is there')
end

-- Vehicle ids change every session; a saved start must work with today's car.
function T.retry_uses_the_current_car()
  local h, M = setup()
  markStartAndFinish(h, M, 'T01')
  M = reloadExtension()
  h.vehicle.id = 42
  M.select('T01')
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
  markStartAndFinish(h, M, 'T01')
  local before = #h.events
  M.onVehicleSwitched(1, 2, 0)
  eq(#h.events, before, 'no state change published')
  eq(h.lastState().phase, 'setup', 'still setup')
end

function T.map_change_swaps_in_that_maps_setup()
  local h, M = setup()
  markStartAndFinish(h, M, 'T01')           -- saved on driver_training
  M.onClientEndMission('/levels/driver_training/')
  local s = h.lastState()
  eq(s.hasStart, false, 'old map start dropped on unload')
  eq(s.selected, 'T01', 'drill stays selected')
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

-- Stale setups: a saved start belongs to the venue and course it was marked for.
local function saveRaw(level, id, entry)
  local data = jsonReadFile(SETUPS) or {schemaVersion = 1, levels = {}}
  data.levels[level] = data.levels[level] or {}
  data.levels[level][id] = entry
  jsonWriteFile(SETUPS, data)
end
local START = {pos = {x = 1, y = 2, z = 3}, dir = {x = 0, y = 1, z = 0}, up = {x = 0, y = 0, z = 1}}

function T.a_start_saved_before_a_drill_got_its_course_is_dropped()
  local h = stubs.install()
  h.level = 'west_coast_usa'
  saveRaw('west_coast_usa', 'A01', {start = START})            -- from before A01 had a course
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  M.select('A01')
  local s = h.lastState()
  eq(s.usingVenueStart, true, 'laid out at the venue instead')
  has(s.reason, 'Your saved start was cleared because it now lays out its own course')
  eq(jsonReadFile(SETUPS).levels.west_coast_usa.A01, nil, 'and forgotten')
end

function T.a_start_marked_for_the_current_course_survives_a_restart()
  local h, M = setup()
  h.level = 'west_coast_usa'
  M.select('A01')
  h.vehicle.pos = stubs.vec3(5, 5, 5)
  M.markStart()
  M = reloadExtension()
  M.select('A01')
  eq(h.lastState().usingVenueStart, false, 'your own start')
  has(h.lastState().reason, 'Loaded your saved start')
end

function T.a_changed_course_drops_the_start_marked_for_the_old_one()
  local h = stubs.install()
  h.level = 'west_coast_usa'
  saveRaw('west_coast_usa', 'A01', {start = START, venue = 'bmp-dirt-arena', course = '{old course}'})
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  M.select('A01')
  has(h.lastState().reason, 'because its course changed')
end

function T.marked_drills_keep_old_setups_unless_their_venue_changed()
  local h = stubs.install()
  saveRaw('driver_training', 'T01', {start = START})            -- recorded no venue: kept
  saveRaw('driver_training', 'T02', {start = START, venue = 'somewhere-else'})
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  M.select('T01')
  eq(h.lastState().hasStart, true, 'old setup kept')
  M.select('T02')
  eq(h.lastState().hasStart, false, 'dropped')
  has(h.lastState().reason, 'because it moved to another venue')
end

return T
