// The input trace (throttle green, brake red, handbrake blue; steering in a lane of its own), shared by the Rally
// Academy panel and the Inputs app (ADR 0012): the car's live inputs, the run's trace Lua publishes, and drawing
// either into a canvas.
import { useStreams } from "@/services/events"

export const TRACE_SECONDS = 8
const THR = "rgba(80, 200, 110, 0.95)"
const BRK = "rgba(235, 75, 75, 0.95)"
const HB = "rgba(90, 160, 255, 0.95)"
const STEER = "rgba(235, 235, 235, 0.9)"
const STEER_LANE = 0.32 // of the height, under the pedals, when steering is drawn

const num = v => Number(v) || 0

// The car's own inputs over the last TRACE_SECONDS, from its electrics stream (the driver's input, before ABS and the
// like, as SimplePedals and SimpleSteering read it). `onSample(buffer, now)` runs after each frame's sample.
export function useLiveInputs(onSample) {
  const buffer = [] // {t (s), thr, brk, hb (0..1), st (-1..1, + left)}
  useStreams(["electrics"], streams => {
    const e = streams && streams.electrics
    if (!e) return
    const t = performance.now() / 1000
    buffer.push({
      t,
      thr: num(e.throttle_input !== undefined ? e.throttle_input : e.throttle),
      brk: num(e.brake_input !== undefined ? e.brake_input : e.brake),
      hb: num(e.parkingbrake_input !== undefined ? e.parkingbrake_input : e.parkingbrake),
      st: -num(e.steering_input), // the game's input is + right; the trace draws left up
    })
    while (buffer.length && buffer[0].t < t - TRACE_SECONDS) buffer.shift()
    if (onSample) onSample(buffer, t)
  })
  return buffer
}

// The run's trace as Lua publishes it ({t, thr, brk, hb, st, marks, span}), or null if there's nothing to draw.
export function runTraceOf(trace) {
  return trace && Array.isArray(trace.t) && trace.t.length > 1 ? trace : null
}

// Draw the live buffer: the last TRACE_SECONDS up to `now`.
export function drawLive(canvas, buffer, now, style) {
  const at = key => buffer.map(p => ({ t: p.t, v: p[key] }))
  drawTrace(canvas, now - TRACE_SECONDS, TRACE_SECONDS,
    [{ color: HB, points: at("hb") }, { color: THR, points: at("thr") }, { color: BRK, points: at("brk") }],
    at("st"), [], style)
}

// Draw a run's trace across the whole run, with its gates marked. Runs recorded before the handbrake or steering were
// in the trace draw without them.
export function drawRun(canvas, trace, style) {
  const span = trace.span || trace.t[trace.t.length - 1] || 1
  const at = key => (Array.isArray(trace[key]) ? trace.t.map((t, i) => ({ t, v: trace[key][i] })) : null)
  const pedals = [{ color: HB, points: at("hb") }, { color: THR, points: at("thr") }, { color: BRK, points: at("brk") }]
  drawTrace(canvas, 0, span, pedals.filter(s => s.points), at("st"), Array.isArray(trace.marks) ? trace.marks : [],
    style)
}

// Pedal series of {t, v} (v 0..1; drawn in order, so the handbrake goes first: it sits at zero most of the time and
// would hide the others there) and steering points (v -1..1, + left; null for none) into the canvas at its displayed
// size, t from t0 to t0 + span. The pedals take the top (a faint grid at 0, 50 and 100 %), the steering a lane under
// them (a centre line, left up); then the marks (vertical ticks with their labels).
// style: {lineWidth, fontPx, pad, steering (false: pedals only)}.
function drawTrace(canvas, t0, span, pedals, steering, marks, style) {
  const c = canvas
  if (!c) return
  const { lineWidth = 2, fontPx = 10, pad = 3, steering: withSteering = true } = style || {}
  const dpr = window.devicePixelRatio || 1
  const w = c.clientWidth, h = c.clientHeight
  if (!w || !h) return
  if (c.width !== Math.round(w * dpr)) c.width = Math.round(w * dpr)
  if (c.height !== Math.round(h * dpr)) c.height = Math.round(h * dpr)
  const g = c.getContext("2d")
  g.setTransform(dpr, 0, 0, dpr, 0, 0)
  g.clearRect(0, 0, w, h)
  const lane = withSteering && steering ? Math.round(h * STEER_LANE) : 0
  const ph = h - lane // the pedals' height
  const x = t => ((t - t0) / span) * w
  const y = v => ph - pad - Math.max(0, Math.min(1, v)) * (ph - 2 * pad)
  const grid = (yy, alpha) => {
    g.strokeStyle = `rgba(255,255,255,${alpha})`
    g.lineWidth = 1
    g.beginPath(); g.moveTo(0, Math.round(yy) + 0.5); g.lineTo(w, Math.round(yy) + 0.5); g.stroke()
  }
  const line = (color, points, yOf) => {
    g.strokeStyle = color
    g.lineWidth = lineWidth
    g.beginPath()
    points.forEach((p, i) => (i ? g.lineTo(x(p.t), yOf(p.v)) : g.moveTo(x(p.t), yOf(p.v))))
    g.stroke()
  }
  for (const v of [0, 0.5, 1]) grid(y(v), 0.12)
  for (const s of pedals) line(s.color, s.points, y)
  g.font = `${fontPx}px sans-serif`
  if (lane) {
    const mid = ph + lane / 2, half = lane / 2 - pad
    const ys = v => mid - Math.max(-1, Math.min(1, v)) * half
    grid(ph, 0.25) // the line between pedals and steering
    grid(mid, 0.18)
    line(STEER, steering, ys)
    g.fillStyle = "rgba(255,255,255,0.55)"
    g.fillText("L", 2, ph + fontPx)
    g.fillText("R", 2, h - 2)
  }
  for (const m of marks) {
    const mx = Math.round(x(m.t)) + 0.5
    g.strokeStyle = "rgba(255,255,255,0.45)"
    g.lineWidth = 1
    g.beginPath(); g.moveTo(mx, 0); g.lineTo(mx, h); g.stroke()
    g.fillStyle = "rgba(255,255,255,0.8)"
    g.fillText(m.label, Math.min(mx + 3, w - 34), fontPx + 1)
  }
}
