-- Watch AI on a technique drill (ADR 0015): the skill runner drives the card in the player's car, the Coach panel
-- shows each phase's cue, the trace marks the phases, and half speed slows the game for it. On T05, with the shipped
-- flick card given a line for T05 (straight ahead).
local stubs = require('beamng_stubs')
local H = require('ra_helpers')
local json = require('json')
local eq, has = H.eq, H.has
local T = {}

local root = (arg and arg[1]) or '.'
local CARD_PATH = 'gameplay/rallyAcademy/techniques/scandinavian_flick.json'

local function onT05()
  local h, M = H.setup()
  local f = assert(io.open(root .. '/mod/' .. CARD_PATH, 'r'))
  local card = json.decode(f:read('*a'))
  f:close()
  card.lines.T05 = {{0, 0}, {0, 150}}
  h.files[CARD_PATH] = json.encode(card)
  M.select('T05')
  h.vehicle.pos, h.vehicle.dir = stubs.vec3(0, 0, 0), stubs.vec3(0, 1, 0)
  M.markStart()
  return h, M, card
end

local function commands(h, needle)
  local n, last = 0, nil
  for _, c in ipairs(h.vehicle.luaCommands) do
    if c:find(needle, 1, true) then n, last = n + 1, c end
  end
  return n, last
end

function T.offered_in_the_drills_car_on_its_course()
  local h, M = onT05()
  local s = h.lastState()
  eq(s.canDemo, true, 'Watch AI is offered')
  eq(s.demoNote, false, 'no note')
  eq(s.demoSlowMo, false, 'full speed by default')
  h.vehicle.partConfig = 'vehicles/covet/rally_gravel.pc'
  M.retry()
  s = h.lastState()
  eq(s.canDemo, false, 'another car: not offered')
  has(s.demoNote, 'Go to drill swaps it')
  M.demo()
  eq(commands(h, 'rallyAcademy/driver'), 0, 'and the runner stays out of the car')
  has(h.lastState().reason, "drives the drill's car")
end

function T.watch_ai_resets_the_car_and_has_the_runner_drive_the_card()
  local h, M = onT05()
  h.vehicle.pos = stubs.vec3(30, 50, 0)
  M.demo()
  local s = h.lastState()
  eq(s.phase, 'ready', 'back at the start')
  eq(s.demo, true, 'a demo')
  local n, cmd = commands(h, "extensions.load('rallyAcademy/driver')")
  eq(n, 1, 'the runner is loaded into the car')
  has(cmd, 'extensions.rallyAcademy_driver.configure({')
  has(cmd, '["flickS"]=40')
  has(cmd, '["exitS"]=100')
  local f = assert(io.open(root .. '/mod/gameplay/rallyAcademy/techniques/scandinavian_flick-gravel.json', 'r'))
  local tuned = json.decode(f:read('*a'))
  f:close()
  has(cmd, string.format('["approachKmh"]=%.6g', tuned.dials.approachKmh)) -- the tuned gravel dials
  has(cmd, '["steerRatePerS"]=4')
  has(s.reason, 'The AI is driving the scandinavian flick')
  eq(commands(h, 'ai.driveUsingPath'), 0, "not the game's AI")
end

function T.each_phase_shows_its_cue_and_marks_the_trace()
  local h, M, card = onT05()
  local s = H.gateRun(h, M, {begin = function()
    M.demo()
    M.onDriverPhase('approach', H.simT)
    eq(h.lastState().demoCue, card.phases[1].cue, "the approach's cue")
    M.onDriverPhase('feint', H.simT + 1.5)
    local st = h.lastState()
    eq(st.demoCue, 'Lift and flick away from the corner', "the feint's cue")
    eq(st.demoPhase, 'feint', 'the step it is on')
    eq(#st.demoSteps, 5, "the card's five steps, for the Coach panel")
    eq(st.demoSteps[2].id, 'feint', 'in order')
  end})
  eq(s.phase, 'scored', 'graded at the last gate')
  eq(s.attempts, 0, 'not an attempt')
  has(s.reason, 'AI demo: PASS')
  local phases = {}
  for _, m in ipairs(s.trace.marks) do
    if m.kind == 'phase' then phases[#phases + 1] = m.label end
  end
  eq(table.concat(phases, ','), 'feint', 'the feint is marked (the approach has no mark)')
  M.onDriverPhase('stop', H.simT)
  eq(h.lastState().demoCue, false, 'no cue once it stops')
  eq(h.lastState().demoPhase, 'stop', 'past the last step')
  M.retry()
  eq(h.lastState().demoSteps, false, 'no steps outside a demo')
end

function T.phases_are_ignored_outside_a_demo()
  local h, M = onT05()
  M.retry()
  M.onDriverPhase('feint', 1) -- tools/driver runs the runner without Watch AI
  eq(h.lastState().demoCue, false, 'no cue')
end

function T.retry_stops_the_runner_and_half_speed_comes_and_goes_with_the_demo()
  local h, M = onT05()
  M.setDemoSlowMo(true)
  has(h.files['settings/rallyAcademy/prefs.json'], '"demoSlowMo":true')
  M.demo()
  eq(h.simSpeed, 0.5, 'half speed while the AI drives')
  M.retry()
  eq(commands(h, 'extensions.rallyAcademy_driver.stop()'), 1, 'Retry switches the runner off')
  eq(h.simSpeed, 1, 'and puts the speed back')
  eq(h.lastState().demo, false, "the next run is the player's")
end

return T
