-- Gates through the extension: marking, live feedback, A04 grading, drawing.
local H = require('ra_helpers')
local stubs = H.stubs
local near = H.near
local eq = H.eq
local setup = H.setup
local reloadExtension = H.reloadExtension
local has = H.has
local setupB01 = H.setupB01
local setupA04 = H.setupA04
local gateRun = H.gateRun
local T = {}

function T.a04_steady_speed_through_three_gates_is_graded_pass()
  local h, M = setupA04()
  eq(h.lastState().gateCount, 3, 'three gates marked')
  local s = gateRun(h, M, {})
  eq(s.phase, 'scored', 'ends at the last gate and is graded')
  eq(s.successes, 1, 'pass recorded')
  eq(#s.grade.checks, 2, 'speed and braking checks')
  has(s.grade.checks[1].text, '30 / 30 / 30 km/h')
  local log = h.logText('rallyAcademy')
  has(log, 'gate 1 passed at 30 km/h')
  has(log, 'A04: last gate in')
  eq(#M.getLastRun().meta.gates, 3, 'gates kept with the run record')
end

-- Found in-game: the run ended on the frame of the last gate, before the car's sample
-- past it had arrived, so grading saw "gate 3 not reached".
function T.a04_grades_the_last_gate_when_telemetry_lags_a_frame()
  local h, M = setupA04()
  local s = gateRun(h, M, {lag = true})
  eq(s.phase, 'scored', 'graded')
  has(s.grade.checks[1].text, '30 / 30 / 30 km/h')
  eq(s.successes, 1, 'pass')
  near(s.lastTime, 90 / (30 / 3.6), 0.2, 'timed at the last gate, not after the grading delay')
end

function T.a04_too_fast_or_braking_between_gates_is_a_miss()
  local h, M = setupA04()
  local s = gateRun(h, M, {kmhAt = function(y) return y > 70 and 38 or 30 end})
  eq(s.phase, 'scored', 'graded')
  eq(s.successes, 0, 'miss')
  has(s.reason, 'MISS: Gate speeds 30 / 30 / 38 km/h')
  s = gateRun(h, M, {brakeAt = function(y) return y > 50 and y < 52 end})
  eq(s.grade.checks[2].ok, false, 'braking check failed')
  has(s.reason, 'Braked between gates 1 and 3')
end

function T.live_gate_feedback_names_the_gate_and_speed()
  local h, M = setupA04()
  gateRun(h, M, {giveUpAtY = 50})
  eq(h.lastState().phase, 'running', 'still between gates')
  eq(h.lastState().reason, 'Gate 1 of 3: 30 km/h', 'live message')
end

function T.add_gate_stops_at_the_drill_count_and_clear_gates_resets()
  local h, M = setupA04()
  M.addGate()
  has(h.lastState().reason, 'All 3 gates are marked')
  eq(h.lastState().gateCount, 3, 'no fourth gate')
  M.clearGates()
  eq(h.lastState().gateCount, 0, 'cleared')
  has(h.lastState().reason, 'press + Gate')
end

function T.gates_are_saved_per_map_and_reloaded()
  local h = setupA04()
  local M = reloadExtension()
  M.select('A04')
  eq(h.lastState().gateCount, 3, 'gates restored after a restart')
  h.level = 'utah'
  M.onClientEndMission('/levels/west_coast_usa/')
  M.onClientPostStartMission('/levels/utah/')
  eq(h.lastState().gateCount, 0, 'no gates on another map')
end

function T.pass_is_refused_mid_run_when_the_run_ends_at_a_gate()
  local h, M = setupA04()
  gateRun(h, M, {giveUpAtY = 20})
  eq(h.lastState().phase, 'running', 'mid-run')
  M.recordAttempt(true)
  has(h.lastState().reason, 'Finish the run to score a pass')
end

function T.gate_drill_without_gates_says_to_mark_them_on_retry()
  local h, M = setup()
  M.select('A04')
  h.vehicle.pos = stubs.vec3(0, 0, 0)
  M.markStart()
  M.retry()
  has(h.lastState().reason, 'No gates marked yet')
end

function T.gates_are_drawn_with_the_next_one_highlighted()
  local h, M = setupA04()
  h.draws = {}
  M.onUpdate(0.1, 0.1)
  eq(#h.draws, 9, 'two posts and a bar per gate')
  M.retry()
  h.draws = {}
  M.onUpdate(0.1, 0.1)
  local c = h.draws[1].colour
  eq(c.r == 1 and c.g > 0.8 and c.b < 0.2, true, 'first gate drawn yellow once a run is armed')
  -- posts stand at the gate's edges: 10 m wide, so x = -5 and +5
  eq(h.draws[1].a.x, -5, 'left post')
  eq(h.draws[2].a.x, 5, 'right post')
end

function T.b01_stop_zone_is_drawn()
  local h, M = setupB01(107)
  h.draws = {}
  M.onUpdate(0.1, 0.1)
  eq(#h.draws, 4, 'four sides of the zone')
end

return T
