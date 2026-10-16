<template>
  <!-- Rally Academy HUD panel (BeamNG 0.39 Vue HUD app: app.json "vue": true). Lua is
       authoritative: this shows the state Lua publishes ("rallyAcademyState") and sends
       commands to extensions.rallyAcademy. -->
  <div class="rally-academy-app">
    <div class="ra-head">
      <span class="ra-title">Rally Academy</span>
      <span class="ra-alpha">alpha</span>
    </div>

    <select v-model="selectedId" class="ra-select" @change="choose">
      <option v-for="x in vm.lessons" :key="x.id" :value="x.id">
        {{ x.id }} · {{ x.title }}{{ x.parked ? " (needs RWD/AWD)" : "" }}
      </option>
    </select>

    <button v-if="lesson && lesson.environment && lesson.environment.levelId" class="ra-btn ra-goto" @click="cmd('goToDrill')">
      ⤳ Go to drill · {{ lesson.environment.mapDisplayName }}
    </button>

    <p v-if="lesson" class="ra-instructions">
      {{ lesson.instructions }}
      <span v-if="isAuto" class="ra-tag ready">Auto-graded</span>
      <span v-else class="ra-tag soon">Coming soon · Pass/Miss</span>
    </p>

    <div class="ra-row">
      <span class="ra-timer" :class="{ running: vm.phase === 'running' }">{{ timerText }}</span>
      <span class="ra-best">best {{ bestText }}</span>
    </div>

    <div class="ra-status">{{ vm.phase }} · {{ vm.successes }}/{{ vm.attempts }} successful · target {{ vm.required }}/{{ vm.target }}</div>

    <div v-if="vm.grade" class="ra-grade">
      <div v-for="(c, i) in vm.grade.checks" :key="i" :class="c.ok ? 'ok' : 'fail'">{{ c.ok ? "✓" : "✗" }} {{ c.text }}</div>
    </div>

    <div class="ra-buttons">
      <button class="ra-btn" @click="cmd('markStart')">Mark start</button>
      <button v-if="assessment.endWhen !== 'gates'" class="ra-btn" @click="cmd('markFinish')">{{ markFinishLabel }}</button>
      <button v-if="assessment.gates" class="ra-btn ra-add-gate" @click="cmd('addGate')">
        + Gate ({{ vm.gateCount || 0 }}/{{ assessment.gates.count }})
      </button>
      <button v-if="assessment.gates && vm.gateCount" class="ra-btn" @click="cmd('clearGates')">Clear gates</button>
      <button class="ra-btn primary" @click="cmd('retry')">↻ Retry</button>
      <button class="ra-btn" @click="cmd('recordAttempt', true)">✓ Pass</button>
      <button class="ra-btn" @click="cmd('recordAttempt', false)">✕ Miss</button>
    </div>

    <p class="ra-reason">{{ vm.reason }}</p>
  </div>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from "vue"
import { useBridge } from "@/bridge"
import { useEvents } from "@/services/events"

const { api } = useBridge()
const events = useEvents() // listeners are removed when the panel unmounts

const vm = reactive({ lessons: [], phase: "loading", successes: 0, attempts: 0 })
const selectedId = ref(null)

const lesson = computed(() => vm.lesson || null)
const assessment = computed(() => (lesson.value && lesson.value.assessment) || {})
const isAuto = computed(() => assessment.value.mode === "automatic")

const markFinishLabel = computed(() => {
  const line = (assessment.value.rules || []).some(r => r.type === "stop_before_line")
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

const COMMANDS = { goToDrill: 1, markStart: 1, markFinish: 1, addGate: 1, clearGates: 1, retry: 1, recordAttempt: 1 }
function cmd(name, arg) {
  if (!COMMANDS[name]) return
  const args = name === "recordAttempt" ? (arg ? "true" : "false") : ""
  api.engineLua(`if extensions.rallyAcademy then extensions.rallyAcademy.${name}(${args}) end`)
}

function choose() {
  if (selectedId.value) api.engineLua(`extensions.rallyAcademy.select(${JSON.stringify(selectedId.value)})`)
}

function onState(data) {
  // Lua publishes partial updates (the catalogue only on request), so merge. Lua sends
  // `grade = false` explicitly when there is none, so a merge clears it.
  Object.assign(vm, data)
  if (data.selected) {
    selectedId.value = data.selected
  } else if (data.lessons && data.lessons.length) {
    // Lua has no drill (game start, or the extension was reloaded): select the one shown
    // here, or the first, so the panel and Lua agree.
    if (!selectedId.value) selectedId.value = data.lessons[0].id
    choose()
  }
}

onMounted(() => {
  events.on("rallyAcademyState", onState)
  // Keeping Lua authoritative also lets the HUD be closed/reopened without losing the session.
  api.engineLua("extensions.load('rallyAcademy'); extensions.rallyAcademy.publish()")
})
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
  padding: 0.25rem;
  font-size: 0.95em;
  background-color: rgb(var(--bng-cool-gray-800-rgb));
  color: var(--bng-off-white);
  border: 1px solid rgb(var(--bng-cool-gray-600-rgb));
  border-radius: var(--bng-corners-1);
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
    color: #4ade80;
  }
  .fail {
    color: #f87171;
  }
}

.ra-buttons {
  display: flex;
  flex-wrap: wrap;
  gap: 0.2rem;
  margin-top: 0.3rem;
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
