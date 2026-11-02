-- Technique demos (docs/decisions/0015-technique-demos.md), pure: a technique card (gameplay/rallyAcademy/techniques/)
-- and its tuned dials, made into the configuration the car's skill runner (vehicle extension rallyAcademy/driver,
-- docs/DRIVER.md) drives from. No engine calls: rallyAcademy.lua reads the files and talks to the car.
local Layout = require('ge/extensions/rallyAcademy/layout')

local T = {}

T.DIR = 'gameplay/rallyAcademy/techniques/'

function T.cardPath(name) return T.DIR .. name .. '.json' end
function T.tunedPath(name, surface) return T.DIR .. name .. '-' .. surface .. '.json' end

-- The surface a drill's dials are tuned for: 'gravel', 'asphalt', 'snow' (the drill's surface, lower case).
function T.surfaceOf(lesson)
  return type(lesson.surface) == 'string' and lesson.surface:lower() or 'gravel'
end

-- The card's starting values, its adjustments for the surface, then the tuned values (tuned: the file tune.py wrote,
-- {dials = {...}}, or nil). As tools/driver/attempt.py's dials().
function T.dials(card, surface, tuned)
  local out = {}
  for _, phase in ipairs(card.phases or {}) do
    for name, spec in pairs(phase.dials or {}) do out[name] = spec[3] end
  end
  for name, v in pairs((card.surfaces or {})[surface] or {}) do out[name] = v end
  for name, v in pairs(tuned and tuned.dials or {}) do out[name] = v end
  return out
end

-- A phase's cue and its label on the input trace: {cue, mark} (either can be nil), or nil for an unknown phase.
function T.phase(card, id)
  for _, phase in ipairs(card.phases or {}) do
    if phase.id == id then return {cue = phase.cue, mark = phase.mark} end
  end
  return nil
end

local function dist(a, b) return math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) end

-- Points about `step` m apart along a polyline ({{x, y}}), as attempt.py's resample.
function T.resample(points, step)
  step = step or 1
  local out = {{points[1][1], points[1][2]}}
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    local n = math.max(1, math.floor(dist(a, b) / step))
    for k = 1, n do out[#out + 1] = {a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n} end
  end
  return out
end

-- Distance along `path` to its point nearest `p`.
function T.along(path, p)
  local best, bestD = 1, math.huge
  for i, q in ipairs(path) do
    local d = dist(q, p)
    if d < bestD then best, bestD = i, d end
  end
  local s = 0
  for i = 2, best do s = s + dist(path[i - 1], path[i]) end
  return s
end

local function round(v, places)
  local m = 10 ^ places
  return math.floor(v * m + 0.5) / m
end

-- Frames the runner holds the car still after Retry, and the frame it selects its gear on. Training holds 80 (a
-- controlled start, tools/driver/attempt.py); a demo shouldn't keep the player waiting that long.
T.HOLD, T.SHIFT_AT = 40, 15

-- The runner's configuration for a drill: the card's line for it laid out from the start pose ({pos, dir}, as the
-- course is), in world metres every 1 m, and how far along it the first and last gates are (the runner's flickS and
-- exitS). gates: the drill's course gates (course frame). nil when the card has no line for the drill.
function T.config(card, drillId, dials, start, gates)
  local line = card.lines and card.lines[drillId]
  if type(line) ~= 'table' or #line < 2 or #gates < 2 then return nil end
  local f = Layout.frame(start)
  local world = {}
  for _, p in ipairs(line) do
    local x, y = Layout.toWorld(f, p[1], p[2])
    world[#world + 1] = {x, y}
  end
  local path = T.resample(world, 1)
  for _, p in ipairs(path) do p[1], p[2] = round(p[1], 3), round(p[2], 3) end
  local function gateAt(g)
    local x, y = Layout.toWorld(f, g.x or 0, g.y)
    return {x, y}
  end
  return {dials = dials, limits = card.humanLimits, path = path, hold = T.HOLD, shiftAt = T.SHIFT_AT,
          flickS = round(T.along(path, gateAt(gates[1])), 2), exitS = round(T.along(path, gateAt(gates[#gates])), 2)}
end

-- A Lua literal for a value (numbers, strings, booleans, lists, tables with string keys in sorted order): how the
-- configuration reaches the car (queueLuaCommand takes source text).
function T.literal(v)
  local t = type(v)
  if t == 'number' then
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format('%d', v) end
    return string.format('%.6g', v)
  elseif t == 'string' then return string.format('%q', v)
  elseif t == 'boolean' then return tostring(v)
  elseif t == 'table' then
    local parts = {}
    if #v > 0 then
      for _, x in ipairs(v) do parts[#parts + 1] = T.literal(x) end
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      for _, k in ipairs(keys) do parts[#parts + 1] = string.format('[%q]=%s', k, T.literal(v[k])) end
    end
    return '{' .. table.concat(parts, ',') .. '}'
  end
  return 'nil'
end

return T
