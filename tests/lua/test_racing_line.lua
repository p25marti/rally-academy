-- The racing line ("Show line"): layout.racingLine (pure) picks the drill's stretch of the map's lines, and the
-- extension draws it when the player turns it on (T03 as a marked-gate drill on a test map with one line).
local L = require('ge/extensions/rallyAcademy/layout')
local H = require('ra_helpers')
local stubs = H.stubs
local eq, near, has = H.eq, H.near, H.has
local T = {}

-- A straight line north along x = 0 from y = -30 to 150, every 3 m: accelerate, then brake from y = 60.
local function northLine()
  local pts = {}
  for y = -30, 150, 3 do pts[#pts + 1] = {0, y, 0, 50, y < 60 and 1 or -1} end
  return {road = 'test', direction = 'forward', points = pts}
end
local NORTH = {pos = {x = 0.5, y = 0, z = 0}, dir = {x = 0, y = 1, z = 0}}

function T.the_line_runs_from_the_start_to_a_little_past_the_last_gate()
  local pts = L.racingLine({northLine()}, NORTH, {x = 0, y = 90})
  near(pts[1].y, 0, 1e-9, 'starts at the point nearest the start')
  near(pts[#pts].y, 90 + L.LINE_TAIL, 1e-9, 'ends LINE_TAIL m past the last gate')
  eq(pts[1].phase, 1, 'accelerate first')
  eq(pts[#pts].phase, -1, 'brake at the end')
  eq(pts[1].kmh, 50, 'target speed carried')
  near(L.racingLine({northLine()}, NORTH)[1].y, 0, 1e-9, 'no gates: from the start ...')
  near(#L.racingLine({northLine()}, NORTH), 51, 1e-9, '... to the end of the line')
end

function T.no_line_for_a_start_off_it_or_facing_the_other_way()
  eq(L.racingLine({northLine()}, {pos = {x = 0, y = 0, z = 0}, dir = {x = 0, y = -1, z = 0}}), nil, 'facing south')
  eq(L.racingLine({northLine()}, {pos = {x = 20, y = 0, z = 0}, dir = {x = 0, y = 1, z = 0}}), nil, '20 m off it')
  eq(L.racingLine({}, NORTH), nil, 'a map without lines')
end

-- T03 on a map whose racing line runs through its start (marked at the origin, facing north; gates at 40, 65, 90).
local function onLine(withLine)
  local h, M = H.setup()
  h.level = 'test_map'
  if withLine then
    local pts = {}
    for y = -30, 150, 3 do pts[#pts + 1] = string.format('[0,%d,0,50,%d]', y, y < 60 and 1 or -1) end
    h.files['levels/test_map/rallyAcademy/racingLines.json'] = '{"lines":[{"road":"test","direction":"forward","points":['
      .. table.concat(pts, ',') .. ']}]}'
  end
  M.select('T03')
  h.vehicle.pos, h.vehicle.dir = stubs.vec3(0, 0, 0), stubs.vec3(0, 1, 0)
  M.markStart()
  for _, y in ipairs({40, 65, 90}) do
    h.vehicle.pos = stubs.vec3(0, y, 0)
    M.addGate()
  end
  return h, M
end

-- Ribbon segments drawn on one frame (course.lua: the line is the only flat prism).
local function lineDraws(h, M)
  h.draws = {}
  M.onUpdate(0.1, 0.1)
  local n = 0
  for _, d in ipairs(h.draws) do
    if d.kind == 'prism' then n = n + 1 end
  end
  return n
end

function T.the_line_is_off_until_the_player_turns_it_on()
  local h, M = onLine(true)
  local s = h.lastState()
  eq(s.hasLine, true, 'this drill has a line')
  eq(s.showLine, false, 'off by default')
  eq(lineDraws(h, M), 0, 'nothing drawn')
  M.setShowLine(true)
  eq(h.lastState().showLine, true, 'on')
  eq(lineDraws(h, M), 40, 'drawn from the start to 30 m past the last gate: 41 points, 40 segments')
  has(h.files['settings/rallyAcademy/prefs.json'], '"showLine":true')
end

function T.the_key_toggles_it_with_a_message()
  local h, M = onLine(true)
  M.toggleLine()
  eq(h.lastState().showLine, true, 'on')
  eq(h.messages[#h.messages], 'Rally Academy: racing line on', 'message')
  M.toggleLine()
  eq(h.lastState().showLine, false, 'off again')
end

function T.a_drill_without_a_line_says_so()
  local h, M = onLine(false)
  eq(h.lastState().hasLine, false, 'no line on this map')
  M.toggleLine()
  eq(h.messages[#h.messages], 'Rally Academy: racing line on (none for this drill here)', 'message')
  eq(lineDraws(h, M), 0, 'nothing to draw')
end

return T
