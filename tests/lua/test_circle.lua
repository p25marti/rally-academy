-- Course circles (B05, left-foot braking): laying the ring out, how far round and how far off it
-- the car is (layout.lua), the lap, corridor, throttle and brake rules (rules.lua), and laps ending
-- the run through the extension.
local L = require('ge/extensions/rallyAcademy/layout')
local Rules = require('ge/extensions/rallyAcademy/rules')
local H = require('ra_helpers')
local stubs = H.stubs
local eq, near, has = H.eq, H.near, H.has
local T = {}

local E = Rules.evaluators
-- A 15 m ring centred on the origin, driven anticlockwise (left) twice.
local RING = {x = 0, y = 0, radiusM = 15, turn = 'left', laps = 2}
local CTX = {course = {circle = RING}}

-- Samples round RING: `laps` turns (negative = clockwise) at `kmh`, 25 Hz, `off` metres outside the
-- line (a function of the angle, or a number), pedals from `pedals(t)` -> thr, brk.
local function lapSamples(opts)
  local laps, v, r = opts.laps or 2, (opts.kmh or 32) / 3.6, RING.radiusM
  local dt, out = 0.04, {}
  local total = 2 * math.pi * math.abs(laps)
  local dA = v * dt / r * (laps < 0 and -1 or 1)
  local a, t = -math.pi / 2, 0
  for _ = 0, math.floor(total / math.abs(dA)) do
    local off = type(opts.off) == 'function' and opts.off(a) or opts.off or 0
    local thr, brk = 0.3, 0
    if opts.pedals then thr, brk = opts.pedals(t) end
    out[#out + 1] = {t = t, x = (r + off) * math.cos(a), y = (r + off) * math.sin(a), air = v,
                     hx = -math.sin(a), hy = math.cos(a), thr = thr, brk = brk}
    a, t = a + dA, t + dt
  end
  return out
end

function T.a_circle_is_laid_out_from_the_start_with_its_centre_to_the_left()
  local east = {pos = {x = 265, y = 25.05, z = 127}, dir = {x = 1, y = 0, z = 0}}
  local c = L.place({circle = {x = -15, y = 0, radiusM = 15, laps = 2}}, east)
  -- Facing east, left is +y: the dirt circle's centre.
  near(c.circle.x, 265, 1e-9, 'centre x')
  near(c.circle.y, 40.05, 1e-9, 'centre 15 m to the left')
  eq(c.circle.turn, 'left', 'anticlockwise by default')
  eq(c.circle.laps, 2, 'laps carried')
  eq(#c.markers, 0, 'nothing to clip')
end

function T.sweep_counts_the_way_round_and_offset_the_distance_off_the_line()
  near(L.circleSweep(RING, {x = 15, y = 0}, {x = 0, y = 15}), math.pi / 2, 1e-9, 'a quarter anticlockwise')
  near(L.circleSweep(RING, {x = 0, y = 15}, {x = 15, y = 0}), -math.pi / 2, 1e-9, 'back again is negative')
  -- across the -x axis, where atan2 wraps from +pi to -pi
  near(L.circleSweep(RING, {x = -15, y = 1}, {x = -15, y = -1}), 2 * math.atan(1 / 15), 1e-9, 'no jump at the wrap')
  local cw = {x = 0, y = 0, radiusM = 15, turn = 'right'}
  near(L.circleSweep(cw, {x = 0, y = 15}, {x = 15, y = 0}), math.pi / 2, 1e-9, 'clockwise ring counts clockwise')
  near(L.circleOffset(RING, 17, 0), 2, 1e-9, 'outside is positive')
  near(L.circleOffset(RING, 0, -14), -1, 1e-9, 'inside is negative')
end

function T.circle_laps_needs_every_lap_the_right_way_round()
  local ok, text = E.circle_laps({}, lapSamples({}), CTX)
  eq(ok, true, 'two laps'); eq(text, '2 laps anticlockwise', 'text')
  ok, text = E.circle_laps({}, lapSamples({laps = 1.5}), CTX)
  eq(ok, false, 'one and a half'); eq(text, 'Only 1.5 of 2 laps', 'text')
  ok, text = E.circle_laps({}, lapSamples({laps = -2}), CTX)
  eq(ok, false, 'clockwise'); has(text, 'wrong way: drive it anticlockwise')
  ok, text = E.circle_laps({}, lapSamples({}), {})
  eq(ok, false, 'no circle'); has(text, 'no circle')
end

function T.circle_corridor_allows_a_moment_outside_but_not_running_wide()
  local ok, text = E.circle_corridor({widthM = 3}, lapSamples({off = 0.8}), CTX)
  eq(ok, true, 'inside 1.5 m'); eq(text, 'Held the line: 0.8 m off at most (corridor ±1.5 m)', 'text')
  -- 2 m wide for a sliver of the ring: about 0.15 s at 32 km/h
  local blip = function(a) return math.abs(a - 1) < 0.08 and 2 or 0 end
  ok = E.circle_corridor({widthM = 3, maxSeconds = 0.3}, lapSamples({off = blip}), CTX)
  eq(ok, true, 'a moment outside is fine')
  local wide = function(a) return math.abs(a - 1) < 0.5 and 2.4 or 0 end
  ok, text = E.circle_corridor({widthM = 3, maxSeconds = 0.3}, lapSamples({off = wide}), CTX)
  eq(ok, false, 'a second outside'); eq(text, 'Ran 2.40 m wide of the line (corridor ±1.5 m)', 'text')
  ok, text = E.circle_corridor({widthM = 3}, lapSamples({off = -2}), CTX)
  eq(ok, false, 'cutting inside'); has(text, 'inside the line')
end

function T.throttle_held_counts_from_the_speed_and_flags_a_lift()
  local ok, text = E.throttle_held({maxGapSeconds = 0.3}, lapSamples({}))
  eq(ok, true, 'steady'); eq(text, 'Throttle held all the way round', 'text')
  local lift = function(t) return (t > 5 and t < 5.6) and 0 or 0.3, 0 end
  ok, text = E.throttle_held({maxGapSeconds = 0.3}, lapSamples({pedals = lift}))
  eq(ok, false, '0.6 s off'); eq(text, 'Off the throttle for 0.6 s (limit 0.3 s): keep your right foot on', 'text')
  local blip = function(t) return (t > 5 and t < 5.2) and 0 or 0.3, 0 end
  ok, text = E.throttle_held({maxGapSeconds = 0.3}, lapSamples({pedals = blip}))
  eq(ok, true, 'a short lift'); has(text, 'longest lift 0.2 s')
  -- pulling away: a gear change below fromKmh is free
  local s = lapSamples({pedals = lift})
  for _, x in ipairs(s) do if x.t < 6 then x.air = 5 end end
  ok = E.throttle_held({maxGapSeconds = 0.3, fromKmh = 25}, s)
  eq(ok, true, 'before 25 km/h it does not count')
end

function T.left_foot_brakes_counts_dabs_made_on_the_throttle()
  local dabs = function(t) return 0.3, (t % 4 > 2 and t % 4 < 2.4) and 0.3 or 0 end
  local ok, text = E.left_foot_brakes({minCount = 3}, lapSamples({pedals = dabs}))
  eq(ok, true, 'a dab every 4 s'); has(text, 'brake dabs on the throttle (target 3+)')
  local short = function(t) return 0.3, (t % 4 > 2 and t % 4 < 2.1) and 0.3 or 0 end
  ok, text = E.left_foot_brakes({minCount = 3, minSeconds = 0.2}, lapSamples({pedals = short}))
  eq(ok, false, 'too short to count'); has(text, '0 brake dabs')
  local lifted = function(t) local b = (t % 4 > 2 and t % 4 < 2.4); return b and 0 or 0.3, b and 0.3 or 0 end
  ok, text = E.left_foot_brakes({minCount = 3}, lapSamples({pedals = lifted}))
  eq(ok, false, 'braking off the throttle'); has(text, 'you lifted to brake')
  ok, text = E.left_foot_brakes({minCount = 3}, lapSamples({}))
  eq(ok, false, 'no brake'); has(text, 'dab it to tighten the line')
end

-- B06: ring gates at 0, 90, 135 and 180 degrees round RING (facing the way round), the car running
-- `wide(a)` metres outside the line at angle a.
local function ringGate(deg, label)
  local Gates = require('ge/extensions/rallyAcademy/gates')
  local a = math.rad(deg - 90)
  local g = Gates.new({pos = {x = 15 * math.cos(a), y = 15 * math.sin(a), z = 0}, dir = {x = -math.sin(a), y = math.cos(a)}}, 12)
  g.label = label
  return g
end
local B06 = {course = {circle = RING}, gates = {ringGate(5, 'Turn in'), ringGate(90, 'Apex'), ringGate(135, 'Regain'),
                                                ringGate(180, 'Exit')}}
local function pushRun(peak, backBy)
  -- angle from the start (south, -90 degrees): wide builds to `peak` at 90 degrees, gone by `backBy`
  return lapSamples({laps = 0.6, off = function(a)
    local d = math.deg(a) + 90
    if d < 90 then return peak * d / 90 end
    return math.max(0, peak * (1 - (d - 90) / (backBy - 90)))
  end})
end

function T.ran_wide_wants_a_mild_push_between_the_gates()
  local ok, text = E.ran_wide({minM = 1, maxM = 5, fromGate = 1, toGate = 3}, pushRun(3, 130), B06)
  eq(ok, true, '3 m'); eq(text, 'Front pushed 3.0 m wide (target 1-5 m)', 'text')
  ok, text = E.ran_wide({minM = 1, maxM = 5, fromGate = 1, toGate = 3}, pushRun(0.4, 130), B06)
  eq(ok, false, 'no push'); has(text, 'carry more speed in')
  ok, text = E.ran_wide({minM = 1, maxM = 5, fromGate = 1, toGate = 3}, pushRun(7, 130), B06)
  eq(ok, false, 'too much'); eq(text, 'Ran 7.0 m wide (limit 5 m): too fast in, the push got away', 'text')
end

function T.back_on_line_by_gate_reads_the_offset_where_the_car_crosses_it()
  local ok, text = E.back_on_line_by_gate({gate = 3, maxM = 1}, pushRun(3, 130), B06)
  eq(ok, true, 'back by the regain'); has(text, 'Back on the line by the regain (0.0 m off')
  ok, text = E.back_on_line_by_gate({gate = 3, maxM = 1}, pushRun(3, 200), B06)
  eq(ok, false, 'still wide'); has(text, 'wide of the line at the regain (target 1 m): ease off sooner')
  ok = E.back_on_line_by_gate({gate = -1, maxM = 1.5}, pushRun(3, 200), B06)
  eq(ok, true, 'back by the exit')
end

-- B05 through the extension: laid out at its venue, laps counted live, the run ending after the last.
local function onB05()
  local h, M = H.setup()
  h.level = 'ra_proving_ground'
  M.select('B05')
  M.retry()
  M.onUpdate(0.1, 0.1)
  return h, M
end

-- Drive the stub car `laps` turns further round the B05 ring at 9 m/s (h.ringAngle carries on
-- from the last call).
local function driveRing(h, M, laps, pedals)
  local sp = H.drills().B05.environment.spawn
  local cx, cy, r = sp.pos.x, sp.pos.y + 15, 15 -- facing east: the centre is 15 m north
  local v, dt = 9, 0.05
  local a, t = h.ringAngle or -math.pi / 2, h.ringT or 0
  local steps = math.floor(laps * 2 * math.pi * r / (v * dt))
  for _ = 1, steps do
    a, t = a + v * dt / r, t + dt
    local x, y = cx + r * math.cos(a), cy + r * math.sin(a)
    local hx, hy = -math.sin(a), math.cos(a)
    local thr, brk = 0.3, 0
    if pedals then thr, brk = pedals(t) end
    h.vehicle.dir = stubs.vec3(hx, hy, 0)
    h.vehicle.vel = stubs.vec3(hx * v, hy * v, 0)
    h.vehicle.pos = stubs.vec3(x, y, sp.pos.z)
    H.simT = H.simT + dt
    M.onTelemetry({id = h.vehicle.id, t = H.simT, x = x, y = y, z = sp.pos.z, air = v, hx = hx, hy = hy,
                   thr = thr, brk = brk, w = {}})
    M.onUpdate(dt, dt)
    if h.lastState().phase == 'scored' then break end
  end
  h.ringAngle, h.ringT = a, t
  for _ = 1, 20 do
    if h.lastState().phase == 'scored' then break end
    H.simT = H.simT + dt
    M.onUpdate(dt, dt)
  end
  return h.lastState()
end

function T.b05_counts_laps_live_and_grades_after_the_second()
  local h, M = onB05()
  local s = h.lastState()
  eq(s.course.steps[1].label, 'Lap 1', 'lap steps first')
  eq(s.course.steps[3].label, 'Hold the line', 'then the corridor')
  local dabs = function(t) return 0.3, (t % 4 > 2 and t % 4 < 2.4) and 0.3 or 0 end
  s = driveRing(h, M, 1.2, dabs)
  eq(s.phase, 'running', 'still running after one lap')
  eq(s.course.steps[1].state, 'passed', 'lap 1 ticked')
  has(s.course.aid, 'the line')
  s = driveRing(h, M, 1.5, dabs)
  eq(s.phase, 'scored', 'ends after two laps')
  eq(s.successes, 1, 'a pass')
  has(h.logText('rallyAcademy'), 'B05: lap 2 of 2')
end

function T.a_circle_drill_that_ends_at_gates_has_no_lap_steps()
  local h, M = H.setup()
  h.level = 'ra_proving_ground'
  M.select('B06')
  M.retry()
  M.onUpdate(0.1, 0.1)
  eq(h.lastState().course.steps[1].label, 'Turn in', 'gates first, no laps')
end

function T.b05_without_brake_dabs_is_a_miss()
  local h, M = onB05()
  local s = driveRing(h, M, 2.5)
  eq(s.phase, 'scored', 'graded')
  eq(s.successes, 0, 'miss')
  has(s.reason, 'brake dabs on the throttle')
end

return T
