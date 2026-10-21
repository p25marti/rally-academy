-- Grading rules: evaluate a drill's typed `assessment.rules` against a run record.
-- Pure Lua (no engine globals), so every rule is unit-tested against synthetic
-- and recorded runs. Each check returns a readable reason: the reason is the coaching.
--
-- Run record samples (runRecord.lua, telemetry.lua): t (sim s), air (m/s), brk/thr (0..1),
-- gear (gearIndex: 0 neutral, -1 reverse), rpm, eng (1 = engine running), hb (handbrake),
-- hx, hy (heading), vx, vy (velocity, m/s), uz (up vector z: 1 upright), dmg (beamstate damage),
-- steer (steering wheel angle in degrees, electrics.steering: about +80 mid-corner in the Covet),
-- flat (deflated tyres),
-- x, y, z (m), w = {{n = 'FR', s = wheel speed m/s, m = surface id, f = downforce}, ...}
-- ctx: {zone = marked stop zone {pos, dir}, gates = marked gates (gates.lua), in order}
local Gates = require('ge/extensions/rallyAcademy/gates')
local Layout = require('ge/extensions/rallyAcademy/layout')
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

-- The car's footprint for this run (measured at Retry), or a typical small car's.
local function carOf(ctx)
  return (ctx and ctx.car) or Layout.centredCar(4, 1.8)
end

local function heading(s)
  if s.hx and (s.hx ~= 0 or s.hy ~= 0) then return s.hx, s.hy end
  return nil
end


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
  local min, max = rule.minM or 0, rule.maxM or 2
  local target = string.format('target %g-%g m before it', min, max)
  local line = ctx and ctx.course and ctx.course.line
  if line then
    -- An authored line: measure from the car's own front bumper (its measured footprint).
    local last, hx, hy = samples[#samples], nil, nil
    if last then hx, hy = heading(last) end
    if not (last and last.x and hx) then return false, 'No position data for this run' end
    local before, side = Layout.bumperToLine(line, carOf(ctx), last.x, last.y, hx, hy)
    if math.abs(side) > line.widthM / 2 then
      return false, string.format('Stopped %.1f m to the side of the line', math.abs(side) - line.widthM / 2)
    end
    if before < min then return false, string.format('Stopped %.2f m past the line (%s)', min - before, target) end
    if before > max then return false, string.format('Stopped %.2f m before the line (%s)', before, target) end
    return true, string.format('Stopped %.2f m before the line (%s)', before, target)
  end
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
  local halfW = (rule.widthM or 8) / 2
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
-- Optional `fromGate` / `toGate`: only between those gates.
-- rule: {type = 'no_sustained_wheelspin', maxSeconds = 1.0, ratio = 1.25, slackKmh = 5}
function E.no_sustained_wheelspin(rule, samples, ctx)
  if rule.fromGate then
    -- only between two gates (D04: from the apex out), not the launch
    local t0, t1 = R.gateWindow(ctx, samples, rule.fromGate, rule.toGate or -1)
    if not t0 then return false, t1 end
    local within = {}
    for _, s in ipairs(samples) do if s.t >= t0 and s.t <= t1 then within[#within + 1] = s end end
    samples = within
  end
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

-- How long the car took from moving off (the run's start mark, about 1 m/s) to `kmh`: the
-- launch's coaching number (A02: 0-40 km/h).
-- rule: {type = 'time_to_speed', kmh = 40, maxSeconds = 8}
function E.time_to_speed(rule, samples)
  local first = samples[1]
  for _, s in ipairs(samples) do
    if (s.air or 0) * KMH >= rule.kmh then
      local t = s.t - first.t
      local text = string.format('0-%d km/h in %.1f s (target %g s)', rule.kmh, t, rule.maxSeconds)
      return t <= rule.maxSeconds, text
    end
  end
  return false, string.format('Never reached %d km/h', rule.kmh)
end

-- Reached a gear during the run (A02: the 1 -> 2 upshift).
-- rule: {type = 'gear_reached', gear = 2}
function E.gear_reached(rule, samples)
  local top = 0
  for _, s in ipairs(samples) do top = math.max(top, s.gear or 0) end
  if top >= rule.gear then return true, string.format('Shifted up to gear %d', top) end
  return false, string.format('Never reached gear %d (highest %d)', rule.gear, top)
end

local ORDINAL = {'1st', '2nd', '3rd', '4th', '5th', '6th', '7th', '8th'}
local function gearName(g) return ORDINAL[g] or (tostring(g) .. 'th') end

-- Slowing down through the gears one at a time after the highest gear reached, down to `toGear`
-- (A03: 3rd -> 2nd, not 4th -> 2nd). Neutral and reverse are skipped; going lower than `toGear`
-- at the stop is fine. A gear counts only once it's held `minHoldSeconds`: the sequential box can
-- blip 3 -> 2 -> 3 within a tenth of a second while shifting up (seen on 0.40.0), which isn't a downshift.
-- rule: {type = 'progressive_downshifts', toGear = 2, minHoldSeconds = 0.3}
function E.progressive_downshifts(rule, samples)
  local hold = rule.minHoldSeconds or 0.3
  -- Forward gears as held stretches: {{gear, t0, t1}}, neutral and reverse dropped, then blips dropped.
  local runs = {}
  for _, s in ipairs(samples) do
    local g = s.gear or 0
    if g > 0 then
      local r = runs[#runs]
      if r and r[1] == g then r[3] = s.t else runs[#runs + 1] = {g, s.t, s.t} end
    end
  end
  local held = {}
  for i, r in ipairs(runs) do
    local nextStart = runs[i + 1] and runs[i + 1][2] or r[3] + hold
    if nextStart - r[2] >= hold then
      if held[#held] and held[#held][1] == r[1] then held[#held][3] = r[3] else held[#held + 1] = {r[1], r[2], r[3]} end
    end
  end
  local top, topAt = 0, nil
  for i, r in ipairs(held) do
    if r[1] > top then top, topAt = r[1], i end
  end
  if top <= rule.toGear then
    return false, string.format('Never above %s, so nothing to downshift', gearName(rule.toGear))
  end
  local seq, last = {top}, top
  for i = topAt + 1, #held do
    local g = held[i][1]
    if g ~= last then
      if g < last - 1 and last > rule.toGear then
        return false, string.format('Skipped from %s to %s: go down one gear at a time', gearName(last), gearName(g))
      end
      if g < last then seq[#seq + 1] = g end
      last = g
      if g <= rule.toGear then break end
    end
  end
  if last > rule.toGear then
    return false, string.format('Stayed in %s: downshift to %s as you slow', gearName(last), gearName(rule.toGear))
  end
  local names = {}
  for i, g in ipairs(seq) do names[i] = tostring(g) end
  return true, 'Downshifted ' .. table.concat(names, '→')
end

-- The engine never spins past `maxRpm`: a downshift at too high a speed (or bouncing off the
-- limiter, for tighter limits). The Covet Student Driver's limiter is 6500 rpm (0.39.4).
-- rule: {type = 'no_over_rev', maxRpm = 6700}
function E.no_over_rev(rule, samples)
  local peak, at = 0, nil
  for _, s in ipairs(samples) do
    if (s.rpm or 0) > peak then peak, at = s.rpm, s end
  end
  if not at then return true, 'No rpm data' end
  if peak > rule.maxRpm then
    return false, string.format('Over-revved to %.0f rpm in %s at %.0f km/h (limit %d)', peak,
      gearName(at.gear or 0), (at.air or 0) * KMH, rule.maxRpm)
  end
  return true, string.format('Peak %.0f rpm (limit %d)', peak, rule.maxRpm)
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

-- Slip angle with a sign: positive when the car points further into a `turn` ('left' | 'right')
-- than it is travelling (the rear stepping out), negative when it points outside it (the front
-- pushing wide). nil below `minAir` m/s or without heading and velocity.
function R.signedSlipDeg(s, minAir, turn)
  local slip = R.slipDeg(s, minAir)
  if not slip then return nil end
  local cross = s.vx * s.hy - s.vy * s.hx -- > 0: heading to the left of travel
  if turn == 'right' then cross = -cross end
  return cross >= 0 and slip or -slip
end

-- Hitting something hard enough to damage the car (barriers, walls, other cars). Cones
-- barely dent a car, so cone contact needs the cones themselves (scene control, later).
-- A tyre deflating adds ~1000 damage, one sample after the flat flag (0.39.4), so damage
-- gained within PUNCTURE_WINDOW of a tyre going flat is a puncture (no_puncture), not contact.
-- `hint` replaces "Hit something" where damage comes from the ground itself (E07's bumps), as coaching.
-- rule: {type = 'no_damage', maxDamage = 50, hint = 'ease off over the bumps'}
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
        if rule.hint then
          return false, string.format('Damaged the car at %.0f km/h (damage +%.0f): %s', (before.air or 0) * KMH, s.dmg - base,
            rule.hint)
        end
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

-- Handbrake pulls while moving (C04: exactly one): each time the handbrake goes on (over 0.5) above
-- `minKmh` counts once.
-- rule: {type = 'handbrake_pulls', count = 1, minKmh = 5}
function E.handbrake_pulls(rule, samples)
  local minAir, want = (rule.minKmh or 5) / KMH, rule.count or 1
  local pulls, on = 0, false
  for _, s in ipairs(samples) do
    local now = (s.hb or 0) > 0.5
    if now and not on and (s.air or 0) > minAir then pulls = pulls + 1 end
    on = now
  end
  local text = string.format('%d handbrake pull%s (target %d)', pulls, pulls == 1 and '' or 's', want)
  if pulls == want then return true, text end
  if pulls == 0 then return false, text .. ': pull it once to rotate the car' end
  return false, text .. ': one firm pull, then drive out'
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
  return true, #gates == 1 and 'Through the gate' or string.format('All %d gates passed', #gates)
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
      speeds[#speeds + 1] = string.format('%.1f', p.kmh) -- tenths: medal bands are 2 km/h wide
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

-- Authored courses (layout.lua): cones, markers, the parking box --------------------

local function courseOf(ctx, what)
  local course = ctx and ctx.course
  if not (course and course[what]) then return nil end
  return course
end

-- Every course cone passed on the side its `keep` says.
-- rule: {type = 'cones_passed'}; ctx.course.cones = {{x, y, dir, keep}}
function E.cones_passed(_rule, samples, ctx)
  local course = courseOf(ctx, 'cones')
  if not course or #course.cones == 0 then return false, 'This drill has no cones laid out' end
  for i, cone in ipairs(course.cones) do
    local name = #course.cones > 1 and ('cone ' .. i) or 'the cone'
    local crossing
    for j = 2, #samples do
      local a, b = samples[j - 1], samples[j]
      if a.x and b.x then crossing = Layout.coneCrossing(cone, a, b) end
      if crossing then break end
    end
    if not crossing then return false, string.format('Never got past %s', name) end
    if crossing.side ~= cone.keep then
      return false, string.format('Went the wrong side of %s (%s)', name, Layout.keepText(cone.keep))
    end
  end
  return true, #course.cones > 1 and string.format('All %d cones passed on the correct side', #course.cones)
    or 'Passed the cone on the correct side'
end

-- The car's body never touches a drawn cone or gate post (they can't be hit, so this is the
-- contact check for drawn courses).
-- rule: {type = 'markers_clear', clearanceM = 0}; ctx.course.markers = {{x, y, name}}
-- With physical markers (props.lua) ctx.hits lists what the car actually touched, {{name, kmh}} in order, and
-- decides; the measured distance only says how close the car came. Without them (or in an old recording) a car
-- closer than a drawn marker's radius clipped it.
function E.markers_clear(rule, samples, ctx)
  local course = courseOf(ctx, 'markers')
  if not course then return false, 'This drill has no course laid out' end
  if ctx.hits and ctx.hits[1] then
    return false, string.format('Clipped %s at %.0f km/h', ctx.hits[1].name, ctx.hits[1].kmh or 0)
  end
  local car, need = carOf(ctx), Layout.MARKER_RADIUS + (rule.clearanceM or 0)
  local closest, closestName, hit = math.huge, nil, nil
  for _, s in ipairs(samples) do
    local hx, hy = heading(s)
    if hx and s.x then
      for _, m in ipairs(course.markers) do
        local d = Layout.distanceToCar(car, s.x, s.y, hx, hy, m.x, m.y)
        if d < closest then closest, closestName = d, m.name end
        if d < need and not hit then hit = {name = m.name, air = s.air or 0} end
      end
    end
  end
  if hit and not ctx.hits then return false, string.format('Clipped %s at %.0f km/h', hit.name, hit.air * KMH) end
  if not closestName then return true, 'Cleared every marker' end
  return true, string.format('Cleared every marker (closest: %s, %.1f m)', closestName,
    math.max(0, closest - Layout.MARKER_RADIUS))
end

-- At rest with the whole car inside the course's parking box, shrunk by `insetM` on every
-- side (the tiers' smaller boxes). `label` names the box in the coaching text.
-- rule: {type = 'park_in_box', insetM = 0, label = 'box'}; ctx.course.box = {x, y, dir, lengthM, widthM}
function E.park_in_box(rule, samples, ctx)
  local course = courseOf(ctx, 'box')
  if not course then return false, 'This drill has no parking box laid out' end
  local last, hx, hy = samples[#samples], nil, nil
  if last then hx, hy = heading(last) end
  if not (last and last.x and hx) then return false, 'No position data for this run' end
  local fit = Layout.boxFit(course.box, carOf(ctx), last.x, last.y, hx, hy, rule.insetM)
  local label = rule.label or 'box'
  if fit.inside then
    return true, string.format('Parked inside the %s (%.2f m to spare)', label, fit.margin)
  end
  if math.abs(fit.along) > course.box.lengthM / 2 + 2 or math.abs(fit.side) > course.box.widthM / 2 + 2 then
    return false, string.format('Stopped %.1f m %s the %s', math.sqrt(fit.along ^ 2 + fit.side ^ 2),
      fit.along < 0 and 'short of' or 'away from', label)
  end
  return false, string.format('%s corner %.2f m over the %s edge of the %s',
    (Layout.CORNER_NAMES[fit.corner]:gsub('^%l', string.upper)), -fit.margin, fit.edge, label)
end

-- Never backs up: distance travelled backwards (against the way the car points) stays
-- under `maxM`, which allows a settle after a hard stop.
-- rule: {type = 'no_reverse', maxM = 0.3}
function E.no_reverse(rule, samples)
  local back, max = 0, rule.maxM or 0.3
  for i = 2, #samples do
    local a, b = samples[i - 1], samples[i]
    local hx, hy = heading(b)
    if hx and a.x and b.x then
      local n = math.sqrt(hx * hx + hy * hy)
      local moved = ((b.x - a.x) * hx + (b.y - a.y) * hy) / n
      if moved < 0 then back = back + -moved end
    end
  end
  if back > max then return false, string.format('Reversed %.1f m (no reversing)', back) end
  return true, 'No reversing'
end

-- Run time at most `maxSeconds` (the tiers' time targets). ctx.time = the run's time.
-- rule: {type = 'max_time', maxSeconds = 12}
function E.max_time(rule, _samples, ctx)
  local t = ctx and ctx.time
  if not t then return false, 'No run time' end
  if t <= rule.maxSeconds then return true, string.format('Time %.1f s (target %g s)', t, rule.maxSeconds) end
  return false, string.format('Time %.1f s (target %g s)', t, rule.maxSeconds)
end

-- Trail braking (B04): still braking (over `minBrake`) while turning in (steering wheel past
-- `minSteerDeg`) for at least `minSeconds` between two gates (default the first two: the braking
-- marker and the apex).
-- rule: {type = 'trail_braked', fromGate = 1, toGate = 2, minSeconds = 0.4, minBrake = 0.1, minSteerDeg = 20}
function E.trail_braked(rule, samples, ctx)
  local gates, err = gateList(ctx)
  if not gates then return false, err end
  local from, to = rule.fromGate or 1, rule.toGate or 2
  local passes = Gates.passes(gates, samples)
  if not (passes[from] and passes[from].reached) then return false, string.format('Gate %d not reached', from) end
  local t0, t1 = passes[from].t, passes[to] and passes[to].reached and passes[to].t or math.huge
  local minBrake, minSteer, need = rule.minBrake or 0.1, rule.minSteerDeg or 20, rule.minSeconds or 0.4
  local overlap, prev = 0, nil
  for _, s in ipairs(samples) do
    if s.t >= t0 and s.t <= t1 then
      if prev and (s.brk or 0) > minBrake and math.abs(s.steer or 0) > minSteer then overlap = overlap + (s.t - prev.t) end
      prev = s
    end
  end
  if overlap >= need then return true, string.format('Trail-braked %.1f s into the turn', overlap) end
  if overlap > 0 then
    return false, string.format('Only %.1f s of braking while turning in (target %.1f s): carry the brake into the corner', overlap, need)
  end
  return false, 'No braking while turning in: keep some brake on as you steer into the corner'
end

-- Brake fully released by a gate (B04: the apex) and kept off to the run's end.
-- rule: {type = 'brake_off_by_gate', gate = 2, maxBrake = 0.05}
function E.brake_off_by_gate(rule, samples, ctx)
  local gates, err = gateList(ctx)
  if not gates then return false, err end
  local g = rule.gate or 2
  g = g < 0 and #gates + 1 + g or g
  local passes = Gates.passes(gates, samples)
  if not (passes[g] and passes[g].reached) then return false, string.format('Gate %d not reached', g) end
  local tg, maxBrake, worst, lastOn = passes[g].t, rule.maxBrake or 0.05, 0, nil
  for _, s in ipairs(samples) do
    local b = s.brk or 0
    if s.t >= tg and (s.air or 0) > 2 and b > worst then worst = b end
    if s.t < tg and b > maxBrake then lastOn = s.t end
  end
  if worst > maxBrake then
    return false, string.format('Still braking at the apex (%.0f%%): release before you reach it', worst * 100)
  end
  if lastOn then return true, string.format('Brake off %.1f s before the apex', tg - lastOn) end
  return true, 'Brake off at the apex'
end

-- A stable exit (A08): between two gates (default the last two) the steering doesn't swing back
-- and forth. Unwinding the lock once is fine; each reversal of more than `minSwingDeg` degrees of
-- steering wheel is a correction (`steer` is the wheel angle in degrees, electrics.steering).
-- `after` names where the window starts in the text (default 'the exit gate').
-- rule: {type = 'steady_exit', fromGate = -2, toGate = -1, maxCorrections = 1, minSwingDeg = 10, after = 'the crest'}
function E.steady_exit(rule, samples, ctx)
  local gates, err = gateList(ctx)
  if not gates then return false, err end
  local function index(i, default) i = i or default; return i < 0 and #gates + 1 + i or i end
  local from, to = index(rule.fromGate, -2), index(rule.toGate, -1)
  local passes = Gates.passes(gates, samples)
  if not (passes[from] and passes[from].reached) then return false, string.format('Gate %d not reached', from) end
  local t0, t1 = passes[from].t, passes[to] and passes[to].reached and passes[to].t or math.huge
  local swing, max = rule.minSwingDeg or 10, rule.maxCorrections or 1
  local ext, dir, corrections = nil, 0, 0
  for _, s in ipairs(samples) do
    if s.t >= t0 and s.t <= t1 and s.steer then
      local v = s.steer
      if not ext then
        ext = v
      elseif dir == 0 then
        if math.abs(v - ext) >= swing then dir, ext = (v > ext) and 1 or -1, v end
      elseif dir == 1 then
        if v > ext then ext = v elseif ext - v >= swing then corrections, dir, ext = corrections + 1, -1, v end
      else
        if v < ext then ext = v elseif v - ext >= swing then corrections, dir, ext = corrections + 1, 1, v end
      end
    end
  end
  if not ext then return false, 'No steering data after ' .. (rule.after or 'the exit gate') end
  local text = corrections == 0 and 'Steady exit: no steering corrections'
    or string.format('%d steering correction%s after %s (limit %d)', corrections, corrections == 1 and '' or 's',
      rule.after or 'the exit gate', max)
  return corrections <= max, text
end

-- Circles (B05): laps, holding the line, throttle and brake together ---------------------

-- Laps driven round the course's circle, the way it is meant to be driven.
-- rule: {type = 'circle_laps', laps = 2}; ctx.course.circle = {x, y, radiusM, turn, laps}
function E.circle_laps(rule, samples, ctx)
  local course = courseOf(ctx, 'circle')
  if not course then return false, 'This drill has no circle laid out' end
  local circle, swept = course.circle, 0
  for i = 2, #samples do
    local a, b = samples[i - 1], samples[i]
    if a.x and b.x then swept = swept + Layout.circleSweep(circle, a, b) end
  end
  local need, laps = rule.laps or circle.laps or 1, swept / (2 * math.pi)
  local way = circle.turn == 'right' and 'clockwise' or 'anticlockwise'
  if laps >= need - 0.02 then return true, string.format('%d lap%s %s', need, need == 1 and '' or 's', way) end
  if laps < 0 then return false, string.format('Went round the wrong way: drive it %s', way) end
  return false, string.format('Only %.1f of %d laps', laps, need)
end

-- Holds the circle's line: the car stays within `widthM` / 2 of it, allowing a moment outside
-- (`maxSeconds`). The text gives the furthest it ran off the line.
-- rule: {type = 'circle_corridor', widthM = 6, maxSeconds = 0.3}
function E.circle_corridor(rule, samples, ctx)
  local course = courseOf(ctx, 'circle')
  if not course then return false, 'This drill has no circle laid out' end
  local circle, half, allow = course.circle, rule.widthM / 2, rule.maxSeconds or 0.3
  local worst, worstOff, n, outT, outMax, longest, prev = 0, 0, 0, 0, 0, 0, nil
  for _, s in ipairs(samples) do
    if s.x then
      local off = Layout.circleOffset(circle, s.x, s.y)
      n = n + 1
      if math.abs(off) > math.abs(worstOff) then worstOff = off end
      if math.abs(off) > half then
        if prev then outT = outT + (s.t - prev.t) end
        if math.abs(off) > math.abs(outMax) then outMax = off end
        if outT > longest then longest, worst = outT, outMax end
      else
        outT, outMax = 0, 0
      end
      prev = s
    end
  end
  if n == 0 then return false, 'No position data for this run' end
  if longest > allow then
    return false, string.format('Ran %.2f m %s the line (corridor ±%g m)', math.abs(worst),
      worst > 0 and 'wide of' or 'inside', half)
  end
  return true, string.format('Held the line: %.1f m off at most (corridor ±%g m)', math.abs(worstOff), half)
end

-- Throttle stays on: from the first moment at `fromKmh` (pulling away and changing up before then
-- is free) to the end of the run, it never drops under `minThrottle` for longer than `maxGapSeconds`.
-- rule: {type = 'throttle_held', maxGapSeconds = 0.3, minThrottle = 0.05, fromKmh = 0}
function E.throttle_held(rule, samples)
  local min, allow, from = rule.minThrottle or 0.05, rule.maxGapSeconds or 0.3, (rule.fromKmh or 0) / KMH
  local started, gap, longest, prev = false, 0, 0, nil
  for _, s in ipairs(samples) do
    local on = (s.thr or 0) >= min
    if on and (s.air or 0) >= from then started = true end
    if on then
      gap = 0
    elseif started and prev then
      gap = gap + (s.t - prev.t)
      longest = math.max(longest, gap)
    end
    prev = s
  end
  if not started then
    return false, from > 0 and string.format('Never on the throttle at %d km/h', rule.fromKmh) or 'Never on the throttle'
  end
  if longest > allow then
    return false, string.format('Off the throttle for %.1f s (limit %g s): keep your right foot on', longest, allow)
  end
  if longest > 0 then return true, string.format('Throttle held (longest lift %.1f s)', longest) end
  return true, 'Throttle held all the way round'
end

-- Left-foot braking: at least `minCount` brake applications made with the throttle still on,
-- each held `minSeconds` or longer.
-- rule: {type = 'left_foot_brakes', minCount = 3, minSeconds = 0.2, minBrake = 0.05, minThrottle = 0.05}
function E.left_foot_brakes(rule, samples)
  local minBrake, minThr = rule.minBrake or 0.05, rule.minThrottle or 0.05
  local need, hold = rule.minCount or 3, rule.minSeconds or 0.2
  local count, on, prev, brakedOff = 0, 0, nil, 0
  local function close() if on >= hold then count = count + 1 end; on = 0 end
  for _, s in ipairs(samples) do
    local brk = (s.brk or 0) > minBrake
    if brk and (s.thr or 0) >= minThr then
      if prev then on = on + (s.t - prev.t) end
    else
      if brk and prev then brakedOff = brakedOff + (s.t - prev.t) end
      close()
    end
    prev = s
  end
  close()
  local text = string.format('%d brake dab%s on the throttle (target %d+)', count, count == 1 and '' or 's', need)
  if count >= need then return true, text end
  if brakedOff > hold then return false, text .. ': you lifted to brake' end
  return false, text .. ': dab it to tighten the line'
end

-- Oversteer (B07) ------------------------------------------------------------------

-- The window between two gates (negative = from the last), as sample times: t0, t1 or nil, error.
local function gateWindow(ctx, samples, fromGate, toGate)
  local gates, err = gateList(ctx)
  if not gates then return nil, err end
  local function index(i) return i < 0 and #gates + 1 + i or i end
  local from, to = index(fromGate), index(toGate)
  local passes = Gates.passes(gates, samples)
  if not (passes[from] and passes[from].reached) then return nil, string.format('Gate %d not reached', from) end
  return passes[from].t, passes[to] and passes[to].reached and passes[to].t or math.huge
end
R.gateWindow = gateWindow

-- The rear stepped out: between two gates (default the first and the last) the car's slip angle
-- with the rear out (R.signedSlipDeg, the drill's `turn`) reaches `minSlipDeg`. Normal cornering at
-- the limit on dirt reads about 5-7 degrees in the Covet Gravel Rally (0.39.4).
-- `hint` is the coaching when it doesn't (default: lift or brake harder as you turn in).
-- rule: {type = 'rear_slide', minSlipDeg = 8, turn = 'left', fromGate = 1, toGate = -1, hint = '...'}
function E.rear_slide(rule, samples, ctx)
  local t0, t1 = gateWindow(ctx, samples, rule.fromGate or 1, rule.toGate or -1)
  if not t0 then return false, t1 end
  local need, worst = rule.minSlipDeg or 8, 0
  for _, s in ipairs(samples) do
    if s.t >= t0 and s.t <= t1 and (s.gear or 0) >= 0 then
      local slip = R.signedSlipDeg(s, 3, rule.turn or 'left')
      if slip and slip > worst then worst = slip end
    end
  end
  if worst >= need then return true, string.format('Rear stepped out %.1f° (target %g°+)', worst, need) end
  return false, string.format('The rear only stepped out %.1f° (target %g°): %s', worst, need,
    rule.hint or 'lift or brake harder as you turn in')
end

-- Settled by a gate (B07: the end of the exit lane): there the slide is over (slip angle within
-- `maxSlipDeg`) and the countersteer unwound (steering wheel within `maxSteerDeg` of straight).
-- rule: {type = 'settled_by_gate', gate = -1, maxSlipDeg = 4, maxSteerDeg = 45}
function E.settled_by_gate(rule, samples, ctx)
  local gates, err = gateList(ctx)
  if not gates then return false, err end
  local g = rule.gate or -1
  g = g < 0 and #gates + 1 + g or g
  local pass = Gates.passes(gates, samples)[g]
  if not (pass and pass.reached) then return false, string.format('Gate %d not reached', g) end
  local at
  for _, s in ipairs(samples) do
    if s.t >= pass.t then at = s; break end
  end
  if not at then return false, 'No data at the gate' end
  local slip, steer = R.slipDeg(at, 1) or 0, math.abs(at.steer or 0)
  local maxSlip, maxSteer = rule.maxSlipDeg or 4, rule.maxSteerDeg or 45
  local name = gates[g].label and gates[g].label:lower() or ('gate ' .. g)
  if slip > maxSlip then return false, string.format('Still sliding at the %s (%.0f°)', name, slip) end
  if steer > maxSteer then
    return false, string.format('Steering still %.0f° at the %s: unwind the countersteer sooner', steer, name)
  end
  return true, string.format('Settled by the %s (slip %.0f°, steering %.0f°)', name, slip, steer)
end

-- A Scandinavian flick (C08): between two gates the steering wheel goes at least `awayDeg` away from
-- the `turn`, then at least `intoDeg` into it within `maxSeconds` (`steer` is the wheel angle in
-- degrees, positive to the left).
-- rule: {type = 'flick', fromGate = 1, toGate = 2, turn = 'left', awayDeg = 30, intoDeg = 60, maxSeconds = 1.5}
function E.flick(rule, samples, ctx)
  local t0, t1 = gateWindow(ctx, samples, rule.fromGate or 1, rule.toGate or 2)
  if not t0 then return false, t1 end
  local into = rule.turn == 'right' and -1 or 1
  local away, need, within = rule.awayDeg or 30, rule.intoDeg or 60, rule.maxSeconds or 1.5
  local best, bestT, turned = 0, nil, nil
  for _, s in ipairs(samples) do
    local v = (s.steer or 0) * into -- positive: into the turn
    if s.t >= t0 and s.t <= t1 and -v > best then best, bestT, turned = -v, s.t, nil end
    if bestT and not turned and s.t > bestT and v >= need then turned = s.t end
  end
  if best < away then
    return false, string.format('No flick: steer at least %g° away from the corner first (%.0f° seen)', away, best)
  end
  if not turned then return false, string.format('Flicked %.0f° away but never turned in past %g°', best, need) end
  local dt = turned - bestT
  if dt > within then
    return false, string.format('Flicked %.0f° away, turned in %.1f s later (target %g s): make it one movement', best, dt, within)
  end
  return true, string.format('Flicked %.0f° away, then into the turn %.1f s later', best, dt)
end

-- Back on the throttle (E02): between two gates (default the apex and the exit) the throttle is at
-- `minThrottle` or more for at least `minSeconds` in total, driving the front out of the corner.
-- rule: {type = 'throttle_on_between', fromGate = 2, toGate = 3, minThrottle = 0.5, minSeconds = 0.5}
function E.throttle_on_between(rule, samples, ctx)
  local t0, t1 = gateWindow(ctx, samples, rule.fromGate or 2, rule.toGate or 3)
  if not t0 then return false, t1 end
  local min, need = rule.minThrottle or 0.5, rule.minSeconds or 0.5
  local on, peak, prev = 0, 0, nil
  for _, s in ipairs(samples) do
    if s.t >= t0 and s.t <= t1 then
      local thr = s.thr or 0
      peak = math.max(peak, thr)
      if prev and thr >= min then on = on + (s.t - prev.t) end
      prev = s
    end
  end
  if on >= need then
    return true, string.format('Back on the throttle for %.1f s before the exit', on)
  end
  return false, string.format('Only %.1f s on the throttle after the apex (peak %.0f%%): drive the front out', on, peak * 100)
end

-- Limping on a flat (F06): from `graceSeconds` after a tyre goes flat (telemetry `flat`, the count of flat
-- tyres) to the end of the run, never faster than `maxKmh`.
-- rule: {type = 'limp_speed', maxKmh = 35, graceSeconds = 4}
function E.limp_speed(rule, samples)
  local t0
  for _, s in ipairs(samples) do
    if (s.flat or 0) > 0 then t0 = s.t; break end
  end
  if not t0 then return false, 'No tyre went flat on this run' end
  local from, peak = t0 + (rule.graceSeconds or 4), 0
  for _, s in ipairs(samples) do
    if s.t >= from then peak = math.max(peak, (s.air or 0) * KMH) end
  end
  if peak <= rule.maxKmh then
    return true, string.format('Limped at up to %.0f km/h on the flat (limit %g km/h)', peak, rule.maxKmh)
  end
  return false, string.format('%.0f km/h on the flat (limit %g km/h): slow right down when a tyre goes', peak, rule.maxKmh)
end

-- Airtime (E05, E06): the longest stretch with all four wheels off the ground (each wheel's
-- downforce under `minForce`, telemetry `w[].f`) is between `minSeconds` and `maxSeconds`.
-- rule: {type = 'airtime', minSeconds = 0, maxSeconds = 0.15, minForce = 50}
function E.airtime(rule, samples)
  local minF, longest, since, seen = rule.minForce or 50, 0, nil, false
  for _, s in ipairs(samples) do
    local w = s.w or {}
    if #w > 0 then
      seen = true
      local off = 0
      for _, wheel in ipairs(w) do if (wheel.f or 0) < minF then off = off + 1 end end
      if off == #w then
        since = since or s.t
        longest = math.max(longest, s.t - since)
      else
        since = nil
      end
    end
  end
  if not seen then return false, 'No wheel data for this run' end
  local lo, hi = rule.minSeconds or 0, rule.maxSeconds or math.huge
  if longest < lo then
    return false, string.format('Only %.2f s in the air (target %g s+)', longest, lo)
  end
  if longest > hi then
    return false, string.format('Wheels off the ground for %.2f s (limit %g s): ease off before the crest', longest, hi)
  end
  if longest == 0 then return true, 'All four wheels stayed on the ground' end
  return true, string.format('%.2f s in the air (limit %g s)', longest, hi)
end

-- Understeer (B06) -----------------------------------------------------------------

-- The front pushed wide: between two gates the car runs outside the course circle's line by `minM`
-- to `maxM` (a mild, safe push, not a trip off the circle).
-- rule: {type = 'ran_wide', minM = 1, maxM = 5, fromGate = 1, toGate = -1}
function E.ran_wide(rule, samples, ctx)
  local course = courseOf(ctx, 'circle')
  if not course then return false, 'This drill has no circle laid out' end
  local t0, t1 = gateWindow(ctx, samples, rule.fromGate or 1, rule.toGate or -1)
  if not t0 then return false, t1 end
  local wide, minM, maxM = 0, rule.minM or 1, rule.maxM or 5
  for _, s in ipairs(samples) do
    if s.x and s.t >= t0 and s.t <= t1 then wide = math.max(wide, Layout.circleOffset(course.circle, s.x, s.y)) end
  end
  if wide < minM then
    return false, string.format('Only %.1f m wide (target %g m+): carry more speed in to make the front push', wide, minM)
  end
  if wide > maxM then return false, string.format('Ran %.1f m wide (limit %g m): too fast in, the push got away', wide, maxM) end
  return true, string.format('Front pushed %.1f m wide (target %g-%g m)', wide, minM, maxM)
end

-- Back on the course circle's line by a gate: where the car crosses it, it is within `maxM` of the line.
-- rule: {type = 'back_on_line_by_gate', gate = -1, maxM = 1.5}
function E.back_on_line_by_gate(rule, samples, ctx)
  local course = courseOf(ctx, 'circle')
  if not course then return false, 'This drill has no circle laid out' end
  local gates, err = gateList(ctx)
  if not gates then return false, err end
  local g = rule.gate or -1
  g = g < 0 and #gates + 1 + g or g
  local pass = Gates.passes(gates, samples)[g]
  if not (pass and pass.reached) then return false, string.format('Gate %d not reached', g) end
  local at
  for _, s in ipairs(samples) do
    if s.x and s.t >= pass.t then at = s; break end
  end
  if not at then return false, 'No data at the gate' end
  local off, maxM = Layout.circleOffset(course.circle, at.x, at.y), rule.maxM or 1.5
  local name = gates[g].label and gates[g].label:lower() or ('gate ' .. g)
  if math.abs(off) <= maxM then
    return true, string.format('Back on the line by the %s (%.1f m off, target %g m)', name, math.abs(off), maxM)
  end
  return false, string.format('Still %.1f m %s the line at the %s (target %g m): ease off sooner', math.abs(off),
    off > 0 and 'wide of' or 'inside', name, maxM)
end

R.evaluators = E

-- Rule types and their required parameters. tools/dev.py validate reads this table and
-- the name lists below from this file, so keep each entry here on one line: name = {'param', ...},
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
  cones_passed = {},
  markers_clear = {},
  park_in_box = {},
  no_reverse = {},
  max_time = {'maxSeconds'},
  time_to_speed = {'kmh', 'maxSeconds'},
  progressive_downshifts = {'toGear'},
  no_over_rev = {'maxRpm'},
  steady_exit = {},
  trail_braked = {},
  brake_off_by_gate = {},
  circle_laps = {},
  circle_corridor = {'widthM'},
  throttle_held = {},
  left_foot_brakes = {},
  rear_slide = {},
  settled_by_gate = {},
  ran_wide = {},
  flick = {},
  handbrake_pulls = {},
  throttle_on_between = {},
  airtime = {},
  limp_speed = {'maxKmh'},
  back_on_line_by_gate = {},
}

-- Rule types that need marked gates (assessment.gates, or gates in assessment.course).
R.GATE_RULES = {'gates_passed', 'speed_at_gates', 'no_brake_between_gates', 'steady_exit', 'trail_braked',
  'brake_off_by_gate', 'rear_slide', 'settled_by_gate', 'ran_wide', 'back_on_line_by_gate', 'flick',
  'throttle_on_between'}
-- Rule types that need an authored course (assessment.course).
R.COURSE_RULES = {'cones_passed', 'markers_clear', 'park_in_box', 'circle_laps', 'circle_corridor', 'ran_wide',
  'back_on_line_by_gate'}
-- Medal tiers above a pass (bronze), in order (assessment.tiers).
R.TIERS = {'silver', 'gold'}

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

-- A tier's rules: the drill's rules, with each tier rule replacing the drill rule of the same
-- type (a smaller box) or adding to them (a time target).
local function tierRules(base, extra)
  local out, replaced = {}, {}
  for _, r in ipairs(extra or {}) do replaced[r.type] = r end
  for _, r in ipairs(base or {}) do out[#out + 1] = replaced[r.type] or r end
  for _, r in ipairs(extra or {}) do
    local found = false
    for _, b in ipairs(base or {}) do if b.type == r.type then found = true end end
    if not found then out[#out + 1] = r end
  end
  return out
end

-- Grade a run against a drill's assessment, medals included: a pass is bronze; each tier
-- in assessment.tiers ({{name = 'silver', rules = {...}}, {name = 'gold', ...}}) is earned
-- when its rules pass too. Returns evaluate()'s result plus, for drills with tiers, `tier`
-- ('bronze' | 'silver' | 'gold'; nil on a miss) and `nextTier` = {name, text} (what the next
-- medal still needs).
function R.grade(a, record, ctx)
  local result = R.evaluate(a.rules, record, ctx)
  if not (result.passed and a.tiers and #a.tiers > 0) then return result end
  result.tier = 'bronze'
  for _, t in ipairs(a.tiers or {}) do
    local rules = {}
    for i, r in ipairs(t.rules or {}) do
      rules[i] = setmetatable({label = r.label or (t.name .. ' box')}, {__index = r})
    end
    local res = R.evaluate(tierRules(a.rules, rules), record, ctx)
    if not res.passed then
      for _, c in ipairs(res.checks) do
        if not c.ok then result.nextTier = {name = t.name, text = c.text}; break end
      end
      break
    end
    result.tier = t.name
  end
  return result
end

return R
