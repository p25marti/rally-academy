-- Unit tests for gate geometry (pure) and the gate rules, on synthetic runs.
local G = require('ge/extensions/rallyAcademy/gates')
local R = require('ge/extensions/rallyAcademy/rules')
local T = {}

local function eq(actual, expected, msg)
  if actual ~= expected then
    error(('%s: expected %s, got %s'):format(msg or 'mismatch', tostring(expected), tostring(actual)), 2)
  end
end
local function near(actual, expected, tol, msg)
  if math.abs(actual - expected) > tol then
    error(('%s: expected %s +/- %s, got %s'):format(msg or 'mismatch', expected, tol, actual), 2)
  end
end
local function has(text, needle)
  if not tostring(text):find(needle, 1, true) then error(('expected %q in %q'):format(needle, tostring(text)), 2) end
end

-- A gate across the y axis at `y`, facing +y (north), `width` wide, centred on x = 0.
local function gateAt(y, width)
  return G.new({pos = {x = 0, y = y, z = 0}, dir = {x = 0, y = 1, z = 0}}, width or 10)
end

-- Driving north along x = `x` at a speed given per metre by kmhAt(y) (default 30), 30 Hz.
-- brakeFrom/brakeTo: brake pressed between those y values.
local function run(opts)
  local dt, y, t, samples = 1 / 30, 0, 0, {}
  local kmhAt = opts.kmhAt or function() return 30 end
  while y < (opts.toY or 120) do
    local v = kmhAt(y) / 3.6
    y = y + v * dt
    t = t + dt
    local braking = opts.brakeFrom and y >= opts.brakeFrom and y <= opts.brakeTo
    samples[#samples + 1] = {t = t, x = opts.x or 0, y = y, z = 0, air = v, brk = braking and 0.6 or 0}
  end
  return {samples = samples, runStartT = samples[1].t}
end

local A04 = {{type = 'speed_at_gates', minKmh = 27, maxKmh = 33}, {type = 'no_brake_between_gates'}}
local function threeGates(width) return {gateAt(40, width), gateAt(65, width), gateAt(90, width)} end

-- Geometry --------------------------------------------------------------------

function T.crossing_forwards_through_the_middle_counts()
  local c = G.crossing(gateAt(10), {x = 1, y = 9}, {x = 1, y = 11})
  assert(c, 'crossed')
  near(c.f, 0.5, 1e-9, 'halfway between the samples')
  near(c.offset, 1, 1e-9, '1 m right of centre')
  eq(c.inside, true, 'inside the 10 m gate')
end

function T.crossing_backwards_or_not_at_all_does_not_count()
  eq(G.crossing(gateAt(10), {x = 0, y = 11}, {x = 0, y = 9}), nil, 'reversing through')
  eq(G.crossing(gateAt(10), {x = 0, y = 5}, {x = 0, y = 9}), nil, 'short of the gate')
  eq(G.crossing(gateAt(10), {x = 0, y = 10.5}, {x = 0, y = 12}), nil, 'already past')
end

function T.crossing_beside_the_gate_is_a_miss_with_its_side()
  local c = G.crossing(gateAt(10, 6), {x = -5, y = 9}, {x = -5, y = 11})
  assert(c, 'reached the gate line')
  eq(c.inside, false, 'outside a 6 m gate')
  near(c.offset, -5, 1e-9, 'left of centre is negative')
  eq(G.missText(gateAt(10, 6), c.offset), '2.0 m left of it', 'miss text')
end

function T.crossing_the_line_far_away_is_not_this_gate()
  eq(G.crossing(gateAt(10, 6), {x = 40, y = 9}, {x = 40, y = 11}), nil, '40 m away')
end

function T.gates_follow_the_marked_heading()
  -- Facing east: the line runs north-south, and north of centre is the driver's left.
  local g = G.new({pos = {x = 50, y = 0, z = 0}, dir = {x = 2, y = 0, z = 0.1}}, 8)
  near(g.dir.x, 1, 1e-9, 'heading normalised flat')
  local c = G.crossing(g, {x = 49, y = 2}, {x = 51, y = 2})
  assert(c and c.inside, 'through, 2 m off centre')
  near(c.offset, -2, 1e-9, 'north = left when facing east')
end

function T.passes_records_time_and_speed_at_each_gate_in_order()
  local rec = run({kmhAt = function(y) return y < 50 and 30 or 36 end})
  local p = G.passes(threeGates(), rec.samples)
  eq(#p, 3, 'one entry per gate')
  for i = 1, 3 do eq(p[i].reached, true, 'gate ' .. i .. ' reached') end
  near(p[1].kmh, 30, 0.01, 'speed at gate 1')
  near(p[3].kmh, 36, 0.01, 'speed at gate 3')
  near(p[1].t, 40 / (30 / 3.6), 0.05, 'time at gate 1')
  assert(p[1].t < p[2].t and p[2].t < p[3].t, 'in order')
end

function T.a_gate_short_of_the_run_is_not_reached()
  local p = G.passes(threeGates(), run({toY = 70}).samples)
  eq(p[2].reached, true, 'gate 2 reached')
  eq(p[3].reached, false, 'gate 3 not reached')
end

-- Rules -------------------------------------------------------------------------

function T.steady_30_through_three_gates_passes_a04()
  local res = R.evaluate(A04, run({}), {gates = threeGates()})
  eq(res.passed, true, 'passed')
  eq(res.checks[1].text, 'Gate speeds 30 / 30 / 30 km/h (band 27-33)', 'speeds listed')
  eq(res.checks[2].text, 'No braking between gates 1 and 3', 'no brake')
end

function T.too_fast_at_one_gate_fails_and_names_it()
  local res = R.evaluate(A04, run({kmhAt = function(y) return y > 80 and 36 or 30 end}), {gates = threeGates()})
  eq(res.passed, false, 'failed')
  has(res.checks[1].text, '30 / 30 / 36 km/h')
  has(res.checks[1].text, 'gate 3 too fast')
end

function T.braking_between_gates_fails_but_braking_before_them_does_not()
  local between = R.evaluate(A04, run({brakeFrom = 70, brakeTo = 72}), {gates = threeGates()})
  eq(between.checks[2].ok, false, 'brake between gates 2 and 3')
  has(between.checks[2].text, 'Braked between gates 1 and 3 (at 30 km/h)')
  local before = R.evaluate(A04, run({brakeFrom = 20, brakeTo = 25}), {gates = threeGates()})
  eq(before.checks[2].ok, true, 'brake before gate 1 is the build-up')
end

function T.speed_at_one_gate_only()
  local rule = {{type = 'speed_at_gates', minKmh = 25, maxKmh = 200, gate = -1}}
  local res = R.evaluate(rule, run({kmhAt = function(y) return y > 80 and 24 or 40 end}), {gates = threeGates()})
  eq(res.passed, false, 'last gate too slow')
  eq(res.checks[1].text, 'Gate 3: 24 km/h (band 25-200): gate 3 too slow', 'only the last gate')
end

function T.gates_passed_reports_misses_and_unreached_gates()
  local rule = {{type = 'gates_passed'}}
  eq(R.evaluate(rule, run({}), {gates = threeGates(6)}).checks[1].text, 'All 3 gates passed', 'clean')
  local wide = R.evaluate(rule, run({x = 4}), {gates = threeGates(6)})
  eq(wide.passed, false, 'driving 4 m right of 6 m gates')
  eq(wide.checks[1].text, 'Missed gate 1 (1.0 m right of it)', 'first miss named')
  eq(R.evaluate(rule, run({toY = 50}), {gates = threeGates()}).checks[1].text, 'Gate 2 not reached', 'short run')
end

function T.gate_rules_without_gates_say_how_to_mark_them()
  local res = R.evaluate(A04, run({}), {gates = {}})
  eq(res.passed, false, 'cannot pass')
  has(res.checks[1].text, 'press + Gate')
end

return T
