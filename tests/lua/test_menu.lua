-- The Academy screen's Lua side: menu data, Start drill, open/close and pause.
local H = require('ra_helpers')
local stubs = H.stubs
local eq = H.eq
local setup = H.setup
local drive = H.drive
local T = {}

function T.menu_data_lists_every_drill_in_order_with_progress()
  local h, M = setup()
  M.select('T01')
  h.vehicle.pos = stubs.vec3(0, 0, 0)
  M.markStart()
  M.retry()
  drive(h, M, 1, {x = 0, y = 5, z = 0})
  M.recordAttempt(true)
  local d = M.getMenuData()
  local shipped = 0
  for _, l in ipairs(d.lessons) do if not H.stubs.isTestDrill(l.id) then shipped = shipped + 1 end end
  eq(shipped, 42, 'all shipped drills (plus the test drills T01-T04 the stubs add)')
  eq(d.lessons[1].id, 'A01', 'curriculum order starts at A01')
  eq(d.lessons[42].id, 'F07', 'and ends at F07')
  eq(d.progress.T01.totalPasses, 1, 'progress included')
  eq(d.selected, 'T01', 'current HUD drill')
  eq(d.info.version, jsonReadFile('ui/modules/apps/RallyAcademy/app.json').version, 'mod version for About')
  assert(d.info.author, 'author for Credits')
end

function T.menu_start_selects_the_drill_and_loads_its_map()
  local h, M = setup()
  eq(M.startDrill('nope'), false, 'unknown drill refused')
  eq(M.startDrill('E08'), true, 'started')
  eq(h.lastState().selected, 'E08', 'selected for the HUD too')
  eq(#h.levelsLoaded, 1, 'its map is loading')
  eq(#h.freeroamStarts, 1, 'started as freeroam, so the game leaves the menus')
  eq(#h.uiRoutes, 0, 'menu stays up while the map loads')
  h.level = 'utah' -- E08's map has loaded
  h.syncSpawnHook = true
  _G.extensions = {rallyAcademy = M}
  M.onClientPostStartMission('/levels/utah/')
  for _ = 1, 20 do M.onUpdate(0.1, 0.1) end
  eq(h.uiRoutes[1], 'play', 'switched to the game view once the car is placed')
  M.goToDrill()
  for _ = 1, 20 do M.onUpdate(0.1, 0.1) end
  eq(#h.uiRoutes, 1, 'Go to drill from inside the map leaves the UI alone')
  _G.extensions = nil
end

function T.menu_key_in_a_map_pauses_and_back_resumes()
  local h, M = setup()
  M.toggleMenu()
  eq(h.uiRoutes[#h.uiRoutes], 'menu.rallyAcademy', 'screen opened')
  eq(h.paused, true, 'physics paused while browsing')
  M.toggleMenu()
  eq(h.uiRoutes[#h.uiRoutes], 'play', 'back to driving')
  eq(h.paused, false, 'resumed')
end

function T.menu_leaves_an_already_paused_game_paused()
  local h, M = setup()
  h.paused = true
  M.openMenu()
  M.onMenuLeave() -- left with Esc
  eq(h.paused, true, 'the player paused it, so it stays paused')
end

function T.menu_start_drill_resumes_physics()
  local h, M = setup()
  M.openMenu()
  M.startDrill('T01')
  eq(h.paused, false, 'resumed for the drive')
end

function T.menu_back_from_the_main_menu_returns_there()
  local h, M = setup()
  h.level = nil
  M.openMenu()
  eq(h.paused, false, 'nothing to pause without a map')
  M.closeMenu()
  eq(h.uiRoutes[#h.uiRoutes], 'menu', 'main menu')
end

-- ADR 0006: full stages are the game's Rally mode; only F06 and F07 remain, IDs unchanged.
function T.stage_drills_are_cut_and_the_rest_keep_their_ids()
  local h = setup()
  local ids = {}
  for _, l in ipairs(h.lastState().lessons) do ids[l.id] = true end
  for _, gone in ipairs({'F01', 'F02', 'F03', 'F04', 'F05', 'F08'}) do assert(not ids[gone], gone .. ' should be cut') end
  assert(ids.F06 and ids.F07, 'F06 and F07 stay, same IDs')
end

return T
