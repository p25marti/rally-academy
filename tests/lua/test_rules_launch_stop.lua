-- Unit tests for the A02 (launch), A05 (stop line) and B02 (lockup recovery) rules,
-- on synthetic runs.
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

-- Driving north from y = 0. phases: list of {seconds, accel (m/s2), opts}; opts per phase:
-- brk, thr, gear, eng, lockFront (front wheels at 0), spinFront (front wheels at air + 6 m/s).
local function run(phases)
  local samples, t, v, y = {}, 0, 0, 0
  for _, ph in ipairs(phases) do
    local o = ph[3] or {}
    local n = math.floor(ph[1] / DT + 0.5)
    for _ = 1, n do
      v = math.max(0, v + ph[2] * DT)
      y = y + v * DT
      t = t + DT
      local front = o.lockFront and 0 or (o.spinFront and v + 6 or v)
      samples[#samples + 1] = {t = t, x = 0, y = y, z = 0, air = v, brk = o.brk or 0, thr = o.thr or 0,
        gear = o.gear or 1, eng = o.eng == nil and 1 or o.eng,
        w = {{n = 'FL', s = front}, {n = 'FR', s = front}, {n = 'RL', s = v}, {n = 'RR', s = v}}}
    end
  end
  return {samples = samples, runStartT = samples[1].t}
end

local function check(rules, rec, ctx) return R.evaluate(rules, rec, ctx).checks[1] end

-- A05: stop line ---------------------------------------------------------------

local LINE = {{type = 'stop_before_line', minM = 0, maxM = 2}}
local function lineAt(y) return {zone = {pos = {x = 0, y = y}, dir = {x = 0, y = 1}}} end
local function stopRun() return run({{4, 3, {thr = 1}}, {3, -4, {brk = 0.6}}}) end
local function stopY(rec) return rec.samples[#rec.samples].y end

function T.stopping_just_before_the_line_passes()
  local rec = stopRun()
  local c = check(LINE, rec, lineAt(stopY(rec) + 1.2))
  eq(c.ok, true, 'passes')
  eq(c.text, 'Stopped 1.2 m before the line (target 0-2 m before it)', 'text')
end

function T.stopping_past_or_well_short_of_the_line_fails()
  local rec = stopRun()
  local past = check(LINE, rec, lineAt(stopY(rec) - 0.5))
  eq(past.ok, false, 'past')
  has(past.text, 'Stopped 0.5 m past the line')
  local short = check(LINE, rec, lineAt(stopY(rec) + 3.4))
  eq(short.ok, false, 'short')
  has(short.text, 'Stopped 3.4 m before the line')
end

function T.stop_line_not_marked_says_how()
  has(check(LINE, stopRun(), {}).text, 'Mark stop line')
end

-- B02: lockup recovery -------------------------------------------------------------

local B02 = {{type = 'lockup_recovered', minSeconds = 0.2, maxSeconds = 1.0}}

function T.short_provoked_lock_then_release_passes()
  local rec = run({{5, 3.5, {thr = 1}}, {0.6, -9, {brk = 1, lockFront = true}}, {2, -5, {brk = 0.5}}})
  local c = check(B02, rec)
  eq(c.ok, true, 'recovered: ' .. c.text)
  has(c.text, 'Locked 0.6 s')
end

function T.no_lock_or_a_long_lock_fails()
  local none = check(B02, run({{5, 3.5, {thr = 1}}, {3, -5, {brk = 0.5}}}))
  eq(none.ok, false, 'never locked')
  has(none.text, 'brake harder to provoke one')
  local long = check(B02, run({{5, 3.5, {thr = 1}}, {2, -8, {brk = 1, lockFront = true}}}))
  eq(long.ok, false, 'held the lock')
  has(long.text, 'stayed locked')
end

-- A02: launch ----------------------------------------------------------------------

function T.clean_launch_and_shift_passes_a02_rules()
  local rec = run({{4, 3, {thr = 1, gear = 1}}, {0.3, 0, {gear = 0}}, {3, 1.5, {thr = 0.8, gear = 2}}, {4, -3, {brk = 0.4, gear = 2}}})
  local res = R.evaluate({{type = 'gear_reached', gear = 2}, {type = 'no_stall'}, {type = 'clean_shifts'},
    {type = 'no_sustained_wheelspin', maxSeconds = 1}}, rec)
  eq(res.passed, true, 'clean')
  eq(res.checks[1].text, 'Shifted up to gear 2', 'shift')
  eq(res.checks[3].text, 'Clean shifts', 'neutral blip during a shift is fine')
end

function T.stall_is_caught_even_after_a_reset_re_idle()
  -- engine off for the first samples (re-idling after Retry), running, then stalls
  local rec = run({{0.3, 0, {eng = 0, gear = 0}}, {2, 2, {thr = 1}}, {1, -2, {eng = 0}}})
  local c = check({{type = 'no_stall'}}, rec)
  eq(c.ok, false, 'stalled')
  has(c.text, 'Stalled at')
  local fine = check({{type = 'no_stall'}}, run({{0.3, 0, {eng = 0, gear = 0}}, {2, 2, {thr = 1}}}))
  eq(fine.ok, true, 'engine off before it ever ran is not a stall')
end

function T.hanging_in_neutral_is_a_missed_shift()
  local rec = run({{4, 3, {thr = 1, gear = 1}}, {1.5, -0.3, {gear = 0}}, {2, 1, {thr = 0.6, gear = 2}}})
  local c = check({{type = 'clean_shifts'}}, rec)
  eq(c.ok, false, 'missed')
  has(c.text, 'Missed a shift: 1.5 s in neutral')
end

function T.long_wheelspin_fails_and_names_the_wheel()
  local c = check({{type = 'no_sustained_wheelspin', maxSeconds = 1}}, run({{2, 2, {thr = 1, spinFront = true}}}))
  eq(c.ok, false, 'spun 2 s')
  has(c.text, 'wheel spun for 2.0 s')
end

function T.never_reaching_second_fails()
  local c = check({{type = 'gear_reached', gear = 2}}, run({{4, 2, {thr = 1, gear = 1}}}))
  eq(c.ok, false, 'stayed in first')
  eq(c.text, 'Never reached gear 2 (highest 1)', 'text')
end

function T.time_to_speed_times_the_launch_from_moving_off()
  -- 4 m/s2 for 5 s: 40 km/h (11.1 m/s) after about 2.8 s
  local rule = {type = 'time_to_speed', kmh = 40, maxSeconds = 3.5}
  local c = check({rule}, run({{5, 4, {thr = 1}}}))
  eq(c.ok, true, 'quick launch')
  has(c.text, '0-40 km/h in 2.8 s (target 3.5 s)')
  local slow = check({rule}, run({{8, 2, {thr = 0.5}}}))
  eq(slow.ok, false, 'slow launch')
  has(slow.text, '0-40 km/h in 5.5 s')
  local never = check({rule}, run({{3, 2, {thr = 0.5}}}))
  eq(never.text, 'Never reached 40 km/h', 'never got there')
end

local function gears(list) -- {gear, seconds} pairs at 10 m/s
  local samples, t = {}, 0
  for _, g in ipairs(list) do
    for _ = 1, math.floor(g[2] / DT + 0.5) do
      t = t + DT
      samples[#samples + 1] = {t = t, x = 0, y = t * 10, air = 10, gear = g[1], rpm = g[3] or 3000, w = {}}
    end
  end
  return {samples = samples, runStartT = samples[1].t}
end

function T.downshifts_one_gear_at_a_time_pass()
  local c = check({{type = 'progressive_downshifts', toGear = 2}},
    gears({{1, 1}, {2, 1}, {3, 2}, {0, 0.3}, {2, 1}, {1, 1}}))
  eq(c.ok, true, c.text)
  eq(c.text, 'Downshifted 3→2', 'text')
end

function T.skipping_a_gear_on_the_way_down_fails()
  local c = check({{type = 'progressive_downshifts', toGear = 2}}, gears({{1, 1}, {2, 1}, {3, 1}, {4, 2}, {2, 1}}))
  eq(c.ok, false, 'skipped 3rd')
  eq(c.text, 'Skipped from 4th to 2nd: go down one gear at a time', 'text')
end

function T.staying_in_a_high_gear_or_never_climbing_fails()
  local stay = check({{type = 'progressive_downshifts', toGear = 2}}, gears({{1, 1}, {2, 1}, {3, 3}}))
  eq(stay.text, 'Stayed in 3rd: downshift to 2nd as you slow', 'stayed in 3rd')
  local low = check({{type = 'progressive_downshifts', toGear = 2}}, gears({{1, 1}, {2, 3}}))
  eq(low.text, 'Never above 2nd, so nothing to downshift', 'never above 2nd')
end

function T.over_rev_names_the_gear_and_speed()
  local c = check({{type = 'no_over_rev', maxRpm = 6700}}, gears({{3, 1, 5000}, {2, 0.2, 7300}, {2, 1, 5000}}))
  eq(c.ok, false, 'over-revved')
  has(c.text, 'Over-revved to 7300 rpm in 2nd at 36 km/h (limit 6700)')
  local fine = check({{type = 'no_over_rev', maxRpm = 6700}}, gears({{3, 1, 6450}}))
  eq(fine.text, 'Peak 6450 rpm (limit 6700)', 'under the limit')
end

return T
