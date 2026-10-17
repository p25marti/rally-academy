-- FWD-first drill lineup and Go to drill (map, car and spot in one press).
local H = require('ra_helpers')
local stubs = H.stubs
local eq = H.eq
local setup = H.setup
local drills = H.drills
local spawnOf = H.spawnOf
local tick = H.tick
local T = {}

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

function T.go_to_drill_on_another_map_loads_it_then_places_the_car()
  local h, M = setup()                       -- stub starts on driver_training
  M.select('A06')                            -- venue: west_coast_usa gravel track, Student Driver
  M.goToDrill()
  eq(h.levelsLoaded[1], '/levels/west_coast_usa/main/', 'map load requested')
  assert(h.lastState().reason:find('Loading', 1, true), 'tells you it is loading')
  eq(#h.vehicle.teleports, 0, 'nothing placed before the map is there')

  h.level = 'west_coast_usa'                 -- the game finishes loading
  M.onClientPostStartMission('/levels/west_coast_usa/main.level.json')
  eq(#h.spawned, 0, 'already in the Student Driver: no respawn')
  local pos, want = h.vehicle.teleports[#h.vehicle.teleports], spawnOf('A06')
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
  M.select('A06')
  M.goToDrill()
  assert(h.lastState().reason:find('Map not installed', 1, true), 'missing map reported')
end

function T.choosing_another_drill_while_loading_cancels_the_arrival()
  local h, M = setup()
  M.select('A06')
  M.goToDrill()
  M.select('B04')                            -- changed your mind during the load
  h.level = 'west_coast_usa'
  M.onClientPostStartMission('/levels/west_coast_usa/main.level.json')
  eq(#h.vehicle.teleports, 0, 'no surprise teleport')
end

-- Venues are shared data (venues.json); the loader fills each drill's map, name and spawn.
function T.drills_get_their_venue_filled_in_on_load()
  local h, M = setup()
  M.select('A04')
  local env = h.lastState().lesson.environment
  eq(env.venue, 'bmp-gravel-track', 'venue id kept')
  eq(env.levelId, 'west_coast_usa', 'map from the venue')
  eq(env.mapDisplayName, 'West Coast USA: BMP Gravel Track', 'display name from the venue')
  assert(env.spawn and env.spawn.pos, 'spawn from the venue')
end

function T.an_unknown_venue_is_logged_as_an_error()
  local h = stubs.install()
  h.files['gameplay/rallyAcademy/venues.json'] = '{"schemaVersion": 1, "venues": []}'
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  H.has(h.logText('rallyAcademy'), 'unknown venue bmp-gravel-track')
end

return T
