-- Venue bookmarks: spots.lua (pure) and "Save spot" through the extension.
local Spots = require('ge/extensions/rallyAcademy/spots')
local H = require('ra_helpers')
local stubs = H.stubs
local eq, has, setup = H.eq, H.has, H.setup
local T = {}

local function measure(over)
  local m = {level = 'west_coast_usa', pos = {x = 110.123, y = 170.456, z = 118.01}, dir = {x = 0, y = 1, z = 0},
             upZ = 1, room = {57.4, 11, 7, 10, 150, 8, 6, 8}, road = {name = 'a-b', width = 8, drivability = 1, dist = 0.5}}
  for k, v in pairs(over or {}) do m[k] = v end
  return m
end

function T.a_spot_records_rounded_measurements_and_slope()
  local s = Spots.record(measure({upZ = math.cos(math.rad(3))}))
  eq(s.pos.x, 110.12, 'position to the centimetre')
  eq(s.room[1], 57, 'room to the metre')
  eq(s.slopeDeg, 3, 'slope from the up vector')
  eq(s.road.width, 8, 'road width')
end

function T.ids_are_unique_and_summaries_read_well()
  local list = {}
  Spots.add(list, Spots.record(measure()))
  local s = Spots.add(list, Spots.record(measure({road = {name = 'x', width = 6, drivability = 0.5, dist = 1}})))
  eq(s.id, 2, 'next id')
  eq(Spots.find(list, 2), s, 'find by id')
  eq(Spots.summary(s), 'Spot 2 saved: room ahead 57 m, behind 150 m; road 6.0 m wide; slope 0.0°', 'summary')
  has(Spots.summary(Spots.record(measure({road = {name = 'x', width = 6, dist = 30}}))), 'off road')
end

function T.save_spot_writes_the_file_shows_a_message_and_asks_the_car_for_surfaces()
  local h, M = setup()
  h.vehicle.pos = stubs.vec3(10, 20, 30)
  local id = M.saveSpot('near the BMP start')
  eq(id, 1, 'first spot')
  local saved = jsonReadFile('settings/rallyAcademy/spots.json').spots[1]
  eq(saved.level, 'driver_training', 'map')
  eq(saved.road.width, 7, 'road width from the narrower node (2 x 3.5 m)')
  eq(saved.road.drivability, 0.5, 'drivability of the link')
  eq(#saved.room, 8, 'room in eight directions')
  eq(saved.note, 'near the BMP start', 'note')
  has(h.messages[1], 'Spot 1 saved')
  has(h.vehicle.luaCommands[#h.vehicle.luaCommands], 'onSpotSurfaces(1,')
  M.onSpotSurfaces(1, {FL = 'GRAVEL', FR = 'ASPHALT'})
  eq(jsonReadFile('settings/rallyAcademy/spots.json').spots[1].surfaces.FL, 'GRAVEL', 'surfaces filled in by the car')
end

-- Venue fit tests record telemetry without touching drills (tools/ingame/fit.py).
function T.dev_recording_captures_samples_without_touching_the_drill()
  local h, M = setup()
  M.select('B01')
  local before = jsonReadFile('settings/rallyAcademySetups.json')
  eq(M.devRecordStart(), true, 'started')
  has(h.vehicle.luaCommands[#h.vehicle.luaCommands], "rallyAcademy_telemetry.start(")
  M.onTelemetry({id = h.vehicle.id, t = 1, x = 0, y = 0, z = 0, air = 5, w = {}})
  M.onTelemetry({id = h.vehicle.id, t = 2, x = 0, y = 5, z = 0, air = 5, w = {}})
  eq(M.devRecordStop(), 2, 'two samples kept')
  eq(M.getLastRun().meta.drill, 'fit test', 'tagged as a fit test')
  eq(jsonReadFile('settings/rallyAcademySetups.json'), before, 'no setup saved')
  eq(h.lastState().attempts, 0, 'nothing scored')
  eq(M.devRecordStop(), 0, 'stopping twice is harmless')
end

return T
