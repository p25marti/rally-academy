-- Racing lines (ADR 0013): the line through a drill, worked out from the map's road (rallyAcademy/roads.json, built
-- with the map by tools/mapgen/racingline.py) and the drill's own start and gates.
--
-- The line is the minimum-curvature path inside the road: the centre line moved sideways at each point, as little
-- bent as the road allows while the car stays on it and goes through every gate. It starts where the drill starts
-- the car. Each point carries a target speed from a simple model (the surface's grip, the road's tilt, a standing
-- start, braking for each corner) and what to do there. A guide, not physics: no gearing, gradient, downforce or
-- combined grip. Pure Lua (no engine globals).
local R = {}

R.CAR_MARGIN = 1.3 -- m kept from each road edge: half a car and a little
R.GATE_MARGIN = 1.5 -- m kept from each gate post: half a car (about 0.95 m) and room to wander
R.REACH = 8 -- m: a road counts for a start this close to its centre line, running within ~45 degrees of its way
R.TAIL = 30 -- m of line past the drill's last gate
R.BRAKE, R.HOLD, R.ACCELERATE = -1, 0, 1 -- what to do at a point
local G, ACCEL, BRAKE_GRIP, TOP = 9.81, 3.0, 0.8, 140 / 3.6 -- m/s2; m/s2 at most; share of grip; m/s
local CENTRE_PULL = 1e-7 -- a slight preference for the middle, so a straight with nothing to bend for stays there
local START_HELD = 2 -- points that stay where the drill starts the car

local function dist(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end

-- Unit vectors to the left of the way the points run, at each point.
function R.normals(pts)
  local out = {}
  for i = 1, #pts do
    local a, b = pts[math.max(1, i - 1)], pts[math.min(#pts, i + 1)]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local n = math.sqrt(dx * dx + dy * dy)
    if n == 0 then n = 1 end
    out[i] = {-dy / n, dx / n}
  end
  return out
end

-- Solve a symmetric positive-definite system with bandwidth 2: rows[i] = {[j] = value} for |i - j| <= 2.
local function solveBanded(rows, rhs)
  local n = #rhs
  local a, b = {}, {}
  for i = 1, n do
    a[i] = {}
    for j, v in pairs(rows[i]) do a[i][j] = v end
    b[i] = rhs[i]
  end
  for i = 1, n do -- elimination without pivoting keeps the band
    for k = i + 1, math.min(n, i + 2) do
      local f = (a[k][i] or 0) / a[i][i]
      if f ~= 0 then
        for j = i, math.min(n, i + 2) do a[k][j] = (a[k][j] or 0) - f * (a[i][j] or 0) end
        b[k] = b[k] - f * b[i]
      end
    end
  end
  local x = {}
  for i = n, 1, -1 do
    local s = b[i]
    for j = i + 1, math.min(n, i + 2) do s = s - (a[i][j] or 0) * x[j] end
    x[i] = s / a[i][i]
  end
  return x
end

-- Sideways offsets (metres left of the centre line, within lo[i]..hi[i]) that make the line as straight as possible:
-- the least sum of squared second differences. The first START_HELD points stay at `first`. Exact, by an active-set
-- solve of the banded system (bounds clamped, then released while they pull the wrong way).
function R.minCurvature(centre, lo, hi, first)
  local n = #centre
  local nv = R.normals(centre)
  local H, g0, coef = {}, {}, {1, -2, 1}
  for i = 1, n do H[i], g0[i] = {}, 0 end
  for j = 2, n - 1 do
    local dx = centre[j - 1][1] - 2 * centre[j][1] + centre[j + 1][1]
    local dy = centre[j - 1][2] - 2 * centre[j][2] + centre[j + 1][2]
    for p = 1, 3 do
      local i = j - 2 + p
      g0[i] = g0[i] + coef[p] * (dx * nv[i][1] + dy * nv[i][2])
      for q = 1, 3 do
        local k = j - 2 + q
        H[i][k] = (H[i][k] or 0) + coef[p] * coef[q] * (nv[i][1] * nv[k][1] + nv[i][2] * nv[k][2])
      end
    end
  end
  local a, held, clamped = {}, {}, {}
  for i = 1, n do
    H[i][i] = (H[i][i] or 0) + CENTRE_PULL
    a[i] = 0
    if i <= START_HELD then a[i], held[i] = first or 0, true
    elseif hi[i] - lo[i] < 1e-6 then a[i], held[i] = hi[i], true end -- a gate as narrow as the car: through its middle
  end
  for _ = 1, 200 do
    local free, pos = {}, {}
    for i = 1, n do
      if not held[i] and not clamped[i] then free[#free + 1] = i; pos[i] = #free end
    end
    if #free > 0 then
      local rows, rhs = {}, {}
      for f, i in ipairs(free) do
        local row, r = {}, -g0[i]
        for k, v in pairs(H[i]) do
          if pos[k] then row[pos[k]] = v else r = r - v * a[k] end
        end
        rows[f], rhs[f] = row, r
      end
      for f, x in ipairs(solveBanded(rows, rhs)) do a[free[f]] = x end
    end
    local over, released = false, false
    for _, i in ipairs(free) do
      if a[i] > hi[i] + 1e-9 then a[i], clamped[i], over = hi[i], 'hi', true
      elseif a[i] < lo[i] - 1e-9 then a[i], clamped[i], over = lo[i], 'lo', true end
    end
    if not over then
      for i, side in pairs(clamped) do
        local grad = g0[i]
        for k, h in pairs(H[i]) do grad = grad + h * a[k] end
        if (side == 'hi' and grad > 1e-9) or (side == 'lo' and grad < -1e-9) then -- it wants back inside
          clamped[i], released = nil, true
        end
      end
    end
    if not over and not released then break end
  end
  return a
end

-- Signed curvature (1/m, + turning left) through the points `reach` either side of i.
function R.curvature(pts, i, reach)
  local a, b, c = pts[math.max(1, i - reach)], pts[i], pts[math.min(#pts, i + reach)]
  local cross = (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
  local d = dist(a, b) * dist(b, c) * dist(c, a)
  return d == 0 and 0 or 2 * cross / d
end

-- Target speed (m/s) at each point and what to do there (R.BRAKE, R.HOLD the corner's limit, R.ACCELERATE): the
-- corner's limit, then what accelerating from a standstill at the first point and braking for each corner allow.
-- bank[i]: the road's tilt across as a slope, + leaning into the turn.
function R.speeds(pts, grip, bank)
  local limit, fwd, v, phase = {}, {}, {}, {}
  for i = 1, #pts do
    local k = math.abs(R.curvature(pts, i, 2)) -- over 12 m: a kink in the road is no corner
    local b = bank and bank[i] or 0
    if k < 1e-6 or 1 - grip * b <= 0 then
      limit[i] = TOP
    else
      limit[i] = math.min(TOP, math.sqrt(math.max(0, G / k * (grip + b) / (1 - grip * b))))
    end
    fwd[i] = limit[i]
  end
  fwd[1] = 0
  for i = 2, #pts do
    fwd[i] = math.min(fwd[i], math.sqrt(fwd[i - 1] ^ 2 + 2 * math.min(ACCEL, grip * G) * dist(pts[i - 1], pts[i])))
  end
  for i = 1, #pts do v[i] = fwd[i] end
  for i = #pts - 1, 1, -1 do
    v[i] = math.min(v[i], math.sqrt(v[i + 1] ^ 2 + 2 * BRAKE_GRIP * grip * G * dist(pts[i], pts[i + 1])))
  end
  for i = 1, #pts do -- braking: held down by the next corner; accelerating: below the limit; within 1 m/s, at it
    phase[i] = v[i] < fwd[i] - 1 and R.BRAKE or (v[i] < limit[i] - 1 and R.ACCELERATE or R.HOLD)
  end
  return v, phase
end

-- The road a start pose is on, running its way: the road, its points in the driven order (tilt flipped when driven
-- against its own direction) and the index nearest the start. nil when no road is near enough.
local function roadAt(roads, start)
  local fx, fy = start.dir.x, start.dir.y
  local n = math.sqrt(fx * fx + fy * fy)
  if n == 0 then return nil end
  fx, fy = fx / n, fy / n
  local best, bestD = nil, R.REACH ^ 2
  for _, road in ipairs(roads or {}) do
    local pts = road.points or {}
    for i = 1, #pts - 1 do
      local d = (pts[i][1] - start.pos.x) ^ 2 + (pts[i][2] - start.pos.y) ^ 2
      local len = dist(pts[i], pts[i + 1])
      local along = len > 0 and ((pts[i + 1][1] - pts[i][1]) * fx + (pts[i + 1][2] - pts[i][2]) * fy) / len or 0
      if d < bestD and math.abs(along) > 0.7 then best, bestD = {road = road, i = i, reverse = along < 0}, d end
    end
  end
  if not best then return nil end
  local pts = best.road.points
  if not best.reverse then return best.road, pts, best.i end
  local rev = {}
  for i = #pts, 1, -1 do rev[#rev + 1] = {pts[i][1], pts[i][2], pts[i][3], -(pts[i][4] or 0)} end
  return best.road, rev, #pts + 1 - best.i
end

local function nearest(pts, from, x, y)
  local at, near = from, math.huge
  for i = from, #pts do
    local d = (pts[i][1] - x) ^ 2 + (pts[i][2] - y) ^ 2
    if d < near then at, near = i, d end
  end
  return at
end

-- The racing line for a drill: from its start pose {pos, dir} along the road it's on, through its gates
-- ({pos, width}, in order) to R.TAIL metres past the last (or on to the road's end), as {{x, y, z, kmh, phase}}.
-- nil when the start isn't on one of the roads.
function R.forDrill(roads, start, gates)
  local road, pts, s = roadAt(roads, start)
  if not road then return nil end
  local e = #pts
  local last = gates and gates[#gates]
  if last then
    e = nearest(pts, s, last.pos.x, last.pos.y)
    local run = 0
    while e < #pts and run < R.TAIL do run = run + dist(pts[e], pts[e + 1]); e = e + 1 end
  end
  local centre = {}
  for i = s, e do centre[#centre + 1] = pts[i] end
  if #centre < 3 then return nil end
  local nv = R.normals(centre)
  local edge = math.max(0, road.width / 2 - R.CAR_MARGIN)
  local function onRoad(v) return math.max(-edge, math.min(edge, v)) end
  local lo, hi = {}, {}
  for i = 1, #centre do lo[i], hi[i] = -edge, edge end
  for _, g in ipairs(gates or {}) do -- through each gate, clear of its posts
    local k = nearest(centre, 1, g.pos.x, g.pos.y)
    local c = (g.pos.x - centre[k][1]) * nv[k][1] + (g.pos.y - centre[k][2]) * nv[k][2]
    local half = math.max(0, (g.width or 0) / 2 - R.GATE_MARGIN)
    lo[k], hi[k] = math.max(lo[k], c - half), math.min(hi[k], c + half)
    if lo[k] > hi[k] then lo[k] = onRoad(c); hi[k] = lo[k] end
  end
  local first = onRoad((start.pos.x - centre[1][1]) * nv[1][1] + (start.pos.y - centre[1][2]) * nv[1][2])
  local off = R.minCurvature(centre, lo, hi, first)
  local line = {}
  for i, c in ipairs(centre) do line[i] = {c[1] + nv[i][1] * off[i], c[2] + nv[i][2] * off[i]} end
  local bank = {}
  for i = 1, #line do
    local tilt = centre[i][4] or 0 -- right above left: leans into a left turn
    bank[i] = R.curvature(line, i, 1) >= 0 and tilt or -tilt
  end
  local v, phase = R.speeds(line, road.grip or 0.65, bank)
  local out = {}
  for i, p in ipairs(line) do
    -- moving left by the offset changes the ground's height by the tilt
    out[i] = {x = p[1], y = p[2], z = centre[i][3] - (centre[i][4] or 0) * off[i], kmh = v[i] * 3.6, phase = phase[i]}
  end
  return out
end

return R
