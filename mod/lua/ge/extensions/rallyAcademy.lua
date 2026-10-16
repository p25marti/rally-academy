-- Rally Academy (BeamNG GE Lua extension): drill session, timing, grading, progress.
-- Design: docs/ARCHITECTURE.md. Engine API status: docs/BEAMNG_API_NOTES.md.
-- UI calls extensions.load('rallyAcademy') and extensions.rallyAcademy.<method>().
local M = {}
-- Re-read our pure modules whenever the extension (re)loads: extensions.reload re-runs
-- this file but `require` would keep the old modules (seen on 0.39.4).
for _, name in ipairs({'runRecord', 'rules', 'gates', 'store', 'course'}) do package.loaded['ge/extensions/rallyAcademy/' .. name] = nil end
local RunRecord = require('ge/extensions/rallyAcademy/runRecord')
local Rules = require('ge/extensions/rallyAcademy/rules')
local Gates = require('ge/extensions/rallyAcademy/gates')
local Store = require('ge/extensions/rallyAcademy/store')
local Course = require('ge/extensions/rallyAcademy/course')
local LESSONS_FILE = 'gameplay/rallyAcademy/exercises.json'
local lessons, byId, lessonSummary = {}, {}, {}
local progress = {schemaVersion = 1, lessons = {}} -- store.lua has the file formats
local setups = {schemaVersion = 1, levels = {}}
local selected, startState, finishGate = nil, nil, nil
local phase, lastReason = 'idle', ''
local attempts, successes = 0, 0
local activeVehicleId = nil
-- Telemetry (docs/decisions/0004): the current or most recent attempt's record.
local TELEMETRY_RATE = 60
local LAST_RUN_FILE = 'settings/rallyAcademy/lastRun.json'
local run, samplingVehId = nil, nil
-- Gates (gates.lua) marked for the selected drill on this map, in driving order.
local gates = {}
-- The car's telemetry reaches GE about a frame late (0.39.4), so after the last gate the
-- run keeps recording briefly before it is graded; the time is taken at the gate.
local GRADE_DELAY = 0.3 -- s of sim time

-- Per-run state. resetRun() replaces it wholesale (Retry, drill change, abandoned run, Go to
-- drill), so nothing from one run leaks into the next.
--   elapsed, lastTime  run clock and final time (s of sim time); grade = last automatic grade
--   settleT, originPos the repair-teleport can nudge the car ~2 m a frame after it lands
--                      (0.39.4, next to barriers), so the start arms SETTLE_FOR after Retry and
--                      departure is measured from the last spot the car was slow at
--   stillT             how long the car has been standing still (endWhen 'stopped')
--   gateIdx, gateResults, prevPos  next gate, each gate's live result, last frame's position
--   endingIn, endTime  grading delay after the last gate, and the time taken at the gate
--   uiAccum            time since the last HUD update
local cur
local function resetRun()
  cur = {elapsed = 0, lastTime = nil, grade = nil, settleT = 0, originPos = nil, stillT = 0,
         gateIdx = 1, gateResults = {}, prevPos = nil, endingIn = nil, endTime = nil, uiAccum = 0}
end
resetRun()
local SETTLE_SPEED, SETTLE_FOR = 0.5, 0.2 -- m/s, s
local STOPPED_SPEED, STOPPED_FOR, STOPPED_MIN_DIST = 0.3, 0.5, 5 -- m/s, s, m from the start
-- Go to drill: drill waiting for its map to load; car swap in progress; deferred placement.
local pendingGoTo, arriveIn = nil, nil
local awaitingCar, awaitT = nil, 0 -- configPath we're waiting to see spawn, and how long we've waited
local SETTLE_AFTER_SPAWN = 0.3     -- s after onVehicleSpawned before teleporting the new car
local SPAWN_TIMEOUT = 6            -- s: place the car anyway if onVehicleSpawned never comes
local placeAtDrill -- defined under "Go to drill"; onUpdate (above it) calls it
-- Started from the main-menu Academy screen: switch the UI to the game view on arrival
-- (the game's own main-menu exit does this; our screen isn't part of that flow).
local leaveMenuOnArrival = false

-- beamng.log lines read `|I|GELua.rallyAcademy.rallyAcademy| ...` (extension + tag);
-- `python tools/dev.py log --ours` shows only these.
local LOG_TAG = 'rallyAcademy'
local function logf(level, fmt, ...)
  log(level, LOG_TAG, string.format(fmt, ...))
end

local function currentVehicle()
  return be and be:getPlayerVehicle(0) or nil
end

local function levelId()
  local id = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  return (type(id) == 'string' and id ~= '') and id or 'unknown'
end

local function snapshotVehicle()
  local veh = currentVehicle()
  if not veh then return nil end
  local pos = veh:getPosition()
  local forward = vec3(veh:getDirectionVector()):normalized()
  local up = vec3(veh:getDirectionVectorUp()):normalized()
  return {
    vehicleId = veh:getID(),
    pos = {x=pos.x, y=pos.y, z=pos.z},
    dir = {x=forward.x, y=forward.y, z=forward.z},
    up = {x=up.x, y=up.y, z=up.z}
  }
end

-- Teleport to the start and repair the car, the way the game's own reset tooling
-- does (spawn.safeTeleport with resetVehicle = true: restores undamaged node
-- positions, zeroes velocity, snaps to the ground; nudges the car if something is
-- in the way). safeTeleport turns the car 180 degrees itself, so it takes the
-- rotation built from the plain direction vector, unlike setPositionRotation.
local function teleportToStart(veh, s)
  local rot = quatFromDir(vec3(s.dir.x, s.dir.y, s.dir.z), vec3(s.up.x, s.up.y, s.up.z))
  spawn.safeTeleport(veh, vec3(s.pos.x, s.pos.y, s.pos.z), rot, nil, nil, nil, nil, true)
end

-- Load the sampler into the car and start it; it reports to M.onTelemetry.
local function startSampling(veh)
  samplingVehId = veh:getID()
  veh:queueLuaCommand(string.format("extensions.load('rallyAcademy/telemetry') "
    .. "if extensions.rallyAcademy_telemetry then extensions.rallyAcademy_telemetry.start(%d, 'rallyAcademy') end",
    TELEMETRY_RATE))
end

local function stopSampling()
  local veh = samplingVehId and getObjectByID(samplingVehId)
  if veh then
    veh:queueLuaCommand("if extensions.rallyAcademy_telemetry then extensions.rallyAcademy_telemetry.stop() end")
  end
  samplingVehId = nil
end

-- Close the open run record, if any, and stop sampling.
-- outcome: 'finished' | 'abandoned' | 'restarted'
local function endRun(outcome)
  if RunRecord.isOpen(run) then
    RunRecord.finish(run, outcome)
    local sum = RunRecord.summary(run)
    logf('I', '%s: run record %s, %d samples over %.1f s (%.0f Hz)%s', tostring(run.meta.drill), outcome,
      sum.samples, sum.span, sum.rateHz, sum.truncated and ', truncated' or '')
  end
  stopSampling()
end

local function output(includeCatalog)
  local lesson = selected and byId[selected] or nil
  guihooks.trigger('rallyAcademyState', {
    phase = phase,
    selected = selected,
    lesson = lesson,
    lessons = includeCatalog and lessonSummary or nil,
    attempts = attempts,
    successes = successes,
    required = lesson and lesson.assessment.requiredPasses or 0,
    target = lesson and lesson.assessment.attempts or 0,
    elapsed = cur.elapsed,
    lastTime = cur.lastTime,
    reason = lastReason,
    hasStart = startState ~= nil,
    hasFinish = finishGate ~= nil,
    gateCount = #gates,
    progress = progress.lessons,
    grade = cur.grade or false -- explicit: the HUD merges updates, so a missing key would keep the old grade
  })
end

local function load()
  local data = jsonReadFile(LESSONS_FILE)
  if not (data and data.exercises) then logf('E', 'could not read drills from %s', LESSONS_FILE) end
  lessons, byId, lessonSummary = (data and data.exercises) or {}, {}, {}
  for _, lesson in ipairs(lessons) do
    byId[lesson.id] = lesson
    table.insert(lessonSummary, {id=lesson.id, title=lesson.title, module=lesson.module,
      parked=lesson.parked ~= nil or nil})
  end
  local warn
  progress, warn = Store.loadProgress()
  if warn then logf('W', '%s', warn) end
  setups, warn = Store.loadSetups()
  if warn then logf('W', '%s', warn) end
  logf('I', 'loaded %d drills on map %s', #lessons, levelId())
end

local function saveProgress() Store.saveProgress(progress) end

-- Persist the selected drill's start, finish and gates for the current map.
local function saveSetup()
  local start = startState and {pos = startState.pos, dir = startState.dir, up = startState.up} or nil
  Store.putSetup(setups, levelId(), selected, {start = start, finish = finishGate, gates = #gates > 0 and gates or nil})
end

function M.onExtensionLoaded()
  load()
  output(true)
end

function M.publish() output(true) end

-- Load the selected drill's saved start/finish for the current map (or clear them).
local function loadSetup()
  startState, finishGate, gates = nil, nil, {}
  local saved = Store.getSetup(setups, levelId(), selected)
  if saved and type(saved.gates) == 'table' then gates = saved.gates end
  if saved and saved.start then
    startState, finishGate = saved.start, saved.finish
    lastReason = finishGate and 'Loaded your saved start and finish for this map. Press Retry to begin.'
      or 'Loaded your saved start for this map. Press Retry to begin.'
  else
    lastReason = 'Select a suitable car/map, mark the start, and optionally mark a finish gate.'
  end
end

-- Abandon the current run (nothing is scored) but keep the drill and its setup.
local function backToSetup(reason)
  logf('I', '%s: run abandoned (%s)', tostring(selected), reason)
  endRun('abandoned')
  phase = 'setup'
  resetRun()
  activeVehicleId = nil
  lastReason = reason
  output()
end

local function assessment()
  local lesson = selected and byId[selected]
  return lesson and lesson.assessment or {}
end

-- Drills like B01 end when the car comes to rest instead of at a finish circle;
-- drills like A04 end at their last gate.
local function endsOnStop() return assessment().endWhen == 'stopped' end
-- A05-style drills mark a line to stop before (front bumper on it), not a zone centre.
local function usesStopLine()
  for _, r in ipairs(assessment().rules or {}) do if r.type == 'stop_before_line' then return true end end
  return false
end
local function endsAtLastGate() return assessment().endWhen == 'gates' end

-- Does a run of this drill end on its own (so a run in progress can't be passed early)?
local function hasEnd() return finishGate ~= nil or (endsAtLastGate() and #gates > 0) end

function M.select(id)
  if type(id) ~= 'string' or not byId[id] then return end
  if id ~= selected then pendingGoTo, arriveIn, awaitingCar = nil, nil, nil end -- changed your mind mid-trip
  if RunRecord.isOpen(run) then endRun('abandoned') end
  selected = id
  phase, attempts, successes = 'setup', 0, 0
  resetRun()
  activeVehicleId = nil
  loadSetup()
  if byId[id].parked then
    -- FWD-first lineup (docs/VEHICLES.md): still drivable, but say why it's parked.
    lastReason = 'Parked for now: ' .. byId[id].parked .. ' ' .. lastReason
  end
  logf('I', 'selected %s on %s (%s)', id, levelId(), startState and 'saved setup loaded' or 'no saved setup')
  output()
end

function M.markStart()
  if not selected then return end
  local snap = snapshotVehicle()
  if not snap then lastReason = 'No player vehicle'; output(); return end
  startState = snap
  activeVehicleId = snap.vehicleId
  phase = 'setup'
  saveSetup()
  logf('I', 'start marked for %s on %s at (%.1f, %.1f, %.1f)', selected, levelId(), snap.pos.x, snap.pos.y, snap.pos.z)
  lastReason = 'Start position and orientation captured and saved for this map.'
  output()
end

function M.markFinish()
  if not selected then return end
  local snap = snapshotVehicle()
  if not snap then lastReason = 'No player vehicle'; output(); return end
  finishGate = {pos=snap.pos, radius=5, dir=snap.dir} -- dir orients a stop zone
  saveSetup()
  logf('I', 'finish marked for %s on %s at (%.1f, %.1f, %.1f)', selected, levelId(), snap.pos.x, snap.pos.y, snap.pos.z)
  lastReason = usesStopLine()
    and 'Stop line marked and saved (where your front bumper is, across the way you are facing). Retry to begin.'
    or endsOnStop()
    and 'Stop zone centre marked and saved (zone runs along the way you are facing). Retry to begin.'
    or '5 m finish circle captured and saved; retry to return to your start.'
  output()
end

-- Mark a gate across the road where the car is, facing the way it points.
function M.addGate()
  if not selected then return end
  local spec = assessment().gates or {}
  if spec.count and #gates >= spec.count then
    lastReason = string.format('All %d gates are marked. Clear gates to mark them again.', spec.count)
    output(); return
  end
  local snap = snapshotVehicle()
  if not snap then lastReason = 'No player vehicle'; output(); return end
  gates[#gates + 1] = Gates.new(snap, spec.widthM)
  saveSetup()
  logf('I', 'gate %d marked for %s on %s at (%.1f, %.1f, %.1f)', #gates, selected, levelId(), snap.pos.x, snap.pos.y, snap.pos.z)
  local of = spec.count and (' of ' .. spec.count) or ''
  lastReason = string.format('Gate %d%s marked and saved (%g m wide, across the way you are facing).', #gates, of, gates[#gates].width)
  if spec.count and #gates == spec.count then lastReason = lastReason .. ' All gates marked: Retry to begin.' end
  output()
end

function M.clearGates()
  if not selected then return end
  gates = {}
  saveSetup()
  logf('I', 'gates cleared for %s on %s', selected, levelId())
  lastReason = 'Gates cleared. Drive to each gate in order and press + Gate.'
  output()
end

function M.retry()
  local veh = currentVehicle()
  if not veh or not startState then
    lastReason = 'Mark a start before retrying.'
    output(); return
  end
  activeVehicleId = veh:getID() -- the run follows whichever car was reset
  if RunRecord.isOpen(run) then endRun('restarted') end
  teleportToStart(veh, startState)
  run = RunRecord.new({drill = selected, level = levelId(), vehicleId = activeVehicleId,
                       start = startState.pos, finish = finishGate, gates = #gates > 0 and gates or nil})
  startSampling(veh)
  logf('I', 'retry: %s, vehicle %s reset to start', selected, tostring(activeVehicleId))
  resetRun()
  phase = 'ready'
  lastReason = 'Car reset and repaired. Accelerate to begin; Retry again any time.'
  if endsAtLastGate() and #gates == 0 then
    lastReason = 'Car reset. No gates marked yet, so this run only ends with Miss: drive to each gate and press + Gate.'
  end
  output()
end

-- Score an attempt: self-assessed drills via the Pass/Miss buttons, automatic drills from
-- finishRun. Only a driven run can be scored: one that reached its end, or one the driver
-- ends with Pass/Miss when the drill has no end of its own. A run that does end on its own
-- can only be abandoned mid-run (Miss), so a partial time never counts.
function M.recordAttempt(passed)
  if not selected then return end
  local finished = phase == 'review' or (phase == 'running' and not hasEnd())
  local abandoned = phase == 'running' and hasEnd()
  if not finished and not abandoned then return end
  if abandoned and passed then
    lastReason = 'Finish the run to score a pass, or press Miss to abandon it.'
    output(); return
  end
  if phase == 'running' then cur.lastTime = finished and cur.elapsed or nil end
  if RunRecord.isOpen(run) then endRun(finished and 'finished' or 'abandoned') end
  if run and not run.score then run.score = {passed = passed == true, time = cur.lastTime} end
  attempts = attempts + 1
  if passed == true then successes = successes + 1 end
  phase = 'scored'
  local entry = progress.lessons[selected] or {totalAttempts=0, totalPasses=0, bestTime=nil}
  entry.totalAttempts = entry.totalAttempts + 1
  entry.totalPasses = entry.totalPasses + (passed and 1 or 0)
  if passed and cur.lastTime and (not entry.bestTime or cur.lastTime < entry.bestTime) then
    entry.bestTime = cur.lastTime
  end
  local config = byId[selected].assessment
  if attempts >= config.attempts then
    entry.lastSessionPassed = successes >= config.requiredPasses
  end
  progress.lessons[selected] = entry
  saveProgress()
  logf('I', '%s: %s, time %s, session %d/%d', selected, passed and 'PASS' or 'MISS',
    cur.lastTime and string.format('%.2f s', cur.lastTime) or '-', successes, attempts)
  lastReason = (passed and 'Recorded a clean attempt.' or 'Recorded an unsuccessful attempt.')
  output()
end

-- Course markers (course.lua draws them) ------------------------------------------

local function stopZoneSize()
  for _, r in ipairs(assessment().rules or {}) do
    if r.type == 'stop_zone' then return r.lengthM or 5, r.widthM or 6 end
  end
  return 5, 6
end

local function drawCourse()
  local zoneLength, zoneWidth = stopZoneSize()
  Course.draw({
    gates = gates, gateResults = cur.gateResults,
    nextGate = (phase == 'ready' or phase == 'running') and cur.gateIdx or nil,
    finish = finishGate,
    finishKind = usesStopLine() and 'line' or endsOnStop() and 'zone' or 'circle',
    zoneLength = zoneLength, zoneWidth = zoneWidth,
  })
end

-- End the run (finish reached, or stopped); automatic drills grade and record it.
local function finishRun(how, atTime)
  cur.lastTime = atTime or cur.elapsed
  phase = 'review'
  logf('I', '%s: %s in %.2f s', selected, how, cur.lastTime)
  endRun('finished')
  local a = assessment()
  if a.mode ~= 'automatic' then
    lastReason = (endsOnStop() and 'Stopped.' or 'Finish reached.') .. ' Grade the technique using Pass/Miss.'
    output(); return
  end
  cur.grade = Rules.evaluate(a.rules, run, {zone = finishGate, gates = gates})
  if run then run.grade = cur.grade end
  local firstFail
  for _, c in ipairs(cur.grade.checks) do
    logf('I', '%s:   %s %s', selected, c.ok and 'ok  ' or 'FAIL', c.text)
    if not c.ok and not firstFail then firstFail = c.text end
  end
  M.recordAttempt(cur.grade.passed)
  lastReason = (cur.grade.passed and 'PASS.' or ('MISS: ' .. firstFail .. '.')) .. ' Retry for the next attempt.'
  output()
end

function M.onUpdate(dtReal, dtSim)
  if awaitingCar then
    awaitT = awaitT + (dtReal or 0)
    if awaitT >= SPAWN_TIMEOUT then
      logf('W', 'go to drill: no spawn event after %d s, placing the car anyway', SPAWN_TIMEOUT)
      awaitingCar, arriveIn = nil, 0
    end
    return
  end
  if arriveIn then
    arriveIn = arriveIn - (dtReal or 0)
    if arriveIn <= 0 then arriveIn = nil; placeAtDrill() end
    return
  end
  if selected then drawCourse() end
  if not selected or (phase ~= 'ready' and phase ~= 'running') then return end
  local veh = currentVehicle()
  if not veh or veh:getID() ~= activeVehicleId then
    -- Fallback for onVehicleSwitched (also covers the car being deleted).
    backToSetup('Vehicle changed. Press Retry to start a new run in this car.')
    return
  end
  cur.uiAccum = cur.uiAccum + (dtReal or 0)
  local speed = veh:getVelocity():length()
  -- The frame after a teleport reports a huge velocity (~430 m/s seen in 0.39.4), and
  -- the car may still be nudged: arm the start only once it has settled (see cur.originPos).
  if phase == 'ready' then
    cur.settleT = cur.settleT + math.max(0, dtReal or 0)
    if not cur.originPos or speed < SETTLE_SPEED then cur.originPos = vec3(veh:getPosition()) end
  end
  local fromOrigin = cur.originPos and (veh:getPosition() - cur.originPos):length() or 0
  local leftStart = cur.settleT >= SETTLE_FOR and fromOrigin > 0.5
  if phase == 'ready' and speed > 1 and leftStart then
    phase = 'running'
    cur.prevPos = vec3(veh:getPosition())
    RunRecord.markRunStart(run)
    logf('I', '%s: run started', selected)
    lastReason = 'Run started.'
    output()
  end
  if phase ~= 'running' then return end
  -- dtSim is game-simulation time, unlike wall clock. Physics pause should not add time.
  cur.elapsed = cur.elapsed + math.max(0, dtSim or 0)
  local vpos = vec3(veh:getPosition())
  if cur.prevPos and gates[cur.gateIdx] then
    -- Live gate feedback; grading re-reads the gates from the run record (rules.lua).
    local c = Gates.crossing(gates[cur.gateIdx], cur.prevPos, vpos)
    if c then
      cur.gateResults[cur.gateIdx] = c.inside and 'passed' or 'missed'
      lastReason = c.inside and string.format('Gate %d of %d: %.0f km/h', cur.gateIdx, #gates, speed * 3.6)
        or string.format('Missed gate %d (%s)', cur.gateIdx, Gates.missText(gates[cur.gateIdx], c.offset))
      logf('I', '%s: gate %d %s at %.0f km/h, %.1f m off centre', selected, cur.gateIdx,
        cur.gateResults[cur.gateIdx], speed * 3.6, c.offset)
      cur.gateIdx = cur.gateIdx + 1
      cur.uiAccum = 1 -- publish now
      if endsAtLastGate() and cur.gateIdx > #gates then cur.endingIn, cur.endTime = GRADE_DELAY, cur.elapsed end
    end
  end
  cur.prevPos = vpos
  if cur.endingIn then
    cur.endingIn = cur.endingIn - math.max(0, dtSim or 0)
    if cur.endingIn <= 0 then cur.endingIn = nil; finishRun('last gate', cur.endTime); return end
  end
  if endsOnStop() then
    if cur.elapsed > 1 and speed < STOPPED_SPEED and fromOrigin > STOPPED_MIN_DIST then
      cur.stillT = cur.stillT + math.max(0, dtSim or 0)
      if cur.stillT >= STOPPED_FOR then finishRun('stopped'); return end
    else
      cur.stillT = 0
    end
  elseif finishGate and not endsAtLastGate() and cur.elapsed > 1 then
    local gate = vec3(finishGate.pos.x,finishGate.pos.y,finishGate.pos.z)
    if (vpos - gate):length() <= finishGate.radius then finishRun('finish reached'); return end
  end
  if cur.uiAccum >= 0.25 then
    cur.uiAccum = 0
    output()
  end
end

-- Go to drill ----------------------------------------------------------------
-- Load the drill's map if needed, put the player in the drill's car, and place it
-- at the saved start (straight into a run) or the venue's default spot.

-- Level names differ in case between the list ('Utah') and the current level ('utah').
local function sameLevel(a, b)
  return type(a) == 'string' and type(b) == 'string' and a:lower() == b:lower()
end

local function levelPathFor(name)
  for _, l in ipairs((core_levels and core_levels.getList and core_levels.getList()) or {}) do
    if sameLevel(l.levelName, name) then return l.fullfilename or l.misFilePath end
  end
end

-- Start the map in freeroam, as the game's Freeroam menu does: it also enters freeroam
-- mode (loading screen, HUD, leaves the menus). Bare core_levels.startLevel only worked
-- from inside freeroam; from the main menu the menu stayed up with no HUD (0.39.4).
local function startMap(path)
  if freeroam_freeroam and freeroam_freeroam.startFreeroam then
    freeroam_freeroam.startFreeroam(path)
  else
    core_levels.startLevel(path)
  end
end

local function configKey(configPath) -- 'vehicles/covet/rally_gravel.pc' -> 'rally_gravel'
  return type(configPath) == 'string' and configPath:match('([^/]+)%.pc$') or nil
end

-- Respawn only if the current car isn't already the drill's model and config.
-- Returns true if a new car was requested; it is placed once onVehicleSpawned
-- reports it. That hook fires synchronously inside replaceVehicle (0.39.4), so
-- start waiting before the call.
local function ensureCar(vehicle)
  if not (vehicle and vehicle.modelId and vehicle.configPath) then return false end
  local veh = currentVehicle()
  if veh and veh.JBeam == vehicle.modelId and veh.partConfig == vehicle.configPath then return false end
  awaitingCar, awaitT = vehicle.configPath, 0
  core_vehicles.replaceVehicle(vehicle.modelId, {config = configKey(vehicle.configPath)})
  logf('I', 'go to drill: spawned %s (%s)', vehicle.modelId, tostring(configKey(vehicle.configPath)))
  return true
end

function placeAtDrill()
  local lesson = byId[selected]
  local veh = currentVehicle()
  if not lesson then return end
  if not veh then arriveIn = 0.25; return end -- car still being built: try again shortly
  local env = lesson.environment
  if startState then
    M.retry()
    lastReason = 'At ' .. env.mapDisplayName .. ' in the drill car, at your saved start. Go when ready; Retry any time.'
  else
    teleportToStart(veh, env.spawn)
    activeVehicleId = veh:getID()
    lastReason = 'At ' .. env.mapDisplayName .. ' in the drill car. Drive to where the drill starts, then Mark start.'
  end
  logf('I', 'go to drill: %s placed at %s', selected, startState and 'saved start' or 'venue spot')
  if leaveMenuOnArrival and ui_router and ui_router.navigate then
    leaveMenuOnArrival = false
    ui_router.navigate('play')
  end
  output()
end

local function arriveAtDrill()
  if ensureCar(byId[selected].vehicle) then
    lastReason = 'Getting the drill car ready...'
    output()
  else
    placeAtDrill()
  end
end

function M.goToDrill()
  if not selected then return end
  local env = byId[selected].environment
  if not (env and env.levelId and env.spawn) then
    lastReason = 'This drill has no venue yet.'
    output(); return
  end
  if RunRecord.isOpen(run) then endRun('abandoned') end
  phase = 'setup'
  resetRun()
  if not sameLevel(levelId(), env.levelId) then
    local path = levelPathFor(env.levelId)
    if not path then
      lastReason = 'Map not installed: ' .. env.levelId
      output(); return
    end
    pendingGoTo = selected
    lastReason = 'Loading ' .. env.mapDisplayName .. '...'
    logf('I', 'go to drill: %s, loading %s', selected, env.levelId)
    output()
    startMap(path)
    return
  end
  arriveAtDrill()
end

-- Main-menu screen (ui/ui-vue/mods/rallyAcademy) --------------------------------

local APP_INFO_FILE = 'ui/modules/apps/RallyAcademy/app.json' -- version kept in sync by dev.py

-- Everything the menu shows: every drill in curriculum order (file order), progress,
-- the drill selected in the HUD, and the mod's version and author (About, Credits).
function M.getMenuData()
  local app = jsonReadFile(APP_INFO_FILE) or {}
  return {lessons = lessons, progress = progress.lessons, selected = selected,
          info = {version = app.version, author = app.author}}
end

-- Opening the screen inside a map pauses physics (unless already paused); leaving it
-- resumes only what we paused.
local menuOpen, pausedForMenu = false, false
local MENU_ROUTE = 'menu.rallyAcademy'

local function inMap() return getCurrentLevelIdentifier and getCurrentLevelIdentifier() ~= nil end

local function resumeIfWePaused()
  if pausedForMenu and simTimeAuthority then simTimeAuthority.pause(false) end
  pausedForMenu = false
end

-- Key binding / HUD: open the Academy screen (over the game when in a map).
function M.openMenu()
  if not (ui_router and ui_router.navigate) then return false end
  if inMap() and simTimeAuthority and not pausedForMenu and not simTimeAuthority.getPause() then
    simTimeAuthority.pause(true)
    pausedForMenu = true
  end
  menuOpen = true
  ui_router.navigate(MENU_ROUTE)
  return true
end

-- Back button: to the game when in a map, else to the main menu.
function M.closeMenu()
  menuOpen = false
  resumeIfWePaused()
  if ui_router and ui_router.navigate then ui_router.navigate(inMap() and 'play' or 'menu') end
end

function M.toggleMenu()
  if menuOpen then M.closeMenu() else M.openMenu() end
end

-- Route lifecycle (index.js luaRoute.onLeave): however the screen was left (Back, Esc,
-- Start drill), resume what we paused.
function M.onMenuLeave()
  menuOpen = false
  resumeIfWePaused()
end

-- Start button: select the drill and go to it (loads its map from the main menu).
function M.startDrill(id)
  if type(id) ~= 'string' or not byId[id] then return false end
  menuOpen = false
  resumeIfWePaused()
  M.select(id)
  leaveMenuOnArrival = true
  M.goToDrill()
  logf('I', 'menu: started %s', id)
  return true
end

-- Telemetry ------------------------------------------------------------------

-- Called by the car's sampler (lua/vehicle/extensions/rallyAcademy/telemetry.lua).
function M.onTelemetry(sample)
  if not RunRecord.isOpen(run) or type(sample) ~= 'table' or sample.id ~= samplingVehId then return end
  RunRecord.add(run, sample)
end

-- The current or most recent attempt's record (for grading and debugging).
function M.getLastRun() return run end

-- Developer hook: write the last run record to disk, e.g. to build test fixtures.
-- Only on request: a minute of samples is ~1 MB of JSON.
function M.saveLastRun(path)
  if not run then return nil end
  path = path or LAST_RUN_FILE
  jsonWriteFile(path, run, false)
  logf('I', 'saved run record (%d samples) to %s', #run.samples, path)
  return path
end

-- Developer hooks (tools/ingame scenarios) -----------------------------------------

-- A snapshot of the session for test scripts, instead of reading Lua internals.
function M.debugState()
  return {phase = phase, selected = selected, level = levelId(), elapsed = cur.elapsed, lastTime = cur.lastTime,
          hasStart = startState ~= nil, hasFinish = finishGate ~= nil, gateCount = #gates, gateIdx = cur.gateIdx,
          attempts = attempts, successes = successes, reason = lastReason,
          menuOpen = menuOpen, passed = cur.grade and cur.grade.passed} -- false = graded MISS, nil = not graded
end

-- Forget a drill's saved progress (scenarios clean up the attempts they record).
function M.devClearProgress(id)
  if type(id) ~= 'string' then return false end
  progress.lessons[id] = nil
  saveProgress()
  if id == selected then attempts, successes = 0, 0 end
  logf('I', 'progress cleared for %s (developer hook)', id)
  output()
  return true
end

-- Engine hooks (lua/ge/main.lua, 0.39.4) --------------------------------------

function M.onVehicleSwitched(_oldId, _newId, _player)
  if phase == 'ready' or phase == 'running' then
    backToSetup('Vehicle changed. Press Retry to start a new run in this car.')
  end
end

-- A car finished (re)spawning: if it's the drill car we asked for, place it shortly.
function M.onVehicleSpawned(_vid, veh)
  if awaitingCar and veh and veh.partConfig == awaitingCar then
    awaitingCar, arriveIn = nil, SETTLE_AFTER_SPAWN
  end
end

-- Map unloading: its start/finish mean nothing on the next map.
function M.onClientEndMission(_levelPath)
  if not selected then return end
  startState, finishGate, gates = nil, nil, {}
  backToSetup('Map closed.')
end

-- Map fully loaded (car spawned): bring in the selected drill's setup for it.
function M.onClientPostStartMission(levelPath)
  if not selected then return end
  logf('I', 'map loaded (%s), reloading setup for %s', tostring(levelPath), selected)
  M.select(selected)
  if pendingGoTo == selected then
    pendingGoTo = nil
    arriveAtDrill()
  end
end

return M
