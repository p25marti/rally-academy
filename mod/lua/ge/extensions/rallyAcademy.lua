-- Rally Academy prototype (BeamNG GE Lua). In-game status: docs/BEAMNG_API_NOTES.md.
-- UI calls extensions.load('rallyAcademy') and extensions.rallyAcademy.<method>().
local M = {}
local RunRecord = require('ge/extensions/rallyAcademy/runRecord')
local Rules = require('ge/extensions/rallyAcademy/rules')
local LESSONS_FILE = 'gameplay/rallyAcademy/exercises.json'
local SAVE_FILE = 'settings/rallyAcademyProgress.json'
-- Marked starts/finishes, per map then drill: levels[levelId][drillId] = {start, finish}
local SETUPS_FILE = 'settings/rallyAcademySetups.json'
local lessons, byId, lessonSummary = {}, {}, {}
local progress = {schemaVersion = 1, lessons = {}}
local setups = {schemaVersion = 1, levels = {}}
local selected, startState, finishGate = nil, nil, nil
local phase, elapsed, uiAccum = 'idle', 0, 0
local lastTime, lastReason = nil, ''
local attempts, successes = 0, 0
local activeVehicleId = nil
-- Telemetry (docs/decisions/0004): the current or most recent attempt's record.
local TELEMETRY_RATE = 60
local LAST_RUN_FILE = 'settings/rallyAcademy/lastRun.json'
local run, samplingVehId = nil, nil
-- Automatic grading: the last run's checks, and how long the car has been standing still.
local lastGrade, stillT = nil, 0
-- Where the car came to rest after Retry. The repair-teleport can nudge the car ~2 m a
-- frame after it lands (seen on 0.39.4 next to barriers), so the start is armed only
-- SETTLE_FOR after Retry, and departure is measured from the last spot the car was slow at.
local originPos, settleT = nil, 0
local SETTLE_SPEED, SETTLE_FOR = 0.5, 0.2 -- m/s, s
local STOPPED_SPEED, STOPPED_FOR, STOPPED_MIN_DIST = 0.3, 0.5, 5 -- m/s, s, m from the start
-- Go to drill: drill waiting for its map to load; car swap in progress; deferred placement.
local pendingGoTo, arriveIn = nil, nil
local awaitingCar, awaitT = nil, 0 -- configPath we're waiting to see spawn, and how long we've waited
local SETTLE_AFTER_SPAWN = 0.3     -- s after onVehicleSpawned before teleporting the new car
local SPAWN_TIMEOUT = 6            -- s: place the car anyway if onVehicleSpawned never comes
local placeAtDrill -- defined under "Go to drill"; onUpdate (above it) calls it

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
    elapsed = elapsed,
    lastTime = lastTime,
    reason = lastReason,
    hasStart = startState ~= nil,
    hasFinish = finishGate ~= nil,
    progress = progress.lessons,
    grade = lastGrade or false -- explicit: the HUD merges updates, so a missing key would keep the old grade
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
  local saved = jsonReadFile(SAVE_FILE)
  if type(saved) == 'table' and type(saved.lessons) == 'table' then progress = saved
  elseif saved ~= nil then logf('W', 'ignoring unreadable %s', SAVE_FILE) end
  local savedSetups = jsonReadFile(SETUPS_FILE)
  if type(savedSetups) == 'table' and type(savedSetups.levels) == 'table' then setups = savedSetups
  elseif savedSetups ~= nil then logf('W', 'ignoring unreadable %s', SETUPS_FILE) end
  logf('I', 'loaded %d drills on map %s', #lessons, levelId())
end

local function saveProgress()
  jsonWriteFile(SAVE_FILE, progress, true)
end

-- Persist the selected drill's start/finish for the current map. The vehicle id
-- isn't saved: ids change every session, and Retry applies to the current car.
local function saveSetup()
  local lvl = levelId()
  setups.levels[lvl] = setups.levels[lvl] or {}
  local start = startState and {pos = startState.pos, dir = startState.dir, up = startState.up} or nil
  setups.levels[lvl][selected] = {start = start, finish = finishGate}
  jsonWriteFile(SETUPS_FILE, setups, true)
end

function M.onExtensionLoaded()
  load()
  output(true)
end

function M.publish() output(true) end

-- Load the selected drill's saved start/finish for the current map (or clear them).
local function loadSetup()
  startState, finishGate = nil, nil
  local saved = setups.levels[levelId()] and setups.levels[levelId()][selected]
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
  phase, elapsed, lastTime = 'setup', 0, nil
  activeVehicleId = nil
  lastReason = reason
  output()
end

local function assessment()
  local lesson = selected and byId[selected]
  return lesson and lesson.assessment or {}
end

-- Drills like B01 end when the car comes to rest instead of at a finish circle.
local function endsOnStop() return assessment().endWhen == 'stopped' end

function M.select(id)
  if type(id) ~= 'string' or not byId[id] then return end
  if id ~= selected then pendingGoTo, arriveIn, awaitingCar = nil, nil, nil end -- changed your mind mid-trip
  if RunRecord.isOpen(run) then endRun('abandoned') end
  selected = id
  phase, elapsed, attempts, successes, lastTime = 'setup', 0, 0, 0, nil
  lastGrade = nil
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
  lastReason = endsOnStop()
    and 'Stop zone centre marked and saved (zone runs along the way you are facing). Retry to begin.'
    or '5 m finish circle captured and saved; retry to return to your start.'
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
                       start = startState.pos, finish = finishGate})
  startSampling(veh)
  logf('I', 'retry: %s, vehicle %s reset to start', selected, tostring(activeVehicleId))
  elapsed, lastTime, lastGrade, stillT, originPos, settleT = 0, nil, nil, 0, nil, 0
  phase = 'ready'
  lastReason = 'Car reset and repaired. Accelerate to begin; Retry again any time.'
  output()
end

-- MVP scoring is intentionally *self-assessed*. Crossing a finish gate only stops the timer.
-- Only a driven run can be scored: one that reached the finish, or one the driver
-- ends with Pass/Miss when the drill has no finish gate. With a finish gate, a
-- run in progress can only be abandoned (Miss), so a partial time never counts.
function M.recordAttempt(passed)
  if not selected then return end
  local finished = phase == 'review' or (phase == 'running' and not finishGate)
  local abandoned = phase == 'running' and finishGate ~= nil
  if not finished and not abandoned then return end
  if abandoned and passed then
    lastReason = 'Finish the run to score a pass, or press Miss to abandon it.'
    output(); return
  end
  if phase == 'running' then lastTime = finished and elapsed or nil end
  if RunRecord.isOpen(run) then endRun(finished and 'finished' or 'abandoned') end
  if run and not run.score then run.score = {passed = passed == true, time = lastTime} end
  attempts = attempts + 1
  if passed == true then successes = successes + 1 end
  phase = 'scored'
  local entry = progress.lessons[selected] or {totalAttempts=0, totalPasses=0, bestTime=nil}
  entry.totalAttempts = entry.totalAttempts + 1
  entry.totalPasses = entry.totalPasses + (passed and 1 or 0)
  if passed and lastTime and (not entry.bestTime or lastTime < entry.bestTime) then
    entry.bestTime = lastTime
  end
  local config = byId[selected].assessment
  if attempts >= config.attempts then
    entry.lastSessionPassed = successes >= config.requiredPasses
  end
  progress.lessons[selected] = entry
  saveProgress()
  logf('I', '%s: %s, time %s, session %d/%d', selected, passed and 'PASS' or 'MISS',
    lastTime and string.format('%.2f s', lastTime) or '-', successes, attempts)
  lastReason = (passed and 'Recorded a clean attempt.' or 'Recorded an unsuccessful attempt.')
  output()
end

-- End the run (finish reached, or stopped); automatic drills grade and record it.
local function finishRun(how)
  lastTime = elapsed
  phase = 'review'
  logf('I', '%s: %s in %.2f s', selected, how, lastTime)
  endRun('finished')
  local a = assessment()
  if a.mode ~= 'automatic' then
    lastReason = (endsOnStop() and 'Stopped.' or 'Finish reached.') .. ' Grade the technique using Pass/Miss.'
    output(); return
  end
  lastGrade = Rules.evaluate(a.rules, run, {zone = finishGate})
  if run then run.grade = lastGrade end
  local firstFail
  for _, c in ipairs(lastGrade.checks) do
    logf('I', '%s:   %s %s', selected, c.ok and 'ok  ' or 'FAIL', c.text)
    if not c.ok and not firstFail then firstFail = c.text end
  end
  M.recordAttempt(lastGrade.passed)
  lastReason = (lastGrade.passed and 'PASS.' or ('MISS: ' .. firstFail .. '.')) .. ' Retry for the next attempt.'
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
  if not selected or (phase ~= 'ready' and phase ~= 'running') then return end
  local veh = currentVehicle()
  if not veh or veh:getID() ~= activeVehicleId then
    -- Fallback for onVehicleSwitched (also covers the car being deleted).
    backToSetup('Vehicle changed. Press Retry to start a new run in this car.')
    return
  end
  uiAccum = uiAccum + (dtReal or 0)
  local speed = veh:getVelocity():length()
  -- The frame after a teleport reports a huge velocity (~430 m/s seen in 0.39.4), and
  -- the car may still be nudged: arm the start only once it has settled (see originPos).
  if phase == 'ready' then
    settleT = settleT + math.max(0, dtReal or 0)
    if not originPos or speed < SETTLE_SPEED then originPos = vec3(veh:getPosition()) end
  end
  local fromOrigin = originPos and (veh:getPosition() - originPos):length() or 0
  local leftStart = settleT >= SETTLE_FOR and fromOrigin > 0.5
  if phase == 'ready' and speed > 1 and leftStart then
    phase = 'running'
    RunRecord.markRunStart(run)
    logf('I', '%s: run started', selected)
    lastReason = 'Run started.'
    output()
  end
  if phase ~= 'running' then return end
  -- dtSim is game-simulation time, unlike wall clock. Physics pause should not add time.
  elapsed = elapsed + math.max(0, dtSim or 0)
  if endsOnStop() then
    if elapsed > 1 and speed < STOPPED_SPEED and fromOrigin > STOPPED_MIN_DIST then
      stillT = stillT + math.max(0, dtSim or 0)
      if stillT >= STOPPED_FOR then finishRun('stopped'); return end
    else
      stillT = 0
    end
  elseif finishGate and elapsed > 1 then
    local vpos = veh:getPosition()
    local gate = vec3(finishGate.pos.x,finishGate.pos.y,finishGate.pos.z)
    if (vpos - gate):length() <= finishGate.radius then finishRun('finish reached'); return end
  end
  if uiAccum >= 0.25 then
    uiAccum = 0
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
  phase, elapsed, lastTime = 'setup', 0, nil
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
    core_levels.startLevel(path)
    return
  end
  arriveAtDrill()
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
  startState, finishGate = nil, nil
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
