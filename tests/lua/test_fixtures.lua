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
-- ev_*: events provoked on the same straight: offroad = steered off at 45 km/h, hit the
--      edge (damage 0 -> 5722) and the arcade gearbox then reversed; spin = handbrake and
--      full lock at 60 km/h (turned 143 degrees); contact = full lock onto the grass at 35
--      km/h (no hit); puncture = beamstate.deflateRandomTire() at 45 km/h.
-- A02 (course, ends at the 40 km/h gate): BMP start straight from the venue start, pure-pursuit
--      script along the centre line; gold = full throttle (0-40 in 2.6 s), bronze = 0.4 throttle
--      (a 0.6 s shift misses silver), slow = 34 km/h cap (too slow at the gate).
-- A03 (course): BMP run-up, sequential gearbox with scripted gears (1st, 2nd at 25 km/h, 3rd at 45,
--      to 61 km/h at the gate, then braking): clean = down to 2nd at 40 km/h (gold); skip = 3rd
--      straight to 1st; stay = 3rd to the stop. No over-rev was recorded: the sequential box seems
--      to refuse a downshift that would over-rev, so no_over_rev is unit-tested only.
-- A04 (course): BMP run-up, three gates 25 m apart, arcade gearbox, throttle-only speed hold:
--      steady = 30.5 km/h target (29.3 / 30.0 / 29.1 at the gates: gold); fast = 40 km/h after 60 m.
-- A05 (course): BMP dirt arena, stop line 60 m from the venue start, pure-pursuit script aimed at a
--      bumper distance before the line, braking at 3.5 m/s2 from 44 km/h: gold = 0.48 m before;
--      bronze = 1.25 m (misses silver's 1 m); just_past = 0.01 m past (a miss); past = 0.78 m past.
-- A07, A08 (course): BMP downhill left (venue bmp-gravel-corner), Covet Gravel Rally, pure-pursuit
--      racing line from tools/ingame/lines.py (outside, late apex, track-out); a07_gold = 50 km/h
--      cap (52 at the exit); a07_clip = line 1 m left at the exit (left post); a08_gold = 46 km/h;
--      a08_weave = weaving across the road after the exit gate (2 corrections).
-- B01, B02 (course): BMP run-up, stop zone 30 m past the start line. b01c_gold = pure pursuit to the
--      zone centre from 72 km/h braking at 5 m/s2 (0.7 m past the centre); b01c_past = 6.5 m/s2 (past
--      the 5 m zone). b02c_gold = hold 62 km/h to 115 m, full brake 0.6 s then eased (0.5 s lock);
--      b02c_held = full brake held to the stop.
-- B04 (course): BMP downhill left, Covet Gravel Rally, racing line from lines.py at up to 60 km/h with
--      scripted pedals: gold = brake 0.35 from the marker easing to 0 three metres before the apex;
--      straight = brake 0.45 only before turn-in; late = brake 0.22 until 12 m past the apex.
-- B05 (course): BMP dirt circle (venue bmp-dirt-ring), Covet Gravel Rally in 2nd (sequential), pure
--      pursuit round the 15 m ring, throttle held (0.15 or more) with 0.25 brake dabs every 25 m:
--      gold = 32 km/h (0.8 m off the line at most); wide = 38 km/h (runs 4 m wide); nobrake = 34 km/h,
--      no dabs; lift = 34 km/h, throttle off for each 0.3 brake dab.
-- B07 (course): BMP dirt circle (venue bmp-dirt-arc), Covet Gravel Rally in 2nd (sequential), pure
--      pursuit along the approach, a left quarter of the 15 m ring and the exit lane, full brake for a
--      few metres at the turn-in gate, then 0.3 throttle (the pursuit countersteers by itself):
--      silver = 60 km/h, 6 m of brake (14.3° caught); bronze = 55 km/h, 4 m (11.5°); noslide = 35
--      km/h, 0.5 brake (no slide); stab = 48 km/h, 2 m with more lock (21.6°, still sliding at the lane).
-- B06 (course): BMP dirt circle (venue bmp-dirt-arc), Covet Gravel Rally in 2nd (sequential), pure
--      pursuit along the approach and a left half of the 15 m ring, throttle holding an entry speed, then
--      a lift, then holding a slower speed: gold = 40 km/h, lift 10 m at 35 m, then 26 (2.9 m push, back
--      by the regain gate); silver = 42, lift 12 m (4.1 m push); bronze = 40, lift at 45 m (back only by
--      the exit); nopush = 30 km/h; wide = 46 km/h, no lift (12 m wide).
-- A01: BMP dirt arena, the authored course from the venue start, 14 km/h with a pure-pursuit
--      script (academy.follow_path, the a01 scenario's lines) and the handbrake for the stop;
--      gold = the clean line, centred in the box (9.7 s); wrong_side = left of the cone;
--      post = 0.95 m right through the gate, clipping its right post. The record carries the
--      laid-out course and the car's measured footprint (meta.course, meta.car).
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

-- Recordings with a marked zone or line (meta.finish): graded on the drill's rules minus the
-- authored-course ones (A05's old marked-line runs predate its course).
local COURSE_ONLY = {markers_clear = true, park_in_box = true, cones_passed = true}
local function grade(name, drill)
  local rec = fixture(name)
  local rules = {}
  for _, r in ipairs(drillRules(drill or 'B01')) do
    local needsZone = (r.type == 'stop_zone' or r.type == 'stop_before_line') and not rec.meta.finish
    if not COURSE_ONLY[r.type] and not needsZone then rules[#rules + 1] = r end
  end
  return Rules.evaluate(rules, rec, {zone = rec.meta.finish, gates = rec.meta.gates}), rec
end

local function check(res, ruleType)
  for _, c in ipairs(res.checks) do if c.type == ruleType then return c end end
end

local function eq(actual, expected, msg)
  if actual ~= expected then
    error(('%s: expected %s, got %s'):format(msg or 'mismatch', tostring(expected), tostring(actual)), 2)
  end
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
                b02_recovered = 'B02', b02_held = 'B02', b02_nolock = 'B02'}
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

-- a02_clean predates A02's course, so only its engine and gear data are checked.
function T.a02_recorded_launch_has_engine_and_gear_data()
  local rec = fixture('a02_clean')
  assert(rec.samples[#rec.samples].eng == 1, 'engine-running flag recorded')
  local res = Rules.evaluate({{type = 'gear_reached', gear = 2}, {type = 'no_stall'}}, rec)
  assert(res.passed, 'shifted to 2nd without stalling')
  has(check(res, 'gear_reached').text, 'gear 2')
end

-- Course drills (A01, A02): the course and footprint come from the record, the time from its score.
local function gradeCourse(name, drill)
  local rec = fixture(name)
  local a
  for _, e in ipairs(read(ROOT .. '/mod/gameplay/rallyAcademy/exercises.json').exercises) do
    if e.id == (drill or 'A01') then a = e.assessment end
  end
  return Rules.grade(a, rec, {course = rec.meta.course, gates = rec.meta.course.gates, car = rec.meta.car,
                              zone = rec.meta.course.zone,
                              time = rec.score and rec.score.time}), rec
end

function T.a01_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {a01_gold = 'gold', a01_wrong_side = false, a01_post = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name)
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
    eq(rec.grade.tier or false, tier, name .. ' medal the game showed')
  end
end

function T.a01_recorded_misses_fail_for_the_right_reasons()
  local wrong = gradeCourse('a01_wrong_side')
  has(check(wrong, 'cones_passed').text, 'wrong side of the cone')
  local post = gradeCourse('a01_post')
  has(check(post, 'markers_clear').text, 'Clipped the right post of the gate')
  eq(check(post, 'park_in_box').ok, true, 'it still parked in the box')
  local gold = gradeCourse('a01_gold')
  has(check(gold, 'park_in_box').text, 'Parked inside the box')
  eq(check(gold, 'no_reverse').ok, true, 'the handbrake stop does not read as reversing')
end

function T.a02_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {a02_gold = 'gold', a02_bronze = 'bronze', a02_slow = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'A02')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
end

function T.a02_recorded_runs_give_the_right_coaching()
  local gold = gradeCourse('a02_gold', 'A02')
  has(check(gold, 'time_to_speed').text, '0-40 km/h in 2.')
  local bronze = gradeCourse('a02_bronze', 'A02')
  has(bronze.nextTier.text, 'in neutral')
  has(check(gradeCourse('a02_slow', 'A02'), 'speed_at_gates').text, 'gate 1 too slow')
end

function T.a03_downshift_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {a03_clean = 'gold', a03_skip = false, a03_stay = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'A03')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  eq(check(gradeCourse('a03_clean', 'A03'), 'progressive_downshifts').text, 'Downshifted 3→2', 'clean sequence')
  has(check(gradeCourse('a03_skip', 'A03'), 'progressive_downshifts').text, 'Skipped from 3rd to 1st')
  has(check(gradeCourse('a03_stay', 'A03'), 'progressive_downshifts').text, 'Stayed in 3rd')
end

function T.a04_speed_hold_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local steady, rec = gradeCourse('a04_steady', 'A04')
  eq(steady.passed, rec.grade.passed, 'steady: same verdict')
  eq(steady.tier, 'gold', 'steady: gold')
  has(check(steady, 'speed_at_gates').text, 'Gate speeds 29.3 / 30.0 / 29.1 km/h')
  local fast, frec = gradeCourse('a04_fast', 'A04')
  eq(fast.passed, frec.grade.passed, 'fast: same verdict')
  has(check(fast, 'speed_at_gates').text, 'gate 3 too fast')
end

function T.a05_course_line_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {a05c_gold = 'gold', a05c_bronze = 'bronze', a05c_just_past = false, a05c_past = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'A05')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('a05c_just_past', 'A05'), 'stop_before_line').text, 'Stopped 0.01 m past the line')
  has(check(gradeCourse('a05c_gold', 'A05'), 'stop_before_line').text, 'Stopped 0.48 m before the line')
end

function T.a07_a08_corner_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {a07_gold = {'A07', 'gold'}, a07_clip = {'A07', false}, a08_gold = {'A08', 'gold'}, a08_weave = {'A08', false}}
  for name, w in pairs(want) do
    local res, rec = gradeCourse(name, w[1])
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, w[2], name .. ' medal')
  end
  has(check(gradeCourse('a07_clip', 'A07'), 'markers_clear').text, 'Clipped the left post of the gate')
  eq(check(gradeCourse('a08_gold', 'A08'), 'steady_exit').text, 'Steady exit: no steering corrections', 'steady')
  has(check(gradeCourse('a08_weave', 'A08'), 'steady_exit').text, '2 steering corrections after the exit gate')
end

function T.b01_b02_course_zone_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {b01c_gold = {'B01', 'gold'}, b01c_past = {'B01', false}, b02c_gold = {'B02', 'gold'}, b02c_held = {'B02', false}}
  for name, w in pairs(want) do
    local res, rec = gradeCourse(name, w[1])
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, w[2], name .. ' medal')
  end
  has(check(gradeCourse('b01c_past', 'B01'), 'stop_zone').text, 'past the zone')
  has(check(gradeCourse('b02c_held', 'B02'), 'lockup_recovered').text, 'stayed locked')
end

function T.b04_trail_braking_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {b04_gold = 'gold', b04_straight = false, b04_late = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'B04')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('b04_gold', 'B04'), 'trail_braked').text, 'Trail-braked')
  has(check(gradeCourse('b04_straight', 'B04'), 'trail_braked').text, 'carry the brake into the corner')
  has(check(gradeCourse('b04_late', 'B04'), 'brake_off_by_gate').text, 'Still braking at the apex')
end

function T.b05_left_foot_braking_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {b05_gold = 'gold', b05_wide = false, b05_nobrake = false, b05_lift = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'B05')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('b05_gold', 'B05'), 'left_foot_brakes').text, 'brake dabs on the throttle')
  has(check(gradeCourse('b05_wide', 'B05'), 'circle_corridor').text, 'wide of the line')
  has(check(gradeCourse('b05_nobrake', 'B05'), 'left_foot_brakes').text, 'dab it to tighten the line')
  has(check(gradeCourse('b05_lift', 'B05'), 'left_foot_brakes').text, 'you lifted to brake')
end

function T.b07_oversteer_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {b07_silver = 'silver', b07_bronze = 'bronze', b07_noslide = false, b07_stab = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'B07')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('b07_silver', 'B07'), 'rear_slide').text, 'Rear stepped out 14.3°')
  has(check(gradeCourse('b07_noslide', 'B07'), 'rear_slide').text, 'lift or brake harder')
  has(check(gradeCourse('b07_stab', 'B07'), 'settled_by_gate').text, 'Still sliding at the lane end')
end

function T.b06_understeer_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {b06_gold = 'gold', b06_silver = 'silver', b06_bronze = 'bronze', b06_nopush = false, b06_wide = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'B06')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('b06_gold', 'B06'), 'ran_wide').text, 'Front pushed 2.9 m wide')
  has(check(gradeCourse('b06_nopush', 'B06'), 'ran_wide').text, 'carry more speed in')
  has(check(gradeCourse('b06_wide', 'B06'), 'ran_wide').text, 'the push got away')
end

local function ruleCheck(name, rule)
  return Rules.evaluate({rule}, fixture(name)).checks[1]
end

function T.recorded_events_are_detected()
  local SURF = {type = 'on_surface', surfaces = {'ASPHALT', 'GRAVEL'}, maxWheelsOff = 2, maxSeconds = 0.5}
  has(ruleCheck('ev_offroad', {type = 'no_damage'}).text, 'Hit something')
  assert(ruleCheck('ev_offroad', {type = 'no_spin'}).ok, 'reversing after the crash is not a spin')
  has(ruleCheck('ev_spin', {type = 'no_spin'}).text, 'Spun at')
  has(ruleCheck('ev_spin', {type = 'no_handbrake'}).text, 'Used the handbrake')
  has(ruleCheck('ev_contact', SURF).text, 'Left the road')
  has(ruleCheck('ev_puncture', {type = 'no_puncture'}).text, 'Punctured')
  assert(ruleCheck('ev_puncture', {type = 'no_damage'}).ok, 'a puncture is not contact')
end

function T.recorded_clean_runs_raise_no_events()
  for _, name in ipairs({'b02_recovered', 'a05_clean', 'a02_clean'}) do
    for _, rule in ipairs({{type = 'no_spin'}, {type = 'no_rollover'}, {type = 'no_puncture'}}) do
      local c = ruleCheck(name, rule)
      assert(c.ok, name .. ': ' .. c.text)
    end
  end
end

return T
