-- Run record: one attempt's telemetry samples plus metadata. Pure Lua (no engine
-- globals), so grading rules can be unit-tested against recorded runs.
--
-- A sample is what lua/vehicle/extensions/rallyAcademy/telemetry.lua sends:
--   {id, t, x, y, z, thr, brk, ti, bi, hb, steer, si, clutch, gear, rpm, eng, ws, air, abs, hx, hy, vx, vy, vz, uz,
--    rr, pr, yr, roll, pitch, gx, gy, gz, dmg, flat, w = {{n, s, m, f}, ...}}
-- (rr, pr, yr: roll, pitch and yaw rates, rad/s; roll, pitch: rad; gx, gy, gz: acceleration, m/s^2; since 2026-11-01)
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

-- The driver's inputs over the run (from its start mark), as at most `n` points for the HUD's input trace:
-- {t = {s from the start}, thr = {0..1}, brk = {0..1}, hb = {0..1}, st = {-1..1, + left} or nil, marks = {{t, label}},
-- span = s}. st is the steering input turned round so left is + (si is + right), there when the samples carry it
-- (si, since 2026-10-29). `marks` come in as sim
-- times ({t, label}) and go out relative. Each point is the first sample in its slice of the run.
function R.inputTrace(rec, n, marks)
  local from = rec and rec.runStartT
  local samples = {}
  for _, s in ipairs(rec and rec.samples or {}) do
    if not from or s.t >= from then samples[#samples + 1] = s end
  end
  if #samples < 2 then return nil end
  local t0, t1 = samples[1].t, samples[#samples].t
  local out = {t = {}, thr = {}, brk = {}, hb = {}, st = samples[1].si and {} or nil, marks = {}, span = t1 - t0}
  local function r2(v) return math.floor((v or 0) * 100 + 0.5) / 100 end
  local slot, step = -1, (t1 - t0) / math.max(1, (n or 160) - 1)
  for _, s in ipairs(samples) do
    local k = step > 0 and math.floor((s.t - t0) / step) or 0
    if k ~= slot then
      slot = k
      out.t[#out.t + 1] = r2(s.t - t0)
      out.thr[#out.thr + 1] = r2(s.ti or s.thr)
      out.brk[#out.brk + 1] = r2(s.bi or s.brk)
      out.hb[#out.hb + 1] = r2(s.hb)
      if out.st then out.st[#out.st + 1] = -r2(s.si) end
    end
  end
  for _, m in ipairs(marks or {}) do
    if m.t and m.t >= t0 and m.t <= t1 then out.marks[#out.marks + 1] = {t = m.t - t0, label = m.label} end
  end
  return out
end

return R
