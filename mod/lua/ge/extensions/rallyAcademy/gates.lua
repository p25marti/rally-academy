-- Gates: a line across the road, `width` wide, centred on `pos` and facing `dir` (the way
-- the car pointed when it was marked). The car passes a gate by crossing its line going
-- forwards; where along the line it crossed says whether it went through or beside it.
-- Pure Lua (no engine globals): used live in onUpdate and offline by the rules.
local G = {}

local KMH = 3.6
-- Crossing the gate's (infinite) line further than this from its centre doesn't count:
-- the car is somewhere else on the course, not missing this gate.
local REACH_MIN = 15 -- m

-- snap: {pos = {x, y, z}, dir = {x, y, z}} (rallyAcademy's vehicle snapshot)
function G.new(snap, width)
  local dx, dy = snap.dir.x, snap.dir.y
  local n = math.sqrt(dx * dx + dy * dy)
  if n == 0 then dx, dy, n = 0, 1, 1 end
  return {pos = {x = snap.pos.x, y = snap.pos.y, z = snap.pos.z},
          dir = {x = dx / n, y = dy / n}, width = width or 8}
end

local function reach(gate) return math.max(REACH_MIN, gate.width * 2) end

-- Does moving from a to b (tables with x, y) cross the gate forwards?
-- Returns nil, or {f = fraction of the way from a to b, offset = metres right (+)
-- or left (-) of the centre, inside = through the gate}.
function G.crossing(gate, a, b)
  local px, py, dx, dy = gate.pos.x, gate.pos.y, gate.dir.x, gate.dir.y
  local alongA = (a.x - px) * dx + (a.y - py) * dy
  local alongB = (b.x - px) * dx + (b.y - py) * dy
  if not (alongA < 0 and alongB >= 0) then return nil end
  local f = -alongA / (alongB - alongA)
  local cx, cy = a.x + f * (b.x - a.x), a.y + f * (b.y - a.y)
  local offset = (cx - px) * dy - (cy - py) * dx -- right of the gate, facing dir
  if math.abs(offset) > reach(gate) then return nil end
  return {f = f, offset = offset, inside = math.abs(offset) <= gate.width / 2}
end

-- Walk a run's samples and pass the gates in order.
-- Returns one entry per gate: {reached = false} or {reached = true, inside, offset, t, kmh}.
function G.passes(gates, samples)
  local out, idx = {}, 1
  for i = 1, #gates do out[i] = {reached = false} end
  for i = 2, #samples do
    local a, b = samples[i - 1], samples[i]
    while idx <= #gates and a.x and b.x do
      local c = G.crossing(gates[idx], a, b)
      if not c then break end
      local air = (a.air or 0) + c.f * ((b.air or 0) - (a.air or 0))
      out[idx] = {reached = true, inside = c.inside, offset = c.offset,
                  t = a.t + c.f * (b.t - a.t), kmh = air * KMH}
      idx = idx + 1
    end
    if idx > #gates then break end
  end
  return out
end

-- "1.4 m left of it" for a missed gate (offset beyond the half-width).
function G.missText(gate, offset)
  return string.format('%.1f m %s of it', math.abs(offset) - gate.width / 2, offset < 0 and 'left' or 'right')
end

return G
