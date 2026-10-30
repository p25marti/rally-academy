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
-- A03 (course): the proving ground's dirt strip (venue pg-dirt-strip, 0.40.0), sequential gearbox with scripted gears
--      (1st, 2nd at 25 km/h, 3rd at 45, to 61 km/h at the gate, then braking at 2.2 m/s2): gold = down to 2nd below
--      40 km/h; skip = 3rd straight to 1st; stay = 3rd to the stop. (On the stock arena the 0.40 sequential box blipped
--      3-2-3 while shifting up, which progressive_downshifts now ignores.) No over-rev was recorded: the sequential
--      box seems to refuse a downshift that would over-rev, so no_over_rev is unit-tested only.
-- A04 (course): BMP run-up, three gates 25 m apart, arcade gearbox, throttle-only speed hold:
--      steady = 30.5 km/h target (29.3 / 30.0 / 29.1 at the gates: gold); fast = 40 km/h after 60 m.
-- A05 (course): the proving ground's dirt strip, stop line 60 m from the venue start, pure-pursuit script aimed at a
--      bumper distance before the line, braking at 3.5 m/s2 from 44 km/h (0.40.0): gold = 0.15 m before; bronze =
--      1.14 m (misses silver's 1 m); just_past = 0.58 m past (a miss); past = 1.25 m past.
-- Corner drills A07, A08, B04, C01, C02, C08, E02 (course): re-recorded 0.40.0 on the proving ground's flat copy of
--      the BMP downhill left (venue pg-corner-left, ADR 0008), Covet Gravel Rally, lines from tools/ingame/lines.py.
-- A07, A08: pure pursuit along the racing line (outside, late apex, track-out); a07_gold / silver / bronze =
--      60 / 50 / 40 km/h (59.9 / 50.0 / 40.0 at the exit); a07_clip = line 1 m left at the exit (left post).
--      A08 on a later apex with the line unwinding to the finish: a08_bronze = 41 km/h (one correction; the
--      scenario's run at the same speed got silver), a08_bronze2 = 44; a08_weave = weaving after the exit.
-- B01, B02 (course): the proving ground's dirt strip, stop zone 150 m from the start, all on dirt (0.40.0).
--      b01c_silver / silver2 = pure pursuit to the zone centre from 72 km/h braking at 4.6 / 5.0 m/s2 (0.8 / 1.3 m
--      past the centre); b01c_past = 7.5 m/s2 (7.1 m past the zone). b02c_gold = hold 62 km/h to 115 m, full brake
--      0.6 s then eased (0.5 s lock); b02c_held = full brake held to the stop.
-- B04 (course): the test road's closing right (scenario trail, RA_SAVE=1; 2026-10-21, arcade, 65 km/h, the line 1.2 m
--      inside round the apex): gold_tr = brake 0.25 from the marker easing to 0 three metres before the apex with 0.1
--      throttle under it, then the throttle fed to 0.6 over 12 m (gold, 50+ km/h out); straight_tr = brake 0.7 for 13 m
--      from the marker only; pumped_tr = the brake pumped +-0.08 every 6 m; stab_tr = full throttle at the apex at once.
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
-- C02 (course): the flat corner, in 2nd (sequential), lines.bmp_left with the line ~2 m further inside at nodes
--      7-9, holding an entry speed, then a full-brake pulse after the Turn in gate, then holding an exit speed:
--      gold = 65 km/h, 8 m pulse from 74 m (17.1°); silver = 65, 7 m from 73 m (12.0°); bronze = 55, 5 m from
--      78 m (8.8°); miss = 55, 4 m from 78 m (6.9°).
-- C08 (course): as C02 plus a Flick gate, the approach nearer the middle, with a scripted steering override:
--      hold 66 km/h, from 54 m lift and steer 0.5 right for 8 m, then full lock left with full brake for 8 m,
--      then the pursuit holds 45 km/h: silver / silver2 = 12.7° / 14.4°; clip = approaching on the outside
--      (right post of the Turn in gate); norotate = the same flick at 56 km/h (4.2°); noflick = no steering away.
-- C04 (course): BMP dirt arena, Covet Gravel Rally in 2nd (sequential), pure pursuit up to a 4.5 m radius
--      turn round the pivot cone and back, braking to an entry speed before the cone, then the handbrake
--      with a steering override (0.3-0.4 lock) from 45 m, then holding an exit speed: gold = 50 km/h,
--      brake to 45, 6 m pull at 0.3 lock, exit 30 (30.4°, 36 km/h out); silver = exit 24 (28.2°, 30 km/h);
--      bronze = brake to 42, 5 m at 0.4 (24.0°); noswing = brake to 38 (17.1°); nohandbrake = no pull.
-- C07 (course): BMP dirt arena, Covet Gravel Rally in 2nd (sequential), pure pursuit up to the crossing, then
--      10 m circles round each cone (clockwise right, anticlockwise left) at a steady speed: gold = 28 km/h
--      (21.3 s); silver = 25 (21.8 s); bronze = 20 (25.0 s); wide = 32 km/h (ran wide of the right lobe gate).
-- C01 (course): the flat corner, in 2nd (sequential), lines.bmp_left about 3 m inside at nodes 7-9, 65 km/h
--      braked to 61 before the Turn in gate, 0.5 throttle, a 15 m lift from 70 m, then holding 45: bronze /
--      bronze2 = 4.6° / 4.4° (the lift rotates the car less on the flat than on the stock downhill, 3.6-11°);
--      norotate = entry 54, lift from 72 m (0.7°).
-- D01 (course): BMP dirt arena, Covet Gravel Rally in 2nd (sequential), pure pursuit along a cosine weave
--      (±amplitude at each cone, 15 m apart) at a steady speed: gold = 32 km/h, ±2.4 m (13.6 s); silver =
--      30, ±3 m (14.6 s); bronze = 26, ±3 m (16.2 s); clip = 38 km/h, ±3 m (hit cone 4).
-- D08 (course): BMP run-up, Covet Gravel Rally, arcade gearbox, pure pursuit at 62 km/h braking to stop on the
--      zone centre at a set deceleration (follow_path decel): gold = 4 m/s2 (0.5 m past the centre); silver =
--      5.5 (1.7 m past); bronze = 5.8 (2.7 m past); overshoot = 6 (0.4 m past the zone); lockup = full brake
--      from 125 m, on the tarmac (locked 1.7 s, 16 m short).
-- E02 (course): the flat corner and C02's line, in 2nd (sequential), 64 km/h, a 7 m brake pulse from 73 m, 0.12
--      throttle, then 0.6 throttle from 110 m (just before the apex): gold / gold2 = 13.6° / 13.2° and 68.6 km/h
--      out; nothrottle = holding 46 km/h after the pulse (peak 16% throttle after the apex).
-- D05, D06, E05 (course): West Coast USA Off-Road Circuit (venues offroad-blind-hairpin, wcusa-offroad-circuit,
--      offroad-kicker), Covet Gravel Rally in 2nd (sequential), pure pursuit along the circuit's road-network
--      centre line holding a speed, then a second speed from a set distance. D05: gold = 37 km/h (38.6 at the Turn
--      in gate); silver = 40.5 (42.0); bronze = 43 (44.5); fast = 55 (55.4). D06: gold = 50 then 45 from 230 m
--      (24.2 s); silver = 45 then 40 (26.0 s); bronze = 38 then 35 (29.6 s); wall = 55 (hit the uphill corner's
--      wall). E05: gold = 55 then 59 from 50 m (55.7 at the crest, a bumper scrape on landing); silver = 56
--      target (50.4); bronze = 45 then 50 (46.4); airborne = 75 target (66.4: 0.3 s off the ground, 1508 damage).
-- D03, D04 (course): gravel lane DR825 (venues gravel-lane-tightening, gravel-lane-opening), Covet Gravel Rally in
--      2nd (sequential), pure pursuit along the road-network centre line. D03: hold a speed, then a lower one from
--      a set distance: gold = 46 then 36 from 45 m (38 km/h out); silver = 45 then 30 from 50 m (32); bronze = 38
--      then 24 (27); wide = 50 then 36 (ran wide where it tightens). D04: 25 km/h to the bend, then a throttle
--      ramp from 0.25 from 32 m: gold = up to 0.45 (54.5 km/h out); silver = up to 0.34 from 36 m (50.9);
--      lowthrottle = capped at 0.25 (never a third); spin = up to 0.6 (front wheel spun 0.9 s, ran wide).
-- A01: BMP dirt arena, the authored course from the venue start, 14 km/h with a pure-pursuit
--      script (academy.follow_path, the a01 scenario's lines) and the handbrake for the stop;
--      gold = the clean line, centred in the box (9.7 s); wrong_side = left of the cone;
--      post = 0.95 m right through the gate, clipping its right post. The record carries the
--      laid-out course and the car's measured footprint (meta.course, meta.car).
-- *_pg: after A01, B05-B07, C04, C07 and D01 moved to the proving ground's dirt strip (0.40.0), one medal run each
--      with the scenario's inputs: a01 = the clean line at 14 km/h; b05 = 32 km/h round the ring with 0.25 dabs every
--      25 m; b06 = 40 km/h, a 10 m lift at 35 m, then 26; b07 = 60 km/h, 6 m of full brake (bronze there); c04 =
--      braked to 45, a 6 m pull at 0.3 lock, exit 30; c07 = 28 km/h circles; d01 = 32 km/h, ±2.4 m. The older runs
--      above them were recorded on the BMP dirt arena and circle (DIRT_DUSTY); the rules didn't change.
--      d03 = the flat copy of lane DR825, 45 km/h easing to 36 from 50 m (38 out); d04 = its opening left, the
--      throttle ramped from 36 m (56 out). d08 = the surface-change straight, 62 km/h braking at 4 m/s2.
--      d05 / d06 / e05 = the hill circuit (the Off-Road Circuit's first 640 m copied with elevation and banking):
--      37 km/h into the blind hairpin; 45 then 40 km/h; e05 re-recorded 2026-10-21 with the raw wheel force: 45 km/h
--      through the banked left then 50 over the kicker (51 at the crest, 0.12 s in the air).
--      e06 = the jump (scenario jump): a steady 57 km/h (gold, about 0.65 s in the air); the miss took 68 (damage +238).
--      e08 = the ford (scenario ford): 60 km/h on the approach, 22 from 25 m before the water to 110 m (gold, 17.5 s);
--      the miss held 40 into the water.
--      e07 = the rough track (scenario rough): 75 km/h on the smooth approach, 50 over the rough (gold, 22.6 s); the
--      miss held 60 all the way (damage on the bumps, wide in the S).
--      d02 = the test road's linked S (scenario linked, real posts): 55 km/h into the first bend, 50 through the rest,
--      on the power from 205 m (gold, 74 km/h at the Exit); the miss took 60 into the first bend.
--      d07 = the camber road (scenario camber, real posts): 57 km/h, slowing to 45 from 25 m before each off-camber
--      corner, arcade (gold, 59 km/h at the banked apex); misses at 45 everywhere and at 64.
--      d09 = the mountain face's gravel switchback (scenario hairpins): 55 km/h legs, 28 round the hairpins, 35 in the
--      bottom and top bends, arcade, 37.7 s.
--      a02 = the launch fed in from 25 % throttle (full at 45 km/h);
--      a04 = the 30 km/h throttle hold (bronze here:
--      gate 3 at 27.9 km/h, under silver's 28).
local json = require('json')
local Rules = require('ge/extensions/rallyAcademy/rules')
local Variants = require('ge/extensions/rallyAcademy/variants')
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
-- authored-course ones (A05's old marked-line runs predate its course) and the venue's surface list
-- (B02's old runs were on the start straight's asphalt; B02 is now all dirt).
local COURSE_ONLY = {markers_clear = true, park_in_box = true, cones_passed = true, on_surface = true}
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
    for _, v in ipairs(Variants.expand(e)) do -- surface variants (A02-snow) grade with their own targets
      if v.id == drill then a = v.assessment end
    end
  end
  -- runs recorded with real cones and posts (ADR 0011) carry what the car touched; older ones are measured
  return Rules.grade(a, rec, {course = rec.meta.course, gates = rec.meta.course.gates, car = rec.meta.car,
                              zone = rec.meta.course.zone, hits = rec.meta.hits,
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

-- One medal run per drill re-driven on the proving ground after the move (ADR 0008), next to the older runs
-- recorded on the BMP arena and circle (the rules are the same; these prove they hold on the new ground too).
function T.proving_ground_medal_runs_still_agree_with_the_in_game_verdicts()
  local want = {a01_gold_pg = {'A01', 'gold'}, a02_gold_pg = {'A02', 'gold'}, a04_bronze_pg = {'A04', 'bronze'},
    b05_gold_pg = {'B05', 'gold'}, b06_gold_pg = {'B06', 'gold'},
    d03_gold_pg = {'D03', 'gold'}, d04_gold_pg = {'D04', 'gold'},
    d08_gold_pg = {'D08', 'gold'}, d05_gold_pg = {'D05', 'gold'}, d06_silver_pg = {'D06', 'silver'},
    e05_gold_pg = {'E05', 'gold'}, e06_gold_pg = {'E06', 'gold'}, d09_gold_pg = {'D09', 'gold'}, d07_gold_pg = {'D07', 'gold'},
    d02_gold_pg = {'D02', 'gold'}, e07_gold_pg = {'E07', 'gold'}, e08_gold_pg = {'E08', 'gold'},
    b07_bronze_pg = {'B07', 'bronze'}, c04_gold_pg = {'C04', 'gold'}, c07_gold_pg = {'C07', 'gold'}, d01_gold_pg = {'D01', 'gold'}}
  for name, w in pairs(want) do
    local res, rec = gradeCourse(name, w[1])
    eq(rec.meta.level, 'ra_proving_ground', name .. ' recorded on the proving ground')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, w[2], name .. ' medal')
  end
end

-- E06 recorded over the kicker with the raw wheel force: the gold run's airtime is measured, and 68 km/h breaks the car.
function T.e06_recorded_jumps_measure_the_air_and_the_landing()
  has(check(gradeCourse('e06_gold_pg', 'E06'), 'airtime').text, 's in the air')
  local miss = gradeCourse('e06_miss_damage_pg', 'E06')
  eq(miss.passed, false, 'a miss')
  has(check(miss, 'no_damage').text, 'too fast for the landing')
end

-- E08 miss recorded at the ford: 40 km/h into the water, over the Entry gate's 25.
function T.e08_recorded_fast_entry_misses_at_the_waters_edge()
  local res = gradeCourse('e08_miss_fast_pg', 'E08')
  eq(res.passed, false, 'a miss')
  local entry
  for _, c in ipairs(res.checks) do if c.type == 'speed_at_gates' and not c.ok then entry = c end end
  has(entry.text, 'gate 1 too fast')
end

-- E07 miss recorded on the rough track: 60 km/h all the way, and the bumps damage the car (with the drill's coaching).
function T.e07_recorded_rush_damages_the_car_on_the_bumps()
  local res = gradeCourse('e07_miss_damage_pg', 'E07')
  eq(res.passed, false, 'a miss')
  has(check(res, 'no_damage').text, 'Damaged the car')
  has(check(res, 'no_damage').text, 'ease off over the rough')
end

-- D02 miss recorded on the test road: 60 km/h into the first bend leaves no room for the second, whose post it touches.
function T.d02_recorded_overcommit_fails_at_the_second_apex()
  local res = gradeCourse('d02_miss_overcommit_pg', 'D02')
  eq(res.passed, false, 'overcommitting misses')
  has(check(res, 'markers_clear').text, 'Clipped the left post of gate 2')
end

-- D07 misses recorded on the camber road with real posts: a cautious 45 km/h everywhere (too slow through the banked
-- apex) and 64 km/h, which runs wide in the off-camber right and touches its post.
function T.d07_recorded_misses_fail_for_the_right_reasons()
  local slow = gradeCourse('d07_miss_slow_pg', 'D07')
  eq(slow.passed, false, 'too slow misses')
  has(check(slow, 'speed_at_gates').text, 'gate 1 too slow')
  local off = gradeCourse('d07_miss_off_pg', 'D07')
  eq(off.passed, false, 'too fast misses')
  has(check(off, 'markers_clear').text, 'Clipped the left post of gate 2')
end

-- A surface variant grades with its own targets (ADR 0009): A02 on snow allows 10 s to 40 km/h (7 s silver,
-- 5.5 s gold) where the dirt base allows 8 (4.5, 3.5). a02-snow_bronze: the launch fed in from 15 % throttle
-- (full at 80 km/h) on the snow strip, 0-40 in 6.2 s, a 0.7 s shift (bronze: silver wants 0.6 s).
function T.a_surface_variant_grades_with_its_own_targets()
  local snow, rec = gradeCourse('a02-snow_bronze', 'A02-snow')
  eq(rec.meta.drill, 'A02-snow', 'recorded as the variant')
  assert(snow.passed == rec.grade.passed, 'rules agree with the game: ' .. tostring(snow.passed))
  eq(snow.tier, 'bronze', 'medal')
  has(check(snow, 'time_to_speed').text, 'target 10 s')
  has(check(gradeCourse('a02-snow_bronze', 'A02'), 'time_to_speed').text, 'target 8 s')
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
  local want = {a03_gold = 'gold', a03_skip = false, a03_stay = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'A03')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  eq(check(gradeCourse('a03_gold', 'A03'), 'progressive_downshifts').text, 'Downshifted 3→2', 'clean sequence')
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
  has(check(gradeCourse('a05c_just_past', 'A05'), 'stop_before_line').text, 'Stopped 0.58 m past the line')
  has(check(gradeCourse('a05c_gold', 'A05'), 'stop_before_line').text, 'Stopped 0.15 m before the line')
end

function T.a07_a08_corner_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {a07_gold = {'A07', 'gold'}, a07_silver = {'A07', 'silver'}, a07_bronze = {'A07', 'bronze'},
    a07_clip = {'A07', false}, a08_bronze = {'A08', 'bronze'}, a08_bronze2 = {'A08', 'bronze'}, a08_weave = {'A08', false}}
  for name, w in pairs(want) do
    local res, rec = gradeCourse(name, w[1])
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, w[2], name .. ' medal')
  end
  has(check(gradeCourse('a07_clip', 'A07'), 'markers_clear').text, 'Clipped the left post of the gate')
  has(check(gradeCourse('a08_bronze', 'A08'), 'steady_exit').text, '1 steering correction after the exit gate')
  has(check(gradeCourse('a08_weave', 'A08'), 'steady_exit').text, '2 steering corrections after the exit gate')
end

function T.b01_b02_course_zone_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {b01c_silver = {'B01', 'silver'}, b01c_silver2 = {'B01', 'silver'}, b01c_past = {'B01', false},
    b02c_gold = {'B02', 'gold'}, b02c_held = {'B02', false}}
  for name, w in pairs(want) do
    local res, rec = gradeCourse(name, w[1])
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, w[2], name .. ' medal')
  end
  has(check(gradeCourse('b01c_past', 'B01'), 'stop_zone').text, 'past the zone')
  has(check(gradeCourse('b02c_held', 'B02'), 'lockup_recovered').text, 'stayed locked')
end

-- The text of a drill's smooth_pedal check for one pedal (B04 has two).
local function pedalCheck(res, pedal)
  for _, c in ipairs(res.checks) do
    if c.type == 'smooth_pedal' and c.text:find(pedal == 'brake' and 'Brake' or 'Throttle', 1, true) then return c end
  end
end

function T.b04_trail_braking_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {b04_gold_tr = 'gold', b04_straight_tr = false, b04_pumped_tr = false, b04_stab_tr = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'B04')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('b04_gold_tr', 'B04'), 'trail_braked').text, 'Trail-braked')
  has(pedalCheck(gradeCourse('b04_gold_tr', 'B04'), 'brake').text, 'eased off in one motion')
  has(pedalCheck(gradeCourse('b04_gold_tr', 'B04'), 'throttle').text, 'fed in smoothly')
  has(check(gradeCourse('b04_straight_tr', 'B04'), 'trail_braked').text, 'keep some brake on')
  has(pedalCheck(gradeCourse('b04_pumped_tr', 'B04'), 'brake').text, 'Brake pumped')
  has(pedalCheck(gradeCourse('b04_stab_tr', 'B04'), 'throttle').text, 'Throttle stabbed')
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

function T.c02_brake_rotation_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {c02_gold = 'gold', c02_silver = 'silver', c02_bronze = 'bronze', c02_miss = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'C02')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('c02_miss', 'C02'), 'rear_slide').text, 'lift or brake harder')
end

function T.c08_flick_rules_still_agree_with_the_in_game_verdicts()
  local want = {c08_silver = 'silver', c08_silver2 = 'silver', c08_clip = false, c08_norotate = false, c08_noflick = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'C08')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('c08_silver', 'C08'), 'flick').text, 'Flicked')
  has(check(gradeCourse('c08_noflick', 'C08'), 'flick').text, 'No flick')
  has(check(gradeCourse('c08_norotate', 'C08'), 'rear_slide').text, 'lift or brake harder')
end

function T.c04_handbrake_hairpin_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {c04_gold = 'gold', c04_silver = 'silver', c04_bronze = 'bronze', c04_noswing = false, c04_nohandbrake = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'C04')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('c04_gold', 'C04'), 'handbrake_pulls').text, '1 handbrake pull')
  has(check(gradeCourse('c04_noswing', 'C04'), 'rear_slide').text, 'pull the handbrake firmly')
  has(check(gradeCourse('c04_nohandbrake', 'C04'), 'handbrake_pulls').text, 'pull it once')
end

function T.c07_figure_eight_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {c07_gold = 'gold', c07_silver = 'silver', c07_bronze = 'bronze', c07_wide = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'C07')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('c07_wide', 'C07'), 'gates_passed').text, 'gate 2')
end

function T.c01_lift_off_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {c01_bronze = 'bronze', c01_bronze2 = 'bronze', c01_norotate = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'C01')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('c01_bronze', 'C01'), 'no_brake_between_gates').text, 'No braking between gates 1 and 2')
  has(check(gradeCourse('c01_norotate', 'C01'), 'rear_slide').text, 'lift sharply')
end

function T.d01_slalom_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {d01_gold = 'gold', d01_silver = 'silver', d01_bronze = 'bronze', d01_clip = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'D01')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('d01_gold', 'D01'), 'cones_passed').text, 'All 6 cones passed on the correct side')
  has(check(gradeCourse('d01_clip', 'D01'), 'markers_clear').text, 'Clipped cone 4')
end

function T.d08_surface_change_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {d08_gold = 'gold', d08_silver = 'silver', d08_bronze = 'bronze', d08_overshoot = false, d08_lockup = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'D08')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('d08_overshoot', 'D08'), 'stop_zone').text, 'past the zone')
  has(check(gradeCourse('d08_lockup', 'D08'), 'no_sustained_lockup').text, 'locked for')
end

function T.e02_fwd_technique_rules_and_medals_still_agree_with_the_in_game_verdicts()
  local want = {e02_gold = 'gold', e02_gold2 = 'gold', e02_nothrottle = false}
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, 'E02')
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
  has(check(gradeCourse('e02_gold', 'E02'), 'throttle_on_between').text, 'Back on the throttle')
  has(check(gradeCourse('e02_nothrottle', 'E02'), 'throttle_on_between').text, 'drive the front out')
end

local function agree(drill, want)
  for name, tier in pairs(want) do
    local res, rec = gradeCourse(name, drill)
    assert(res.passed == rec.grade.passed, name .. ': rules now say ' .. tostring(res.passed)
      .. ', the game said ' .. tostring(rec.grade.passed))
    eq(res.tier or false, tier, name .. ' medal')
  end
end

function T.off_road_circuit_drills_still_agree_with_the_in_game_verdicts()
  agree('D05', {d05_gold = 'gold', d05_silver = 'silver', d05_bronze = 'bronze', d05_fast = false})
  agree('D06', {d06_gold = 'gold', d06_silver = 'silver', d06_bronze = 'bronze', d06_wall = false})
  -- E05's medals moved down 2026-10-21 (silver 46, gold 50 km/h) once airtime read the raw wheel force: 50.4 km/h at
  -- the crest is gold now, 46.4 silver. These stock recordings carry the smoothed force, so their airtime reads low.
  agree('E05', {e05_gold = 'gold', e05_silver = 'gold', e05_bronze = 'silver', e05_airborne = false})
  has(check(gradeCourse('d05_fast', 'D05'), 'speed_at_gates').text, 'too fast')
  has(check(gradeCourse('e05_gold', 'E05'), 'airtime').text, 'All four wheels stayed on the ground')
  has(check(gradeCourse('e05_airborne', 'E05'), 'airtime').text, 'ease off before the crest')
end

function T.gravel_lane_corner_drills_still_agree_with_the_in_game_verdicts()
  agree('D03', {d03_gold = 'gold', d03_silver = 'silver', d03_bronze = 'bronze', d03_wide = false})
  agree('D04', {d04_gold = 'gold', d04_silver = 'silver', d04_lowthrottle = false, d04_spin = false})
  has(check(gradeCourse('d04_spin', 'D04'), 'no_sustained_wheelspin').text, 'spun for')
  has(check(gradeCourse('d04_gold', 'D04'), 'no_sustained_wheelspin').text, 'No sustained wheelspin')
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

-- D10 recorded in the hay-bale chicane (scenario chicane, 2026-10-30, 0.40.4, arcade, real bales): d10_medal = flat out to
-- the Brake gate, braked to 34 km/h and weaved straight through each gap (gold, 9.5 s); d10_clip = 40 km/h through the
-- chicane, the car hit a bale (the game's collision report); d10_slow = braked from 20 m, 31 km/h at the Brake gate.
function T.d10_chicane_rules_and_medals_agree_with_the_in_game_verdicts()
  agree('D10', {d10_medal = 'gold', d10_clip = false, d10_slow = false})
  has(check(gradeCourse('d10_clip', 'D10'), 'markers_clear').text, 'Clipped bale')
  has(check(gradeCourse('d10_slow', 'D10'), 'speed_at_gates').text, 'gate 1 too slow')
end

-- C09 recorded round the bale (scenario donut, 2026-10-30, 0.40.4, arcade, a controller in the car's Lua): c09_pass = 30
-- km/h in, a 0.6 s handbrake swing, then 22 km/h held with a handbrake tap every second, steering to keep 5 m from the
-- bale (bronze: about 18 degrees of slide, 4-5 m off the circle); c09_noslide = round on the lock at 18 km/h, no
-- handbrake.
function T.c09_donut_rules_agree_with_the_in_game_verdicts()
  agree('C09', {c09_pass = 'bronze', c09_noslide = false})
  has(check(gradeCourse('c09_pass', 'C09'), 'turned').text, 'round (target 330°)')
  has(check(gradeCourse('c09_noslide', 'C09'), 'rear_slide').text, 'rear only stepped out')
end

-- F06 recorded on the test road (scenario puncture): the mod deflates a tyre at the Puncture gate. 50 km/h to it, then a
-- 30 km/h limp (gold, 33 at most on the flat); the miss limped at 38 (40 on the flat).
function T.f06_recorded_limps_grade_the_pace_on_the_flat()
  agree('F06', {f06_gold_pg = 'gold', f06_miss_fast_pg = false})
  has(check(gradeCourse('f06_gold_pg', 'F06'), 'limp_speed').text, 'Limped at up to')
  has(check(gradeCourse('f06_miss_fast_pg', 'F06'), 'limp_speed').text, 'slow right down when a tyre goes')
end

-- B03 recorded on the dirt, asphalt and snow strips (scenario predict): 50 km/h to the Brake line, 0.8 brake from it, the
-- mark set where the car stops (dirt 18 m, asphalt 15, snow 24: gold each); the miss set 30 m on dirt.
function T.b03_recorded_estimates_grade_against_the_mark()
  agree('B03', {b03_gold_pg = 'gold', b03_miss_far_pg = false})
  agree('B03-asphalt', {['b03-asphalt_gold_pg'] = 'gold'})
  agree('B03-snow', {['b03-snow_gold_pg'] = 'gold'})
  has(check(gradeCourse('b03_miss_far_pg', 'B03'), 'predicted_stop').text, 'short of your mark')
end

return T
