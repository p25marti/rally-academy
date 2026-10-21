<template>
  <!-- Rally Academy input trace (ADR 0012): throttle (green) and brake (red) over time, like a sim's input telemetry.
       Live from the car's own input stream; between runs, the last run's whole trace with its gates marked (from Lua,
       "rallyAcademyState".trace). Fills whatever size the layout gives it. -->
  <div class="ra-inputs">
    <canvas ref="canvas"></canvas>
    <span class="ra-key">
      <i class="thr"></i>throttle <i class="brk"></i>brake<span class="ra-mode">{{ showingRun ? " · last run" : " · live" }}</span>
    </span>
  </div>
</template>

<script setup>
import { computed, nextTick, onMounted, onUnmounted, reactive, ref, watch } from "vue"
import { useBridge } from "@/bridge"
import { useEvents, useStreams } from "@/services/events"

const { api } = useBridge()
const events = useEvents()
const vm = reactive({ phase: "loading", trace: null })
const canvas = ref(null)

const TRACE_SECONDS = 8
const THR = "rgba(80, 200, 110, 0.95)"
const BRK = "rgba(235, 75, 75, 0.95)"
const live = [] // {t (s), thr, brk}, the last TRACE_SECONDS
const runTrace = computed(() => (vm.trace && Array.isArray(vm.trace.t) && vm.trace.t.length > 1 ? vm.trace : null))
// The last run stays up after it's graded until the next one starts; otherwise the trace is live.
const showingRun = computed(() => (vm.phase === "review" || vm.phase === "scored") && !!runTrace.value)

// Series of {t, v} (t from t0 to t0 + span) into the canvas: a faint grid at 0, 50 and 100 %, the lines, then the
// gate marks (vertical ticks with their labels).
function draw(t0, span, series, marks) {
  const c = canvas.value
  if (!c) return
  const dpr = window.devicePixelRatio || 1
  const w = c.clientWidth, h = c.clientHeight
  if (!w || !h) return
  if (c.width !== Math.round(w * dpr)) c.width = Math.round(w * dpr)
  if (c.height !== Math.round(h * dpr)) c.height = Math.round(h * dpr)
  const g = c.getContext("2d")
  g.setTransform(dpr, 0, 0, dpr, 0, 0)
  g.clearRect(0, 0, w, h)
  const pad = 3
  const x = t => ((t - t0) / span) * w
  const y = v => h - pad - Math.max(0, Math.min(1, v)) * (h - 2 * pad)
  g.strokeStyle = "rgba(255,255,255,0.12)"
  g.lineWidth = 1
  for (const v of [0, 0.5, 1]) {
    g.beginPath(); g.moveTo(0, Math.round(y(v)) + 0.5); g.lineTo(w, Math.round(y(v)) + 0.5); g.stroke()
  }
  for (const s of series) {
    g.strokeStyle = s.color
    g.lineWidth = 2
    g.beginPath()
    s.points.forEach((p, i) => (i ? g.lineTo(x(p.t), y(p.v)) : g.moveTo(x(p.t), y(p.v))))
    g.stroke()
  }
  g.font = "10px sans-serif"
  for (const m of marks || []) {
    const mx = Math.round(x(m.t)) + 0.5
    g.strokeStyle = "rgba(255,255,255,0.45)"
    g.beginPath(); g.moveTo(mx, 0); g.lineTo(mx, h); g.stroke()
    g.fillStyle = "rgba(255,255,255,0.8)"
    g.fillText(m.label, Math.min(mx + 3, w - 34), 11)
  }
}

useStreams(["electrics"], streams => {
  const e = streams && streams.electrics
  if (!e) return
  const t = performance.now() / 1000
  const thr = e.throttle_input !== undefined ? e.throttle_input : e.throttle
  const brk = e.brake_input !== undefined ? e.brake_input : e.brake
  live.push({ t, thr: Number(thr) || 0, brk: Number(brk) || 0 })
  while (live.length && live[0].t < t - TRACE_SECONDS) live.shift()
  if (showingRun.value) return
  draw(t - TRACE_SECONDS, TRACE_SECONDS, [
    { color: THR, points: live.map(p => ({ t: p.t, v: p.thr })) },
    { color: BRK, points: live.map(p => ({ t: p.t, v: p.brk })) },
  ])
})

function drawRun() {
  const tr = runTrace.value
  if (!tr || !showingRun.value) return
  const span = tr.span || tr.t[tr.t.length - 1] || 1
  draw(0, span, [
    { color: THR, points: tr.t.map((t, i) => ({ t, v: tr.thr[i] })) },
    { color: BRK, points: tr.t.map((t, i) => ({ t, v: tr.brk[i] })) },
  ], Array.isArray(tr.marks) ? tr.marks : [])
}
watch([runTrace, showingRun], () => nextTick(drawRun))

function onState(data) {
  if ("phase" in data) vm.phase = data.phase
  if ("trace" in data) vm.trace = data.trace || null
  // A reloaded extension forgets which apps are up: say so again, so the main panel leaves the trace to this one.
  if (data.hudParts && !data.hudParts.inputs) api.engineLua("if extensions.rallyAcademy then extensions.rallyAcademy.hudPart('inputs', true) end")
}

onMounted(() => {
  events.on("rallyAcademyState", onState)
  api.engineLua("extensions.load('rallyAcademy'); extensions.rallyAcademy.hudPart('inputs', true); extensions.rallyAcademy.publish()")
})
onUnmounted(() => api.engineLua("if extensions.rallyAcademy then extensions.rallyAcademy.hudPart('inputs', false) end"))
</script>

<style scoped lang="scss">
.ra-inputs {
  position: relative;
  height: 100%;
  box-sizing: border-box;
  padding: 0.3rem;
  background-color: rgba(var(--bng-off-black-rgb), 0.75);
  border-radius: var(--bng-corners-2);
  canvas {
    display: block;
    width: 100%;
    height: 100%;
  }
  .ra-key {
    position: absolute;
    right: 0.5rem;
    bottom: 0.3rem;
    font-size: 0.7rem;
    color: var(--bng-cool-gray-100);
    i {
      display: inline-block;
      width: 0.7rem;
      height: 0.18rem;
      margin: 0 0.25rem 0.15rem 0.5rem;
      vertical-align: middle;
      &.thr { background: rgb(80, 200, 110); }
      &.brk { background: rgb(235, 75, 75); }
    }
  }
}
</style>
