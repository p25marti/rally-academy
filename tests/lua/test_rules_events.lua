-- Unit tests for the car-event rules: contact, spin, leaving the road, rollover,
-- handbrake and puncture (synthetic runs).
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

local DT = 1 / 30

-- 4 s north at 15 m/s (54 km/h). `at(i, s)` edits sample i (1..120) in place.
local function run(at)
  local samples = {}
  for i = 1, 120 do
    local s = {t = i * DT, x = 0, y = i * 0.5, z = 0, air = 15, brk = 0, thr = 0.5, hb = 0,
      hx = 0, hy = 1, vx = 0, vy = 15, uz = 1, dmg = 0, flat = 0,
      w = {{n = 'FL', s = 15, m = 19}, {n = 'FR', s = 15, m = 19}, {n = 'RL', s = 15, m = 10}, {n = 'RR', s = 15, m = 10}}}
    if at then at(i, s) end
    samples[i] = s
  end
  return {samples = samples, runStartT = samples[1].t}
end

local function check(rule, rec) return R.evaluate({rule}, rec).checks[1] end

function T.clean_run_passes_every_event_rule()
  local res = R.evaluate({{type = 'no_damage'}, {type = 'no_spin'},
    {type = 'on_surface', surfaces = {'ASPHALT', 'GRAVEL'}}, {type = 'no_rollover'},
    {type = 'no_handbrake'}, {type = 'no_puncture'}}, run())
  eq(res.passed, true, 'clean')
  eq(res.checks[2].text, 'No spin (largest slide 0°)', 'spin text')
  eq(res.checks[3].text, 'Stayed on the road', 'surface text')
end

function T.damage_jump_is_contact_with_the_speed_it_happened_at()
  local c = check({type = 'no_damage', maxDamage = 50}, run(function(i, s)
    if i >= 60 then s.dmg = 400 end
  end))
  eq(c.ok, false, 'hit')
  eq(c.text, 'Hit something at 54 km/h (damage +400)', 'text')
  eq(check({type = 'no_damage', maxDamage = 50}, run(function(i, s) if i >= 60 then s.dmg = 30 end end)).ok, true,
    'a scrape under the limit')
end

function T.damage_counts_from_the_run_start_not_from_zero()
  eq(check({type = 'no_damage'}, run(function(_, s) s.dmg = 900 end)).ok, true, 'already-damaged car')
end

function T.sliding_sideways_for_long_is_a_spin()
  -- heading swings to east-southeast while still travelling north: ~120 degrees of slide
  local c = check({type = 'no_spin'}, run(function(i, s)
    if i >= 50 and i < 70 then s.hx, s.hy = 0.87, -0.5 end
  end))
  eq(c.ok, false, 'spun')
  has(c.text, 'Spun at 54 km/h')
  local brief = check({type = 'no_spin'}, run(function(i, s)
    if i >= 50 and i < 55 then s.hx, s.hy = 0.87, -0.5 end
  end))
  eq(brief.ok, true, 'a 0.15 s flick is not a spin')
end

function T.slip_angle_is_measured_between_heading_and_travel()
  local slip = R.slipDeg({hx = 1, hy = 0, vx = 0, vy = 10})
  assert(math.abs(slip - 90) < 1e-6, 'sideways = 90, got ' .. slip)
  eq(R.slipDeg({hx = 0, hy = 1, vx = 0, vy = 0.2}), nil, 'too slow to tell')
end

function T.three_wheels_on_grass_for_a_second_is_leaving_the_road()
  local rule = {type = 'on_surface', surfaces = {'ASPHALT', 'GRAVEL'}, maxWheelsOff = 2, maxSeconds = 0.5}
  local c = check(rule, run(function(i, s)
    if i >= 40 and i < 80 then for k = 1, 3 do s.w[k].m = 20 end end
  end))
  eq(c.ok, false, 'off')
  eq(c.text, 'Left the road: 3 wheels on GRASS at 54 km/h', 'text')
  local two = check(rule, run(function(i, s)
    if i >= 40 and i < 80 then s.w[1].m, s.w[3].m = 20, 20 end
  end))
  eq(two.ok, true, 'two wheels on the verge is allowed')
  local airborne = check(rule, run(function(i, s)
    if i >= 40 and i < 80 then for k = 1, 4 do s.w[k].m = -1 end end
  end))
  eq(airborne.ok, true, 'wheels in the air are not off the road')
end

function T.tipping_past_seventy_degrees_is_a_rollover()
  local c = check({type = 'no_rollover'}, run(function(i, s) if i >= 90 then s.uz = 0.1 end end))
  eq(c.ok, false, 'rolled')
  has(c.text, 'Rolled over')
end

function T.handbrake_counts_only_while_moving()
  eq(check({type = 'no_handbrake'}, run(function(i, s) if i < 5 then s.hb, s.air = 1, 0 end end)).ok, true,
    'held at rest after a reset')
  local c = check({type = 'no_handbrake'}, run(function(i, s) if i == 60 then s.hb = 1 end end))
  eq(c.ok, false, 'pulled at speed')
  eq(c.text, 'Used the handbrake at 54 km/h', 'text')
end

function T.a_tyre_going_flat_is_a_puncture()
  local c = check({type = 'no_puncture'}, run(function(i, s) if i >= 70 then s.flat = 1 end end))
  eq(c.ok, false, 'flat')
  has(c.text, 'Punctured a tyre')
  eq(check({type = 'no_puncture'}, run(function(_, s) s.flat = 1 end)).ok, true, 'already flat at the start')
end

function T.reversing_is_not_a_spin()
  local c = check({type = 'no_spin'}, run(function(i, s)
    if i >= 50 then s.gear, s.vy = -1, -4 end -- backing up: travel opposite the heading
  end))
  eq(c.ok, true, 'reverse gear skipped')
end

function T.a_puncture_is_not_contact()
  local c = check({type = 'no_damage'}, run(function(i, s)
    if i >= 70 then s.flat = 1 end
    if i >= 71 then s.dmg = 1000 end -- deflating adds ~1000 damage, a sample after the flag (0.39.4)
  end))
  eq(c.ok, true, 'puncture damage ignored: ' .. c.text)
  local hit = check({type = 'no_damage'}, run(function(i, s)
    if i >= 70 then s.flat, s.dmg = 1, 1000 end
    if i >= 90 then s.dmg = 1600 end
  end))
  eq(hit.ok, false, 'a hit after the puncture still counts')
end

return T
