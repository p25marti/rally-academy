// The input trace (throttle green, brake red), shared by the Rally Academy panel and the Inputs app (ADR 0012): the
// car's live inputs, the run's trace Lua publishes, and drawing either into a canvas.
import { useStreams } from "@/services/events"

export const TRACE_SECONDS = 8
const THR = "rgba(80, 200, 110, 0.95)"
const BRK = "rgba(235, 75, 75, 0.95)"

// The car's own throttle and brake input over the last TRACE_SECONDS, from its electrics stream (the driver's input,
// before ABS and the like, as SimplePedals reads it). `onSample(buffer, now)` runs after each frame's sample.
export function useLiveInputs(onSample) {
  const buffer = [] // {t (s), thr, brk}
  useStreams(["electrics"], streams => {
    const e = streams && streams.electrics
    if (!e) return
    const t = performance.now() / 1000
    const thr = e.throttle_input !== undefined ? e.throttle_input : e.throttle
    const brk = e.brake_input !== undefined ? e.brake_input : e.brake
    buffer.push({ t, thr: Number(thr) || 0, brk: Number(brk) || 0 })
    while (buffer.length && buffer[0].t < t - TRACE_SECONDS) buffer.shift()
    if (onSample) onSample(buffer, t)
  })
  return buffer
}

// The run's trace as Lua publishes it ({t, thr, brk, marks, span}), or null if there's nothing to draw.
export function runTraceOf(trace) {
  return trace && Array.isArray(trace.t) && trace.t.length > 1 ? trace : null
}

// Draw the live buffer: the last TRACE_SECONDS up to `now`.
export function drawLive(canvas, buffer, now, style) {
  drawTrace(canvas, now - TRACE_SECONDS, TRACE_SECONDS, [
    { color: THR, points: buffer.map(p => ({ t: p.t, v: p.thr })) },
    { color: BRK, points: buffer.map(p => ({ t: p.t, v: p.brk })) },
  ], [], style)
}

// Draw a run's trace across the whole run, with its gates marked.
export function drawRun(canvas, trace, style) {
  const span = trace.span || trace.t[trace.t.length - 1] || 1
  drawTrace(canvas, 0, span, [
    { color: THR, points: trace.t.map((t, i) => ({ t, v: trace.thr[i] })) },
    { color: BRK, points: trace.t.map((t, i) => ({ t, v: trace.brk[i] })) },
  ], Array.isArray(trace.marks) ? trace.marks : [], style)
}

// Series of {t, v} (t from t0 to t0 + span, v 0..1) into the canvas at its displayed size: a faint grid at 0, 50 and
// 100 %, the lines, then the marks (vertical ticks with their labels). style: {lineWidth, fontPx, pad}.
function drawTrace(canvas, t0, span, series, marks, style) {
  const c = canvas
  if (!c) return
  const { lineWidth = 2, fontPx = 10, pad = 3 } = style || {}
  const dpr = window.devicePixelRatio || 1
  const w = c.clientWidth, h = c.clientHeight
  if (!w || !h) return
  if (c.width !== Math.round(w * dpr)) c.width = Math.round(w * dpr)
  if (c.height !== Math.round(h * dpr)) c.height = Math.round(h * dpr)
  const g = c.getContext("2d")
  g.setTransform(dpr, 0, 0, dpr, 0, 0)
  g.clearRect(0, 0, w, h)
  const x = t => ((t - t0) / span) * w
  const y = v => h - pad - Math.max(0, Math.min(1, v)) * (h - 2 * pad)
  g.strokeStyle = "rgba(255,255,255,0.12)"
  g.lineWidth = 1
  for (const v of [0, 0.5, 1]) {
    g.beginPath(); g.moveTo(0, Math.round(y(v)) + 0.5); g.lineTo(w, Math.round(y(v)) + 0.5); g.stroke()
  }
  for (const s of series) {
    g.strokeStyle = s.color
    g.lineWidth = lineWidth
    g.beginPath()
    s.points.forEach((p, i) => (i ? g.lineTo(x(p.t), y(p.v)) : g.moveTo(x(p.t), y(p.v))))
    g.stroke()
  }
  g.font = `${fontPx}px sans-serif`
  for (const m of marks) {
    const mx = Math.round(x(m.t)) + 0.5
    g.strokeStyle = "rgba(255,255,255,0.45)"
    g.beginPath(); g.moveTo(mx, 0); g.lineTo(mx, h); g.stroke()
    g.fillStyle = "rgba(255,255,255,0.8)"
    g.fillText(m.label, Math.min(mx + 3, w - 34), fontPx + 1)
  }
}
