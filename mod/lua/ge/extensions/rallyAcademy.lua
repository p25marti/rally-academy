-- Rally Academy prototype (BeamNG GE Lua); NOT tested in a live 0.39 installation.
-- UI calls extensions.load('rallyAcademy') and extensions.rallyAcademy.<method>().
local M = {}
local LESSONS_FILE = 'gameplay/rallyAcademy/exercises.json'
local SAVE_FILE = 'settings/rallyAcademyProgress.json'
local lessons, byId, lessonSummary = {}, {}, {}
local progress = {schemaVersion = 1, lessons = {}}
local selected, startState, finishGate = nil, nil, nil
local phase, elapsed, uiAccum = 'idle', 0, 0
local lastTime, lastReason = nil, ''
local attempts, successes = 0, 0
local activeVehicleId = nil

local function currentVehicle()
  return be and be:getPlayerVehicle(0) or nil
end

local function snapshotVehicle()
  local veh = currentVehicle()
  if not veh then return nil end
  local pos = veh:getPosition()
  local forward = vec3(veh:getDirectionVector()):normalized()
  local up = vec3(veh:getDirectionVectorUp()):normalized()
  -- setPositionRotation expects the rotation built from the *negated* direction
  -- vector (as core_checkpoints does); without it Retry faces the car backwards.
  local rot = quatFromDir(-forward, up)
  return {
    vehicleId = veh:getID(),
    pos = {x=pos.x, y=pos.y, z=pos.z},
    rot = {x=rot.x, y=rot.y, z=rot.z, w=rot.w}
  }
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
    prototypeWarning = 'Route detection and self-assessment only; car-control metrics are not implemented.'
  })
end

local function load()
  local data = jsonReadFile(LESSONS_FILE)
  lessons, byId, lessonSummary = (data and data.exercises) or {}, {}, {}
  for _, lesson in ipairs(lessons) do
    byId[lesson.id] = lesson
    table.insert(lessonSummary, {id=lesson.id, title=lesson.title, module=lesson.module})
  end
  local saved = jsonReadFile(SAVE_FILE)
  if type(saved) == 'table' and type(saved.lessons) == 'table' then progress = saved end
end

local function saveProgress()
  jsonWriteFile(SAVE_FILE, progress, true)
end

function M.onExtensionLoaded()
  load()
  output(true)
end

function M.publish() output(true) end

function M.select(id)
  if type(id) ~= 'string' or not byId[id] then return end
  selected, startState, finishGate = id, nil, nil
  phase, elapsed, attempts, successes, lastTime = 'setup', 0, 0, 0, nil
  activeVehicleId = nil
  lastReason = 'Select a suitable car/map, mark the start, and optionally mark a finish gate.'
  output()
end

function M.markStart()
  if not selected then return end
  local snap = snapshotVehicle()
  if not snap then lastReason = 'No player vehicle'; output(); return end
  startState = snap
  activeVehicleId = snap.vehicleId
  phase = 'setup'
  lastReason = 'Start position and orientation captured.'
  output()
end

function M.markFinish()
  if not selected then return end
  local snap = snapshotVehicle()
  if not snap then lastReason = 'No player vehicle'; output(); return end
  finishGate = {pos=snap.pos, radius=5}
  lastReason = '5 m finish circle captured; retry to return to your start.'
  output()
end

function M.retry()
  local veh = currentVehicle()
  if not veh or not startState or veh:getID() ~= activeVehicleId then
    lastReason = 'Mark a start with the current vehicle before retrying.'
    output(); return
  end
  local p,r = startState.pos, startState.rot
  veh:setPositionRotation(p.x,p.y,p.z, r.x,r.y,r.z,r.w)
  elapsed, lastTime = 0, nil
  phase = 'ready'
  lastReason = 'Ready: accelerate to begin. Retry again any time.'
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
  lastReason = (passed and 'Recorded a clean attempt.' or 'Recorded an unsuccessful attempt.')
  output()
end

function M.onUpdate(dtReal, dtSim)
  if not selected or (phase ~= 'ready' and phase ~= 'running') then return end
  local veh = currentVehicle()
  if not veh or veh:getID() ~= activeVehicleId then return end
  uiAccum = uiAccum + (dtReal or 0)
  local speed = veh:getVelocity():length()
  -- The frame after a teleport reports a huge velocity (~430 m/s seen in 0.39.4),
  -- so also require the car to have actually left the start.
  local s = startState.pos
  local leftStart = (veh:getPosition() - vec3(s.x, s.y, s.z)):length() > 0.5
  if phase == 'ready' and speed > 1 and leftStart then
    phase = 'running'
    lastReason = 'Run started.'
    output()
  end
  if phase ~= 'running' then return end
  -- dtSim is game-simulation time, unlike wall clock. Physics pause should not add time.
  elapsed = elapsed + math.max(0, dtSim or 0)
  if finishGate and elapsed > 1 then
    local vpos = veh:getPosition()
    local gate = vec3(finishGate.pos.x,finishGate.pos.y,finishGate.pos.z)
    if (vpos - gate):length() <= finishGate.radius then
      lastTime = elapsed
      phase = 'review'
      lastReason = 'Finish reached. Grade the technique using Pass/Miss.'
      output()
      return
    end
  end
  if uiAccum >= 0.25 then
    uiAccum = 0
    output()
  end
end

return M
