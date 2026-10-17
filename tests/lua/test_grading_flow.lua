-- Automatic grading through the extension (B01 stop zone, catalogue rules).
local H = require('ra_helpers')
local stubs = H.stubs
local eq = H.eq
local setup = H.setup
local markStartAndFinish = H.markStartAndFinish
local brakingRun = H.brakingRun
local setupB01 = H.setupB01
local T = {}

-- With these defaults (70 km/h, braking at 80 m, 7 m/s2) the car stops near y = 107.
function T.b01_clean_stop_in_the_zone_is_graded_pass()
  local h, M = setupB01(107)
  local s = brakingRun(h, M, {})
  eq(s.phase, 'scored', 'graded and recorded on its own')
  eq(s.attempts, 1, 'one attempt')
  eq(s.successes, 1, 'counted as a pass')
  eq(s.grade.passed, true, 'grade passed')
  eq(#s.grade.checks, 3, 'three checks shown')
  assert(s.reason:find('PASS', 1, true), s.reason)
  local saved = jsonReadFile('settings/rallyAcademyProgress.json').lessons.B01
  eq(saved.totalPasses, 1, 'pass saved')
  eq(M.getLastRun().grade.passed, true, 'grade kept on the run record')
end

function T.b01_overshoot_is_graded_miss_with_the_reason()
  local h, M = setupB01(95)
  local s = brakingRun(h, M, {})
  eq(s.successes, 0, 'miss')
  eq(s.attempts, 1, 'recorded')
  assert(s.reason:find('MISS: Stopped', 1, true) and s.reason:find('past the zone', 1, true), s.reason)
end

function T.b01_locked_stop_is_graded_miss_for_lockup()
  local h, M = setupB01(107)
  local s = brakingRun(h, M, {lockFor = 1.5})
  eq(s.grade.passed, false, 'failed')
  local lock = s.grade.checks[3]
  eq(lock.ok, false, 'lockup check failed')
  assert(lock.text:find('locked for', 1, true), lock.text)
end

function T.b01_marking_says_stop_zone_and_the_run_ends_on_stopping()
  local h, M = setupB01(107)
  -- (setupB01 marked the zone; check the message it left)
  assert(h.lastState().reason:find('Stop zone centre marked', 1, true), h.lastState().reason)
  M.retry()
  -- drive past the start then sit still: run should end even far from any finish circle
  for _ = 1, 20 do h.vehicle.vel = stubs.vec3(0, 10, 0); h.vehicle.pos = h.vehicle.pos + stubs.vec3(0, 0.5, 0); M.onUpdate(0.05, 0.05) end
  h.vehicle.vel = stubs.vec3(0, 0, 0)
  for _ = 1, 40 do M.onUpdate(0.05, 0.05) end
  eq(h.lastState().attempts, 1, 'ended on stopping and was graded')
end

-- The HUD merges each published state into the last one, so "no grade" must be sent
-- explicitly or the previous drill's checks stay on screen.
function T.changing_drill_clears_the_shown_grade()
  local h, M = setupB01(107)
  brakingRun(h, M, {})
  assert(h.lastState().grade, 'graded first')
  M.select('A06')
  eq(h.lastState().grade, false, 'grade cleared on drill change')
end

function T.self_assessed_drills_still_wait_for_pass_or_miss()
  local h, M = setup()
  markStartAndFinish(h, M, 'B04')
  M.retry()
  for _ = 1, 100 do h.vehicle.vel = stubs.vec3(0, 20, 0); h.vehicle.pos = h.vehicle.pos + stubs.vec3(0, 2, 0); M.onUpdate(0.1, 0.1) end
  local s = h.lastState()
  eq(s.phase, 'review', 'waiting for the driver')
  eq(s.attempts, 0, 'not recorded automatically')
  eq(s.grade, false, 'no automatic grade')
end

function T.every_rule_in_the_drill_data_is_known_with_its_parameters()
  stubs.install()
  local Rules = require('ge/extensions/rallyAcademy/rules')
  for _, e in ipairs(jsonReadFile('gameplay/rallyAcademy/exercises.json').exercises) do
    for _, rule in ipairs(e.assessment.rules or {}) do
      local params = Rules.TYPES[rule.type]
      assert(params, e.id .. ': unknown rule type ' .. tostring(rule.type))
      for _, k in ipairs(params) do assert(type(rule[k]) == 'number', e.id .. ': ' .. rule.type .. ' needs ' .. k) end
    end
  end
end

-- Auto-retry (on by default) follows a graded B01 run once the zone is marked, but not the
-- first run, which is the one you mark the stop zone from.
function T.auto_retry_waits_until_the_stop_zone_is_marked()
  local h, M = setup()
  M.select('B01')
  h.vehicle.pos, h.vehicle.dir = stubs.vec3(0, 0, 0), stubs.vec3(0, 1, 0)
  M.markStart()
  local s = brakingRun(h, M, {})
  eq(s.phase, 'scored', 'graded (a miss: no zone)')
  eq(s.autoRetryIn, false, 'no countdown without a zone')
  M.markFinish()
  s = brakingRun(h, M, {})
  eq(s.autoRetryIn, 3, 'counting down once the zone is marked')
end

return T
