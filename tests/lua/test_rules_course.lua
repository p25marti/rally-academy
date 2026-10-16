-- Unit tests for the authored-course rules (cones_passed, markers_clear, park_in_box,
-- no_reverse, max_time) and medal tiers (R.grade), on synthetic runs through A01's course.
local L = require('ge/extensions/rallyAcademy/layout')
local R = require('ge/extensions/rallyAcademy/rules')
local H = require('ra_helpers')
local eq, has = H.eq, H.has
local T = {}

local COVET = {front = 1.85, rear = 2.07, left = 1.23, right = 0.58}
local START = {pos = {x = 0, y = 0, z = 0}, dir = {x = 0, y = 1, z = 0}}
-- A01's course, read from the drill data so the tests follow it.
H.stubs.install() -- jsonReadFile, to read the drill data
local A01 = H.drills().A01.assessment
local COURSE = L.place(A01.course, START)

-- Drive a polyline of {x, y} points (car positions, course frame = world here) at `speed`
-- m/s, heading along the path, then stand still for a second. Samples every 0.05 s.
local function drive(points, opts)
  opts = opts or {}
  local samples, t, speed = {}, 0, opts.speed or 5
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    local steps = math.max(1, math.floor(len / (speed * 0.05)))
    local hx, hy = dx / len, dy / len
    if b.reverse then hx, hy = -hx, -hy end
    for k = 1, steps do
      t = t + 0.05
      samples[#samples + 1] = {t = t, x = a[1] + dx * k / steps, y = a[2] + dy * k / steps, air = speed,
                               hx = hx, hy = hy, brk = 0, w = {}}
    end
  end
  local last = samples[#samples]
  for _ = 1, 20 do
    t = t + 0.05
    samples[#samples + 1] = {t = t, x = last.x, y = last.y, air = 0, hx = last.hx, hy = last.hy, brk = 0.5, w = {}}
  end
  return {samples = samples, runStartT = samples[1].t}
end

-- Body centre at the box centre: the car's position sits 0.11 m ahead, 0.325 m right of it.
local function parkAt(dx, dy) return {-1.5 + 0.325 + (dx or 0), 33 + 0.11 + (dy or 0)} end

-- Through the gate, right of the cone (it stays on your left), into the box.
local function cleanLine(park)
  return {{0, 0}, {0, 10}, {1.8, 17}, {1.8, 23}, {park[1], 30}, park}
end

local function ctx(time) return {course = COURSE, gates = COURSE.gates, car = COVET, time = time} end
local function check(rule, rec, c) return R.evaluate({rule}, rec, c or ctx()).checks[1] end

function T.the_clean_line_passes_every_a01_rule()
  local g = R.evaluate(A01.rules, drive(cleanLine(parkAt())), ctx())
  for _, c in ipairs(g.checks) do eq(c.ok, true, c.type .. ': ' .. c.text) end
end

function T.cones_passed_names_the_side_to_keep_it_on()
  local wrong = drive({{0, 0}, {0, 10}, {-1.8, 17}, {-1.8, 23}, parkAt()})
  local c = check({type = 'cones_passed'}, wrong)
  eq(c.ok, false, 'wrong side fails')
  has(c.text, 'Went the wrong side of the cone (keep it on your left)')
  local short = check({type = 'cones_passed'}, drive({{0, 0}, {0, 15}}))
  has(short.text, 'Never got past the cone')
  has(check({type = 'cones_passed'}, drive(cleanLine(parkAt()))).text, 'Passed the cone on the correct side')
end

function T.markers_clear_catches_clipping_a_post_or_the_cone()
  -- 0.9 m right of the gate centre: the 0.58 m right side reaches the post at 1.5 m minus 0.15.
  local post = drive({{0, 0}, {0.9, 5}, {0.9, 11}, {1.8, 17}, {1.8, 23}, parkAt()})
  local c = check({type = 'markers_clear'}, post)
  eq(c.ok, false, 'post clipped')
  has(c.text, 'Clipped the right post of the gate')
  -- Passing 1.3 m right of the cone: the car's 1.23 m left side brushes it.
  local cone = drive({{0, 0}, {0, 10}, {1.3, 17}, {1.3, 23}, parkAt()})
  has(check({type = 'markers_clear'}, cone).text, 'Clipped the cone')
  local clean = check({type = 'markers_clear'}, drive(cleanLine(parkAt())))
  eq(clean.ok, true, clean.text)
  has(clean.text, 'Cleared every marker (closest:')
end

function T.park_in_box_wants_the_whole_body_inside()
  eq(check({type = 'park_in_box'}, drive(cleanLine(parkAt()))).ok, true, 'centred')
  local over = check({type = 'park_in_box'}, drive(cleanLine(parkAt(0.845, 0))))
  eq(over.ok, false, '0.845 m right is out')
  has(over.text, 'Front-right corner 0.15 m over the right edge of the box')
  local short = check({type = 'park_in_box'}, drive({{0, 0}, {0, 10}, {1.8, 17}, {1.8, 23}, {-1.2, 26}}))
  has(short.text, 'm short of the box')
  local gold = check({type = 'park_in_box', insetM = 0.5, label = 'gold box'}, drive(cleanLine(parkAt(0.3, 0))))
  has(gold.text, 'over the right edge of the gold box')
end

function T.no_reverse_allows_a_settle_but_not_backing_up()
  local back = cleanLine(parkAt(0, 1))
  back[#back + 1] = {parkAt()[1], parkAt()[2], reverse = true}
  local c = check({type = 'no_reverse', maxM = 0.3}, drive(back))
  eq(c.ok, false, 'a metre back fails')
  has(c.text, 'Reversed 1.0 m')
  local settle = cleanLine(parkAt(0, 0.2))
  settle[#settle + 1] = {parkAt()[1], parkAt()[2], reverse = true}
  eq(check({type = 'no_reverse', maxM = 0.3}, drive(settle)).ok, true, '0.2 m settle is fine')
end

function T.max_time_compares_the_run_time()
  eq(check({type = 'max_time', maxSeconds = 10}, drive({{0, 0}, {0, 5}}), ctx(9.5)).ok, true, 'under')
  local slow = check({type = 'max_time', maxSeconds = 10}, drive({{0, 0}, {0, 5}}), ctx(10.4))
  eq(slow.ok, false, 'over')
  has(slow.text, 'Time 10.4 s (target 10 s)')
end

function T.grade_awards_gold_silver_or_bronze_and_says_what_the_next_needs()
  local centred = drive(cleanLine(parkAt()))
  local g = R.grade(A01, centred, ctx(8))
  eq(g.passed, true, 'pass')
  eq(g.tier, 'gold', 'centred and quick: gold')
  eq(g.nextTier, nil, 'nothing above gold')
  g = R.grade(A01, centred, ctx(12))
  eq(g.tier, 'silver', 'too slow for gold')
  eq(g.nextTier.name, 'gold', 'next is gold')
  has(g.nextTier.text, 'Time 12.0 s (target 10 s)')
  g = R.grade(A01, drive(cleanLine(parkAt(0.5, 0))), ctx(8))
  eq(g.tier, 'bronze', 'in the box, but not the silver box')
  has(g.nextTier.text, 'over the right edge of the silver box')
  for _, c in ipairs(g.checks) do eq(c.ok, true, 'bronze checks are the drill rules: ' .. c.text) end
end

function T.grade_gives_no_medal_for_a_miss_or_a_drill_without_tiers()
  local g = R.grade(A01, drive(cleanLine(parkAt(1.5, 0))), ctx(8))
  eq(g.passed, false, 'out of the box')
  eq(g.tier, nil, 'no medal')
  local plain = R.grade({rules = {{type = 'no_reverse'}}}, drive(cleanLine(parkAt())), ctx(8))
  eq(plain.passed, true, 'passes')
  eq(plain.tier, nil, 'no tiers, no medal')
end

function T.course_rules_explain_a_missing_course()
  local rec = drive({{0, 0}, {0, 5}})
  has(check({type = 'cones_passed'}, rec, {}).text, 'no cones laid out')
  has(check({type = 'park_in_box'}, rec, {}).text, 'no parking box laid out')
  has(check({type = 'markers_clear'}, rec, {}).text, 'no course laid out')
end

return T
