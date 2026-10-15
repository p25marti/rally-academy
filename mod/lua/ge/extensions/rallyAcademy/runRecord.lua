-- Run record: one attempt's telemetry samples plus metadata. Pure Lua (no engine
-- globals), so grading rules can be unit-tested against recorded runs.
--
-- A sample is what lua/vehicle/extensions/rallyAcademy/telemetry.lua sends:
--   {id, t, thr, brk, hb, steer, clutch, gear, rpm, ws, air, abs, w = {{n, s, m, f}, ...}}
-- t is the car's sim time (obj:getSimTime), so it stops while physics is paused.
local R = {}

R.MAX_SAMPLES = 20000 -- ~5.5 min at 60 Hz

function R.new(meta)
  return {meta = meta or {}, samples = {}, truncated = false,
          runStartT = nil, endT = nil, outcome = nil}
end

function R.isOpen(rec)
  return rec ~= nil and rec.outcome == nil
end

-- Appends a sample; returns true if kept. Repeated or out-of-order timestamps are
-- dropped (the car keeps sending while the sim is paused, with the same t).
function R.add(rec, s)
  if not R.isOpen(rec) or type(s) ~= 'table' or type(s.t) ~= 'number' then return false end
  local last = rec.samples[#rec.samples]
  if last and s.t <= last.t then return false end
  if #rec.samples >= R.MAX_SAMPLES then rec.truncated = true; return false end
  rec.samples[#rec.samples + 1] = s
  return true
end

function R.lastT(rec)
  local last = rec and rec.samples[#rec.samples]
  return last and last.t or nil
end

-- The moment the car left the start (the record may begin earlier, at Retry).
function R.markRunStart(rec)
  if R.isOpen(rec) and not rec.runStartT then rec.runStartT = R.lastT(rec) end
end

-- outcome: 'finished' | 'abandoned' | 'restarted'
function R.finish(rec, outcome)
  if not R.isOpen(rec) then return end
  rec.outcome = outcome
  rec.endT = R.lastT(rec)
end

function R.summary(rec)
  local n = #rec.samples
  local span = n > 1 and (rec.samples[n].t - rec.samples[1].t) or 0
  local maxSpeed = 0
  for _, s in ipairs(rec.samples) do
    if (s.air or 0) > maxSpeed then maxSpeed = s.air end
  end
  return {
    samples = n,
    span = span,
    rateHz = span > 0 and (n - 1) / span or 0,
    runDuration = (rec.runStartT and rec.endT) and (rec.endT - rec.runStartT) or nil,
    maxSpeed = maxSpeed,
    outcome = rec.outcome,
    truncated = rec.truncated,
  }
end

return R
