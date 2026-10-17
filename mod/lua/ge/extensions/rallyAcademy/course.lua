-- Course markers drawn in the world every frame: gates, stop zone or stop line, finish
-- circle, and authored courses' cones and parking box (with its medal boxes). Uses
-- debugDrawer, a debug overlay rather than scene objects, so there is nothing
-- to clean up and nothing to hit. The only module that draws.
local C = {}

local COLOURS = {
  upcoming = {0.55, 0.8, 1, 0.85}, next = {1, 0.82, 0.1, 0.95},
  passed = {0.25, 0.9, 0.4, 0.9}, missed = {1, 0.3, 0.3, 0.9}, zone = {0.25, 0.9, 0.4, 0.35},
  cone = {1, 0.45, 0.05, 0.95}, hint = {0.9, 0.95, 1, 0.7}, car = {0.9, 0.95, 1, 0.8},
  bronze = {0.8, 0.5, 0.25, 0.9}, silver = {0.78, 0.8, 0.86, 0.9}, gold = {1, 0.8, 0.1, 0.95},
}
local function colour(name) local c = COLOURS[name]; return ColorF(c[1], c[2], c[3], c[4]) end

local function drawGate(g, state)
  local c = colour(state)
  local rx, ry, half = g.dir.y, -g.dir.x, g.width / 2 -- right of the gate, facing dir
  local z0, z1 = g.pos.z - 0.6, g.pos.z + 1.4
  local left = {x = g.pos.x - rx * half, y = g.pos.y - ry * half}
  local right = {x = g.pos.x + rx * half, y = g.pos.y + ry * half}
  debugDrawer:drawCylinder(vec3(left.x, left.y, z0), vec3(left.x, left.y, z1), 0.12, c)
  debugDrawer:drawCylinder(vec3(right.x, right.y, z0), vec3(right.x, right.y, z1), 0.12, c)
  debugDrawer:drawCylinder(vec3(left.x, left.y, z1), vec3(right.x, right.y, z1), 0.05, c)
end

local function drawStopZone(zone, len, wid, col, radius)
  local d = vec3(zone.dir.x, zone.dir.y, 0):normalized()
  local r = vec3(d.y, -d.x, 0)
  local centre = vec3(zone.pos.x, zone.pos.y, zone.pos.z - 0.4)
  local corners = {centre + d * (len / 2) + r * (wid / 2), centre + d * (len / 2) - r * (wid / 2),
                   centre - d * (len / 2) - r * (wid / 2), centre - d * (len / 2) + r * (wid / 2)}
  local c = col or colour('passed')
  for i = 1, 4 do
    debugDrawer:drawCylinder(corners[i], corners[i % 4 + 1], radius or 0.06, c)
  end
end

-- Marked with the car's front bumper on the line; the car's centre was half a car length
-- behind it, so draw the line ~2 m ahead of the marked centre (Covet: ~4 m long).
local function drawStopLine(line)
  local d = vec3(line.dir.x, line.dir.y, 0):normalized()
  local r = vec3(d.y, -d.x, 0)
  local mid = vec3(line.pos.x, line.pos.y, line.pos.z - 0.4) + d * 2
  debugDrawer:drawCylinder(mid - r * 4, mid + r * 4, 0.08, colour('passed'))
end

-- Course objects (layout.lua) sit at a car's height (~0.4 m) above the ground.
local GROUND = 0.4

-- A traffic cone: three stacked cylinders, narrower towards the top.
local function drawCone(c, state)
  local col = colour(state == 'passed' and 'passed' or state == 'missed' and 'missed' or 'cone')
  local z = c.z - GROUND
  for _, seg in ipairs({{0.15, 0, 0.25}, {0.11, 0.25, 0.5}, {0.06, 0.5, 0.7}}) do -- radius, bottom, top
    debugDrawer:drawCylinder(vec3(c.x, c.y, z + seg[2]), vec3(c.x, c.y, z + seg[3]), seg[1], col)
  end
end

-- A chevron on the ground beside a cone, on the side to pass it, pointing the way to go.
local function drawPassHint(c)
  local fx, fy = c.dir.x, c.dir.y
  local side = c.keep == 'left' and 1 or -1 -- keep it on your left: pass on its right
  local rx, ry = fy * side, -fx * side
  local z = c.z - GROUND + 0.03
  local px, py = c.x + rx * 1.8, c.y + ry * 1.8
  local tip = vec3(px + fx * 0.5, py + fy * 0.5, z)
  local col = colour('hint')
  debugDrawer:drawCylinder(vec3(px - fx * 0.2 + rx * 0.5, py - fy * 0.2 + ry * 0.5, z), tip, 0.04, col)
  debugDrawer:drawCylinder(vec3(px - fx * 0.2 - rx * 0.5, py - fy * 0.2 - ry * 0.5, z), tip, 0.04, col)
end

local function drawRect(corners, z, radius, col)
  for i = 1, 4 do
    local a, b = corners[i], corners[i % 4 + 1]
    debugDrawer:drawCylinder(vec3(a.x, a.y, z), vec3(b.x, b.y, z), radius, col)
  end
end

-- The parking box and its medal boxes (each `inset` smaller); the one the car is in now is
-- drawn green and thicker.
local function drawBox(box, boxes, fit)
  local fx, fy = box.dir.x, box.dir.y
  local rx, ry = fy, -fx
  local z = box.z - GROUND + 0.02
  for _, b in ipairs(boxes) do
    local hl, hw = box.lengthM / 2 - b.inset, box.widthM / 2 - b.inset
    local function at(a, s) return {x = box.x + fx * a + rx * s, y = box.y + fy * a + ry * s} end
    local current = b.name == fit
    drawRect({at(hl, -hw), at(hl, hw), at(-hl, hw), at(-hl, -hw)}, z,
      current and 0.06 or (b.inset == 0 and 0.05 or 0.03), colour(current and 'passed' or b.name))
  end
end

-- A course's stop line across the ground, and thin medal lines before it (each zone's far edge),
-- coloured by medal; the zone the car's bumper is in now is drawn green.
local function drawCourseLine(line, zones, fit)
  local fx, fy = line.dir.x, line.dir.y
  local rx, ry, half = fy, -fx, line.widthM / 2
  local z = line.z - GROUND + 0.03
  local function across(back, radius, col)
    local cx, cy = line.x - fx * back, line.y - fy * back
    debugDrawer:drawCylinder(vec3(cx - rx * half, cy - ry * half, z), vec3(cx + rx * half, cy + ry * half, z), radius, col)
  end
  across(0, 0.08, colour('missed'))
  for _, zn in ipairs(zones or {}) do
    across(zn.maxM, zn.name == fit and 0.05 or 0.03, colour(zn.name == fit and 'passed' or zn.name))
  end
end

-- course = {
--   gates = {...}, gateResults = {[i] = 'passed' | 'missed'}, nextGate = index or nil,
--   finish = {pos, dir, radius} or nil, finishKind = 'line' | 'zone' | 'circle',
--   zoneLength = m, zoneWidth = m,
--   cones = {{x, y, z, dir, keep}}, coneResults = {[i] = 'passed' | 'missed'}, nextCone = index or nil,
--   box = {x, y, z, dir, lengthM, widthM}, boxes = {{name, inset}}, fit = medal box the car is in,
--   footprint = the car's four corners (near the box), or nil
--   line = {x, y, z, dir, widthM}, lineCones = {{x, y, z}}, lineZones = {{name, maxM}}: a stop line
--   zoneTiers = {{name, lengthM, widthM}}: a course stop zone's medal sizes (drawn nested)
-- }
function C.draw(course)
  if not (debugDrawer and ColorF) then return end
  for i, g in ipairs(course.gates or {}) do
    drawGate(g, course.gateResults[i] or (i == course.nextGate and 'next') or 'upcoming')
  end
  for i, c in ipairs(course.cones or {}) do
    drawCone(c, course.coneResults and course.coneResults[i])
    if i == course.nextCone then drawPassHint(c) end
  end
  if course.line then
    drawCourseLine(course.line, course.lineZones, course.fit)
    for _, c in ipairs(course.lineCones or {}) do drawCone(c, nil) end
  end
  if course.box then
    drawBox(course.box, course.boxes or {{name = 'bronze', inset = 0}}, course.fit)
    if course.footprint then
      drawRect(course.footprint, course.box.z - GROUND + 0.05, 0.03, colour(course.fit and 'passed' or 'car'))
    end
  end
  local f = course.finish
  if not (f and f.pos) then return end
  if course.finishKind == 'line' and f.dir then
    drawStopLine(f)
  elseif course.finishKind == 'zone' and f.dir and course.zoneTiers then
    -- a course stop zone with its medal zones nested inside; the one the car is in is green
    for _, t in ipairs(course.zoneTiers) do
      local current = t.name == course.fit
      drawStopZone(f, t.lengthM, t.widthM, colour(current and 'passed' or t.name), current and 0.06 or 0.04)
    end
  elseif course.finishKind == 'zone' and f.dir then
    drawStopZone(f, course.zoneLength or 5, course.zoneWidth or 6)
  else
    local p = f.pos
    debugDrawer:drawCylinder(vec3(p.x, p.y, p.z - 0.5), vec3(p.x, p.y, p.z - 0.45), f.radius or 5, colour('zone'))
  end
end

return C
