-- Authored courses (assessment.course): gates, cones and a parking box laid out relative to
-- the start, so a drill is ready to drive with no marking. Also the car's footprint, which
-- the box and marker rules need ("the whole car inside the box", "clear of every cone").
-- Pure Lua (no engine globals): the extension places and draws, the rules grade.
--
-- Course coordinates are metres from the start: x to the right, y ahead (the way the car
-- faces at the start). A placed course is in world x, y; the extension fills in heights.
-- Any item may carry a `label`, which the HUD's checklist shows ("40 km/h", "Stop box"). Gates
-- may carry `headingDeg`: the way the road goes there, degrees right of ahead (negative = left).
local Gates = require('ge/extensions/rallyAcademy/gates')
local L = {}

-- Radius of a drawn cone or gate post: the car "clips" it inside this distance.
L.MARKER_RADIUS = 0.15 -- m
-- Crossing a cone's line further than this from it doesn't count (elsewhere on the course).
local CONE_REACH = 10 -- m

local function unit(x, y)
  local n = math.sqrt(x * x + y * y)
  if n == 0 then return 0, 1 end
  return x / n, y / n
end

-- Frame of a start pose {pos, dir}: origin, forward and right unit vectors (horizontal).
function L.frame(start)
  local fx, fy = unit(start.dir.x, start.dir.y)
  return {ox = start.pos.x, oy = start.pos.y, fx = fx, fy = fy, rx = fy, ry = -fx}
end

function L.toWorld(f, x, y)
  return f.ox + f.rx * x + f.fx * y, f.oy + f.ry * x + f.fy * y
end

-- The course's forward direction turned `deg` degrees to the right (negative: left), as a
-- world direction {x, y}: corner gates face the way the road goes there (`headingDeg`).
function L.turned(f, deg)
  local a = math.rad(deg or 0)
  local c, s = math.cos(a), math.sin(a)
  return {x = f.fx * c + f.rx * s, y = f.fy * c + f.ry * s}
end

-- Lay a course definition out from a start pose. Returns
-- {gates = {...} (gates.lua format), cones = {{x, y, dir, keep}}, box = {x, y, dir, lengthM, widthM},
--  markers = {{x, y, name}}, zone, line, circle = {x, y, radiusM, turn, laps}} with world x, y;
-- heights are left to the caller.
function L.place(def, start)
  local f = L.frame(start)
  local dir = {x = f.fx, y = f.fy}
  local out = {gates = {}, cones = {}, markers = {}}
  for i, g in ipairs(def.gates or {}) do
    local x, y = L.toWorld(f, g.x or 0, g.y)
    local gdir = L.turned(f, g.headingDeg)
    local gate = Gates.new({pos = {x = x, y = y, z = start.pos.z}, dir = gdir}, g.widthM)
    gate.label = g.label
    out.gates[i] = gate
    local half, rx, ry = gate.width / 2, gate.dir.y, -gate.dir.x
    local label = #(def.gates) > 1 and (' of gate ' .. i) or ' of the gate'
    out.markers[#out.markers + 1] = {x = x - rx * half, y = y - ry * half, name = 'the left post' .. label}
    out.markers[#out.markers + 1] = {x = x + rx * half, y = y + ry * half, name = 'the right post' .. label}
  end
  for i, c in ipairs(def.cones or {}) do
    local x, y = L.toWorld(f, c.x or 0, c.y)
    out.cones[i] = {x = x, y = y, z = start.pos.z, dir = dir, keep = c.keep or 'left', label = c.label}
    out.markers[#out.markers + 1] = {x = x, y = y, name = #(def.cones) > 1 and ('cone ' .. i) or 'the cone'}
  end
  if def.box then
    local x, y = L.toWorld(f, def.box.x or 0, def.box.y)
    out.box = {x = x, y = y, z = start.pos.z, dir = dir, lengthM = def.box.lengthM, widthM = def.box.widthM,
               label = def.box.label}
  end
  if def.zone then
    -- A stop zone's centre (B01): shaped like a marked zone ({pos, dir}), so stop_zone grades it
    -- as before; its size comes from the stop_zone rule (and each tier's smaller one).
    local x, y = L.toWorld(f, def.zone.x or 0, def.zone.y)
    out.zone = {pos = {x = x, y = y, z = start.pos.z}, dir = dir, label = def.zone.label}
  end
  if def.line then
    -- A line across the course to stop before (A05), with a cone at each end.
    local x, y = L.toWorld(f, def.line.x or 0, def.line.y)
    local half = (def.line.widthM or 8) / 2
    out.line = {x = x, y = y, z = start.pos.z, dir = dir, widthM = def.line.widthM or 8, label = def.line.label}
    out.lineCones = {}
    for i, side in ipairs({-1, 1}) do
      local cx, cy = x + f.rx * half * side, y + f.ry * half * side
      out.lineCones[i] = {x = cx, y = cy, z = start.pos.z, dir = dir}
      out.markers[#out.markers + 1] = {x = cx, y = cy, name = side < 0 and 'the left cone of the line' or 'the right cone of the line'}
    end
  end
  if def.circle then
    -- A circle to lap (B05): its centre, the radius of the line to hold and which way round
    -- ('left' = anticlockwise seen from above). The corridor either side of the line comes from
    -- the circle_corridor rule (and each tier's narrower one).
    local x, y = L.toWorld(f, def.circle.x or 0, def.circle.y or 0)
    out.circle = {x = x, y = y, z = start.pos.z, radiusM = def.circle.radiusM, turn = def.circle.turn or 'left',
                  laps = def.circle.laps or 1, label = def.circle.label}
  end
  return out
end

-- Circles --------------------------------------------------------------------------

-- How far round the circle moving from a to b goes, in radians: positive the way the circle
-- is driven (its `turn`), negative against it.
function L.circleSweep(circle, a, b)
  local d = math.atan2(b.y - circle.y, b.x - circle.x) - math.atan2(a.y - circle.y, a.x - circle.x)
  if d > math.pi then d = d - 2 * math.pi elseif d < -math.pi then d = d + 2 * math.pi end
  return circle.turn == 'right' and -d or d
end

-- Metres off the circle's line: positive outside it, negative inside.
function L.circleOffset(circle, x, y)
  return math.sqrt((x - circle.x) ^ 2 + (y - circle.y) ^ 2) - circle.radiusM
end

-- A stable text fingerprint of a course definition (keys sorted, numbers to the millimetre): a
-- saved start remembers it, so a changed course doesn't get laid out from a stale start.
function L.fingerprint(v)
  local t = type(v)
  if t == 'number' then return string.format('%.3f', v) end
  if t ~= 'table' then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. '=' .. L.fingerprint(v[k]) end
  return '{' .. table.concat(parts, ',') .. '}'
end

-- Car footprint ------------------------------------------------------------------
-- car = {front, rear, left, right}: metres from the car's position (what telemetry and
-- getPosition report, which isn't the body's centre) to each side of its body.

-- A centred footprint, for when the body can't be measured.
function L.centredCar(length, width)
  return {front = length / 2, rear = length / 2, left = width / 2, right = width / 2}
end

-- The four corners in world x, y, for a car at (x, y) pointing (hx, hy).
-- Order: front-left, front-right, rear-right, rear-left.
function L.corners(car, x, y, hx, hy)
  local fx, fy = unit(hx, hy)
  local rx, ry = fy, -fx
  local function at(a, s) return {x = x + fx * a + rx * s, y = y + fy * a + ry * s} end
  return {at(car.front, -car.left), at(car.front, car.right), at(-car.rear, car.right), at(-car.rear, -car.left)}
end
L.CORNER_NAMES = {'front-left', 'front-right', 'rear-right', 'rear-left'}

-- Distance from a point to the car's footprint (0 when the point is under the car).
function L.distanceToCar(car, x, y, hx, hy, px, py)
  local fx, fy = unit(hx, hy)
  local dx, dy = px - x, py - y
  local a, s = dx * fx + dy * fy, dx * fy - dy * fx -- along (forward +), side (right +)
  local da = math.max(0, a - car.front, -car.rear - a)
  local ds = math.max(0, s - car.right, -car.left - s)
  return math.sqrt(da * da + ds * ds)
end

-- Where the car is relative to a box: each corner's margin inside the box (negative =
-- outside) after shrinking the box by `inset` on every side, and the body centre's offset
-- from the box centre (along = ahead of it, side = right of it, in the box's direction).
-- Returns {inside, margin = smallest corner margin, corner = its index, edge = 'front' |
-- 'back' | 'left' | 'right' (the edge it's nearest or past), along, side}.
function L.boxFit(box, car, x, y, hx, hy, inset)
  local bx, by = unit(box.dir.x, box.dir.y)
  local halfL, halfW = box.lengthM / 2 - (inset or 0), box.widthM / 2 - (inset or 0)
  local worst = {margin = math.huge}
  for i, c in ipairs(L.corners(car, x, y, hx, hy)) do
    local dx, dy = c.x - box.x, c.y - box.y
    local a, s = dx * bx + dy * by, dx * by - dy * bx
    local edges = {{halfL - a, 'front'}, {halfL + a, 'back'}, {halfW - s, 'right'}, {halfW + s, 'left'}}
    for _, e in ipairs(edges) do
      if e[1] < worst.margin then worst = {margin = e[1], corner = i, edge = e[2]} end
    end
  end
  -- Body centre: midway between the front and rear, left and right.
  local fx, fy = unit(hx, hy)
  local midA, midS = (car.front - car.rear) / 2, (car.right - car.left) / 2
  local cx, cy = x + fx * midA + fy * midS, y + fy * midA - fx * midS
  local dx, dy = cx - box.x, cy - box.y
  worst.along, worst.side = dx * bx + dy * by, dx * by - dy * bx
  worst.inside = worst.margin >= 0
  return worst
end

-- Where the car's front bumper is against a line (facing `line.dir`): metres before it
-- (negative = past it), and the body centre's offset to the side of the line's centre.
function L.bumperToLine(line, car, x, y, hx, hy)
  local lx, ly = unit(line.dir.x, line.dir.y)
  local front = -math.huge
  for _, c in ipairs(L.corners(car, x, y, hx, hy)) do
    front = math.max(front, (c.x - line.x) * lx + (c.y - line.y) * ly)
  end
  local fx, fy = unit(hx, hy)
  local midA, midS = (car.front - car.rear) / 2, (car.right - car.left) / 2
  local cx, cy = x + fx * midA + fy * midS, y + fy * midA - fx * midS
  return -front, (cx - line.x) * ly - (cy - line.y) * lx
end

-- Cones -------------------------------------------------------------------------

-- Does moving from a to b pass the cone (cross the line through it, square to the course,
-- going forwards)? Returns nil or {offset = metres right (+) or left (-) of the cone,
-- side = which side of the car the cone was on: 'left' | 'right'}.
function L.coneCrossing(cone, a, b)
  local dx, dy = cone.dir.x, cone.dir.y
  local alongA = (a.x - cone.x) * dx + (a.y - cone.y) * dy
  local alongB = (b.x - cone.x) * dx + (b.y - cone.y) * dy
  if not (alongA < 0 and alongB >= 0) then return nil end
  local f = -alongA / (alongB - alongA)
  local cx, cy = a.x + f * (b.x - a.x), a.y + f * (b.y - a.y)
  local offset = (cx - cone.x) * dy - (cy - cone.y) * dx
  if math.abs(offset) > CONE_REACH then return nil end
  return {offset = offset, side = offset >= 0 and 'left' or 'right'}
end

-- "Keep the cone on your left": you pass to its right.
function L.keepText(keep) return 'keep it on your ' .. keep end

return L
