-- A01 through the extension: an authored course laid out at the venue (no marking), live
-- checklist and parking aid, medals, progress, and auto-retry after a graded run.
local L = require('ge/extensions/rallyAcademy/layout')
local H = require('ra_helpers')
local stubs = H.stubs
local eq, has, setup = H.eq, H.has, H.setup
local T = {}

H.stubs.install() -- jsonReadFile, to read the drill data
local SPAWN = H.drills().A01.environment.spawn

-- A01 selected on its own map (the proving ground), so the course starts at the venue spawn.
local function onA01()
  local h, M = setup()
  h.level = 'ra_proving_ground'
  M.select('A01')
  return h, M
end

-- Drive the stub car along course-frame points {x, y} (metres from the venue start: x right,
-- y ahead) at `speed` m/s, the car's sampler reporting every step, then stand still until
-- the run is graded (or `holdFor` seconds pass).
local function driveCourse(h, M, points, opts)
  opts = opts or {}
  local spawn = opts.spawn or SPAWN
  local f = L.frame(spawn)
  local dt, speed = 0.05, opts.speed or 5
  local function step(x, y, hx, hy, v)
    local wx, wy = L.toWorld(f, x, y)
    local dwx, dwy = f.rx * hx + f.fx * hy, f.ry * hx + f.fy * hy
    h.vehicle.dir = stubs.vec3(dwx, dwy, 0)
    h.vehicle.vel = stubs.vec3(dwx * v, dwy * v, 0)
    h.vehicle.pos = stubs.vec3(wx, wy, spawn.pos.z)
    H.simT = H.simT + dt
    M.onTelemetry({id = h.vehicle.id, t = H.simT, x = wx, y = wy, z = spawn.pos.z, air = v,
                   hx = dwx, hy = dwy, brk = v == 0 and 0.5 or 0, w = {}})
    M.onUpdate(dt, dt)
  end
  M.onUpdate(0.1, 0.1) -- settle after the teleport
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    local steps = math.max(1, math.floor(len / (speed * dt)))
    for k = 1, steps do step(a[1] + dx * k / steps, a[2] + dy * k / steps, dx / len, dy / len, speed) end
  end
  local last = points[#points]
  local p0, p1 = points[#points - 1], last
  local dx, dy = p1[1] - p0[1], p1[2] - p0[2]
  local len = math.sqrt(dx * dx + dy * dy)
  for _ = 1, math.floor((opts.holdFor or 3) / dt) do
    step(last[1], last[2], dx / len, dy / len, 0)
    if h.lastState().phase == 'scored' and not opts.keepTicking then break end
  end
  return h.lastState()
end

-- Car position that puts the measured Covet body on the box centre (0.11 m ahead and
-- 0.325 m right of the body centre), plus an offset.
local function parkAt(dx) return {-1.5 + 0.325 + (dx or 0), 33 + 0.11} end
local function cleanLine(park) return {{0, 0}, {0, 10}, {1.8, 17}, {1.8, 23}, {park[1], 30}, park} end

function T.on_its_map_a01_is_ready_with_no_marking()
  local h, M = onA01()
  local s = h.lastState()
  eq(s.hasStart, true, 'the venue spawn is the start')
  eq(s.usingVenueStart, true, 'flagged as the venue start')
  has(s.reason, 'The course is laid out at the venue')
  eq(s.gateCount, 1, 'the course brings its gate')
  eq(s.course.steps[1].label, 'Gate', 'checklist: gate')
  eq(s.course.steps[2].label, 'Cone', 'then the cone')
  eq(s.course.steps[3].label, 'Box', 'then the box')
  eq(s.course.keep, 'left', 'which side to keep the cone')
  M.retry()
  eq(h.lastState().phase, 'ready', 'Retry works straight away')
  eq(h.lastState().course.steps[1].state, 'next', 'gate is next')
end

function T.on_another_map_a01_says_to_go_to_the_drill()
  local h, M = setup() -- driver_training
  M.select('A01')
  local s = h.lastState()
  eq(s.hasStart, false, 'no start away from the venue')
  eq(s.course, false, 'nothing laid out')
  has(s.reason, 'Press Go to drill')
end

function T.go_to_drill_lands_ready_at_the_start_of_the_course()
  local h, M = setup()
  M.select('A01')
  M.goToDrill()
  h.level = 'ra_proving_ground'
  M.onClientPostStartMission('/levels/ra_proving_ground/main.level.json')
  local s = h.lastState()
  eq(s.phase, 'ready', 'straight into a run')
  has(s.reason, 'at the start of the course')
  local tp = h.vehicle.teleports[#h.vehicle.teleports]
  eq(tp.x, SPAWN.pos.x, 'placed at the venue start (x)')
  eq(tp.y, SPAWN.pos.y, 'placed at the venue start (y)')
end

function T.a_clean_centred_quick_run_earns_gold_and_counts_it()
  local h, M = onA01()
  M.setAutoRetry(false)
  M.retry()
  local s = driveCourse(h, M, cleanLine(parkAt()))
  eq(s.phase, 'scored', 'graded when the car stopped')
  eq(s.grade.passed, true, 'pass')
  eq(s.grade.tier, 'gold', 'gold')
  has(s.reason, 'PASS · Gold.')
  has(s.reason, 'Retry for the next attempt')
  eq(s.course.steps[1].state, 'passed', 'gate ticked')
  eq(s.course.steps[2].state, 'passed', 'cone ticked')
  eq(s.course.steps[3].state, 'passed', 'box ticked')
  eq(s.course.fit, 'gold', 'car sits in the gold box')
  local p = jsonReadFile('settings/rallyAcademyProgress.json').lessons.A01
  eq(p.totalPasses, 1, 'pass saved')
  eq(p.bestTier, 'gold', 'best medal saved')
  eq(p.tiers.gold, 1, 'gold counted')
  has(h.logText('rallyAcademy'), 'car footprint: 3.92 m long, 1.81 m wide')
end

function T.a_run_off_centre_earns_bronze_and_says_what_silver_needs()
  local h, M = onA01()
  M.setAutoRetry(false)
  M.retry()
  local s = driveCourse(h, M, cleanLine(parkAt(0.5)))
  eq(s.grade.tier, 'bronze', 'bronze')
  has(s.reason, 'PASS · Bronze.')
  eq(s.grade.nextTier.name, 'silver', 'next medal')
  has(s.grade.nextTier.text, 'over the right edge of the silver box')
  local p = jsonReadFile('settings/rallyAcademyProgress.json').lessons.A01
  eq(p.bestTier, 'bronze', 'best so far')
  M.retry()
  driveCourse(h, M, cleanLine(parkAt()))
  p = jsonReadFile('settings/rallyAcademyProgress.json').lessons.A01
  eq(p.bestTier, 'gold', 'best medal goes up')
  eq(p.tiers.bronze, 1, 'bronze still counted')
end

function T.wrong_side_of_the_cone_is_a_miss_shown_live()
  local h, M = onA01()
  M.setAutoRetry(false)
  M.retry()
  local s = driveCourse(h, M, {{0, 0}, {0, 10}, {-1.8, 17}, {-1.8, 23}, parkAt()})
  eq(s.grade.passed, false, 'miss')
  eq(s.grade.tier, nil, 'no medal')
  eq(s.course.steps[2].state, 'missed', 'cone crossed out')
  has(s.reason, 'MISS: Went the wrong side of the cone (keep it on your left)')
end

function T.clipping_the_gate_post_is_flagged_while_driving()
  local h, M = onA01()
  M.setAutoRetry(false)
  M.retry()
  local s = driveCourse(h, M, {{0, 0}, {0.9, 5}, {0.9, 11}, {1.8, 17}, {1.8, 23}, parkAt()})
  eq(s.course.clipped, 'the right post of the gate', 'clip shown live')
  eq(s.grade.passed, false, 'graded a miss')
  has(s.reason, 'Clipped the right post of the gate')
end

function T.the_parking_aid_reads_out_the_distance_to_the_box()
  local h, M = onA01()
  M.retry()
  driveCourse(h, M, {{0, 0}, {0, 10}, {1.8, 17}, {1.8, 23}, {parkAt()[1], 28}}, {holdFor = 0.2})
  local s = h.lastState()
  has(s.course.aid, 'm to go')
  eq(s.course.fit, false, 'not in a box yet')
end

function T.auto_retry_starts_the_next_attempt_after_three_seconds()
  local h, M = onA01()
  M.retry()
  local teleports = #h.vehicle.teleports
  local s = driveCourse(h, M, cleanLine(parkAt()))
  eq(s.phase, 'scored', 'graded')
  eq(s.autoRetry, true, 'on by default')
  eq(s.autoRetryIn, 3, 'counting down')
  has(s.reason, 'Next attempt in a moment')
  H.tick(M, 1.5)
  eq(h.lastState().autoRetryIn, 2, 'still counting')
  H.tick(M, 1.6)
  eq(h.lastState().phase, 'ready', 'next attempt ready')
  eq(#h.vehicle.teleports, teleports + 1, 'car reset to the start')
  eq(h.lastState().attempts, 1, 'the graded run stays counted')
end

function T.driving_off_cancels_auto_retry_and_the_choice_is_saved()
  local h, M = onA01()
  M.retry()
  driveCourse(h, M, cleanLine(parkAt()))
  h.vehicle.vel = stubs.vec3(5, 0, 0)
  H.tick(M, 0.2)
  eq(h.lastState().autoRetryIn, false, 'cancelled')
  has(h.lastState().reason, 'Auto-retry cancelled')
  H.tick(M, 4)
  eq(h.lastState().phase, 'scored', 'no surprise teleport')
  M.setAutoRetry(false)
  eq(jsonReadFile('settings/rallyAcademy/prefs.json').autoRetry, false, 'preference saved')
  local M2 = H.reloadExtension()
  M2.select('A01')
  eq(h.lastState().autoRetry, false, 'remembered after a reload')
end

function T.mark_start_moves_the_course_and_use_venue_start_puts_it_back()
  local h, M = onA01()
  local before = M.debugState()
  h.vehicle.pos, h.vehicle.dir = stubs.vec3(0, 0, 0), stubs.vec3(0, 1, 0)
  M.markStart()
  has(h.lastState().reason, 'the course is now laid out ahead of you from here')
  eq(h.lastState().usingVenueStart, false, 'your own start')
  eq(before.hasCourse, true, 'course before')
  local g = h.draws
  for i = #g, 1, -1 do g[i] = nil end
  M.onUpdate(0.1, 0.1)
  local sawGate = false
  for _, d in ipairs(h.draws) do
    if math.abs(d.a.y - 8) < 0.01 and math.abs(math.abs(d.a.x) - 1.5) < 0.01 then sawGate = true end
  end
  eq(sawGate, true, 'gate posts drawn 8 m ahead of the new start')
  M.useVenueStart()
  eq(h.lastState().usingVenueStart, true, 'back at the venue')
  eq(jsonReadFile('settings/rallyAcademySetups.json').levels.ra_proving_ground.A01, nil, 'saved start forgotten')
end

function T.leaving_the_map_clears_the_course()
  local h, M = onA01()
  M.onClientEndMission('/levels/west_coast_usa/main.level.json')
  eq(h.lastState().course, false, 'no course on the way out')
  eq(h.lastState().gateCount, 0, 'no gates')
end

function T.course_drills_ignore_mark_finish_and_gate_marking()
  local h, M = onA01()
  M.markFinish()
  M.addGate()
  M.clearGates()
  eq(h.lastState().hasFinish, false, 'no finish circle')
  eq(h.lastState().gateCount, 1, 'still the course gate')
end

function T.the_run_record_carries_the_course_and_footprint_for_fixtures()
  local h, M = onA01()
  M.setAutoRetry(false)
  M.retry()
  driveCourse(h, M, cleanLine(parkAt()))
  local run = M.getLastRun()
  eq(#run.meta.course.cones, 1, 'course in the record')
  eq(run.meta.car.front, 1.85, 'footprint in the record')
end

-- A02: the same course machinery on a straight: one labelled gate, and the run ends there.
function T.a02_lays_out_a_labelled_gate_that_ends_the_run()
  local h, M = setup()
  h.level = 'ra_proving_ground'
  M.select('A02')
  local s = h.lastState()
  eq(s.usingVenueStart, true, 'ready at the venue')
  eq(#s.course.steps, 1, 'just the gate: no stop box')
  eq(s.course.steps[1].label, '40 km/h', 'gate label')
  eq(s.lesson.assessment.endWhen, 'gates', 'the run ends at the gate')
end

-- The stopping targets' live feedback through the same code path (TARGETS): a stop zone (B01) and a
-- stop line (A05), driven towards from their venue starts.
local function approach(h, M, id, metres)
  h.level = H.drills()[id].environment.levelId
  M.select(id)
  local sp = H.drills()[id].environment.spawn
  M.retry()
  M.onUpdate(0.1, 0.1)
  local d = stubs.vec3(sp.dir.x, sp.dir.y, 0):normalized()
  h.vehicle.dir = d
  H.drive(h, M, metres / 10, {x = d.x * 10, y = d.y * 10, z = 0})
  return h.lastState()
end

function T.a_course_stop_zone_reads_out_the_distance_to_its_centre()
  local h, M = setup()
  local s = approach(h, M, 'B01', 130)
  eq(s.course.steps[1].label, 'Stop zone', 'checklist step')
  has(s.course.aid, 'm to the zone centre')
end

function T.a_course_stop_line_reads_out_the_distance_to_it()
  local h, M = setup()
  local s = approach(h, M, 'A05', 45)
  eq(s.course.steps[1].label, 'Stop line', 'checklist step')
  has(s.course.aid, 'm to the line')
end


-- Physical markers (props.lua, ADR 0011): real posts and a cone stand on the course, Retry stands them back up,
-- and knocking one is what fails the run.
local function onA01WithProps()
  local h = stubs.install()
  stubs.installProps(h)
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  h.level = 'ra_proving_ground'
  M.select('A01')
  return h, M
end

function T.a01_lays_out_real_posts_and_a_cone_and_retry_stands_them_up()
  local h, M = onA01WithProps()
  eq(#h.props, 3, 'two gate posts and the cone')
  eq(h.lastState().course ~= false, true, 'course laid out')
  M.retry()
  eq(h.props[3].resets, 1, 'Retry resets the props')
  eq(M.debugState().props, true, 'debug state says so')
end

function T.a01_knocking_the_cone_misses_even_on_a_clean_line()
  local h, M = onA01WithProps()
  M.setAutoRetry(false)
  M.retry()
  h.collisions[h.props[3].id] = true -- the car touches the cone as it passes
  local s = driveCourse(h, M, cleanLine(parkAt()))
  eq(s.grade.passed, false, 'a miss')
  has(s.reason, 'Clipped the cone')
  has(h.logText('rallyAcademy'), 'hit the cone')
end

function T.a01_clean_with_props_still_earns_gold()
  local h, M = onA01WithProps()
  M.setAutoRetry(false)
  M.retry()
  local s = driveCourse(h, M, cleanLine(parkAt()))
  eq(s.grade.tier, 'gold', 'gold')
end

-- F06: crossing a gate with event 'puncture' deflates a random tyre on the car, as the game's own binding does.
function T.f06_puncture_gate_deflates_a_tyre_as_the_car_crosses()
  local h = stubs.install()
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  h.level = 'ra_proving_ground'
  M.select('F06')
  M.setAutoRetry(false)
  M.retry()
  driveCourse(h, M, {{0, 0}, {0, 40}}, {spawn = H.drills().F06.environment.spawn, holdFor = 0.2})
  local deflated = false
  for _, c in ipairs(h.vehicle.luaCommands) do deflated = deflated or c == 'beamstate.deflateRandomTire()' end
  eq(deflated, true, 'a tyre deflated at the Puncture gate')
  has(h.logText('rallyAcademy'), 'F06: puncture at gate 1')
end

-- B03: the driver's mark sits `prediction` metres past the Brake gate; the HUD's buttons move it within the range.
function T.b03_the_mark_follows_the_prediction()
  local h = stubs.install()
  local M = stubs.loadExtension('rallyAcademy')
  M.onExtensionLoaded()
  h.level = 'ra_proving_ground'
  M.select('B03')
  local s = h.lastState()
  eq(s.course.predict.m, 25, 'the default mark')
  eq(s.course.predict.min, 10, 'range from')
  local function markAhead() -- metres ahead of the start, read from the course a run record carries
    local sp = H.drills().B03.environment.spawn
    M.retry()
    local line = M.getLastRun().meta.course.line
    return (line.x - sp.pos.x) * sp.dir.x + (line.y - sp.pos.y) * sp.dir.y
  end
  eq(math.floor(markAhead() + 0.5), 145, 'brake gate at 120 m + 25')
  M.nudgePrediction(5)
  eq(h.lastState().course.predict.m, 30, 'moved')
  eq(math.floor(markAhead() + 0.5), 150, 'the mark moved with it')
  M.setPrediction(99)
  eq(h.lastState().course.predict.m, 45, 'clamped to the range')
  has(h.lastState().reason, 'Your mark: 45 m past the brake line')
end

return T
