-- Saved data in the user folder: progress per drill, and marked setups (start, finish,
-- gates) per map and drill. Engine-facing only through jsonReadFile/jsonWriteFile.
-- Entries for drills no longer in the catalogue (e.g. cut by ADR 0006) are kept, unused:
-- deleting player data automatically isn't worth the risk if the catalogue fails to load.
local S = {}

S.PROGRESS_FILE = 'settings/rallyAcademyProgress.json'
S.SETUPS_FILE = 'settings/rallyAcademySetups.json'
S.SPOTS_FILE = 'settings/rallyAcademy/spots.json'

-- Read a saved file; `valid(t)` checks its shape. Returns the table (or `fallback`) and a
-- warning when a file exists but can't be used.
local function read(path, valid, fallback)
  local t = jsonReadFile(path)
  if type(t) == 'table' and valid(t) then return t, nil end
  if t ~= nil then return fallback, 'ignoring unreadable ' .. path end
  return fallback, nil
end

-- progress = {schemaVersion = 1, lessons = {[drillId] = {totalAttempts, totalPasses, bestTime, lastSessionPassed,
--   bestTier, tiers = {bronze = n, silver = n, gold = n}}}} (tiers: drills with medals)
function S.loadProgress()
  return read(S.PROGRESS_FILE, function(t) return type(t.lessons) == 'table' end, {schemaVersion = 1, lessons = {}})
end

function S.saveProgress(progress)
  jsonWriteFile(S.PROGRESS_FILE, progress, true)
end

-- setups = {schemaVersion = 1, levels = {[levelId] = {[drillId] = {start, finish, gates}}}}
function S.loadSetups()
  return read(S.SETUPS_FILE, function(t) return type(t.levels) == 'table' end, {schemaVersion = 1, levels = {}})
end

function S.getSetup(setups, levelId, drillId)
  return setups.levels[levelId] and setups.levels[levelId][drillId] or nil
end

-- Save one drill's setup on one map. The vehicle id isn't stored: ids change every
-- session, and Retry applies to whichever car you drive.
function S.putSetup(setups, levelId, drillId, setup)
  setups.levels[levelId] = setups.levels[levelId] or {}
  setups.levels[levelId][drillId] = setup
  jsonWriteFile(S.SETUPS_FILE, setups, true)
end

-- spots = {schemaVersion = 1, spots = {{id, level, pos, dir, slopeDeg, room, road, surfaces, note}, ...}}
-- (venue bookmarks, spots.lua)
function S.loadSpots()
  return read(S.SPOTS_FILE, function(t) return type(t.spots) == 'table' end, {schemaVersion = 1, spots = {}})
end

function S.saveSpots(spots)
  jsonWriteFile(S.SPOTS_FILE, spots, true)
end

-- prefs = {schemaVersion = 1, autoRetry = bool} (the player's choices in the HUD)
S.PREFS_FILE = 'settings/rallyAcademy/prefs.json'

function S.loadPrefs()
  local t = read(S.PREFS_FILE, function(p) return type(p) == 'table' end, {schemaVersion = 1})
  if t.autoRetry == nil then t.autoRetry = true end -- on by default (owner decision, PRODUCT.md)
  return t
end

function S.savePrefs(prefs)
  jsonWriteFile(S.PREFS_FILE, prefs, true)
end

return S
