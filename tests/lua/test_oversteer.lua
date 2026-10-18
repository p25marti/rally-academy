-- Oversteer (B07): the signed slip angle, the rear stepping out between gates and the car settled
-- by a gate (rules.lua), on synthetic runs through three gates.
local Rules = require('ge/extensions/rallyAcademy/rules')
local Gates = require('ge/extensions/rallyAcademy/gates')
local H = require('ra_helpers')
local eq, near, has = H.eq, H.near, H.has
local T = {}

local E = Rules.evaluators
-- Turn in at y = 0, the lane at y = 10, the lane end at y = 30, all facing north.
local function gate(y, label)
  local g = Gates.new({pos = {x = 0, y = y, z = 0}, dir = {x = 0, y = 1, z = 0}}, 7)
  g.label = label
  return g
end
local CTX = {gates = {gate(0, 'Turn in'), gate(10, 'Lane'), gate(30, 'Lane end')}}

-- North at 10 m/s from y = -10 to 40, the car pointing `slip(y)` degrees left of travel (the rear
-- out in a left-hander), the steering wheel at `steer(y)` degrees.
local function run(slip, steer)
  local out, v, dt = {}, 10, 0.04
  local y, t = -10, 0
  while y <= 40 do
    local b = math.rad(slip and slip(y) or 0)
    out[#out + 1] = {t = t, x = 0, y = y, air = v, vx = 0, vy = v, hx = -math.sin(b), hy = math.cos(b),
                     steer = steer and steer(y) or 0, gear = 2}
    y, t = y + v * dt, t + dt
  end
  return out
end

-- A slide that builds after turn-in, peaks at `peak` degrees at y = 8 and is gone by y = 20.
local function slide(peak)
  return function(y) return (y > 0 and y < 20) and peak * math.max(0, 1 - math.abs(y - 8) / 12) or 0 end
end

function T.signed_slip_is_positive_with_the_rear_out()
  local s = {vx = 0, vy = 10, hx = -math.sin(math.rad(12)), hy = math.cos(math.rad(12))}
  near(Rules.signedSlipDeg(s, 1, 'left'), 12, 1e-6, 'heading left of travel: rear out in a left-hander')
  near(Rules.signedSlipDeg(s, 1, 'right'), -12, 1e-6, 'the same attitude pushes wide in a right-hander')
  eq(Rules.signedSlipDeg({vx = 0, vy = 0.5, hx = 0, hy = 1}, 1, 'left'), nil, 'too slow to tell')
end

function T.rear_slide_needs_the_rear_out_between_the_gates()
  local ok, text = E.rear_slide({minSlipDeg = 8}, run(slide(14)), CTX)
  eq(ok, true, '14 degrees'); eq(text, 'Rear stepped out 14.0° (target 8°+)', 'text')
  ok, text = E.rear_slide({minSlipDeg = 8}, run(slide(5)), CTX)
  eq(ok, false, '5 degrees'); has(text, 'only stepped out 5.0°'); has(text, 'lift or brake harder')
  ok = E.rear_slide({minSlipDeg = 8}, run(function(y) return -slide(14)(y) end), CTX)
  eq(ok, false, 'the front pushing wide is not oversteer')
  ok = E.rear_slide({minSlipDeg = 8}, run(function(y) return y < -2 and 14 or 0 end), CTX)
  eq(ok, false, 'a slide before the turn-in gate does not count')
  ok, text = E.rear_slide({}, run(slide(14)), {})
  eq(ok, false, 'no gates'); has(text, 'No gates')
end

function T.settled_by_gate_needs_the_slide_over_and_the_steering_unwound()
  local ok, text = E.settled_by_gate({gate = -1}, run(slide(14), function() return 10 end), CTX)
  eq(ok, true, 'straight by the lane end'); eq(text, 'Settled by the lane end (slip 0°, steering 10°)', 'text')
  ok, text = E.settled_by_gate({gate = -1}, run(function(y) return y > 0 and 9 or 0 end), CTX)
  eq(ok, false, 'still sliding'); eq(text, 'Still sliding at the lane end (9°)', 'text')
  ok, text = E.settled_by_gate({gate = -1, maxSteerDeg = 45}, run(nil, function(y) return y > 25 and -90 or 0 end), CTX)
  eq(ok, false, 'countersteer held'); has(text, 'Steering still 90° at the lane end: unwind the countersteer sooner')
  ok, text = E.settled_by_gate({gate = 2}, run(slide(14)), CTX)
  eq(ok, false, 'the slide is still on at the lane gate'); has(text, 'Still sliding at the lane')
end

function T.flick_needs_steering_away_then_into_the_turn_quickly()
  -- steer right (negative) from y = 1 to 4, then left from y = 4
  local flick = function(y) return (y > 1 and y < 4) and -120 or y >= 4 and 150 or 0 end
  local ok, text = E.flick({fromGate = 1, toGate = 3, awayDeg = 60, intoDeg = 60}, run(nil, flick), CTX)
  eq(ok, true, 'a flick'); has(text, 'Flicked 120° away, then into the turn 0.')
  ok, text = E.flick({fromGate = 1, toGate = 3, awayDeg = 60}, run(nil, function(y) return y > 2 and 150 or 0 end), CTX)
  eq(ok, false, 'straight in'); has(text, 'No flick: steer at least 60° away')
  local slow = function(y) return (y > 1 and y < 4) and -120 or y >= 25 and 150 or 0 end
  ok, text = E.flick({fromGate = 1, toGate = 3, awayDeg = 60, maxSeconds = 1.5}, run(nil, slow), CTX)
  eq(ok, false, 'turned in too late'); has(text, 'make it one movement')
  local right = function(y) return (y > 1 and y < 4) and 120 or y >= 4 and -150 or 0 end
  ok = E.flick({fromGate = 1, toGate = 3, turn = 'right', awayDeg = 60}, run(nil, right), CTX)
  eq(ok, true, 'mirrored for a right-hander')
end

function T.throttle_on_between_needs_the_throttle_back_after_the_apex()
  local function withThrottle(thr)
    local s = run()
    for _, x in ipairs(s) do x.thr = thr(x.y) end
    return s
  end
  local ok, text = E.throttle_on_between({fromGate = 2, toGate = 3}, withThrottle(function(y) return y > 12 and 0.7 or 0.1 end), CTX)
  eq(ok, true, 'on from the lane gate'); has(text, 'Back on the throttle for 1.')
  ok, text = E.throttle_on_between({fromGate = 2, toGate = 3}, withThrottle(function() return 0.3 end), CTX)
  eq(ok, false, 'part throttle'); eq(text, 'Only 0.0 s on the throttle after the apex (peak 30%): drive the front out', 'text')
  ok = E.throttle_on_between({fromGate = 2, toGate = 3, minSeconds = 0.5}, withThrottle(function(y) return y > 28 and 0.9 or 0 end), CTX)
  eq(ok, false, 'too late')
end

return T
