-- Physical course markers (props.lua, ADR 0011): a real cone or post at each marker, left alone when the same
-- course is laid out again, reset on Retry, and the player car's collisions naming what it touched.
local L = require('ge/extensions/rallyAcademy/layout')
local H = require('ra_helpers')
local stubs = H.stubs
local eq = H.eq
local T = {}

local START = {pos = {x = 0, y = 0, z = 0}, dir = {x = 0, y = 1, z = 0}}
local COURSE = {gates = {{y = 20, widthM = 4}}, cones = {{y = 40}}, line = {y = 60, widthM = 8}}

local function fresh()
  local h = stubs.install()
  stubs.installProps(h)
  package.loaded['ge/extensions/rallyAcademy/props'] = nil
  return h, require('ge/extensions/rallyAcademy/props')
end

local function ground() return 100 end

function T.markers_say_what_stands_there()
  local placed = L.place(COURSE, START)
  local kinds = {}
  for _, m in ipairs(placed.markers) do kinds[#kinds + 1] = m.kind end
  eq(table.concat(kinds, ','), 'post,post,cone,cone,cone', 'two gate posts, the cone, the line cones')
end

function T.a_gate_can_carry_an_event()
  local placed = L.place({gates = {{y = 20, widthM = 4, event = 'puncture'}, {y = 40}}}, START)
  eq(placed.gates[1].event, 'puncture', 'kept on the placed gate')
  eq(placed.gates[2].event, nil, 'only where given')
end

function T.a_prop_stands_at_every_marker_on_the_ground()
  local h, P = fresh()
  local markers = L.place(COURSE, START).markers
  eq(P.place(markers, ground), 5, 'five props')
  eq(P.active(), true, 'active')
  eq(h.props[1].model, 'delineator', 'a gate post is a delineator')
  eq(h.props[1].config, 'vehicles/delineator/pole.pc', 'the pole')
  eq(h.props[3].model, 'cones', 'a cone is a cone')
  eq(h.props[3].pos.z, 100, 'on the ground')
  eq(h.props[3].autoEnter, false, 'the player stays in the car')
  eq(h.props[1].playerUsable, false, 'not one to switch into')
  eq(h.props[1].name:sub(1, 8), 'ra_prop_', 'named so a reload can find it')
end

function T.the_same_course_again_keeps_its_props_and_a_new_one_replaces_them()
  local h, P = fresh()
  local markers = L.place(COURSE, START).markers
  P.place(markers, ground)
  P.place(L.place(COURSE, START).markers, ground)
  eq(#h.props, 5, 'not spawned again')
  P.place(L.place({cones = {{y = 30}}}, START).markers, ground)
  eq(#h.props, 6, 'the new course spawned')
  for i = 1, 5 do eq(h.props[i].deleted, true, 'old prop ' .. i .. ' removed') end
end

function T.reset_puts_them_back_and_touching_names_what_the_car_hit()
  local h, P = fresh()
  P.place(L.place(COURSE, START).markers, ground)
  P.reset()
  eq(h.props[3].resets, 1, 'physics reset requested')
  eq(#P.touching(h.vehicle.id), 0, 'nothing touched')
  h.collisions[h.props[3].id] = true
  eq(P.touching(h.vehicle.id)[1], 'the cone', 'the cone, by its marker name')
end

function T.clear_removes_ours_and_a_previous_loads_leftovers()
  local h, P = fresh()
  P.place(L.place(COURSE, START).markers, ground)
  h.leftovers = {'ra_prop_7', 'someone_elses_cone'}
  P.clear()
  eq(P.active(), false, 'none left')
  eq(h.props[1].deleted, true, 'ours deleted')
  eq(table.concat(h.leftoversDeleted, ','), 'ra_prop_7', 'the leftover of ours, not anyone else\'s')
end

function T.without_the_engine_nothing_is_placed()
  stubs.install() -- no prop spawning
  package.loaded['ge/extensions/rallyAcademy/props'] = nil
  local P = require('ge/extensions/rallyAcademy/props')
  eq(P.place(L.place(COURSE, START).markers, ground), 0, 'nothing placed')
  eq(P.active(), false, 'grading measures instead')
end

return T
