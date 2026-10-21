-- The racing line ("Show line", ADR 0013): racingLine.lua (pure) works out a drill's line from the map's road and its
-- gates, and the extension draws it when the player turns it on, or has the AI drive it (T03 as a marked-gate drill on
-- a test map with one straight road).
local RL = require('ge/extensions/rallyAcademy/racingLine')
local H = require('ra_helpers')
local stubs = H.stubs
local eq, near, has = H.eq, H.near, H.has
local T = {}

-- A road's centre line, a point every 3 m: straights ('S', length) and arcs ('L' or 'R', radius, degrees), heading
-- north from (0, 0). Points {x, y, z, tilt}.
local function road(width, grip, segments, tilt)
  local x, y, h, pts = 0, 0, math.pi / 2, {{0, 0, 0, tilt or 0}}
  for _, s in ipairs(segments) do
    local len = s[1] == 'S' and s[2] or s[2] * math.rad(s[3])
    local n = math.floor(len / 3 + 0.5)
    for _ = 1, n do
      if s[1] ~= 'S' then h = h + (s[1] == 'L' and 1 or -1) * (len / n) / s[2] / 2 end
      x, y = x + math.cos(h) * len / n, y + math.sin(h) * len / n
      if s[1] ~= 'S' then h = h + (s[1] == 'L' and 1 or -1) * (len / n) / s[2] / 2 end
      pts[#pts + 1] = {x, y, 0, tilt or 0}
    end
  end
  return {id = 'test', width = width, grip = grip, points = pts}
end
local NORTH = {pos = {x = 0, y = 0, z = 0}, dir = {x = 0, y = 1, z = 0}}
local CORNER = {{'S', 100}, {'L', 30, 90}, {'S', 100}}

-- Metres left of the centre line at each line point (the centre line runs north, then west after the corner).
local function offsets(r, line)
  local nv = RL.normals(r.points)
  local out = {}
  for i, p in ipairs(line) do out[i] = (p.x - r.points[i][1]) * nv[i][1] + (p.y - r.points[i][2]) * nv[i][2] end
  return out
end

local function slowestHeld(line)
  local v = math.huge
  for _, p in ipairs(line) do if p.phase == RL.HOLD then v = math.min(v, p.kmh) end end
  return v
end

function T.a_straight_road_keeps_to_the_middle_and_accelerates()
  local r = road(8, 0.65, {{'S', 200}})
  local line = RL.forDrill({r}, NORTH)
  eq(#line, #r.points, 'the whole road')
  for i, o in ipairs(offsets(r, line)) do near(o, 0, 0.01, 'in the middle at ' .. i) end
  eq(line[5].phase, RL.ACCELERATE, 'accelerating')
  near(line[1].kmh, 0, 1e-9, 'from a standstill')
end

function T.a_corner_goes_outside_inside_outside_and_brakes_before_it()
  local r = road(10, 0.65, CORNER)
  local line = RL.forDrill({r}, NORTH)
  local off, edge = offsets(r, line), 5 - RL.CAR_MARGIN
  local apex, slow = 1, math.huge
  for i, p in ipairs(line) do if p.phase == RL.HOLD and p.kmh < slow then apex, slow = i, p.kmh end end
  local minIn, minOut = 0, 0
  for i, o in ipairs(off) do
    assert(math.abs(o) <= edge + 1e-6, 'on the road')
    if i < apex then minIn = math.min(minIn, o) else minOut = math.min(minOut, o) end
  end
  assert(off[apex] > edge - 0.5, 'inside (left) at the apex: ' .. off[apex])
  assert(minIn < -(edge - 0.5), 'outside (right) on the way in')
  assert(minOut < -(edge - 0.5), 'outside on the way out')
  local seq = {}
  for _, p in ipairs(line) do
    local c = p.phase == RL.BRAKE and 'B' or p.phase == RL.HOLD and '-' or 'a'
    if seq[#seq] ~= c then seq[#seq + 1] = c end
  end
  eq(table.concat(seq), 'aB-a', 'accelerate, brake, hold the corner, accelerate out')
end

function T.the_line_goes_through_the_drills_gates_and_ends_past_the_last()
  local r = road(10, 0.65, CORNER)
  local free = RL.forDrill({r}, NORTH)
  -- a 3 m gate on the inside where the free line runs wide: the line now goes through it
  local k = 60
  local nv = RL.normals(r.points)
  local gate = {pos = {x = r.points[k][1] + nv[k][1] * 2.5, y = r.points[k][2] + nv[k][2] * 2.5}, width = 3}
  assert(offsets(r, free)[k] < 1, 'the free line passes right of the gate')
  local line = RL.forDrill({r}, NORTH, {gate})
  local o = offsets(r, line)[k]
  assert(o >= 2.5 - 0.5 - 1e-6 and o <= 2.5 + 0.5 + 1e-6, 'through the gate, clear of its posts: ' .. o)
  near(#line, k + RL.TAIL / 3, 1, 'on to TAIL m past the gate')
end

function T.the_line_starts_where_the_car_starts_and_follows_the_way_it_faces()
  local r = road(10, 0.65, {{'S', 200}})
  local line = RL.forDrill({r}, {pos = {x = 2, y = 30, z = 0}, dir = {x = 0, y = 1, z = 0}})
  near(line[1].x, 2, 1e-6, 'from the car, 2 m right of the centre') -- heading north, right is +x
  near(line[1].y, 30, 1.5, 'from the start (the road point nearest it)')
  local back = RL.forDrill({r}, {pos = {x = 0, y = 150, z = 0}, dir = {x = 0, y = -1, z = 0}})
  near(back[#back].y, 0, 1e-6, "driven the other way: to the road's start")
  eq(RL.forDrill({r}, {pos = {x = 20, y = 0, z = 0}, dir = {x = 0, y = 1, z = 0}}), nil, '20 m off the road')
  eq(RL.forDrill({r}, {pos = {x = 0, y = 0, z = 0}, dir = {x = 1, y = 0, z = 0}}), nil, 'across it')
  eq(RL.forDrill({}, NORTH), nil, 'a map without roads')
end

function T.grip_and_banking_set_the_corner_speed()
  local snow = slowestHeld(RL.forDrill({road(10, 0.35, CORNER)}, NORTH))
  local gravel = slowestHeld(RL.forDrill({road(10, 0.65, CORNER)}, NORTH))
  local asphalt = slowestHeld(RL.forDrill({road(10, 1.0, CORNER)}, NORTH))
  assert(snow < gravel and gravel < asphalt, ('snow %.0f < gravel %.0f < asphalt %.0f'):format(snow, gravel, asphalt))
  local banked = slowestHeld(RL.forDrill({road(10, 0.65, CORNER, 0.15)}, NORTH)) -- right side higher: into the left
  assert(banked > gravel + 3, ('a banked corner is faster: %.0f > %.0f'):format(banked, gravel))
  local offCamber = slowestHeld(RL.forDrill({road(10, 0.65, CORNER, -0.1)}, NORTH))
  assert(offCamber < gravel - 3, ('an off-camber corner is slower: %.0f < %.0f'):format(offCamber, gravel))
end

-- T03 on a map whose racing line runs through its start (marked at the origin, facing north; gates at 40, 65, 90).
local function onLine(withLine)
  local h, M = H.setup()
  h.level = 'test_map'
  if withLine then -- a straight road north along x = 0 from y = -30 to 150
    local pts = {}
    for y = -30, 150, 3 do pts[#pts + 1] = string.format('[0,%d,0,0]', y) end
    h.files['levels/test_map/rallyAcademy/roads.json'] = '{"roads":[{"id":"test","width":8,"grip":0.65,"points":['
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

-- Watch AI ---------------------------------------------------------------------

local function aiCommands(h, pattern)
  local n = 0
  for _, c in ipairs(h.vehicle.luaCommands) do
    if c:find(pattern, 1, true) then n = n + 1 end
  end
  return n
end

function T.watch_ai_resets_the_car_and_has_the_ai_drive_the_line()
  local h, M = onLine(true)
  h.vehicle.pos = stubs.vec3(30, 50, 0)
  M.demo()
  local s = h.lastState()
  eq(s.phase, 'ready', 'back at the start')
  eq(s.demo, true, 'an AI demo')
  near(h.vehicle.pos.y, 0, 1e-6, 'car reset to the start')
  eq(aiCommands(h, 'ai.driveUsingPath({script = {{x=0.00,y=0.00,z=0.00,r=0.5},{x=0.00,y=3.00'), 1, 'the AI drives the line from the start')
  has(h.vehicle.luaCommands[#h.vehicle.luaCommands], '{x=0.00,y=120.00,z=0.00,r=0.5}}, aggression = 0.80')
  has(s.reason, 'The AI is driving the racing line')
end

function T.the_ai_run_is_graded_but_not_recorded_and_the_car_is_handed_back()
  local h, M = onLine(true)
  local s = H.gateRun(h, M, {begin = M.demo})
  eq(s.phase, 'scored', 'graded at the last gate')
  eq(s.grade.passed, true, 'the grade is shown')
  eq(s.attempts, 0, 'not an attempt')
  eq((s.progress or {}).T03, nil, 'no progress recorded')
  eq(s.autoRetryIn, false, 'no auto-retry after a demo')
  has(s.reason, 'AI demo: PASS')
  eq(M.getLastRun().meta.demo, true, 'the run record says so')
  eq(aiCommands(h, "ai.setMode('disabled')"), 0, 'the AI drives on to the end of the line')
  h.vehicle.vel = stubs.vec3(0, 0, 0)
  M.onUpdate(0.1, 0.1)
  eq(aiCommands(h, "ai.setMode('disabled')"), 1, "stopped: the car is the player's again")
  M.retry()
  eq(h.lastState().demo, false, "the next run is the player's")
  eq(aiCommands(h, "ai.setMode('disabled')"), 1, 'nothing more to hand back')
end

function T.retry_or_miss_during_the_ai_run_stops_it()
  local h, M = onLine(true)
  M.demo()
  M.retry()
  eq(aiCommands(h, "ai.setMode('disabled')"), 1, 'Retry hands the car back')
  H.gateRun(h, M, {begin = M.demo, giveUpAtY = 20}) -- the AI 20 m along, before the first gate
  eq(h.lastState().phase, 'running', 'the AI is driving')
  M.recordAttempt(false)
  eq(aiCommands(h, "ai.setMode('disabled')"), 2, 'Miss hands the car back')
  eq(h.lastState().attempts, 0, 'and records nothing')
  has(h.lastState().reason, 'AI demo stopped')
end

function T.a_drill_without_a_line_says_so()
  local h, M = onLine(false)
  eq(h.lastState().hasLine, false, 'no line on this map')
  M.toggleLine()
  eq(h.messages[#h.messages], 'Rally Academy: racing line on (none for this drill here)', 'message')
  eq(lineDraws(h, M), 0, 'nothing to draw')
  M.demo()
  eq(aiCommands(h, 'ai.driveUsingPath'), 0, 'no AI demo either')
  has(h.lastState().reason, 'no AI demo')
end

return T
