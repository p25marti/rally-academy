<template>
  <!-- Rally Academy HUD panel (BeamNG 0.39 Vue HUD app: app.json "vue": true). Lua is
       authoritative: this shows the state Lua publishes ("rallyAcademyState") and sends
       commands to extensions.rallyAcademy. -->
  <div class="rally-academy-app">
    <div class="ra-head">
      <span class="ra-title">Rally Academy</span>
      <span class="ra-alpha">alpha</span>
    </div>

    <!-- The game's own drop-down: a native <select> can't open its list in BeamNG's
         off-screen UI browser (0.39.4), so it couldn't be clicked. -->
    <BngDropdown
      v-model="selectedId"
      class="ra-select"
      :items="drillItems"
      show-search
      search-group-name
      @value-changed="choose" />

    <!-- Surface variants (ADR 0009): the same drill on another strip of the proving ground, each with its own
         progress. The drop-down shows the base drill; these pick the surface. Hidden while driving: the panel
         needs the room for the run and its result. -->
    <div v-if="surfaces.length > 1 && !driving" class="ra-surfaces">
      <span class="ra-surfaces-label">Surface</span>
      <button v-for="s in surfaces" :key="s.id" class="ra-chip" :class="{ on: s.id === vm.selected }" @click="pick(s.id)">
        {{ s.name }}
        <span v-if="tierOf(s.id)" class="ra-dot" :class="tierOf(s.id)"></span>
      </button>
    </div>

    <button v-if="lesson && lesson.environment && lesson.environment.levelId && !driving" class="ra-btn ra-goto" @click="cmd('goToDrill')">
      ⤳ Go to drill · {{ lesson.environment.mapDisplayName }}
    </button>

    <!-- Instructions while setting up (unless the Coach app shows them); once driving, the space goes to the run. -->
    <p v-if="lesson && !driving && !coachUp" class="ra-instructions">
      {{ lesson.instructions }}
      <span v-if="isAuto" class="ra-tag ready">Auto-graded</span>
      <span v-else class="ra-tag soon">Coming soon · Pass/Miss</span>
    </p>

    <!-- Authored course: checklist, which side of the cone, and the parking aid near the box. -->
    <div v-if="vm.course" class="ra-course">
      <span v-for="(st, i) in courseSteps" :key="i" class="ra-step" :class="st.state">
        {{ st.state === "passed" ? "✓" : st.state === "missed" ? "✗" : "·" }} {{ st.label }}
      </span>
      <span v-if="vm.course.keep" class="ra-keep">cone on your {{ vm.course.keep }}</span>
      <!-- B03: the driver's predicted stop, set before the run (Lua moves the mark). -->
      <div v-if="vm.course.predict && !driving" class="ra-predict">
        Your mark
        <button class="ra-btn" @click="cmd('nudgePrediction', -1)">−</button>
        <b>{{ vm.course.predict.m }} m</b>
        <button class="ra-btn" @click="cmd('nudgePrediction', 1)">+</button>
        past the brake line
      </div>
      <div v-if="vm.course.clipped" class="ra-aid fail">Clipped {{ vm.course.clipped }}</div>
      <div v-else-if="vm.course.aid" class="ra-aid">
        {{ vm.course.aid }}
        <span v-if="vm.course.fit" class="ra-medal" :class="vm.course.fit">in {{ vm.course.fit }}</span>
      </div>
    </div>

    <!-- Throttle (green) and brake (red), like a sim's input telemetry: live while driving (the last TRACE_SECONDS
         from the car's own input stream; the instructions make way), then the run's trace with its gates marked. -->
    <div v-if="showTrace && !inputsUp" class="ra-trace">
      <canvas ref="traceCanvas"></canvas>
      <span class="ra-trace-key"><i class="thr"></i>throttle <i class="brk"></i>brake <i class="hb"></i>handbrake{{ traceLive ? "" : " · this run" }}</span>
    </div>

    <div class="ra-row">
      <span class="ra-timer" :class="{ running: vm.phase === 'running' }">{{ timerText }}</span>
      <span class="ra-best">
        best {{ bestText }}
        <span v-if="bestTier" class="ra-medal" :class="bestTier">{{ bestTier }}</span>
      </span>
    </div>

    <div class="ra-status">{{ vm.phase }} · {{ vm.successes }}/{{ vm.attempts }} successful · target {{ vm.required }}/{{ vm.target }}</div>

    <div v-if="vm.grade" class="ra-grade">
      <div v-if="vm.grade.tier" class="ra-result">
        <span class="ra-medal big" :class="vm.grade.tier">{{ vm.grade.tier }}</span>
        <span v-if="vm.grade.nextTier" class="ra-next">{{ vm.grade.nextTier.name }}: {{ vm.grade.nextTier.text }}</span>
      </div>
      <template v-if="!coachUp">
        <div v-for="(c, i) in gradeChecks.shown" :key="i" :class="c.ok ? 'ok' : 'fail'">{{ c.ok ? "✓" : "✗" }} {{ c.text }}</div>
        <div v-if="gradeChecks.folded" class="ok folded">✓ {{ gradeChecks.folded }} more checks passed</div>
      </template>
    </div>
    <div v-if="vm.autoRetryIn" class="ra-countdown">Next attempt in {{ vm.autoRetryIn }}… (drive off to stay)</div>

    <div class="ra-buttons">
      <button class="ra-btn" @click="cmd('markStart')">{{ hasCourse ? "Move course here" : "Mark start" }}</button>
      <button v-if="hasCourse && vm.hasStart && !vm.usingVenueStart" class="ra-btn" @click="cmd('useVenueStart')">Use venue start</button>
      <button v-if="!hasCourse && assessment.endWhen !== 'gates'" class="ra-btn" @click="cmd('markFinish')">{{ markFinishLabel }}</button>
      <button v-if="assessment.gates" class="ra-btn ra-add-gate" @click="cmd('addGate')">
        + Gate ({{ vm.gateCount || 0 }}/{{ assessment.gates.count }})
      </button>
      <button v-if="assessment.gates && vm.gateCount" class="ra-btn" @click="cmd('clearGates')">Clear gates</button>
      <button class="ra-btn primary" @click="cmd('retry')">↻ Retry</button>
      <button v-if="!isAuto" class="ra-btn" @click="cmd('recordAttempt', true)">✓ Pass</button>
      <button class="ra-btn" @click="cmd('recordAttempt', false)">✕ Miss</button>
      <button v-if="isAuto" class="ra-btn" :class="{ on: vm.autoRetry }" @click="cmd('setAutoRetry', !vm.autoRetry)">
        Auto-retry {{ vm.autoRetry ? "on" : "off" }}
      </button>
      <button v-if="vm.hasLine" class="ra-btn" :class="{ on: vm.showLine }" @click="cmd('setShowLine', !vm.showLine)">
        Line {{ vm.showLine ? "on" : "off" }}
      </button>
      <button v-if="vm.canDemo" class="ra-btn" :class="{ on: vm.demo }" @click="cmd('demo')">▶ Watch AI</button>
    </div>

    <p v-if="!vm.autoRetryIn" class="ra-reason">{{ vm.reason }}</p>
  </div>
</template>

<script setup>
import { computed, nextTick, ref, watch } from "vue"
import { BngDropdown } from "@/common/components/base"
import { useAcademyState } from "./hud.js"
import { drawLive, drawRun, runTraceOf, useLiveInputs } from "./trace.js"


const { state: vm, lua } = useAcademyState(null, onData)
const selectedId = ref(null)

const lesson = computed(() => vm.lesson || null)

// "01  FOUNDATION & PRECISION" -> "Foundation & precision"
function moduleName(module) {
  const raw = String(module || "").replace(/^\d+\s*/, "").toLowerCase()
  return raw.charAt(0).toUpperCase() + raw.slice(1)
}

// Drill list for the drop-down, with a header per module (curriculum order, as Lua sends it).
const drillItems = computed(() => {
  const out = []
  let letter = null
  for (const x of Array.isArray(vm.lessons) ? vm.lessons : []) {
    if (x.id.charAt(0) !== letter) {
      letter = x.id.charAt(0)
      out.push({ label: `${letter} · ${moduleName(x.module)}`, value: `module-${letter}`, group: true })
    }
    out.push({ label: `${x.id} · ${x.title}${x.parked ? " (needs RWD/AWD)" : ""}`, value: x.id, grouped: true })
  }
  return out
})
const assessment = computed(() => (lesson.value && lesson.value.assessment) || {})
// Lua lists may arrive as {} when empty, so check before iterating.
const surfaces = computed(() => (lesson.value && Array.isArray(lesson.value.surfaces) ? lesson.value.surfaces : []))
function tierOf(id) {
  const p = vm.progress
  return (p && p[id] && p[id].bestTier) || null
}
function pick(id) {
  if (id !== vm.selected) lua(`select(${JSON.stringify(id)})`)
}
const isAuto = computed(() => assessment.value.mode === "automatic")
const hasCourse = computed(() => !!assessment.value.course)
const driving = computed(() => ["running", "review", "scored"].includes(vm.phase))
// Lua lists may arrive as {} when empty, so check before iterating.
const courseSteps = computed(() => (vm.course && Array.isArray(vm.course.steps) ? vm.course.steps : []))
// The panel fits about five grade lines (three under the run's input trace): failed checks first (always all of them), then passed
// checks that carry a number (the coaching: "0-40 km/h in 3.1 s"), then the rest; whatever
// doesn't fit folds into "N more checks passed".
const gradeChecks = computed(() => {
  const MAX_GRADE_LINES = showTrace.value && !inputsUp.value ? 3 : 5 // the run's input trace takes two lines' room
  const all = vm.grade && Array.isArray(vm.grade.checks) ? vm.grade.checks : []
  const failed = all.filter(c => !c.ok)
  const passed = all.filter(c => c.ok)
  const ranked = passed.filter(c => /\d/.test(c.text)).concat(passed.filter(c => !/\d/.test(c.text)))
  const room = Math.max(0, MAX_GRADE_LINES - failed.length)
  const keep = all.length <= MAX_GRADE_LINES ? passed : ranked.slice(0, room - 1 > 0 ? room - 1 : 0)
  const kept = new Set(failed.concat(keep))
  return { shown: all.filter(c => kept.has(c)), folded: passed.length - keep.length }
})
const bestTier = computed(() => {
  const p = vm.progress
  const id = vm.selected
  return (p && id && p[id] && p[id].bestTier) || null
})

const markFinishLabel = computed(() => {
  // An empty Lua table arrives as {} (an object), not [], so check before using it as a list.
  const rules = Array.isArray(assessment.value.rules) ? assessment.value.rules : []
  const line = rules.some(r => r.type === "stop_before_line")
  return line ? "Mark stop line" : assessment.value.endWhen === "stopped" ? "Mark stop zone" : "Mark finish"
})

// Seconds -> "12.3" or "1:02.34". Lua sends elapsed at ~4 Hz, so the live clock shows
// tenths; final times show hundredths.
function fmt(t, digits) {
  if (typeof t !== "number" || !isFinite(t)) return "--"
  const k = Math.pow(10, digits)
  t = Math.round(t * k) / k // round first so 119.96 becomes 2:00.0, not 1:60.0
  const m = Math.floor(t / 60)
  const s = (t - m * 60).toFixed(digits)
  if (m === 0) return s
  return m + ":" + (parseFloat(s) < 10 ? "0" : "") + s
}

const timerText = computed(() => {
  if (vm.phase === "running") return fmt(vm.elapsed, 1)
  if (vm.phase === "review" || vm.phase === "scored") return fmt(vm.lastTime, 2)
  if (vm.phase === "ready") return fmt(0, 1)
  return "--"
})

const bestText = computed(() => {
  const p = vm.progress
  const id = vm.selected
  return fmt(p && id && p[id] ? p[id].bestTime : null, 2)
})

const COMMANDS = { goToDrill: 1, markStart: 1, markFinish: 1, addGate: 1, clearGates: 1, retry: 1, recordAttempt: 1,
                   useVenueStart: 1, setAutoRetry: 1, setShowLine: 1, nudgePrediction: 1, demo: 1 }
const BOOL_ARG = { recordAttempt: 1, setAutoRetry: 1, setShowLine: 1 }
const NUM_ARG = { nudgePrediction: 1 }
function cmd(name, arg) {
  if (!COMMANDS[name]) return
  const args = BOOL_ARG[name] ? (arg ? "true" : "false") : NUM_ARG[name] ? String(Number(arg) || 0) : ""
  lua(`${name}(${args})`)
}

// Our other HUD apps (ADR 0012): when they're on screen this panel leaves the trace or the notes to them.
const inputsUp = computed(() => !!(vm.hudParts && vm.hudParts.inputs))
const coachUp = computed(() => !!(vm.hudParts && vm.hudParts.coach))

// Input trace (trace.js): live while driving, then the run's own trace with its gates marked, unless the Inputs app
// is up. Drawn smaller than the Inputs app's.
const TRACE_STYLE = { lineWidth: 1.75, fontPx: 9, pad: 2, steering: false } // too small for a steering lane: the Inputs app has one
const traceCanvas = ref(null)
const traceLive = computed(() => vm.phase === "running")
const runTrace = computed(() => runTraceOf(vm.trace))
const showTrace = computed(() => !!lesson.value && (traceLive.value || ((vm.phase === "review" || vm.phase === "scored") && !!runTrace.value)))
useLiveInputs((buffer, now) => {
  if (traceLive.value && !inputsUp.value) drawLive(traceCanvas.value, buffer, now, TRACE_STYLE)
})
watch([runTrace, () => vm.phase], () => nextTick(() => {
  if (runTrace.value && !traceLive.value) drawRun(traceCanvas.value, runTrace.value, TRACE_STYLE)
}))

function choose() {
  const id = selectedId.value
  const base = vm.lesson && vm.lesson.variantOf
  if (!id || String(id).startsWith("module-") || id === vm.selected || id === base) return
  lua(`select(${JSON.stringify(id)})`)
}

// Each state update (merged into vm by useAcademyState): keep the drop-down on Lua's drill.
function onData(data) {
  if (data.selected) {
    // a surface variant shows as its base drill in the drop-down (the chips show which surface)
    const l = data.lesson || vm.lesson
    selectedId.value = (l && l.id === data.selected && l.variantOf) || data.selected
  } else if (data.lessons && data.lessons.length) {
    // Lua has no drill (game start, or the extension was reloaded): select the one shown
    // here, or the first, so the panel and Lua agree.
    if (!selectedId.value) selectedId.value = data.lessons[0].id
    choose()
  }
}
</script>

<style scoped lang="scss">
.rally-academy-app {
  height: 100%;
  box-sizing: border-box;
  padding: 0.5rem 0.65rem;
  overflow-y: auto;
  background-color: rgba(var(--bng-off-black-rgb), 0.9);
  border-radius: var(--bng-corners-2);
  color: var(--bng-off-white);
  font-size: 0.8rem;
  line-height: 1.3;
}

.ra-head {
  display: flex;
  align-items: baseline;
  gap: 0.4rem;
  margin-bottom: 0.3rem;
  .ra-title {
    font-weight: 700;
    font-size: 1.15em;
    text-transform: uppercase;
  }
  .ra-alpha {
    font-size: 0.75em;
    color: var(--bng-cool-gray-100);
  }
}

.ra-select {
  width: 100%;
  font-size: 0.95em;
}

.ra-surfaces {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.2rem;
  margin-top: 0.3rem;
  .ra-surfaces-label {
    color: var(--bng-cool-gray-100);
    margin-right: 0.15rem;
  }
}

.ra-chip {
  padding: 0.05rem 0.45rem;
  font-size: 0.9em;
  color: var(--bng-off-white);
  background-color: rgb(var(--bng-cool-gray-700-rgb));
  border: 1px solid rgb(var(--bng-cool-gray-600-rgb));
  border-radius: var(--bng-corners-1);
  cursor: pointer;
  &.on {
    background-color: var(--bng-orange-500);
    border-color: var(--bng-orange-500);
    color: var(--bng-off-black);
    font-weight: 600;
  }
  .ra-dot {
    display: inline-block;
    width: 0.45rem;
    height: 0.45rem;
    margin-left: 0.2rem;
    border-radius: 50%;
    &.bronze { background-color: #c8813f; }
    &.silver { background-color: #c9ccd6; }
    &.gold { background-color: #f2c014; }
  }
}

.ra-instructions {
  margin: 0.3rem 0;
  color: var(--bng-cool-gray-100);
}

.ra-tag {
  display: inline-block;
  font-size: 0.8em;
  font-weight: 600;
  padding: 0 0.35rem;
  border-radius: var(--bng-corners-1);
  &.ready {
    background-color: var(--bng-orange-500);
    color: var(--bng-off-black);
  }
  &.soon {
    background-color: var(--bng-cool-gray-100);
    color: var(--bng-off-black);
  }
}

.ra-trace {
  position: relative;
  margin: 0.15rem 0;
  canvas {
    display: block;
    width: 100%;
    height: 2.3rem;
    background: rgba(255, 255, 255, 0.04);
    border-radius: var(--bng-corners-1);
  }
  .ra-trace-key {
    position: absolute;
    right: 0.3rem;
    bottom: 0.15rem;
    font-size: 0.65rem;
    color: var(--bng-cool-gray-100);
    i {
      display: inline-block;
      width: 0.6rem;
      height: 0.15rem;
      margin: 0 0.2rem 0.15rem 0.4rem;
      vertical-align: middle;
      &.thr { background: rgb(80, 200, 110); }
      &.brk { background: rgb(235, 75, 75); }
      &.hb { background: rgb(90, 160, 255); }
    }
  }
}

.ra-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
}

.ra-timer {
  font-size: 1.9em;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  &.running {
    color: var(--bng-orange-400);
  }
}

.ra-best {
  color: var(--bng-cool-gray-100);
}

.ra-status {
  margin: 0.3rem 0;
  padding: 0.25rem 0.4rem;
  border-radius: var(--bng-corners-1);
  background-color: rgb(var(--bng-cool-gray-800-rgb));
}

.ra-grade {
  margin: 0.3rem 0;
  font-size: 0.95em;
  .ok {
    color: var(--bng-add-green-400);
  }
  .fail {
    color: var(--bng-add-red-400);
  }
  .folded {
    opacity: 0.75;
  }
}

.ra-buttons {
  display: flex;
  flex-wrap: wrap;
  gap: 0.2rem;
  margin-top: 0.3rem;
}

.ra-course {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 0.15rem 0.45rem;
  margin: 0.25rem 0;
  .ra-step {
    color: var(--bng-cool-gray-100);
    &.next {
      color: var(--bng-orange-400);
      font-weight: 600;
    }
    &.passed {
      color: var(--bng-add-green-400);
    }
    &.missed {
      color: var(--bng-add-red-400);
    }
  }
  .ra-predict {
    display: flex;
    align-items: center;
    gap: 0.35rem;
    width: 100%;
    margin-top: 0.2rem;
    .ra-btn {
      padding: 0 0.5rem;
      min-width: 1.6rem;
    }
  }
  .ra-keep {
    margin-left: auto;
    font-size: 0.9em;
    color: var(--bng-cool-gray-100);
  }
  .ra-aid {
    width: 100%;
    font-variant-numeric: tabular-nums;
    &.fail {
      color: var(--bng-add-red-400);
    }
  }
}

.ra-medal {
  display: inline-block;
  padding: 0 0.3rem;
  border-radius: var(--bng-corners-1);
  font-size: 0.85em;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--bng-off-black);
  &.bronze {
    background-color: #c8813f;
  }
  &.silver {
    background-color: #c9ccd6;
  }
  &.gold {
    background-color: #f2c014;
  }
  &.big {
    font-size: 1em;
    padding: 0.05rem 0.45rem;
  }
}

.ra-result {
  display: flex;
  align-items: baseline;
  gap: 0.4rem;
  margin-bottom: 0.15rem;
  .ra-next {
    color: var(--bng-cool-gray-100);
  }
}

.ra-countdown {
  margin: 0.2rem 0;
  color: var(--bng-orange-400);
  font-weight: 600;
}

.ra-btn {
  padding: 0.15rem 0.4rem;
  font-size: 0.9em;
  color: var(--bng-off-white);
  background-color: rgb(var(--bng-cool-gray-700-rgb));
  border: 1px solid rgb(var(--bng-cool-gray-600-rgb));
  border-radius: var(--bng-corners-1);
  cursor: pointer;
  &:hover {
    background-color: rgb(var(--bng-cool-gray-600-rgb));
  }
  &.on {
    border-color: var(--bng-orange-500);
  }
  &.primary {
    background-color: var(--bng-orange-500);
    border-color: var(--bng-orange-500);
    color: var(--bng-off-black);
    font-weight: 600;
  }
}

.ra-goto {
  width: 100%;
  margin-top: 0.3rem;
}

.ra-reason {
  margin: 0.4rem 0 0;
  color: var(--bng-cool-gray-100);
}
</style>
