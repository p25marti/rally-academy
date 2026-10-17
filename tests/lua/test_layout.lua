-- Unit tests for authored-course geometry (layout.lua, pure): placing a course from a
-- start, the car's footprint, fitting it in a box, and passing a cone.
local L = require('ge/extensions/rallyAcademy/layout')
local H = require('ra_helpers')
local eq, near = H.eq, H.near
local T = {}

-- The Covet Student Driver, measured in-game on 0.39.4: its position isn't the body's centre.
local COVET = {front = 1.85, rear = 2.07, left = 1.23, right = 0.58}
local NORTH = {pos = {x = 0, y = 0, z = 5}, dir = {x = 0, y = 1, z = 0}}

function T.a_course_is_laid_out_ahead_of_and_to_the_right_of_the_start()
  local east = {pos = {x = 100, y = 50, z = 3}, dir = {x = 1, y = 0, z = 0}}
  local c = L.place({gates = {{x = 0, y = 8, widthM = 3}}, cones = {{x = 2, y = 20, keep = 'right'}},
                     box = {x = -1.5, y = 33, lengthM = 6, widthM = 3.2}}, east)
  -- Facing east, "ahead" is +x and "right" is -y.
  near(c.gates[1].pos.x, 108, 1e-9, 'gate 8 m ahead')
  near(c.gates[1].pos.y, 50, 1e-9, 'gate on the line')
  eq(c.gates[1].width, 3, 'gate width')
  near(c.gates[1].dir.x, 1, 1e-9, 'gate faces the course')
  near(c.cones[1].x, 120, 1e-9, 'cone 20 m ahead')
  near(c.cones[1].y, 48, 1e-9, 'cone 2 m to the right')
  eq(c.cones[1].keep, 'right', 'keep side carried')
  near(c.box.x, 133, 1e-9, 'box 33 m ahead')
  near(c.box.y, 51.5, 1e-9, 'box 1.5 m to the left')
  eq(#c.markers, 3, 'two gate posts and the cone')
  eq(c.markers[1].name, 'the left post of the gate', 'post named for the coaching text')
  near(c.markers[1].y, 51.5, 1e-9, 'left post 1.5 m left of the gate centre')
  eq(c.markers[3].name, 'the cone', 'cone named')
end

function T.corners_follow_the_measured_body_not_the_cars_position()
  local cs = L.corners(COVET, 0, 0, 0, 1)
  near(cs[1].x, -1.23, 1e-9, 'front-left x')
  near(cs[1].y, 1.85, 1e-9, 'front-left y')
  near(cs[3].x, 0.58, 1e-9, 'rear-right x')
  near(cs[3].y, -2.07, 1e-9, 'rear-right y')
  local east = L.corners(COVET, 0, 0, 1, 0) -- facing east, left is +y
  near(east[1].x, 1.85, 1e-9, 'rotated front')
  near(east[1].y, 1.23, 1e-9, 'rotated left')
end

function T.distance_to_the_car_is_zero_underneath_and_measured_from_the_body()
  eq(L.distanceToCar(COVET, 0, 0, 0, 1, 0, 0), 0, 'under the car')
  near(L.distanceToCar(COVET, 0, 0, 0, 1, 1.58, 0), 1.0, 1e-9, '1 m off the right side')
  near(L.distanceToCar(COVET, 0, 0, 0, 1, -2.23, 0), 1.0, 1e-9, '1 m off the left side (wider)')
  near(L.distanceToCar(COVET, 0, 0, 0, 1, 3.58, 4.85), math.sqrt(18), 1e-9, 'diagonal from the front-right corner')
end

function T.box_fit_reports_the_tightest_corner_and_the_body_offset()
  local box = {x = 0, y = 10, dir = {x = 0, y = 1}, lengthM = 6, widthM = 3.2}
  -- Body centre lands on the box centre: position = centre - (front - rear)/2 ahead, - (right - left)/2 right.
  local x, y = 0.325, 10.11
  local fit = L.boxFit(box, COVET, x, y, 0, 1, 0)
  eq(fit.inside, true, 'centred car fits')
  near(fit.along, 0, 1e-9, 'level with the centre')
  near(fit.side, 0, 1e-9, 'centred')
  near(fit.margin, 1.6 - 0.905, 1e-9, 'side margin is the tightest')
  local gold = L.boxFit(box, COVET, x, y, 0, 1, 0.5)
  near(gold.margin, 1.1 - 0.905, 1e-9, 'the inset shrinks every side')
  local left = L.boxFit(box, COVET, x - 0.8, y, 0, 1, 0)
  eq(left.inside, false, '0.8 m left: out')
  eq(left.edge, 'left', 'over the left edge')
  eq(L.CORNER_NAMES[left.corner]:find('left') ~= nil, true, 'a left corner')
  near(left.margin, -0.105, 1e-9, 'by 0.105 m')
  near(left.side, -0.8, 1e-9, 'body 0.8 m left of centre')
  local short = L.boxFit(box, COVET, x, y - 2, 0, 1, 0)
  eq(short.edge, 'back', 'short: over the back edge')
  near(short.along, -2, 1e-9, '2 m to go')
end

function T.a_crooked_car_can_poke_out_of_a_box_its_centre_is_in()
  local box = {x = 0, y = 10, dir = {x = 0, y = 1}, lengthM = 6, widthM = 3.2}
  local r = math.rad(25)
  local fit = L.boxFit(box, L.centredCar(4, 1.8), 0, 10, math.sin(r), math.cos(r), 0)
  eq(fit.inside, false, 'turned 25 degrees: a corner is out')
end

function T.cone_crossing_says_which_side_of_the_car_the_cone_was_on()
  local cone = {x = 0, y = 20, dir = {x = 0, y = 1}}
  local c = L.coneCrossing(cone, {x = 1.8, y = 19.8}, {x = 1.8, y = 20.2})
  eq(c.side, 'left', 'passing to its right leaves it on your left')
  near(c.offset, 1.8, 1e-9, 'offset')
  eq(L.coneCrossing(cone, {x = -1.8, y = 19.8}, {x = -1.8, y = 20.2}).side, 'right', 'and the other way')
  eq(L.coneCrossing(cone, {x = 1.8, y = 20.2}, {x = 1.8, y = 19.8}), nil, 'backwards does not count')
  eq(L.coneCrossing(cone, {x = 30, y = 19.8}, {x = 30, y = 20.2}), nil, 'far away does not count')
end

function T.frame_handles_a_start_with_no_horizontal_direction()
  local f = L.frame({pos = {x = 1, y = 2}, dir = {x = 0, y = 0}})
  eq(f.fy, 1, 'falls back to north')
  local x, y = L.toWorld(L.frame(NORTH), 1, 2)
  eq(x, 1, 'right is +x facing north')
  eq(y, 2, 'ahead is +y')
end

function T.bumper_to_line_measures_from_the_front_of_the_body()
  local line = {x = 0, y = 10, dir = {x = 0, y = 1}, widthM = 8}
  local before, side = L.bumperToLine(line, COVET, 0, 7, 0, 1)
  near(before, 10 - 7 - 1.85, 1e-9, 'front bumper 1.15 m before the line')
  near(side, -0.325, 1e-9, 'body centre 0.325 m left of the line centre')
  near(L.bumperToLine(line, COVET, 0, 8.65, 0, 1), -0.5, 1e-9, 'half a metre past')
end

function T.a_course_line_gets_a_cone_at_each_end_as_markers()
  local c = L.place({line = {x = 0, y = 60, widthM = 8, label = 'Stop line'}}, NORTH)
  near(c.line.y, 60, 1e-9, 'line 60 m ahead')
  eq(c.line.label, 'Stop line', 'label')
  eq(#c.lineCones, 2, 'two cones')
  near(c.lineCones[1].x, -4, 1e-9, 'left cone at the line end')
  eq(c.markers[2].name, 'the right cone of the line', 'cones are markers')
end

return T
