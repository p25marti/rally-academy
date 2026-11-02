-- Unit tests for technique demos (technique.lua, pure, ADR 0015): a card and its tuned dials made into the skill
-- runner's configuration, and the shipped flick card read as the mod reads it.
local Tq = require('ge/extensions/rallyAcademy/technique')
local H = require('ra_helpers')
local eq, near = H.eq, H.near
local T = {}

local root = (arg and arg[1]) or '.'
local json = require('json')

local function readJson(path)
  local f = assert(io.open(root .. '/mod/' .. path, 'r'))
  local s = f:read('*a')
  f:close()
  return json.decode(s)
end

local CARD = {
  phases = {
    {id = 'approach', cue = 'Settle', dials = {approachKmh = {55, 80, 66}}},
    {id = 'feint', cue = 'Flick away', mark = 'feint', dials = {feintSteer = {0.2, 1, 0.5}}},
  },
  surfaces = {asphalt = {approachKmh = 72}},
  lines = {C08 = {{0, 0}, {0, 10}, {-10, 20}}},
  humanLimits = {steerRatePerS = 4},
}
local NORTH = {pos = {x = 0, y = 0, z = 5}, dir = {x = 0, y = 1, z = 0}}

function T.dials_are_the_cards_then_the_surfaces_then_the_tuned_ones()
  local d = Tq.dials(CARD, 'gravel', nil)
  eq(d.approachKmh, 66, 'start value')
  eq(Tq.dials(CARD, 'asphalt', nil).approachKmh, 72, "the card's asphalt adjustment")
  local tuned = Tq.dials(CARD, 'asphalt', {dials = {approachKmh = 70.5}})
  eq(tuned.approachKmh, 70.5, 'tuned values win')
  eq(tuned.feintSteer, 0.5, 'untuned dials keep their start value')
end

function T.the_surface_is_the_drills_in_lower_case()
  eq(Tq.surfaceOf({surface = 'Snow'}), 'snow')
  eq(Tq.surfaceOf({}), 'gravel', 'no surface: gravel')
  eq(Tq.tunedPath('scandinavian_flick', 'snow'), 'gameplay/rallyAcademy/techniques/scandinavian_flick-snow.json')
end

function T.a_phase_has_its_cue_and_mark()
  eq(Tq.phase(CARD, 'feint').cue, 'Flick away')
  eq(Tq.phase(CARD, 'feint').mark, 'feint')
  eq(Tq.phase(CARD, 'approach').mark, nil, 'the approach has no mark')
  eq(Tq.phase(CARD, 'stop'), nil, 'not a card phase')
end

function T.the_config_lays_the_line_out_from_the_start_every_metre()
  local east = {pos = {x = 100, y = 50, z = 3}, dir = {x = 1, y = 0, z = 0}}
  local gates = {{x = 0, y = 5}, {x = -10, y = 20}}
  local cfg = Tq.config(CARD, 'C08', {approachKmh = 66}, east, gates)
  -- Facing east, ahead is +x and right is -y: the line's (-10, 20) is 20 m ahead and 10 m to the left.
  near(cfg.path[1][1], 100, 1e-9, 'starts at the start')
  near(cfg.path[#cfg.path][1], 120, 1e-9, 'ends 20 m ahead')
  near(cfg.path[#cfg.path][2], 60, 1e-9, 'and 10 m left')
  eq(#cfg.path, 1 + 10 + 14, '1 m steps: 10 on the straight, 14 on the 14.1 m diagonal')
  near(cfg.flickS, 5, 1e-9, 'the first gate, 5 m along')
  near(cfg.exitS, 10 + math.sqrt(200), 0.01, 'the last gate, at the end')
  eq(cfg.limits.steerRatePerS, 4, "the card's human limits")
  eq(Tq.config(CARD, 'C09', {}, NORTH, gates), nil, 'no line for the drill')
end

function T.the_literal_reads_back_as_the_same_table()
  local cfg = Tq.config(CARD, 'C08', {approachKmh = 66.25, feintSteer = 0.5}, NORTH, {{x = 0, y = 5}, {x = -10, y = 20}})
  local back = loadstring('return ' .. Tq.literal(cfg))()
  eq(back.dials.approachKmh, 66.25)
  eq(#back.path, #cfg.path)
  near(back.path[20][1], cfg.path[20][1], 1e-5)
  eq(back.flickS, cfg.flickS)
  eq(Tq.literal({a = 'x"y', b = true}), '{["a"]="x\\"y",["b"]=true}', 'strings quoted, keys sorted')
end

-- The shipped card, as the mod reads it: its line for C08 is laid out between the Flick and Exit gates.
function T.the_flick_card_ships_a_line_for_C08_and_tuned_dials()
  local card = readJson(Tq.cardPath('scandinavian_flick'))
  local drills = readJson('gameplay/rallyAcademy/exercises.json').exercises
  local c08
  for _, d in ipairs(drills) do if d.id == 'C08' then c08 = d end end
  eq(c08.assessment.technique, 'scandinavian_flick', 'C08 names the card')
  local cfg = Tq.config(card, 'C08', Tq.dials(card, 'gravel', nil), NORTH, c08.assessment.course.gates)
  assert(cfg and cfg.flickS > 35 and cfg.flickS < 45, 'the Flick gate about 40 m in: ' .. tostring(cfg and cfg.flickS))
  assert(cfg.exitS > cfg.flickS + 60, 'the Exit gate well after it: ' .. cfg.exitS)
  for _, surface in ipairs({'gravel', 'asphalt', 'snow'}) do
    local tuned = readJson(Tq.tunedPath('scandinavian_flick', surface))
    assert(tuned.dials.approachKmh, surface .. ': tuned dials')
  end
end

return T
