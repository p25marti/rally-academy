-- Rally Academy telemetry sampler (vehicle Lua); design in docs/decisions/0004.
-- Not wired into the mod yet.
-- Loaded into a car by GE with: extensions.load('rallyAcademy/telemetry')
-- then extensions.rallyAcademy_telemetry.start(rateHz, geCallback).
-- Each tick sends ONE batched sample to GE: geCallback({t=..., thr=..., w={...}}).
local M = {}

local buf = require('string.buffer').new()
local period, acc, target = nil, 0, nil

function M.start(rateHz, geCallback)
  period = 1 / math.max(1, rateHz or 50)
  target = geCallback
  acc = 0
end

function M.stop()
  period, target = nil, nil
end

local function send()
  local e = electrics.values
  buf:reset()
  buf:putf('%s({t=%.4f,thr=%.3f,brk=%.3f,hb=%.3f,steer=%.3f,clutch=%.3f,gear=%d,rpm=%.0f,ws=%.3f,air=%.3f,abs=%d,w={',
    target, obj:getSimTime(), e.throttle or 0, e.brake or 0, e.parkingbrake or 0, e.steering or 0, e.clutch or 0,
    e.gearIndex or 0, e.rpm or 0, e.wheelspeed or 0, e.airspeed or 0, (e.absActive or 0) > 0 and 1 or 0)
  for i = 0, wheels.wheelRotatorCount - 1 do
    local wd = wheels.wheelRotators[i]
    buf:putf('{n=%q,s=%.3f,m=%d,f=%.0f},', wd.name, wd.wheelSpeed or 0, wd.contactMaterialID1 or -1, wd.downForce or 0)
  end
  buf:put('}})')
  obj:queueGameEngineLua(buf:tostring())
end

function M.updateGFX(dt)
  if not period then return end
  acc = acc + dt
  if acc < period then return end
  acc = acc - period
  if acc > period then acc = 0 end -- don't burst to catch up after a hitch
  send()
end

return M
