-- Skill runner (vehicle Lua, extension rallyAcademy_driver), docs/DRIVER.md: drives a technique card's phases in the
-- car. Decides on a fixed clock of simulation time (decisionHz, 20 = deterministic mode's 0.05 s frame), switches
-- phases on measurements, and keeps its outputs within the card's human limits. Watch AI loads it for a technique drill
-- (ADR 0015) and tools/driver/attempt.py for training; either then calls configure(cfg) with the card's dials and the
-- course (path and gates in world metres).
--
-- The core (M.new, M.decide and the helpers) is pure, for tests/lua/test_driver_runner.lua; the engine side (obj,
-- input, controller) is at the end.
local M = {}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
M.clamp = clamp

-- Times are sums of 0.05 s steps: compare with a little slack (nine steps make 0.44999...).
local function past(t, limit) return t + 1e-6 >= limit end

-- Slip angle in degrees, positive when the car points further into a left turn than it travels (the rear stepping
-- out), as the grader's R.signedSlipDeg(s, minAir, 'left'). nil below `minAir` m/s.
function M.signedSlipDeg(hx, hy, vx, vy, minAir)
  local sp = math.sqrt(vx * vx + vy * vy)
  local hn = math.sqrt(hx * hx + hy * hy)
  if sp < (minAir or 3) or hn == 0 then return nil end
  local c = clamp((hx * vx + hy * vy) / (hn * sp), -1, 1)
  local slip = math.deg(math.acos(c))
  return (vx * hy - vy * hx) >= 0 and slip or -slip
end

-- Move `from` towards `to` by at most `rate` per second over `dt`.
function M.limit(from, to, rate, dt)
  local step = rate * dt
  return from + clamp(to - from, -step, step)
end

-- Pure pursuit along `path` ({{x, y}, ...}, about 1 m apart), as academy.follow_path. Returns the steering input
-- (-1 left .. 1 right), the nearest path index and the distance along the path to it.
function M.pursuit(d, x, y, hx, hy, v)
  local path, best, bestD = d.path, d.idx, math.huge
  for i = d.idx, math.min(d.idx + 80, #path) do
    local dx, dy = path[i][1] - x, path[i][2] - y
    local dd = dx * dx + dy * dy
    if dd < bestD then best, bestD = i, dd end
  end
  d.idx = best
  local look = math.max(2.5, 0.9 * v)
  local j = best
  while j < #path and math.sqrt((path[j][1] - x) ^ 2 + (path[j][2] - y) ^ 2) < look do j = j + 1 end
  local hn = math.sqrt(hx * hx + hy * hy)
  if hn == 0 then hn = 1 end
  hx, hy = hx / hn, hy / hn
  local dx, dy = path[j][1] - x, path[j][2] - y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist == 0 then dist = 1 end
  local sinA = (hx * dy - hy * dx) / dist -- + when the point is to the left
  local angle = math.atan(2 * 2.45 * sinA / math.max(dist, 1.0))
  return clamp(-angle / 0.55, -1, 1), best, d.along[best]
end

local function hold(kmh, target)
  if kmh > target + 8 then return 0, 0.3 end
  return clamp(0.3 + (target - kmh) * 0.1, 0.05, 1), 0
end

-- cfg: {dials = {name = value}, limits = card.humanLimits, path = {{x, y}}, flickS = m, exitS = m}
function M.new(cfg)
  local along = {0}
  for i = 2, #cfg.path do
    local a, b = cfg.path[i - 1], cfg.path[i]
    along[i] = along[i - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
  end
  return {
    dials = cfg.dials, limits = cfg.limits, path = cfg.path, along = along, idx = 1,
    flickS = cfg.flickS, exitS = cfg.exitS,
    phase = 'approach', phaseT = 0,
    out = {throttle = 0, brake = 0, handbrake = 0, steering = 0},
    lastYaw = nil, t = 0, slipHist = {},
    report = {phases = {}, maxSlip = 0, exitKmh = nil, spun = false},
  }
end

local ORDER = {approach = 'feint', feint = 'load_turn_in', load_turn_in = 'catch', catch = 'exit', exit = 'stop'}

local function enter(d, phase)
  d.phase, d.phaseT = phase, 0
  table.insert(d.report.phases, {phase, d.t, d.slip or 0, d.yawRate or 0, d.turned or 0})
  d.heading0 = d.lastYaw
end

-- A phase ends as soon as its measurement says so: a rehearsed move is anticipated, not reacted to (owner,
-- 2026-11-01). The reaction time applies to corrections only (see `felt`).
local function finish(d)
  enter(d, ORDER[d.phase])
end

-- What the driver can react to now: the slip angle as it was reactionMs ago (corrections, such as the catch's
-- counter-steer, respond to the car with a human delay).
local function felt(d)
  local lag = (d.limits.reactionMs or 0) / 1000
  local h, value = d.slipHist, 0
  for i = #h, 1, -1 do
    if past(d.t - lag, h[i][1]) then value = h[i][2] break end
  end
  while #h > 1 and h[2][1] < d.t - lag - 0.5 do table.remove(h, 1) end
  return value
end

-- One decision. obs: {x, y, hx, hy, vx, vy} (world, m and m/s). Returns the outputs (throttle, brake, handbrake,
-- steering), already rate-limited.
function M.decide(d, obs, dt)
  d.t, d.phaseT = d.t + dt, d.phaseT + dt
  local k = d.dials
  local v = math.sqrt(obs.vx * obs.vx + obs.vy * obs.vy)
  local kmh = v * 3.6
  local yaw = math.atan2(obs.hy, obs.hx)
  local yawRate = 0
  if d.lastYaw then
    local dy = yaw - d.lastYaw
    if dy > math.pi then dy = dy - 2 * math.pi elseif dy < -math.pi then dy = dy + 2 * math.pi end
    yawRate = dy / dt -- + turning left
  end
  d.lastYaw = yaw
  local slip = M.signedSlipDeg(obs.hx, obs.hy, obs.vx, obs.vy) or 0
  d.slip, d.yawRate = slip, math.deg(yawRate)
  table.insert(d.slipHist, {d.t, slip})
  if d.heading0 then
    local dh = yaw - d.heading0
    if dh > math.pi then dh = dh - 2 * math.pi elseif dh < -math.pi then dh = dh + 2 * math.pi end
    d.turned = math.deg(dh) -- since the phase began, + to the left
  end
  local line, _, s = M.pursuit(d, obs.x, obs.y, obs.hx, obs.hy, v)
  if s >= d.flickS and s <= d.exitS and slip > d.report.maxSlip then d.report.maxSlip = slip end
  if math.abs(slip) > 90 then d.report.spun = true end
  if s >= d.exitS and not d.report.exitKmh then d.report.exitKmh = kmh end

  local want = {throttle = 0, brake = 0, handbrake = 0, steering = line}
  local p = d.phase
  if p == 'approach' then
    want.throttle, want.brake = hold(kmh, k.approachKmh)
    if s >= d.flickS + k.feintAfterM then enter(d, 'feint') end
  elseif p == 'feint' then
    want.steering = k.feintSteer
    if past(d.phaseT, k.feintMaxS) or (past(d.phaseT, k.feintMinS) and -(d.turned or 0) >= k.feintYawDeg) then
      finish(d)
    end
  elseif p == 'load_turn_in' then
    want.steering, want.brake = -k.turnSteer, k.loadBrake
    -- the pendulum: the feint's swing away has to stop before the rear comes round into the corner
    if past(d.phaseT, k.loadMaxS) or (past(d.phaseT, k.loadMinS) and math.deg(yawRate) >= -k.loadUnwindDegS) then
      finish(d)
    end
  elseif p == 'catch' then
    want.steering = clamp(line + k.catchGain * felt(d) / 30, -1, 1)
    want.throttle, want.brake = hold(kmh, k.catchKmh)
    if past(d.phaseT, k.catchMaxS) or (past(d.phaseT, 0.3) and math.abs(slip) < k.settleSlipDeg) then finish(d) end
  elseif p == 'exit' then
    want.throttle, want.brake = hold(kmh, k.exitKmh)
    if s >= d.exitS + 12 then enter(d, 'stop') end
  else -- stop: brake, then the handbrake once slow (a held brake at a standstill can select reverse)
    local slow = v < 1
    want.steering, want.brake, want.handbrake = 0, slow and 0 or 0.6, slow and 1 or 0
  end

  local o, steerRate, pedalRate = d.out, d.limits.steerRatePerS, d.limits.pedalRatePerS
  o.steering = M.limit(o.steering, want.steering, steerRate, dt)
  o.throttle = M.limit(o.throttle, want.throttle, pedalRate, dt)
  o.brake = M.limit(o.brake, want.brake, pedalRate, dt)
  o.handbrake = want.handbrake
  return o
end

-- Engine side ------------------------------------------------------------------------------------------------------

local HOLD, SHIFT_AT, GEAR = 80, 20, 2 -- frames: as tape.py's controlled start
local d, frames, acc, done = nil, 0, 0, false
local savedGearbox = nil -- the player's gearbox mode, put back when the run ends ('arcade' would shift on its own)

local function apply(o)
  input.event('throttle', o.throttle, 2)
  input.event('brake', o.brake, 2)
  input.event('parkingbrake', o.handbrake, 2)
  input.event('steering', o.steering, 2)
end

local function restoreGearbox()
  if savedGearbox and savedGearbox ~= 'realistic' then controller.mainController.setGearboxMode(savedGearbox) end
  savedGearbox = nil
end

-- Tell the GE extension about each phase as it begins (the HUD's cue, the trace's marks), with the car's sim time.
local function notify(phase)
  obj:queueGameEngineLua(string.format(
    'if extensions.rallyAcademy then extensions.rallyAcademy.onDriverPhase(%q, %.3f) end', phase, obj:getSimTime()))
end

function M.configure(cfg)
  d, frames, acc, done = M.new(cfg), 0, 0, false
  HOLD, SHIFT_AT, GEAR = cfg.hold or HOLD, cfg.shiftAt or SHIFT_AT, cfg.gear or GEAR
  local mc = controller.mainController
  if savedGearbox == nil then savedGearbox = mc.gearboxBehavior end
  if mc.gearboxBehavior ~= 'realistic' then mc.setGearboxMode('realistic') end -- the runner picks its gear itself
  notify(d.phase)
end

function M.updateGFX(dt)
  if not d or done or dt <= 0 then return end -- physics stopped
  frames = frames + 1
  math.randomseed(frames) -- the engine's ignition noise draws math.random every frame (BEAMNG_API_NOTES)
  if frames <= HOLD then
    apply({throttle = 0, brake = 0, handbrake = 0, steering = 0})
    if frames == SHIFT_AT then controller.mainController.shiftToGearIndex(GEAR) end
    return
  end
  acc = acc + dt
  local step = 1 / (d.limits.decisionHz or 20)
  if acc + 1e-6 < step then return end
  local h, vel = obj:getDirectionVector(), obj:getVelocity()
  local x, y = obj:getPositionXYZ()
  local before = d.phase
  apply(M.decide(d, {x = x, y = y, hx = h.x, hy = h.y, vx = vel.x, vy = vel.y}, acc))
  acc = 0
  if d.phase ~= before then notify(d.phase) end
  if d.phase == 'stop' and vel:length() < 0.3 then
    done = true
    apply({throttle = 0, brake = 0, handbrake = 1, steering = 0})
    restoreGearbox()
    obj:queueGameEngineLua('raDriverReport = ' .. string.format('%q', M.report())) -- attempt.py waits for this
    notify('done')
  end
end

-- Off for good: the controls let go and the player's gearbox back, no more inputs until the next configure.
function M.stop()
  if d then apply({throttle = 0, brake = 0, handbrake = 0, steering = 0}) end
  restoreGearbox()
  d, done = nil, true
end

M.onExtensionUnloaded = M.stop

function M.state()
  if not d then return 'none' end
  return (done and 'done' or d.phase) .. ' ' .. frames
end

function M.report()
  if not d then return '{}' end
  local r = d.report
  local ph = {}
  for _, e in ipairs(r.phases) do ph[#ph + 1] = string.format('["%s",%.2f,%.1f,%.1f,%.1f]', e[1], e[2], e[3], e[4], e[5]) end
  return string.format('{"maxSlip":%.1f,"exitKmh":%s,"spun":%s,"phases":[%s]}', r.maxSlip,
    r.exitKmh and string.format('%.1f', r.exitKmh) or 'null', tostring(r.spun), table.concat(ph, ','))
end

return M
