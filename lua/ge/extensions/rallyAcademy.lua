-- Rally Academy: main game-engine extension
local M = {}

local logTag = "rallyAcademy"

local function onExtensionLoaded()
  log("I", logTag, "Rally Academy loaded")
end

local function onExtensionUnloaded()
  log("I", logTag, "Rally Academy unloaded")
end

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

return M
