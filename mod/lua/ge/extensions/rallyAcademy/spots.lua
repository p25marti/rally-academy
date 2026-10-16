-- Venue bookmarks: "Rally Academy: Save spot" records where the car is and what it's like
-- there (room, slope, nearest road, surfaces), for finding drill venues later
-- (tools/ingame/survey.py report). Pure Lua: the extension gathers the measurements.
local S = {}

S.ROOM_DIRECTIONS = {'ahead', 'ahead-right', 'right', 'behind-right', 'behind', 'behind-left', 'left', 'ahead-left'}
S.ROOM_ANGLES = {0, 45, 90, 135, 180, -135, -90, -45} -- degrees clockwise from the car's heading

local function round(x, step) return math.floor(x / step + 0.5) * step end

-- m = {level, pos = {x,y,z}, dir = {x,y,z}, upZ, room = {8 distances, m}, road = {name, width,
--      drivability, dist} or nil, note}. Returns the spot record (without id or surfaces).
function S.record(m)
  local slope = math.deg(math.acos(math.max(-1, math.min(1, m.upZ or 1))))
  local room = {}
  for i, d in ipairs(m.room or {}) do room[i] = round(d, 1) end
  return {
    level = m.level,
    pos = {x = round(m.pos.x, 0.01), y = round(m.pos.y, 0.01), z = round(m.pos.z, 0.01)},
    dir = {x = round(m.dir.x, 0.0001), y = round(m.dir.y, 0.0001), z = round(m.dir.z, 0.0001)},
    slopeDeg = round(slope, 0.1),
    room = room,
    road = m.road and {name = m.road.name, width = round(m.road.width or 0, 0.1),
                       drivability = m.road.drivability, dist = round(m.road.dist or 0, 0.1)} or nil,
    note = m.note,
  }
end

-- Append with the next id (ids stay unique across maps). Returns the spot.
function S.add(list, spot)
  local top = 0
  for _, s in ipairs(list) do top = math.max(top, s.id or 0) end
  spot.id = top + 1
  list[#list + 1] = spot
  return spot
end

function S.find(list, id)
  for _, s in ipairs(list) do if s.id == id then return s end end
end

-- "Spot 3 saved: room ahead 57 m, behind 150 m; road 8.0 m wide; slope 1.2°". Not "paved":
-- the road map's drivability is a road class (the asphalt BMP straight is 0.5), so the
-- surface comes from the wheels instead (onSpotSurfaces).
function S.summary(spot)
  local r = spot.room or {}
  local parts = {string.format('room ahead %d m, behind %d m', r[1] or 0, r[5] or 0)}
  if spot.road and spot.road.dist <= spot.road.width then
    parts[#parts + 1] = string.format('road %.1f m wide', spot.road.width)
  else
    parts[#parts + 1] = 'off road'
  end
  parts[#parts + 1] = string.format('slope %.1f°', spot.slopeDeg or 0)
  return string.format('Spot %d saved: %s', spot.id or 0, table.concat(parts, '; '))
end

return S
