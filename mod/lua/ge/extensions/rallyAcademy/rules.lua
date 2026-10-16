-- Grading rules: evaluate a drill's typed `assessment.rules` against a run record.
-- Pure Lua (no engine globals), so every rule is unit-tested against synthetic
-- and recorded runs. Each check returns a readable reason: the reason is the coaching.
--
-- Run record samples (runRecord.lua, telemetry.lua): t (sim s), air (m/s), brk/thr (0..1),
-- gear (gearIndex: 0 neutral, -1 reverse), rpm, eng (1 = engine running), hb (handbrake),
-- hx, hy (heading), vx, vy (velocity, m/s), uz (up vector z: 1 upright), dmg (beamstate damage),
-- flat (deflated tyres),
-- x, y, z (m), w = {{n = 'FR', s = wheel speed m/s, m = surface id, f = downforce}, ...}
-- ctx: {zone = marked stop zone {pos, dir}, gates = marked gates (gates.lua), in order}
local Gates = require('ge/extensions/rallyAcademy/gates')
local R = {}

local KMH = 3.6
local WHEEL_NAMES = {FL = 'front-left', FR = 'front-right', RL = 'rear-left', RR = 'rear-right'}

-- Samples from the moment the car left the start (Retry's settling is not graded).
local function runSamples(record)
  local out, from = {}, record.runStartT
  for _, s in ipairs(record.samples or {}) do
    if not from or s.t >= from then out[#out + 1] = s end
  end
  return out
end

local E = {}

-- Peak speed reached on the run (the approach speed for a braking drill). Not "speed
-- when the brake was first touched": right after a Retry the brake reads 0.3 (the
-- game's idle hold, seen on 0.39.4), which would look like braking from 0 km/h.
-- rule: {type = 'entry_speed', minKmh = 65}
function E.entry_speed(rule, samples)
  local maxAir = 0
  for _, s in ipairs(samples) do maxAir = math.max(maxAir, s.air or 0) end
  local kmh, min = maxAir * KMH, rule.minKmh or 0
  if kmh >= min then
    return true, string.format('Braked from %.0f km/h (target %d+)', kmh, min)
  end
  return false, string.format('Only %.0f km/h before braking (target %d+)', kmh, min)
end

-- Where the car came to rest relative to the marked stop zone.
-- rule: {type = 'stop_zone', lengthM = 5, widthM = 6}; ctx.zone = {pos = {x, y}, dir = {x, y}}
function E.stop_zone(rule, samples, ctx)
  local zone = ctx and ctx.zone
  if not (zone and zone.pos and zone.dir) then
    return false, 'No stop zone marked: park on the zone centre and press Mark stop zone'
  end
  local last = samples[#samples]
  if not (last and last.x and last.y) then return false, 'No position data for this run' end
  local dx, dy = zone.dir.x, zone.dir.y
  local n = math.sqrt(dx * dx + dy * dy)
  if n == 0 then return false, 'Stop zone has no direction: mark it again' end
  dx, dy = dx / n, dy / n
  local px, py = last.x - zone.pos.x, last.y - zone.pos.y
  local along, side = px * dx + py * dy, px * dy - py * dx
  local half, halfW = (rule.lengthM or 5) / 2, (rule.widthM or 6) / 2
  if along > half then return false, string.format('Stopped %.1f m past the zone', along - half) end
  if along < -half then return false, string.format('Stopped %.1f m short of the zone', -half - along) end
  if math.abs(side) > halfW then
    return false, string.format('Stopped %.1f m to the side of the zone', math.abs(side) - halfW)
  end
  return true, string.format('Stopped in the zone (%.1f m %s its centre)', math.abs(along), along >= 0 and 'past' or 'before')
end

-- A05: stop with the front bumper just before a line. The line is marked by parking with the
-- front bumper on it, so the car's centre moves exactly as its bumper does.
-- rule: {type = 'stop_before_line', minM = 0, maxM = 2, widthM = 8}; ctx.zone = {pos, dir}
function E.stop_before_line(rule, samples, ctx)
  local zone = ctx and ctx.zone
  if not (zone and zone.pos and zone.dir) then
    return false, 'No stop line marked: park with your front bumper on the line and press Mark stop line'
  end
  local last = samples[#samples]
  if not (last and last.x and last.y) then return false, 'No position data for this run' end
  local dx, dy = zone.dir.x, zone.dir.y
  local n = math.sqrt(dx * dx + dy * dy)
  if n == 0 then return false, 'Stop line has no direction: mark it again' end
  dx, dy = dx / n, dy / n
  local px, py = last.x - zone.pos.x, last.y - zone.pos.y
  local before, side = -(px * dx + py * dy), math.abs(px * dy - py * dx)
  local min, max, halfW = rule.minM or 0, rule.maxM or 2, (rule.widthM or 8) / 2
  local target = string.format('target %g-%g m before it', min, max)
  if side > halfW then return false, string.format('Stopped %.1f m to the side of the line', side - halfW) end
  if before < min then return false, string.format('Stopped %.1f m past the line (%s)', min - before, target) end
  if before > max then return false, string.format('Stopped %.1f m before the line (%s)', before, target) end
  return true, string.format('Stopped %.1f m before the line (%s)', before, target)
end

local function wheelName(n)
  local name = (WHEEL_NAMES[n] or tostring(n)):gsub('^%l', string.upper) -- 1st return only
  return name
end

-- Longest continuous streak of `test(sample, wheel)` on any one wheel.
-- Returns {t = seconds, wheel = 'FL', air = car speed (m/s) when it began}.
local function longestWheelStreak(samples, test)
  local streakStart, worst = {}, {t = 0}
  for i, s in ipairs(samples) do
    local nextT = samples[i + 1] and samples[i + 1].t or s.t
    for _, w in ipairs(s.w or {}) do
      if test(s, w) then
        streakStart[w.n] = streakStart[w.n] or {t = s.t, air = s.air or 0}
        local dur = nextT - streakStart[w.n].t
        if dur > worst.t then worst = {t = dur, wheel = w.n, air = streakStart[w.n].air} end
      else
        streakStart[w.n] = nil
      end
    end
  end
  return worst
end

-- A wheel counts as locked when it turns slower than `ratio` x the car's speed while braking.
local function longestLock(rule, samples)
  local ratio, minAir = rule.ratio or 0.3, (rule.minKmh or 7) / KMH
  return longestWheelStreak(samples, function(s, w)
    return (s.brk or 0) > 0.1 and (s.air or 0) > minAir and math.abs(w.s or 0) < ratio * s.air
  end)
end

-- Longest continuous lockup of any wheel while braking.
-- rule: {type = 'no_sustained_lockup', maxSeconds = 0.5, ratio = 0.3, minKmh = 7}
function E.no_sustained_lockup(rule, samples)
  local worst = longestLock(rule, samples)
  local max = rule.maxSeconds or 0.5
  if worst.t > max then
    return false, string.format('%s wheel locked for %.1f s from %.0f km/h (limit %.1f s)',
      wheelName(worst.wheel), worst.t, worst.air * KMH, max)
  end
  if worst.t > 0 then return true, string.format('No sustained lockup (longest %.1f s)', worst.t) end
  return true, 'No lockup'
end

-- B02: provoke a lockup on purpose, then release it quickly.
-- rule: {type = 'lockup_recovered', maxSeconds = 1.0, minSeconds = 0.2}
function E.lockup_recovered(rule, samples)
  local worst = longestLock(rule, samples)
  local min, max = rule.minSeconds or 0.2, rule.maxSeconds or 1.0
  if worst.t < min then
    return false, string.format('No lockup to recover from (longest %.1f s): brake harder to provoke one', worst.t)
  end
  if worst.t > max then
    return false, string.format('%s wheel stayed locked %.1f s from %.0f km/h (release within %.1f s)',
      wheelName(worst.wheel), worst.t, worst.air * KMH, max)
  end
  return true, string.format('Locked %.1f s from %.0f km/h, then released (limit %.1f s)', worst.t, worst.air * KMH, max)
end

-- A wheel spinning: faster than the car by `ratio` plus `slackKmh`, on throttle.
-- rule: {type = 'no_sustained_wheelspin', maxSeconds = 1.0, ratio = 1.25, slackKmh = 5}
function E.no_sustained_wheelspin(rule, samples)
  local ratio, slack = rule.ratio or 1.25, (rule.slackKmh or 5) / KMH
  local worst = longestWheelStreak(samples, function(s, w)
    return (s.thr or 0) > 0.1 and math.abs(w.s or 0) > (s.air or 0) * ratio + slack
  end)
  local max = rule.maxSeconds or 1.0
  if worst.t > max then
    return false, string.format('%s wheel spun for %.1f s from %.0f km/h (limit %.1f s)',
      wheelName(worst.wheel), worst.t, worst.air * KMH, max)
  end
  if worst.t > 0 then return true, string.format('No sustained wheelspin (longest %.1f s)', worst.t) end
  return true, 'No wheelspin'
end

-- The engine stopped after the run began. Uses the `eng` flag, not rpm: rpm reads ~160
-- while the engine re-idles after a reset (0.39.4). Samples without `eng` can't stall.
-- rule: {type = 'no_stall'}
function E.no_stall(_rule, samples)
  local wasRunning = false
  for _, s in ipairs(samples) do
    if s.eng == 1 then
      wasRunning = true
    elseif s.eng == 0 and wasRunning then
      return false, string.format('Stalled at %.0f km/h', (s.air or 0) * KMH)
    end
  end
  return true, 'No stall'
end

-- Reached a gear during the run (A02: the 1 -> 2 upshift).
-- rule: {type = 'gear_reached', gear = 2}
function E.gear_reached(rule, samples)
  local top = 0
  for _, s in ipairs(samples) do top = math.max(top, s.gear or 0) end
  if top >= rule.gear then return true, string.format('Shifted up to gear %d', top) end
  return false, string.format('Never reached gear %d (highest %d)', rule.gear, top)
end

-- A shift that hangs in neutral while moving: a missed or fumbled gear.
-- rule: {type = 'clean_shifts', maxNeutralSeconds = 1.0, minKmh = 10}
function E.clean_shifts(rule, samples)
  local max, minAir = rule.maxNeutralSeconds or 1.0, (rule.minKmh or 10) / KMH
  local inGear, since, worst, worstAir = false, nil, 0, 0
  for _, s in ipairs(samples) do
    local g = s.gear or 0
    if g ~= 0 then
      inGear, since = true, nil
    elseif inGear and (s.air or 0) > minAir then
      since = since or {t = s.t, air = s.air}
      if s.t - since.t > worst then worst, worstAir = s.t - since.t, since.air end
    else
      since = nil
    end
  end
  if worst > max then
    return false, string.format('Missed a shift: %.1f s in neutral at %.0f km/h (limit %.1f s)', worst, worstAir * KMH, max)
  end
  return true, 'Clean shifts'
end

-- Car events: contact, spin, leaving the road, rollover, handbrake, puncture -----------

-- Surface ids (wheels' contactMaterialID1) -> names, read in-game on 0.39.4 with
-- particles.getMaterialByID (vehicle Lua only; GE has no `particles`).
R.SURFACES = {
  [2] = 'METAL', [3] = 'PLASTIC', [4] = 'RUBBER', [5] = 'GLASS', [6] = 'WOOD', [7] = 'FOLIAGE', [8] = 'CLOTH',
  [9] = 'WATER', [10] = 'ASPHALT', [11] = 'ASPHALT_WET', [12] = 'SLIPPERY', [13] = 'ROCK', [14] = 'DIRT_DUSTY',
  [15] = 'DIRT', [16] = 'SAND', [17] = 'SANDY_ROAD', [18] = 'MUD', [19] = 'GRAVEL', [20] = 'GRASS', [21] = 'ICE',
  [22] = 'SNOW', [29] = 'RUMBLE_STRIP', [30] = 'COBBLESTONE', [31] = 'FOLIAGE_THIN', [32] = 'SPIKE_STRIP',
}

-- Angle between where the car points and where it's going, in degrees (0..180), or nil
-- when it's too slow for that to mean anything.
function R.slipDeg(s, minAir)
  if not (s.hx and s.vx) then return nil end
  local sp = math.sqrt(s.vx * s.vx + s.vy * s.vy)
  if sp < (minAir or 1) then return nil end
  local hn = math.sqrt(s.hx * s.hx + s.hy * s.hy)
  if hn == 0 then return nil end
  local c = (s.hx * s.vx + s.hy * s.vy) / (hn * sp)
  return math.deg(math.acos(math.max(-1, math.min(1, c))))
end

-- Hitting something hard enough to damage the car (barriers, walls, other cars). Cones
-- barely dent a car, so cone contact needs the cones themselves (scene control, later).
-- A tyre deflating adds ~1000 damage, one sample after the flat flag (0.39.4), so damage
-- gained within PUNCTURE_WINDOW of a tyre going flat is a puncture (no_puncture), not contact.
-- rule: {type = 'no_damage', maxDamage = 50}
local PUNCTURE_WINDOW = 0.3 -- s
function E.no_damage(rule, samples)
  local base, max, prev, punctureUntil = nil, rule.maxDamage or 50, nil, -math.huge
  for i, s in ipairs(samples) do
    if s.dmg then
      base = base or s.dmg
      if prev and (s.flat or 0) > (prev.flat or 0) then punctureUntil = s.t + PUNCTURE_WINDOW end
      if prev and prev.dmg and s.t <= punctureUntil then base = base + (s.dmg - prev.dmg) end
      prev = s
      if s.dmg - base > max then
        local before = samples[i - 1] or s
        return false, string.format('Hit something at %.0f km/h (damage +%.0f)', (before.air or 0) * KMH, s.dmg - base)
      end
    end
  end
  if not base then return true, 'No contact (no damage data)' end
  return true, 'No contact'
end

-- Spinning: the car slides more than `maxSlipDeg` off its direction of travel for longer
-- than `maxSeconds` while moving faster than `minKmh`. Reverse gear is skipped (backing up
-- reads as a 180 degree slide). Defaults from a recorded handbrake spin on 0.39.4: the car
-- turned 143 degrees, sliding past 75 for 0.47 s but past 90 for only 0.2 s; normal runs
-- stayed under 25. Drills that slide on purpose set their own limits.
-- rule: {type = 'no_spin', maxSlipDeg = 70, minKmh = 10, maxSeconds = 0.3}
function E.no_spin(rule, samples)
  local maxSlip, minAir, maxT = rule.maxSlipDeg or 70, (rule.minKmh or 10) / KMH, rule.maxSeconds or 0.3
  local since, worst = nil, 0
  for _, s in ipairs(samples) do
    local slip = (s.gear or 0) >= 0 and R.slipDeg(s, minAir) or nil
    if slip and slip > maxSlip then
      since = since or {t = s.t, air = s.air or 0}
      if s.t - since.t > maxT then
        return false, string.format('Spun at %.0f km/h (sliding %.0f° off your direction of travel)', since.air * KMH, slip)
      end
    else
      since = nil
    end
    if slip and slip > worst then worst = slip end
  end
  return true, string.format('No spin (largest slide %.0f°)', worst)
end

-- Leaving the road: more than `maxWheelsOff` wheels touching a surface not in `surfaces`
-- for longer than `maxSeconds`. Wheels in the air don't count either way.
-- rule: {type = 'on_surface', surfaces = {'ASPHALT', 'GRAVEL'}, maxWheelsOff = 2, maxSeconds = 0.5}
function E.on_surface(rule, samples, ctx)
  local names = (ctx and ctx.surfaces) or R.SURFACES
  local ok = {}
  for _, n in ipairs(rule.surfaces or {}) do ok[n] = true end
  local maxOff, maxT = rule.maxWheelsOff or 2, rule.maxSeconds or 0.5
  local since, offName
  for _, s in ipairs(samples) do
    local off, name = 0, nil
    for _, w in ipairs(s.w or {}) do
      if w.m and w.m >= 0 then
        local n = names[w.m] or ('surface ' .. w.m)
        if not ok[n] then off, name = off + 1, n end
      end
    end
    if off > maxOff then
      if not since then since, offName = {t = s.t, air = s.air or 0, off = off}, name end
      if s.t - since.t > maxT then
        return false, string.format('Left the road: %d wheels on %s at %.0f km/h', since.off, offName, since.air * KMH)
      end
    else
      since = nil
    end
  end
  return true, 'Stayed on the road'
end

-- Rolled: the car's up vector tipped past ~70 degrees.
-- rule: {type = 'no_rollover', minUpZ = 0.35}
function E.no_rollover(rule, samples)
  for _, s in ipairs(samples) do
    if s.uz and s.uz < (rule.minUpZ or 0.35) then
      return false, string.format('Rolled over at %.0f km/h', (s.air or 0) * KMH)
    end
  end
  return true, 'Stayed upright'
end

-- Handbrake pulled while moving (the handbrake reads 1 at rest after a reset).
-- rule: {type = 'no_handbrake', minKmh = 10}
function E.no_handbrake(rule, samples)
  local minAir = (rule.minKmh or 10) / KMH
  for _, s in ipairs(samples) do
    if (s.hb or 0) > 0.5 and (s.air or 0) > minAir then
      return false, string.format('Used the handbrake at %.0f km/h', s.air * KMH)
    end
  end
  return true, 'No handbrake'
end

-- A tyre went flat during the run.
-- rule: {type = 'no_puncture'}
function E.no_puncture(_rule, samples)
  local base = nil
  for _, s in ipairs(samples) do
    if s.flat then
      base = base or s.flat
      if s.flat > base then return false, string.format('Punctured a tyre at %.0f km/h', (s.air or 0) * KMH) end
    end
  end
  return true, 'No puncture'
end

-- Gates ------------------------------------------------------------------------

local function gateList(ctx)
  local gates = ctx and ctx.gates
  if not (gates and #gates > 0) then return nil, 'No gates marked: drive to each gate and press + Gate' end
  return gates
end

-- Every gate driven through, in order, inside its width.
-- rule: {type = 'gates_passed'}
function E.gates_passed(_rule, samples, ctx)
  local gates, err = gateList(ctx)
  if not gates then return false, err end
  for i, p in ipairs(Gates.passes(gates, samples)) do
    if not p.reached then return false, string.format('Gate %d not reached', i) end
    if not p.inside then
      return false, string.format('Missed gate %d (%s)', i, Gates.missText(gates[i], p.offset))
    end
  end
  return true, string.format('All %d gates passed', #gates)
end

-- Speed when crossing each gate inside a band. A gate not reached or missed fails.
-- rule: {type = 'speed_at_gates', minKmh = 27, maxKmh = 33, gate = 3 (optional: just that one; -1 = last)}
function E.speed_at_gates(rule, samples, ctx)
  local gates, err = gateList(ctx)
  if not gates then return false, err end
  local min, max = rule.minKmh or 0, rule.maxKmh or math.huge
  local passes = Gates.passes(gates, samples)
  local first, last = 1, #gates
  if rule.gate then
    first = rule.gate < 0 and #gates + 1 + rule.gate or rule.gate
    last = first
    if not gates[first] then return false, string.format('Gate %d is not marked', rule.gate) end
  end
  local speeds, problem = {}, nil
  for i = first, last do
    local p = passes[i]
    if not p.reached then
      speeds[#speeds + 1] = '-'
      problem = problem or string.format('gate %d not reached', i)
    else
      speeds[#speeds + 1] = string.format('%.0f', p.kmh)
      if p.kmh < min then problem = problem or string.format('gate %d too slow', i)
      elseif p.kmh > max then problem = problem or string.format('gate %d too fast', i) end
    end
  end
  local band = max == math.huge and string.format('%d+', min) or string.format('%d-%d', min, max)
  local text = string.format('%s %s km/h (band %s)', first == last and ('Gate ' .. first .. ':') or 'Gate speeds',
    table.concat(speeds, ' / '), band)
  if problem then return false, text .. ': ' .. problem end
  return true, text
end

-- No braking between two gates (default: first to last). Braking at a crawl is ignored:
-- the brake reads 0.3 at rest after a reset (0.39.4).
-- rule: {type = 'no_brake_between_gates', fromGate = 1, toGate = -1}
function E.no_brake_between_gates(rule, samples, ctx)
  local gates, err = gateList(ctx)
  if not gates then return false, err end
  local function index(i, default) i = i or default; return i < 0 and #gates + 1 + i or i end
  local from, to = index(rule.fromGate, 1), index(rule.toGate, -1)
  local passes = Gates.passes(gates, samples)
  if not (passes[from] and passes[from].reached) then return false, string.format('Gate %d not reached', from) end
  local endT = passes[to] and passes[to].reached and passes[to].t or math.huge
  for _, s in ipairs(samples) do
    if s.t > passes[from].t and s.t < endT and (s.brk or 0) > 0.1 and (s.air or 0) > 2 then
      return false, string.format('Braked between gates %d and %d (at %.0f km/h)', from, to, s.air * KMH)
    end
  end
  return true, string.format('No braking between gates %d and %d', from, to)
end

R.evaluators = E

-- Rule types and their required parameters. tools/dev.py validate reads this table and
-- R.GATE_RULES from this file, so keep each entry on one line: name = {'param', ...},
R.TYPES = {
  entry_speed = {'minKmh'},
  stop_zone = {'lengthM', 'widthM'},
  no_sustained_lockup = {'maxSeconds'},
  lockup_recovered = {'maxSeconds'},
  no_sustained_wheelspin = {'maxSeconds'},
  no_stall = {},
  gear_reached = {'gear'},
  clean_shifts = {},
  stop_before_line = {'minM', 'maxM'},
  no_damage = {},
  no_spin = {},
  on_surface = {},
  no_rollover = {},
  no_handbrake = {},
  no_puncture = {},
  gates_passed = {},
  speed_at_gates = {'minKmh', 'maxKmh'},
  no_brake_between_gates = {},
}

-- Rule types that need marked gates (assessment.gates in the drill data).
R.GATE_RULES = {'gates_passed', 'speed_at_gates', 'no_brake_between_gates'}

-- Returns {passed = bool, checks = {{type, ok, text}, ...}}; an empty record fails.
function R.evaluate(rules, record, ctx)
  local samples = runSamples(record or {})
  local result = {passed = true, checks = {}}
  if #samples == 0 then
    result.passed = false
    result.checks[1] = {type = 'record', ok = false, text = 'No telemetry for this run'}
    return result
  end
  for _, rule in ipairs(rules or {}) do
    local fn = E[rule.type]
    local ok, text
    if fn then
      ok, text = fn(rule, samples, ctx)
    else
      ok, text = false, 'Unknown rule type: ' .. tostring(rule.type)
    end
    result.checks[#result.checks + 1] = {type = rule.type, ok = ok, text = text}
    result.passed = result.passed and ok
  end
  return result
end

return R
