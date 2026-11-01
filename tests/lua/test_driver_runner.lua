-- The driver's skill runner (tools/driver/runner.lua, docs/DRIVER.md): its pure core, on synthetic runs.
local root = (arg and arg[1]) or '.'
local Run = dofile(root .. '/tools/driver/runner.lua')
local R = require('ge.extensions.rallyAcademy.rules')

local T = {}

local DIALS = {
  approachKmh = 66, feintAfterM = 14,
  feintSteer = 0.5, feintMinS = 0.2, feintMaxS = 0.7, feintYawDeg = 3,
  turnSteer = 1.0, loadBrake = 1.0, loadUnwindDegS = 20, loadMinS = 0.1, loadMaxS = 0.8,
  catchGain = 0.0, catchKmh = 45, settleSlipDeg = 5, catchMaxS = 2.5,
  exitKmh = 45,
}
local LIMITS = {reactionMs = 150, steerRatePerS = 4.0, pedalRatePerS = 8.0, decisionHz = 20}

local function straight()
  local path = {}
  for i = 0, 200 do path[#path + 1] = {0, i} end
  return path
end

local function driver(dials)
  local k = {}
  for n, v in pairs(DIALS) do k[n] = v end
  for n, v in pairs(dials or {}) do k[n] = v end
  return Run.new({dials = k, limits = LIMITS, path = straight(), flickS = 40, exitS = 120})
end

-- An observation at `y` m along the straight, heading `yawDeg` left of north, travelling `travelDeg` left of north.
local function obs(y, kmh, yawDeg, travelDeg)
  local h, t, v = math.rad(yawDeg or 0), math.rad(travelDeg or yawDeg or 0), (kmh or 60) / 3.6
  return {x = 0, y = y, hx = -math.sin(h), hy = math.cos(h), vx = -math.sin(t) * v, vy = math.cos(t) * v}
end

local function eq(a, b, msg) assert(a == b, (msg or '') .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a)) end

function T.slip_sign_matches_the_grader()
  for _, case in ipairs({{10, 0}, {0, 10}, {-20, -5}, {30, 30}}) do
    local o = obs(0, 50, case[1], case[2])
    local mine = Run.signedSlipDeg(o.hx, o.hy, o.vx, o.vy)
    local graders = R.signedSlipDeg({hx = o.hx, hy = o.hy, vx = o.vx, vy = o.vy}, 3, 'left')
    assert(math.abs(mine - graders) < 1e-9, string.format('%s vs %s', mine, graders))
  end
  assert(Run.signedSlipDeg(obs(0, 50, 12, 0).hx, obs(0, 50, 12, 0).hy, obs(0, 50, 12, 0).vx, obs(0, 50, 12, 0).vy) > 0,
    'pointing further left than travelling is the rear stepping out of a left turn')
end

function T.limit_moves_at_most_rate_times_dt()
  eq(Run.limit(0, 1, 4, 0.05), 0.2, 'rising')
  eq(Run.limit(0.5, -1, 4, 0.05), 0.3, 'falling')
  eq(Run.limit(0.9, 1, 4, 0.05), 1, 'reaches the target')
end

function T.approach_follows_the_line_and_holds_speed_until_past_the_flick_gate()
  local d = driver()
  local o = Run.decide(d, obs(30, 50), 0.05)
  eq(d.phase, 'approach')
  assert(o.throttle > 0 and o.brake == 0, 'below the target speed it accelerates')
  Run.decide(d, obs(53, 66), 0.05)
  eq(d.phase, 'approach', 'not yet feintAfterM past the gate')
  Run.decide(d, obs(54.5, 66), 0.05)
  eq(d.phase, 'feint')
end

function T.feint_steers_away_and_ends_once_turned_far_enough_plus_the_reaction_time()
  local d = driver()
  Run.decide(d, obs(54.5, 66), 0.05)
  eq(d.phase, 'feint')
  -- turning right (away from the left turn) 1 degree per decision: 3 degrees after the 3rd decision, but feintMinS
  -- (0.2 s) holds until the 4th; then the 150 ms reaction time holds the phase for 3 decisions
  local seen
  for i = 1, 12 do
    local o = Run.decide(d, obs(55 + i, 66, -i), 0.05)
    if i == 1 then assert(o.steering > 0, 'steers right, away from the corner') end
    if d.phase ~= 'feint' and not seen then seen = i end
  end
  eq(seen, 6, 'the decision the feint ended')
end

function T.feint_ends_at_its_time_limit_if_the_car_doesnt_turn()
  local d = driver()
  Run.decide(d, obs(54.5, 66), 0.05)
  local n = 0
  while d.phase == 'feint' and n < 50 do
    n = n + 1
    Run.decide(d, obs(55 + n, 66, 0), 0.05)
  end
  eq(n, 14, 'decisions until feintMaxS (0.7 s)')
end

function T.load_turns_in_with_brake_until_the_swing_away_stops()
  local d = driver()
  d.phase, d.out.steering = 'load_turn_in', 0.5
  local yaw = 0
  local function step(rate)
    yaw = yaw + rate * 0.05
    return Run.decide(d, obs(70, 60, yaw, 0), 0.05)
  end
  d.lastYaw = 0
  local o = step(-40)
  assert(o.brake > 0, 'brakes')
  eq(o.steering, 0.3, 'steering towards full left lock, at the rate limit')
  step(-35)
  step(-30) -- still swinging away faster than loadUnwindDegS
  eq(d.phase, 'load_turn_in')
  step(-15) step(-10) -- slowed below 20 degrees/s: the reaction time runs
  eq(d.phase, 'load_turn_in', 'waiting out the reaction time (150 ms: the 3rd decision)')
  step(-5)
  eq(d.phase, 'catch')
end

function T.report_records_the_slip_between_the_gates_and_the_exit_speed()
  local d = driver()
  Run.decide(d, obs(30, 60, 25, 0), 0.05) -- before the Flick gate: not counted
  Run.decide(d, obs(80, 60, 14, 0), 0.05)
  Run.decide(d, obs(121, 41, 0, 0), 0.05)
  assert(math.abs(d.report.maxSlip - 14) < 1e-6, 'max slip ' .. d.report.maxSlip)
  assert(math.abs(d.report.exitKmh - 41) < 1e-6, 'exit speed ' .. tostring(d.report.exitKmh))
end

function T.stop_brakes_then_holds_the_handbrake()
  local d = driver()
  d.phase = 'stop'
  local o = Run.decide(d, obs(140, 30), 0.05)
  assert(o.brake > 0 and o.handbrake == 0, 'brakes while moving')
  Run.decide(d, obs(141, 2), 0.05)
  o = Run.decide(d, obs(141, 0.5), 0.05)
  eq(o.handbrake, 1, 'handbrake once slow')
end

return T
