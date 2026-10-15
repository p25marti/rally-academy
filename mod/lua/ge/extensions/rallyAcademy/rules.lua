-- Grading rules: evaluate a drill's typed `assessment.rules` against a run record.
-- Pure Lua (no engine globals), so every rule is unit-tested against synthetic
-- and recorded runs. Each check returns a readable reason: the reason is the coaching.
--
-- Run record samples (runRecord.lua, telemetry.lua): t (sim s), air (m/s), brk (0..1),
-- x, y, z (m), w = {{n = 'FR', s = wheel speed m/s, m = surface id, f = downforce}, ...}
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

-- Longest continuous lockup of any wheel while braking.
-- A wheel counts as locked when it turns slower than `ratio` x the car's speed.
-- rule: {type = 'no_sustained_lockup', maxSeconds = 0.5, ratio = 0.3, minKmh = 7}
function E.no_sustained_lockup(rule, samples)
  local ratio, minAir = rule.ratio or 0.3, (rule.minKmh or 7) / KMH
  local streakStart, worst = {}, {t = 0}
  for i, s in ipairs(samples) do
    local nextT = samples[i + 1] and samples[i + 1].t or s.t
    for _, w in ipairs(s.w or {}) do
      local locked = (s.brk or 0) > 0.1 and (s.air or 0) > minAir and math.abs(w.s or 0) < ratio * s.air
      if locked then
        streakStart[w.n] = streakStart[w.n] or {t = s.t, air = s.air}
        local dur = nextT - streakStart[w.n].t
        if dur > worst.t then worst = {t = dur, wheel = w.n, air = streakStart[w.n].air} end
      else
        streakStart[w.n] = nil
      end
    end
  end
  local max = rule.maxSeconds or 0.5
  if worst.t > max then
    local name = (WHEEL_NAMES[worst.wheel] or tostring(worst.wheel)):gsub('^%l', string.upper) -- 1st return only
    return false, string.format('%s wheel locked for %.1f s from %.0f km/h (limit %.1f s)',
      name, worst.t, worst.air * KMH, max)
  end
  if worst.t > 0 then return true, string.format('No sustained lockup (longest %.1f s)', worst.t) end
  return true, 'No lockup'
end

R.evaluators = E

-- Rule types and their required parameters (mirrored by tools/dev.py validate).
R.TYPES = {
  entry_speed = {'minKmh'},
  stop_zone = {'lengthM', 'widthM'},
  no_sustained_lockup = {'maxSeconds'},
}

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
