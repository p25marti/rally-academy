-- Grading rules against runs recorded in-game (tests/fixtures/*.json, saved with
-- extensions.rallyAcademy.saveLastRun). Real BeamNG physics, not synthetic data:
-- if a rule change breaks these, check the change against the real runs first.
--
-- All recorded on 0.39.4, West Coast USA BMP start straight, Covet Student Driver, scripted
-- inputs (arcade gearbox):
-- B01: clean = eased threshold braking from 70 km/h into the zone; overshoot = same technique
--      braking 0.9 s later; lockup = full brake from 70 km/h.
-- A05: line marked 1 m beyond a calibration stop; clean = eased braking from 43 km/h;
--      late = braking 0.5 s later; lockup = full brake.
-- B02: from 62 km/h; recovered = full brake 0.6 s then eased; held = full brake to a stop;
--      nolock = gentle 0.25 brake.
-- A02: 0.6 throttle launch to 42 km/h (arcade shifts 1->2), eased stop.
local json = require('json')
local Rules = require('ge/extensions/rallyAcademy/rules')
local T = {}

local ROOT = arg and arg[1] or '.'

local function read(path)
  local f = assert(io.open(path, 'r'), 'missing ' .. path)
  local text = f:read('*a'); f:close()
  return json.decode(text)
end

local function fixture(name) return read(ROOT .. '/tests/fixtures/' .. name .. '.json') end

local function drillRules(id)
  for _, e in ipairs(read(ROOT .. '/mod/gameplay/rallyAcademy/exercises.json').exercises) do
    if e.id == id then return e.assessment.rules end
  end
end

local function grade(name, drill)
  local rec = fixture(name)
  return Rules.evaluate(drillRules(drill or 'B01'), rec, {zone = rec.meta.finish, gates = rec.meta.gates}), rec
end

local function check(res, ruleType)
  for _, c in ipairs(res.checks) do if c.type == ruleType then return c end end
end

local function has(text, needle)
  if not tostring(text):find(needle, 1, true) then error(('expected %q in %q'):format(needle, tostring(text)), 2) end
end

function T.b01_recorded_clean_stop_passes()
  local res = grade('b01_clean')
  assert(res.passed, 'clean run should pass: ' .. check(res, 'stop_zone').text .. ' / ' .. check(res, 'no_sustained_lockup').text)
  has(check(res, 'entry_speed').text, 'Braked from 7')
  has(check(res, 'stop_zone').text, 'Stopped in the zone')
end

function T.b01_recorded_overshoot_fails_past_the_zone()
  local res = grade('b01_overshoot')
  assert(not res.passed, 'overshoot should fail')
  local zone = check(res, 'stop_zone')
  assert(not zone.ok, 'zone check fails')
  has(zone.text, 'past the zone')
end

function T.b01_recorded_full_brake_fails_for_a_front_lockup()
  local res = grade('b01_lockup')
  local lock = check(res, 'no_sustained_lockup')
  assert(not lock.ok, 'lockup check fails')
  has(lock.text, 'Front-')
  local secs = tonumber(lock.text:match('locked for ([%d%.]+) s'))
  assert(secs and secs > 1.5, 'a long lock (recorded ~2 s), got ' .. lock.text)
end

-- The grade stored in the fixture is what the game showed; today's rules must agree.
function T.b01_rules_still_agree_with_the_in_game_verdicts()
  for _, name in ipairs({'b01_clean', 'b01_overshoot', 'b01_lockup'}) do
    local res, rec = grade(name)
    assert(rec.grade, name .. ' has no recorded grade')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
  end
end

function T.recorded_samples_have_the_fields_the_rules_need()
  local rec = fixture('b01_clean')
  local s = rec.samples[#rec.samples]
  for _, k in ipairs({'t', 'x', 'y', 'z', 'air', 'brk', 'thr', 'gear', 'w'}) do
    assert(s[k] ~= nil, 'sample field ' .. k)
  end
  assert(#s.w == 4 and s.w[1].n and s.w[1].s and s.w[1].m, 'four wheels with name, speed, surface')
  assert(rec.runStartT and rec.endT and rec.outcome == 'finished', 'run start/end and outcome')
end

-- A05, B02, A02: today's rules must agree with what the game showed for each recorded run.
function T.a05_b02_a02_rules_still_agree_with_the_in_game_verdicts()
  local runs = {a05_clean = 'A05', a05_late = 'A05', a05_lockup = 'A05',
                b02_recovered = 'B02', b02_held = 'B02', b02_nolock = 'B02', a02_clean = 'A02'}
  for name, drill in pairs(runs) do
    local res, rec = grade(name, drill)
    assert(rec.grade, name .. ' has no recorded grade')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
  end
end

function T.a05_recorded_runs_fail_for_the_right_reasons()
  has(check(grade('a05_clean', 'A05'), 'stop_before_line').text, 'before the line')
  local late = check(grade('a05_late', 'A05'), 'stop_before_line')
  assert(not late.ok, 'late braking fails the line')
  has(late.text, 'past the line')
  assert(not check(grade('a05_lockup', 'A05'), 'no_sustained_lockup').ok, 'full brake locks a wheel')
end

function T.b02_recorded_runs_tell_lock_held_and_no_lock_apart()
  assert(check(grade('b02_recovered', 'B02'), 'lockup_recovered').ok, 'short lock released')
  has(check(grade('b02_held', 'B02'), 'lockup_recovered').text, 'stayed locked')
  has(check(grade('b02_nolock', 'B02'), 'lockup_recovered').text, 'brake harder')
end

function T.a02_recorded_launch_has_engine_and_gear_data()
  local res, rec = grade('a02_clean', 'A02')
  assert(res.passed, 'clean launch passes')
  assert(rec.samples[#rec.samples].eng == 1, 'engine-running flag recorded')
  has(check(res, 'gear_reached').text, 'gear 2')
end

return T
