-- Unit tests for the grading rules (pure; synthetic runs).
local R = require('ge/extensions/rallyAcademy/rules')
local T = {}

local function eq(actual, expected, msg)
  if actual ~= expected then
    error(('%s: expected %s, got %s'):format(msg or 'mismatch', tostring(expected), tostring(actual)), 2)
  end
end
local function has(text, needle)
  if not tostring(text):find(needle, 1, true) then error(('expected %q in %q'):format(needle, tostring(text)), 2) end
end

-- A straight run along +y at 30 Hz: accelerate to `kmh`, brake from `brakeAtY` with
-- deceleration `decel`, stop. lockFrom/lockFor lock both front wheels for a while.
local function run(opts)
  local dt, v, y, t, samples = 1 / 30, 0, 0, 0, {}
  local vmax = (opts.kmh or 70) / 3.6
  local braking, lockedT = false, 0
  while true do
    if not braking and y >= (opts.brakeAtY or 80) then braking = true end
    if braking then v = math.max(0, v - (opts.decel or 6) * dt) else v = math.min(vmax, v + 3 * dt) end
    y = y + v * dt
    t = t + dt
    local lock = braking and opts.lockFor and lockedT < opts.lockFor
    if lock then lockedT = lockedT + dt end
    local ws = lock and 0 or v
    samples[#samples + 1] = {t = t, air = v, brk = braking and 0.8 or 0, x = 0, y = y, z = 0,
      w = {{n = 'FL', s = ws}, {n = 'FR', s = ws}, {n = 'RL', s = v}, {n = 'RR', s = v}}}
    if braking and v == 0 then break end
    if t > 60 then error('runaway synthetic run') end
  end
  return {samples = samples, runStartT = samples[1].t}
end

local B01 = {
  {type = 'entry_speed', minKmh = 65},
  {type = 'stop_zone', lengthM = 5, widthM = 6},
  {type = 'no_sustained_lockup', maxSeconds = 0.5},
}

local function zoneAt(y) return {pos = {x = 0, y = y}, dir = {x = 0, y = 1}} end

local function stopY(rec) return rec.samples[#rec.samples].y end

function T.clean_stop_in_the_zone_passes()
  local rec = run({kmh = 70})
  local res = R.evaluate(B01, rec, {zone = zoneAt(stopY(rec) - 1)})
  eq(res.passed, true, 'passed')
  has(res.checks[1].text, 'Braked from 70 km/h')
  has(res.checks[2].text, 'Stopped in the zone (1.0 m past its centre)')
  eq(res.checks[3].text, 'No lockup', 'lockup text')
end

function T.overshoot_fails_with_distance_past_the_zone()
  local rec = run({kmh = 70})
  local res = R.evaluate(B01, rec, {zone = zoneAt(stopY(rec) - 6)})
  eq(res.passed, false, 'failed')
  has(res.checks[2].text, 'Stopped 3.5 m past the zone')
end

function T.stopping_short_fails_with_distance()
  local rec = run({kmh = 70})
  local res = R.evaluate(B01, rec, {zone = zoneAt(stopY(rec) + 4)})
  has(res.checks[2].text, 'Stopped 1.5 m short of the zone')
  eq(res.checks[2].ok, false, 'short is a fail')
end

function T.stopping_beside_the_zone_fails()
  local rec = run({kmh = 70})
  local zone = {pos = {x = 5, y = stopY(rec)}, dir = {x = 0, y = 1}}
  local res = R.evaluate(B01, rec, {zone = zone})
  has(res.checks[2].text, 'Stopped 2.0 m to the side of the zone')
end

function T.too_slow_an_approach_fails_entry_speed()
  local rec = run({kmh = 50})
  local res = R.evaluate(B01, rec, {zone = zoneAt(stopY(rec))})
  eq(res.checks[1].ok, false, 'entry speed failed')
  has(res.checks[1].text, 'Only 50 km/h before braking (target 65+)')
  eq(res.passed, false, 'whole run fails')
end

function T.sustained_lockup_fails_with_wheel_and_duration()
  local rec = run({kmh = 70, lockFor = 1.0})
  local res = R.evaluate(B01, rec, {zone = zoneAt(stopY(rec))})
  eq(res.checks[3].ok, false, 'lockup failed')
  has(res.checks[3].text, 'wheel locked for 1.0 s from 69 km/h (limit 0.5 s)') -- lock starts one braking step in
  has(res.checks[3].text, 'Front-')
end

function T.brief_lockup_is_allowed()
  local rec = run({kmh = 70, lockFor = 0.3})
  local res = R.evaluate(B01, rec, {zone = zoneAt(stopY(rec))})
  eq(res.checks[3].ok, true, 'brief lock ok')
  has(res.checks[3].text, 'No sustained lockup (longest 0.3 s)')
end

function T.lockup_while_not_braking_is_ignored()
  -- e.g. a wheel off the ground spinning down, or the settle after a Retry teleport
  local rec = run({kmh = 70})
  for i = 5, 40 do rec.samples[i].w[1].s = 0 end -- front-left reads 0 while accelerating
  local res = R.evaluate({{type = 'no_sustained_lockup', maxSeconds = 0.5}}, rec)
  eq(res.passed, true, 'not braking: not a lockup')
end

function T.samples_before_the_run_start_are_not_graded()
  local rec = run({kmh = 70})
  table.insert(rec.samples, 1, {t = rec.samples[1].t - 1, air = 30, brk = 1, x = 0, y = -50, z = 0,
    w = {{n = 'FL', s = 0}, {n = 'FR', s = 0}}})  -- Retry settling: fake locked wheels at 108 km/h
  rec.runStartT = rec.samples[2].t
  local res = R.evaluate(B01, rec, {zone = zoneAt(stopY(rec))})
  eq(res.passed, true, 'pre-run samples ignored')
end

function T.missing_zone_and_empty_runs_fail_with_a_reason()
  local rec = run({kmh = 70})
  local res = R.evaluate(B01, rec, {})
  has(res.checks[2].text, 'No stop zone marked')
  local empty = R.evaluate(B01, {samples = {}})
  eq(empty.passed, false, 'empty fails')
  has(empty.checks[1].text, 'No telemetry')
end

-- Seen in-game: right after Retry the brake reads 0.3 (idle hold) at standstill.
function T.idle_brake_at_the_start_does_not_count_as_braking()
  local rec = run({kmh = 70})
  for i = 1, 10 do rec.samples[i].brk = 0.3 end
  local res = R.evaluate({{type = 'entry_speed', minKmh = 65}}, rec)
  eq(res.passed, true, 'entry speed from the peak, not the first brake reading')
end

function T.unknown_rule_types_fail_loudly()
  local res = R.evaluate({{type = 'teleport_ok'}}, run({}), {})
  eq(res.passed, false, 'unknown fails')
  has(res.checks[1].text, 'Unknown rule type: teleport_ok')
end

return T
