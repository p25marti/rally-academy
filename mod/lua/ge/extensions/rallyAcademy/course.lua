-- Course markers drawn in the world every frame: gates, stop zone or stop line, finish
-- circle. Uses debugDrawer, a debug overlay rather than scene objects, so there is nothing
-- to clean up and nothing to hit. The only module that draws.
local C = {}

local COLOURS = {
  upcoming = {0.55, 0.8, 1, 0.85}, next = {1, 0.82, 0.1, 0.95},
  passed = {0.25, 0.9, 0.4, 0.9}, missed = {1, 0.3, 0.3, 0.9}, zone = {0.25, 0.9, 0.4, 0.35},
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

local function drawStopZone(zone, len, wid)
  local d = vec3(zone.dir.x, zone.dir.y, 0):normalized()
  local r = vec3(d.y, -d.x, 0)
  local centre = vec3(zone.pos.x, zone.pos.y, zone.pos.z - 0.4)
  local corners = {centre + d * (len / 2) + r * (wid / 2), centre + d * (len / 2) - r * (wid / 2),
                   centre - d * (len / 2) - r * (wid / 2), centre - d * (len / 2) + r * (wid / 2)}
  local c = colour('passed')
  for i = 1, 4 do
    debugDrawer:drawCylinder(corners[i], corners[i % 4 + 1], 0.06, c)
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

-- course = {
--   gates = {...}, gateResults = {[i] = 'passed' | 'missed'}, nextGate = index or nil,
--   finish = {pos, dir, radius} or nil, finishKind = 'line' | 'zone' | 'circle',
--   zoneLength = m, zoneWidth = m,
-- }
function C.draw(course)
  if not (debugDrawer and ColorF) then return end
  for i, g in ipairs(course.gates or {}) do
    drawGate(g, course.gateResults[i] or (i == course.nextGate and 'next') or 'upcoming')
  end
  local f = course.finish
  if not (f and f.pos) then return end
  if course.finishKind == 'line' and f.dir then
    drawStopLine(f)
  elseif course.finishKind == 'zone' and f.dir then
    drawStopZone(f, course.zoneLength or 5, course.zoneWidth or 6)
  else
    local p = f.pos
    debugDrawer:drawCylinder(vec3(p.x, p.y, p.z - 0.5), vec3(p.x, p.y, p.z - 0.45), f.radius or 5, colour('zone'))
  end
end

return C
