-- Rally Academy telemetry sampler (vehicle Lua); design in docs/decisions/0004.
-- Loaded into the player's car by the GE extension on Retry:
--   extensions.load('rallyAcademy/telemetry')
--   extensions.rallyAcademy_telemetry.start(rateHz, 'rallyAcademy')
-- Each tick sends ONE batched sample to that GE extension's onTelemetry(sample);
-- the call is guarded, so a missing extension costs nothing and raises no error.
local M = {}

local buf = require('string.buffer').new()
local period, acc, target = nil, 0, nil

function M.start(rateHz, geExtension)
  period = 1 / math.max(1, rateHz or 60)
  target = geExtension
  acc = 0
end

function M.stop()
  period, target = nil, nil
end

local function send()
  local e = electrics.values
  buf:reset()
  local x, y, z = obj:getPositionXYZ()
  local h, v, u = obj:getDirectionVector(), obj:getVelocity(), obj:getDirectionVectorUp()
  local flat = 0
  for i = 0, wheels.wheelRotatorCount - 1 do
    if wheels.wheelRotators[i].isTireDeflated then flat = flat + 1 end
  end
  buf:putf('local m=extensions[%q] if m and m.onTelemetry then m.onTelemetry({id=%d,t=%.4f,x=%.2f,y=%.2f,z=%.2f,'
    .. 'thr=%.3f,brk=%.3f,ti=%.3f,bi=%.3f,hb=%.3f,steer=%.3f,clutch=%.3f,gear=%d,rpm=%.0f,eng=%d,ws=%.3f,air=%.3f,abs=%d,'
    .. 'hx=%.3f,hy=%.3f,vx=%.2f,vy=%.2f,uz=%.3f,dmg=%.0f,flat=%d,w={',
    target, obj:getId(), obj:getSimTime(), x, y, z, e.throttle or 0, e.brake or 0,
    e.throttle_input or e.throttle or 0, e.brake_input or e.brake or 0, e.parkingbrake or 0, e.steering or 0, e.clutch or 0,
    e.gearIndex or 0, e.rpm or 0, (e.engineRunning or 0) > 0 and 1 or 0, e.wheelspeed or 0, e.airspeed or 0,
    (e.absActive or 0) > 0 and 1 or 0,
    h.x, h.y, v.x, v.y, u.z, beamstate and beamstate.damage or 0, flat)
  for i = 0, wheels.wheelRotatorCount - 1 do
    local wd = wheels.wheelRotators[i]
    buf:putf('{n=%q,s=%.3f,m=%d,f=%.0f},', wd.name, wd.wheelSpeed or 0, wd.contactMaterialID1 or -1, wd.downForceRaw or 0)
  end
  buf:put('}}) end')
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
