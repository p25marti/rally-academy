-- Rally Academy (BeamNG GE Lua extension): drill session, timing, grading, progress.
-- Design: docs/ARCHITECTURE.md. Engine API status: docs/BEAMNG_API_NOTES.md.
-- UI calls extensions.load('rallyAcademy') and extensions.rallyAcademy.<method>().
local M = {}
-- Re-read our pure modules whenever the extension (re)loads: extensions.reload re-runs
-- this file but `require` would keep the old modules (seen on 0.39.4).
for _, name in ipairs({'runRecord', 'rules', 'gates', 'layout', 'store', 'course', 'spots'}) do
  package.loaded['ge/extensions/rallyAcademy/' .. name] = nil
end
local RunRecord = require('ge/extensions/rallyAcademy/runRecord')
local Rules = require('ge/extensions/rallyAcademy/rules')
local Gates = require('ge/extensions/rallyAcademy/gates')
local Layout = require('ge/extensions/rallyAcademy/layout')
local Store = require('ge/extensions/rallyAcademy/store')
local Course = require('ge/extensions/rallyAcademy/course')
local Spots = require('ge/extensions/rallyAcademy/spots')
local LESSONS_FILE = 'gameplay/rallyAcademy/exercises.json'
-- Named venues drills refer to (environment.venue); the loader fills in each drill's map,
-- display name and spawn from it, so the rest of the mod reads them from the drill.
local VENUES_FILE = 'gameplay/rallyAcademy/venues.json'
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
-- Gates (gates.lua) marked for the selected drill on this map, in driving order. For a drill
-- with an authored course they come from the course instead.
local gates = {}
-- Authored course (layout.lua) laid out from the start, or nil; usingVenueStart = the start
-- is the venue's spawn, not one the player marked.
local course, usingVenueStart = nil, false
-- The car's footprint (layout.lua), measured from its nodes once per car: {vid, config, car}.
local carSize = nil
-- Player preferences (store.lua): auto-retry after a graded run.
local prefs = {autoRetry = true}
local AUTO_RETRY_DELAY = 3 -- s of sim time after a graded run
local AUTO_RETRY_CANCEL_SPEED = 2 -- m/s: driving off cancels it
-- Medals, lowest first.
local TIER_RANK = {bronze = 1, silver = 2, gold = 3}
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
--   coneIdx, coneResults  next cone, each cone's live result ('passed' | 'wrong')
--   clipped            the first marker the car touched (live), fit = medal box the car is in now
--   aid                parking aid text near the box; autoRetryIn = countdown after a graded run
local cur
local function resetRun()
  cur = {elapsed = 0, lastTime = nil, grade = nil, settleT = 0, originPos = nil, stillT = 0,
         gateIdx = 1, gateResults = {}, prevPos = nil, endingIn = nil, endTime = nil, uiAccum = 0,
         coneIdx = 1, coneResults = {}, clipped = nil, fit = nil, aid = nil, autoRetryIn = nil}
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

-- Level names differ in case between the list ('Utah') and the current level ('utah').
local function sameLevel(a, b)
  return type(a) == 'string' and type(b) == 'string' and a:lower() == b:lower()
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

local liveCourse -- defined under "Course markers"; the HUD's checklist and parking aid

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
    -- Explicit `false`s: the HUD merges updates, so a missing key would keep the old value.
    grade = cur.grade or false,
    course = liveCourse() or false,
    usingVenueStart = usingVenueStart,
    autoRetry = prefs.autoRetry ~= false,
    autoRetryIn = cur.autoRetryIn and math.ceil(cur.autoRetryIn) or false,
  })
end

local function load()
  local data = jsonReadFile(LESSONS_FILE)
  if not (data and data.exercises) then logf('E', 'could not read drills from %s', LESSONS_FILE) end
  lessons, byId, lessonSummary = (data and data.exercises) or {}, {}, {}
  local venueById = {}
  for _, v in ipairs((jsonReadFile(VENUES_FILE) or {}).venues or {}) do venueById[v.id] = v end
  for _, lesson in ipairs(lessons) do
    byId[lesson.id] = lesson
    local env = lesson.environment
    local venue = env and venueById[env.venue]
    if venue then
      env.levelId, env.mapDisplayName, env.spawn, env.venueNotes = venue.levelId, venue.name, venue.spawn, venue.notes
    elseif env and env.venue then
      logf('E', '%s: unknown venue %s (%s)', lesson.id, tostring(env.venue), VENUES_FILE)
    end
    table.insert(lessonSummary, {id=lesson.id, title=lesson.title, module=lesson.module,
      parked=lesson.parked ~= nil or nil})
  end
  local warn
  progress, warn = Store.loadProgress()
  if warn then logf('W', '%s', warn) end
  setups, warn = Store.loadSetups()
  if warn then logf('W', '%s', warn) end
  prefs = Store.loadPrefs()
  logf('I', 'loaded %d drills on map %s', #lessons, levelId())
end

local function saveProgress() Store.saveProgress(progress) end

-- The selected drill's authored course definition (assessment.course), or nil.
local function courseDef()
  local lesson = selected and byId[selected]
  return lesson and lesson.assessment and lesson.assessment.course or nil
end

-- Persist the selected drill's start, finish and gates for the current map. A course's
-- gates come from the course, so only its start is saved.
local function venueOf(id) local env = byId[id] and byId[id].environment return env and env.venue or nil end

local function saveSetup()
  local start = startState and {pos = startState.pos, dir = startState.dir, up = startState.up} or nil
  local def = courseDef()
  local marked = not def and #gates > 0 and gates or nil
  -- The venue and course it was marked for: if either changes, the setup is stale (loadSetup).
  Store.putSetup(setups, levelId(), selected, {start = start, finish = finishGate, gates = marked,
    venue = venueOf(selected), course = def and Layout.fingerprint(def) or nil})
end

-- Is a saved setup from before the drill's venue or course changed? Course drills need a matching
-- course fingerprint (a setup without one predates the course); any drill needs the same venue if
-- the setup recorded one (setups from before venues were recorded are kept for marked drills).
local function staleSetup(saved)
  local def = courseDef()
  if def and saved.course ~= Layout.fingerprint(def) then
    return saved.course and 'its course changed' or 'it now lays out its own course'
  end
  if saved.venue and saved.venue ~= venueOf(selected) then return 'it moved to another venue' end
  return nil
end

-- Ground height under (x, y), or `z` when the engine can't tell (be:getSurfaceHeightBelow
-- answers -1e10 or so with nothing below; seen on 0.39.4).
local function groundZ(x, y, z)
  if not (be and be.getSurfaceHeightBelow) then return z end
  local h = be:getSurfaceHeightBelow(vec3(x, y, z + 3))
  if type(h) ~= 'number' or h < z - 20 then return z end
  return h
end

-- Lay the selected drill's course out from the start (or clear it). Course objects sit at a
-- car's height above the ground, like marked gates (the car's position is ~0.4 m up).
local CAR_HEIGHT = 0.4
local function placeCourse()
  local def = courseDef()
  if not (def and startState) then course = nil; return end
  course = Layout.place(def, startState)
  local z0 = startState.pos.z
  for _, g in ipairs(course.gates) do g.pos.z = groundZ(g.pos.x, g.pos.y, z0) + CAR_HEIGHT end
  for _, c in ipairs(course.cones) do c.z = groundZ(c.x, c.y, z0) + CAR_HEIGHT end
  if course.box then course.box.z = groundZ(course.box.x, course.box.y, z0) + CAR_HEIGHT end
  if course.zone then course.zone.pos.z = groundZ(course.zone.pos.x, course.zone.pos.y, z0) + CAR_HEIGHT end
  if course.line then course.line.z = groundZ(course.line.x, course.line.y, z0) + CAR_HEIGHT end
  gates = course.gates
end

function M.onExtensionLoaded()
  load()
  output(true)
end

function M.publish() output(true) end

-- Load the selected drill's saved start/finish for the current map (or clear them).
local function loadSetup()
  startState, finishGate, gates, usingVenueStart = nil, nil, {}, false
  local saved = Store.getSetup(setups, levelId(), selected)
  local def = courseDef()
  local stale = saved and staleSetup(saved)
  if stale then
    logf('I', '%s: dropped the saved setup on %s (%s)', tostring(selected), levelId(), stale)
    Store.putSetup(setups, levelId(), selected, nil)
    saved = nil
  end
  if saved and type(saved.gates) == 'table' and not def then gates = saved.gates end
  if saved and saved.start then
    startState, finishGate = saved.start, (not def) and saved.finish or nil
    lastReason = def and 'Loaded your saved start; the course is laid out ahead of it. Press Retry to begin.'
      or finishGate and 'Loaded your saved start and finish for this map. Press Retry to begin.'
      or 'Loaded your saved start for this map. Press Retry to begin.'
  elseif def then
    -- A course needs no marking: on the drill's own map it starts at the venue's spawn.
    local env = byId[selected].environment or {}
    if env.spawn and sameLevel(levelId(), env.levelId) then
      startState, usingVenueStart = {pos = env.spawn.pos, dir = env.spawn.dir, up = env.spawn.up}, true
      lastReason = 'The course is laid out at the venue. Press Retry to begin.'
    else
      lastReason = 'Press Go to drill: the course is laid out for you at ' .. tostring(env.mapDisplayName) .. '.'
    end
  else
    lastReason = 'Select a suitable car/map, mark the start, and optionally mark a finish gate.'
  end
  if stale then lastReason = 'Your saved start was cleared because ' .. stale .. '. ' .. lastReason end
  placeCourse()
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
local function hasEnd() return finishGate ~= nil or course ~= nil or (endsAtLastGate() and #gates > 0) end

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
  startState, usingVenueStart = snap, false
  activeVehicleId = snap.vehicleId
  phase = 'setup'
  saveSetup()
  placeCourse()
  logf('I', 'start marked for %s on %s at (%.1f, %.1f, %.1f)', selected, levelId(), snap.pos.x, snap.pos.y, snap.pos.z)
  lastReason = course and 'Start marked and saved: the course is now laid out ahead of you from here.'
    or 'Start position and orientation captured and saved for this map.'
  output()
end

-- Course drills: forget the marked start and lay the course out at the venue again.
function M.useVenueStart()
  if not (selected and courseDef()) then return end
  Store.putSetup(setups, levelId(), selected, nil)
  loadSetup()
  phase = 'setup'
  resetRun()
  logf('I', '%s: back to the venue start (%s)', selected, startState and 'laid out' or 'not on this map')
  output()
end

-- HUD toggle: start the next attempt automatically after a graded run.
function M.setAutoRetry(on)
  prefs.autoRetry = on == true
  Store.savePrefs(prefs)
  if not prefs.autoRetry then cur.autoRetryIn = nil end
  output()
end

-- Key bindings (Stream Deck, docs/STREAM_DECK.md) --------------------------------------

function M.toggleAutoRetry()
  M.setAutoRetry(prefs.autoRetry == false)
  if ui_message then ui_message('Rally Academy: auto-retry ' .. (prefs.autoRetry and 'on' or 'off'), 3, 'rallyAcademy') end
end

-- The next or previous drill in curriculum order (wrapping round), with a message so it
-- works without looking at the HUD.
local function step(by)
  if #lessons == 0 then return end
  local idx = 0
  for i, l in ipairs(lessons) do if l.id == selected then idx = i end end
  if idx == 0 then idx = by > 0 and 0 or 1 end
  local lesson = lessons[(idx - 1 + by) % #lessons + 1]
  M.select(lesson.id)
  if ui_message then ui_message('Rally Academy: ' .. lesson.id .. ' · ' .. lesson.title, 4, 'rallyAcademy') end
end
function M.selectNext() step(1) end
function M.selectPrevious() step(-1) end

function M.markFinish()
  if not selected or courseDef() then return end
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
  if not selected or courseDef() then return end
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
  if not selected or courseDef() then return end
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
                       start = startState.pos, finish = finishGate, gates = #gates > 0 and gates or nil,
                       course = course})
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
  local tier = finished and cur.grade and cur.grade.tier
  if tier then
    entry.tiers = entry.tiers or {}
    entry.tiers[tier] = (entry.tiers[tier] or 0) + 1
    if TIER_RANK[tier] > (TIER_RANK[entry.bestTier] or 0) then entry.bestTier = tier end
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

-- The stop zone the rules grade: a marked one, or the course's.
local function stopZone() return finishGate or (course and course.zone) end

-- A stop zone's medal sizes, largest first: {{name, lengthM, widthM}} (the drill's stop_zone
-- rule, then each tier's).
local function tierZones()
  local out = {}
  for _, r in ipairs(assessment().rules or {}) do
    if r.type == 'stop_zone' then out[1] = {name = 'bronze', lengthM = r.lengthM or 5, widthM = r.widthM or 6} end
  end
  for _, t in ipairs(assessment().tiers or {}) do
    for _, r in ipairs(t.rules or {}) do
      if r.type == 'stop_zone' then out[#out + 1] = {name = t.name, lengthM = r.lengthM or 5, widthM = r.widthM or 6} end
    end
  end
  return out
end

-- The parking box and its medal boxes, lowest first: {{name, inset}} (bronze = the drill's
-- own park_in_box rule, then each tier's smaller box).
-- A course line's medal zones, widest first: {{name, maxM}} (metres before the line the front
-- bumper may stop for that medal, from stop_before_line in the rules and the tiers).
local function tierLines()
  local out = {}
  for _, r in ipairs(assessment().rules or {}) do
    if r.type == 'stop_before_line' then out[1] = {name = 'bronze', maxM = r.maxM or 2, minM = r.minM or 0} end
  end
  for _, t in ipairs(assessment().tiers or {}) do
    for _, r in ipairs(t.rules or {}) do
      if r.type == 'stop_before_line' then out[#out + 1] = {name = t.name, maxM = r.maxM or 2, minM = r.minM or 0} end
    end
  end
  return out
end

local function tierBoxes()
  local out = {{name = 'bronze', inset = 0}}
  for _, r in ipairs(assessment().rules or {}) do
    if r.type == 'park_in_box' then out[1].inset = r.insetM or 0 end
  end
  for _, t in ipairs(assessment().tiers or {}) do
    for _, r in ipairs(t.rules or {}) do
      if r.type == 'park_in_box' then out[#out + 1] = {name = t.name, inset = r.insetM or 0} end
    end
  end
  return out
end

-- The car's footprint (layout.lua) from its node positions: getNodePosition gives each node's
-- offset from the car's position in world axes (0.39.4), so project on forward and right.
-- Measured once per car; a car without nodes gets a centred box from its initial size.
local function measureCar(veh)
  local key = tostring(veh:getID()) .. '|' .. tostring(veh.partConfig)
  if carSize and carSize.key == key then return carSize.car end
  local d = veh:getDirectionVector()
  local fx, fy = d.x, d.y
  local n = math.sqrt(fx * fx + fy * fy)
  if n == 0 then return nil end
  fx, fy = fx / n, fy / n
  local car
  local count = veh.getNodeCount and veh:getNodeCount() or 0
  if count > 0 then
    local lo, hi, left, right = math.huge, -math.huge, math.huge, -math.huge
    for i = 0, count - 1 do
      local p = veh:getNodePosition(i)
      local a, s = p.x * fx + p.y * fy, p.x * fy - p.y * fx
      lo, hi, left, right = math.min(lo, a), math.max(hi, a), math.min(left, s), math.max(right, s)
    end
    car = {front = hi, rear = -lo, left = -left, right = right}
  elseif veh.getInitialLength then
    car = Layout.centredCar(veh:getInitialLength(), veh:getInitialWidth())
  end
  if not car then return nil end
  carSize = {key = key, car = car}
  logf('I', 'car footprint: %.2f m long, %.2f m wide (front %.2f, rear %.2f, left %.2f, right %.2f of its position)',
    car.front + car.rear, car.left + car.right, car.front, car.rear, car.left, car.right)
  return car
end

local function drawCourse()
  local zoneLength, zoneWidth = stopZoneSize()
  local active = phase == 'ready' or phase == 'running'
  local footprint
  if course and course.box and cur.aid and carSize then
    local veh = currentVehicle()
    if veh then
      local p, h = veh:getPosition(), veh:getDirectionVector()
      footprint = Layout.corners(carSize.car, p.x, p.y, h.x, h.y)
    end
  end
  Course.draw({
    gates = gates, gateResults = cur.gateResults,
    nextGate = active and cur.gateIdx or nil,
    finish = stopZone(),
    finishKind = usesStopLine() and 'line' or endsOnStop() and 'zone' or 'circle',
    zoneTiers = course and course.zone and tierZones(),
    zoneLength = zoneLength, zoneWidth = zoneWidth,
    cones = course and course.cones, coneResults = cur.coneResults, nextCone = active and cur.coneIdx or nil,
    box = course and course.box, boxes = course and course.box and tierBoxes(), fit = cur.fit,
    line = course and course.line, lineCones = course and course.lineCones, lineZones = course and course.line and tierLines(),
    footprint = footprint,
  })
end

-- "1.2 m to go · 0.3 m left of centre": where the car's body is against the box centre.
local function aidText(fit)
  local along = fit.along < -0.05 and string.format('%.1f m to go', -fit.along)
    or fit.along > 0.05 and string.format('%.1f m past the centre', fit.along) or 'level with the centre'
  local side = math.abs(fit.side) < 0.05 and 'centred'
    or string.format('%.1f m %s of centre', math.abs(fit.side), fit.side > 0 and 'right' or 'left')
  return along .. ' · ' .. side
end

-- Live course feedback while driving: cones passed on the right side, a marker clipped, and
-- near the box, where the car is and which medal box it fits right now. Grading re-reads all
-- of this from the run record (rules.lua); this is only what the HUD shows meanwhile.
local function trackCourse(veh, vpos)
  local cone = course.cones[cur.coneIdx]
  if cone and cur.prevPos then
    local c = Layout.coneCrossing(cone, cur.prevPos, vpos)
    if c then
      local ok = c.side == cone.keep
      cur.coneResults[cur.coneIdx] = ok and 'passed' or 'missed'
      lastReason = ok and 'Cone passed on the correct side.'
        or ('Wrong side of the cone: ' .. Layout.keepText(cone.keep) .. '.')
      logf('I', '%s: cone %d %s (%.1f m %s of it)', selected, cur.coneIdx, cur.coneResults[cur.coneIdx],
        math.abs(c.offset), c.offset >= 0 and 'right' or 'left')
      cur.coneIdx = cur.coneIdx + 1
      cur.uiAccum = 1
    end
  end
  local car = carSize and carSize.car
  if not car then return end
  local h = veh:getDirectionVector()
  if not cur.clipped then
    for _, m in ipairs(course.markers) do
      if Layout.distanceToCar(car, vpos.x, vpos.y, h.x, h.y, m.x, m.y) < Layout.MARKER_RADIUS then
        cur.clipped, lastReason, cur.uiAccum = m.name, 'Clipped ' .. m.name .. '.', 1
        logf('I', '%s: clipped %s', selected, m.name)
        break
      end
    end
  end
  if course.zone then
    -- The car's position against the zone centre, as stop_zone grades it.
    local z = course.zone
    local dx, dy = vpos.x - z.pos.x, vpos.y - z.pos.y
    local along, side = dx * z.dir.x + dy * z.dir.y, dx * z.dir.y - dy * z.dir.x
    cur.fit = nil
    for _, t in ipairs(tierZones()) do
      if math.abs(along) <= t.lengthM / 2 and math.abs(side) <= t.widthM / 2 then cur.fit = t.name end
    end
    cur.aid = math.abs(along) < 30 and ((along < -0.05 and string.format('%.1f m to the zone centre', -along)
      or along > 0.05 and string.format('%.1f m past the centre', along) or 'on the zone centre')) or nil
  end
  if course.line then
    local before = Layout.bumperToLine(course.line, car, vpos.x, vpos.y, h.x, h.y)
    cur.fit = nil
    for _, z in ipairs(tierLines()) do
      if before >= z.minM and before <= z.maxM then cur.fit = z.name end
    end
    cur.aid = math.abs(before) < 25 and (before >= 0 and string.format('%.1f m to the line', before)
      or string.format('%.1f m past the line', -before)) or nil
  end
  if not course.box then return end
  local first
  cur.fit = nil
  for _, t in ipairs(tierBoxes()) do
    local f = Layout.boxFit(course.box, car, vpos.x, vpos.y, h.x, h.y, t.inset)
    first = first or f
    if f.inside then cur.fit = t.name end
  end
  local near = math.abs(first.along) < 15 and math.abs(first.side) < 8
  cur.aid = near and aidText(first) or nil
end

-- The HUD's course panel: a checklist (gate, cone, box), the parking aid and the medal box
-- the car is in. nil for drills without a course.
function liveCourse()
  if not course then return nil end
  local steps = {}
  for i = 1, #course.gates do
    local g = course.gates[i]
    steps[#steps + 1] = {label = g.label or (#course.gates > 1 and ('Gate ' .. i) or 'Gate'), state = cur.gateResults[i] or 'todo'}
  end
  for i = 1, #course.cones do
    local c = course.cones[i]
    steps[#steps + 1] = {label = c.label or (#course.cones > 1 and ('Cone ' .. i) or 'Cone'), state = cur.coneResults[i] or 'todo'}
  end
  if course.box then
    local state = 'todo'
    for _, c in ipairs(cur.grade and cur.grade.checks or {}) do
      if c.type == 'park_in_box' then state = c.ok and 'passed' or 'missed' end
    end
    steps[#steps + 1] = {label = course.box.label or 'Box', state = state}
  end
  if course.zone then
    local state = 'todo'
    for _, c in ipairs(cur.grade and cur.grade.checks or {}) do
      if c.type == 'stop_zone' then state = c.ok and 'passed' or 'missed' end
    end
    steps[#steps + 1] = {label = course.zone.label or 'Stop zone', state = state}
  end
  if course.line then
    local state = 'todo'
    for _, c in ipairs(cur.grade and cur.grade.checks or {}) do
      if c.type == 'stop_before_line' then state = c.ok and 'passed' or 'missed' end
    end
    steps[#steps + 1] = {label = course.line.label or 'Line', state = state}
  end
  if phase == 'ready' or phase == 'running' then
    for _, st in ipairs(steps) do
      if st.state == 'todo' then st.state = 'next'; break end
    end
  end
  local cone = course.cones[1]
  return {steps = steps, aid = cur.aid or false, fit = cur.fit or false, clipped = cur.clipped or false,
          keep = cone and cone.keep or false}
end

local function tierLabel(name) return (name:gsub('^%l', string.upper)) end

-- Is something the rules need still unmarked (B01's first run is the one you mark the stop
-- zone from)? Then don't auto-retry: the driver needs to stay where the car stopped.
local ZONE_RULES = {stop_zone = true, stop_before_line = true}
local function setupMissing()
  local gateRules = {}
  for _, t in ipairs(Rules.GATE_RULES) do gateRules[t] = true end
  for _, r in ipairs(assessment().rules or {}) do
    if ZONE_RULES[r.type] and not stopZone() and not (course and course.line) then return true end
    if gateRules[r.type] and #gates == 0 then return true end
  end
  return false
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
  cur.grade = Rules.grade(a, run, {zone = stopZone(), gates = gates, course = course,
                                   car = carSize and carSize.car, time = cur.lastTime})
  if run then run.grade = cur.grade end
  local firstFail
  for _, c in ipairs(cur.grade.checks) do
    logf('I', '%s:   %s %s', selected, c.ok and 'ok  ' or 'FAIL', c.text)
    if not c.ok and not firstFail then firstFail = c.text end
  end
  M.recordAttempt(cur.grade.passed)
  local g = cur.grade
  local verdict = g.passed and ('PASS' .. (g.tier and (' · ' .. tierLabel(g.tier)) or '') .. '.')
    or ('MISS: ' .. firstFail .. '.')
  if g.tier then logf('I', '%s:   medal %s%s', selected, g.tier, g.nextTier and (', next: ' .. g.nextTier.text) or '') end
  if prefs.autoRetry ~= false and not setupMissing() then
    cur.autoRetryIn = AUTO_RETRY_DELAY
    lastReason = verdict .. ' Next attempt in a moment; drive off to stay here.'
  else
    lastReason = verdict .. ' Retry for the next attempt.'
  end
  output()
end

-- After a graded run: count down, then Retry, unless the driver drives off. Sim time, so a
-- physics pause holds it.
local function autoRetryTick(dtSim)
  local veh = currentVehicle()
  if veh and veh:getVelocity():length() > AUTO_RETRY_CANCEL_SPEED then
    cur.autoRetryIn = nil
    lastReason = 'Auto-retry cancelled: you drove off. Press Retry when you want the next attempt.'
    output()
    return
  end
  local shown = math.ceil(cur.autoRetryIn)
  cur.autoRetryIn = cur.autoRetryIn - math.max(0, dtSim or 0)
  if cur.autoRetryIn <= 0 then
    cur.autoRetryIn = nil
    M.retry()
    return
  end
  if math.ceil(cur.autoRetryIn) ~= shown then output() end
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
  if selected and phase == 'scored' and cur.autoRetryIn then autoRetryTick(dtSim) end
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
    if course then
      -- Fresh from Retry's repair, so the body is undamaged: measure it for the box and markers.
      local car = measureCar(veh)
      if run then run.meta.car = car end
    end
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
  if course then trackCourse(veh, vpos) end
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
    lastReason = 'At ' .. env.mapDisplayName .. ' in the drill car, '
      .. (usingVenueStart and 'at the start of the course.' or 'at your saved start.') .. ' Go when ready; Retry any time.'
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

-- Venue bookmarks ("Rally Academy: Save spot", spots.lua) --------------------------

-- Nearest road from the AI road network: name, width (2 x node radius), drivability, distance.
local function nearestRoad(pos)
  if not (map and map.findClosestRoad and map.getMap) then return nil end
  local n1, n2, dist = map.findClosestRoad(pos)
  local nodes = n1 and (map.getMap() or {}).nodes
  local a, b = nodes and nodes[n1], nodes and n2 and nodes[n2]
  if not a then return nil end
  local link = (a.links and a.links[n2]) or (b and b.links and b.links[n1]) or {}
  local radius = b and math.min(a.radius or 0, b.radius or 0) or a.radius or 0
  return {name = n1 .. '-' .. tostring(n2), width = 2 * radius, drivability = link.drivability, dist = dist or 0}
end

-- Distance to static objects (walls, barriers, trees) in eight directions, up to 150 m.
local function roomAround(veh)
  local p = veh:getPosition() + vec3(0, 0, 0.6)
  local fwd = vec3(veh:getDirectionVector()):normalized()
  local right = fwd:cross(vec3(0, 0, 1)):normalized()
  local out = {}
  for i, deg in ipairs(Spots.ROOM_ANGLES) do
    local r = math.rad(deg)
    out[i] = castRayStatic and castRayStatic(p, (fwd * math.cos(r) + right * math.sin(r)):normalized(), 150) or 150
  end
  return out
end

-- Save where the car is as a candidate venue. The car reports its wheels' surfaces back
-- through onSpotSurfaces (names only exist in vehicle Lua).
function M.saveSpot(note)
  local veh = currentVehicle()
  local snap = snapshotVehicle()
  if not (veh and snap) then lastReason = 'No player vehicle'; output(); return nil end
  local data = Store.loadSpots()
  local spot = Spots.add(data.spots, Spots.record({level = levelId(), pos = snap.pos, dir = snap.dir, upZ = snap.up.z,
    room = roomAround(veh), road = nearestRoad(veh:getPosition()), note = note}))
  Store.saveSpots(data)
  veh:queueLuaCommand(string.format("local mats = particles.getMaterialsParticlesTable() local s = {} "
    .. "for i = 0, wheels.wheelRotatorCount - 1 do local w = wheels.wheelRotators[i] "
    .. "local m = particles.getMaterialByID(mats, w.contactMaterialID1) s[w.name] = m and m.name or 'none' end "
    .. "obj:queueGameEngineLua('if extensions.rallyAcademy then extensions.rallyAcademy.onSpotSurfaces(%d, ' .. serialize(s) .. ') end')",
    spot.id))
  local msg = Spots.summary(spot)
  logf('I', '%s at (%.1f, %.1f, %.1f) on %s', msg, spot.pos.x, spot.pos.y, spot.pos.z, spot.level)
  if ui_message then ui_message(msg, 6, 'rallyAcademy') end
  lastReason = msg
  output()
  return spot.id
end

function M.onSpotSurfaces(id, surfaces)
  local data = Store.loadSpots()
  local spot = Spots.find(data.spots, id)
  if not spot or type(surfaces) ~= 'table' then return end
  spot.surfaces = surfaces
  Store.saveSpots(data)
end

-- Developer hooks (tools/ingame scenarios) -----------------------------------------

-- A snapshot of the session for test scripts, instead of reading Lua internals.
function M.debugState()
  return {phase = phase, selected = selected, level = levelId(), elapsed = cur.elapsed, lastTime = cur.lastTime,
          hasStart = startState ~= nil, hasFinish = finishGate ~= nil, gateCount = #gates, gateIdx = cur.gateIdx,
          attempts = attempts, successes = successes, reason = lastReason,
          menuOpen = menuOpen, passed = cur.grade and cur.grade.passed, -- false = graded MISS, nil = not graded
          tier = cur.grade and cur.grade.tier, nextTier = cur.grade and cur.grade.nextTier and cur.grade.nextTier.text,
          hasCourse = course ~= nil, usingVenueStart = usingVenueStart, autoRetry = prefs.autoRetry ~= false,
          autoRetryIn = cur.autoRetryIn, clipped = cur.clipped, fit = cur.fit, aid = cur.aid,
          car = carSize and carSize.car}
end

-- Record the car's telemetry outside any drill (venue fit tests, tools/ingame/fit.py): no
-- setup, progress or grading is touched. getLastRun() returns the record; devRecordStop()
-- closes it and returns the sample count.
function M.devRecordStart()
  local veh = currentVehicle()
  if not veh then return false end
  if phase == 'ready' or phase == 'running' then backToSetup('Recording a venue fit test.') end
  if RunRecord.isOpen(run) then endRun('abandoned') end
  run = RunRecord.new({drill = 'fit test', level = levelId(), vehicleId = veh:getID()})
  startSampling(veh)
  logf('I', 'fit test: recording started')
  return true
end

function M.devRecordStop()
  if not RunRecord.isOpen(run) then return 0 end
  endRun('finished')
  return #run.samples
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
  startState, finishGate, gates, course, usingVenueStart = nil, nil, {}, nil, false
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
