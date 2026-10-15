-- Unit tests for the pure run-record module (no engine stubs needed).
local R = require('ge/extensions/rallyAcademy/runRecord')
local T = {}

local function eq(actual, expected, msg)
  if actual ~= expected then
    error(('%s: expected %s, got %s'):format(msg or 'mismatch', tostring(expected), tostring(actual)), 2)
  end
end

local function near(actual, expected, msg)
  if type(actual) ~= 'number' or math.abs(actual - expected) > 1e-6 then
    error(('%s: expected %s, got %s'):format(msg or 'mismatch', tostring(expected), tostring(actual)), 2)
  end
end

local function sample(t, air) return {id = 1, t = t, air = air or 0, w = {}} end

function T.new_record_is_open_and_empty()
  local rec = R.new({drill = 'B01'})
  eq(R.isOpen(rec), true, 'open')
  eq(#rec.samples, 0, 'empty')
  eq(rec.meta.drill, 'B01', 'meta kept')
  eq(R.isOpen(nil), false, 'nil is not an open record')
end

function T.adds_samples_in_time_order()
  local rec = R.new()
  eq(R.add(rec, sample(1.00)), true, 'first')
  eq(R.add(rec, sample(1.02)), true, 'second')
  eq(#rec.samples, 2, 'two kept')
  eq(R.lastT(rec), 1.02, 'last t')
end

-- While physics is paused the car keeps sending with the same sim time.
function T.drops_repeated_and_out_of_order_timestamps()
  local rec = R.new()
  R.add(rec, sample(2.00))
  eq(R.add(rec, sample(2.00)), false, 'repeat dropped')
  eq(R.add(rec, sample(1.50)), false, 'older dropped')
  eq(#rec.samples, 1, 'one kept')
end

function T.rejects_malformed_samples()
  local rec = R.new()
  eq(R.add(rec, nil), false, 'nil')
  eq(R.add(rec, {air = 3}), false, 'no t')
  eq(R.add(rec, 'x'), false, 'not a table')
  eq(#rec.samples, 0, 'nothing kept')
end

function T.caps_length_and_flags_truncation()
  local old = R.MAX_SAMPLES
  R.MAX_SAMPLES = 3
  local rec = R.new()
  for i = 1, 5 do R.add(rec, sample(i)) end
  R.MAX_SAMPLES = old
  eq(#rec.samples, 3, 'capped')
  eq(rec.truncated, true, 'flagged')
end

function T.run_start_is_marked_once_at_the_latest_sample()
  local rec = R.new()
  R.add(rec, sample(1.0))
  R.add(rec, sample(1.5))
  R.markRunStart(rec)
  R.add(rec, sample(2.0))
  R.markRunStart(rec)
  eq(rec.runStartT, 1.5, 'first mark wins')
end

function T.finish_closes_the_record()
  local rec = R.new()
  R.add(rec, sample(1.0))
  R.add(rec, sample(4.0))
  R.finish(rec, 'finished')
  eq(R.isOpen(rec), false, 'closed')
  eq(rec.outcome, 'finished', 'outcome')
  eq(rec.endT, 4.0, 'end time')
  eq(R.add(rec, sample(5.0)), false, 'no samples after closing')
  R.finish(rec, 'abandoned')
  eq(rec.outcome, 'finished', 'first outcome kept')
end

function T.summary_reports_rate_duration_and_max_speed()
  local rec = R.new()
  for i = 0, 60 do R.add(rec, sample(10 + i / 60, i / 6)) end -- 1 s at 60 Hz, speed 0..10
  R.add(rec, sample(11.5, 2))
  rec.runStartT = 10.5
  R.finish(rec, 'finished')
  local s = R.summary(rec)
  eq(s.samples, 62, 'samples')
  near(s.span, 1.5, 'span')
  near(s.runDuration, 1.0, 'run duration from run start to end')
  near(s.maxSpeed, 10, 'max speed')
  eq(s.outcome, 'finished', 'outcome')
end

return T
