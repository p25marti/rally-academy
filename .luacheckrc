-- luacheck config. BeamNG's Game Engine Lua is LuaJIT (Lua 5.1 + extensions).
std = "luajit"
max_line_length = 140
codes = true

-- Globals provided by BeamNG's GE Lua environment that the mod may READ.
-- Add here only after confirming the global exists in-game (docs/BEAMNG_API_NOTES.md).
read_globals = {
  "be", "extensions", "guihooks", "log", "dump", "dumpz",
  "vec3", "quat", "quatFromDir",
  "jsonReadFile", "jsonWriteFile", "readFile", "writeFile", "FS",
  "deepcopy", "tableSize", "scenetree", "core_vehicles", "core_input_actions",
  "spawn", "getPlayerVehicle", "setExtensionUnloadMode", "getCurrentLevelIdentifier",
  "getObjectByID", "core_levels", "debugDrawer", "ColorF", "freeroam_freeroam", "ui_router", "simTimeAuthority", "castRayStatic", "map", "ui_message",
  "sanitizeVehicleSpawnOptions", "RESET_PHYSICS",
}

-- Vehicle Lua (runs inside each car's own VM), verified 0.39.4.
files["mod/lua/vehicle/**"] = { read_globals = { "electrics", "wheels", "obj", "beamstate" } }

-- modScript.lua calls BeamNG's global `load(extName)`, which shadows Lua's builtin.
files["mod/scripts/**"] = { read_globals = { "load", "setExtensionUnloadMode" } }

files["tests/lua/**"] = {
  globals = { "_G", "vec3", "quatFromDir", "log", "dump", "be", "guihooks", "jsonReadFile", "jsonWriteFile",
              "debugDrawer", "ColorF" },
}
files["tests/vendor/**"] = { only = {} } -- third-party, not linted
exclude_files = { "tests/vendor/**" }
