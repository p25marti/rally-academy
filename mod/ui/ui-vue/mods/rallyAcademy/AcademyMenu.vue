<template>
  <LayoutSingle v-bng-blur class="layout-content-full flex-column ra-menu">
    <div class="ra-page">
      <BngScreenHeading divider>Rally Academy</BngScreenHeading>

      <div v-if="error" class="ra-error">{{ error }}</div>

      <nav v-if="!error" class="ra-modules">
        <div
          v-for="m in modules"
          :key="m.letter"
          class="ra-module"
          :class="{ active: m.letter === activeModule }"
          @click="jumpTo(m.letter)">
          <span>{{ m.letter }} · {{ m.name }}</span>
          <span class="ra-count">{{ m.passed }}/{{ m.lessons.length }}</span>
        </div>
      </nav>

      <div v-if="!error" class="ra-body">
        <div ref="grid" class="ra-grid">
          <template v-for="m in modules" :key="m.letter">
            <div :id="'ra-module-' + m.letter" class="ra-group-label">{{ m.letter }} · {{ m.name }}</div>
            <div
              v-for="l in m.lessons"
              :key="l.id"
              class="ra-card"
              :class="{ selected: l.id === chosenId, soon: !isAuto(l) }"
              @click="chosenId = l.id">
              <div class="ra-card-title">{{ l.id }} · {{ l.title }}</div>
              <div class="ra-card-sub">{{ l.environment && l.environment.mapDisplayName }}</div>
              <div class="ra-card-tags">
                <span v-if="isAuto(l)" class="ra-tag ready">Auto-graded</span>
                <span v-else class="ra-tag soon">Coming soon</span>
                <span v-if="l.parked" class="ra-tag parked">Needs RWD/AWD</span>
                <span class="ra-status">{{ statusText(l) }}</span>
              </div>
            </div>
          </template>
        </div>

        <aside v-if="chosen" class="ra-details">
          <div class="ra-details-title">{{ chosen.id }} · {{ chosen.title }}</div>
          <div class="ra-details-meta">{{ chosen.difficulty }} · {{ moduleName(chosen) }}</div>
          <div v-if="!isAuto(chosen)" class="ra-soon-note">
            <strong>Coming soon.</strong> Automatic grading for this drill isn't built yet. You can
            still practise it and grade yourself with Pass/Miss.
          </div>
          <p>{{ chosen.instructions }}</p>
          <div class="ra-section">Pass when</div>
          <p>{{ chosen.assessment.successDefinition }}</p>
          <div class="ra-section">Car and venue</div>
          <p>
            {{ chosen.vehicle && chosen.vehicle.displayName }}<br />
            {{ chosen.environment && chosen.environment.mapDisplayName }}
          </p>
          <div class="ra-section">Your progress</div>
          <p>{{ progressText(chosen) }}</p>
          <p v-if="chosen.parked" class="ra-parked-note">{{ chosen.parked }}</p>
          <div class="ra-actions">
            <BngButton :accent="isAuto(chosen) ? ACCENTS.main : ACCENTS.secondary" :disabled="starting" @click="start">
              {{ starting ? "Loading…" : isAuto(chosen) ? "Start drill" : "Practise (Pass/Miss)" }}
            </BngButton>
            <BngButton :accent="ACCENTS.secondary" @click="back">Back</BngButton>
          </div>
        </aside>
      </div>
    </div>
  </LayoutSingle>
</template>

<script setup>
import { computed, onBeforeMount, ref } from "vue"
import { BngButton, BngScreenHeading, ACCENTS } from "@/common/components/base"
import { LayoutSingle } from "@/common/layouts"
import { vBngBlur } from "@/common/directives"
import { useBridge } from "@/bridge"
import { runRaw } from "@/bridge/libs/Lua.js"

// `lua.*` only knows the game's own functions (LuaFunctionSignatures.js); our extension
// is called with raw Lua, as game screens do for theirs.
const { lua } = useBridge()
const academy = (fn, ...args) => runRaw(`extensions.rallyAcademy.${fn}(${args.map(a => JSON.stringify(a)).join(",")})`)

const lessons = ref([])
const progress = ref({})
const chosenId = ref(null)
const activeModule = ref("A")
const starting = ref(false)
const error = ref("")
const grid = ref(null)

// "01  FOUNDATION & PRECISION" -> "Foundation & precision"
function moduleName(lesson) {
  const raw = String(lesson.module || "").replace(/^\d+\s*/, "").toLowerCase()
  return raw.charAt(0).toUpperCase() + raw.slice(1)
}

const isAuto = lesson => lesson.assessment && lesson.assessment.mode === "automatic"
const entry = lesson => (progress.value && progress.value[lesson.id]) || null

function statusText(lesson) {
  const p = entry(lesson)
  if (!p || !p.totalAttempts) return "Not started"
  if (p.lastSessionPassed) return "Block passed"
  return `${p.totalPasses}/${p.totalAttempts} passed`
}

function progressText(lesson) {
  const p = entry(lesson)
  const a = lesson.assessment
  const target = `Target: ${a.requiredPasses} of ${a.attempts} in a block.`
  if (!p || !p.totalAttempts) return `Not tried yet. ${target}`
  const best = p.bestTime ? ` Best time ${p.bestTime.toFixed(2)} s.` : ""
  return `${p.totalPasses} passes from ${p.totalAttempts} attempts.${best} ${target}`
}

// Drills grouped by module, in curriculum order (the order Lua sends them).
const modules = computed(() => {
  const out = []
  for (const l of lessons.value) {
    const letter = l.id.charAt(0)
    let m = out[out.length - 1]
    if (!m || m.letter !== letter) {
      m = { letter, name: moduleName(l), lessons: [], passed: 0 }
      out.push(m)
    }
    m.lessons.push(l)
    if (entry(l) && entry(l).lastSessionPassed) m.passed++
  }
  return out
})

const chosen = computed(() => lessons.value.find(l => l.id === chosenId.value) || null)

function jumpTo(letter) {
  activeModule.value = letter
  const el = grid.value && grid.value.querySelector("#ra-module-" + letter)
  if (el) el.scrollIntoView({ behavior: "smooth", block: "start" })
}

async function start() {
  if (!chosen.value || starting.value) return
  starting.value = true
  const ok = await academy("startDrill", chosen.value.id)
  if (!ok) {
    starting.value = false
    error.value = "Couldn't start that drill. Check beamng.log for rallyAcademy lines."
  }
}

const back = () => lua.extensions.ui_router.navigate("menu")

onBeforeMount(async () => {
  try {
    await lua.extensions.load("rallyAcademy") // already loaded by modScript.lua; harmless if so
    const data = await academy("getMenuData")
    lessons.value = Array.isArray(data && data.lessons) ? data.lessons : []
    progress.value = (data && data.progress) || {}
    chosenId.value = (data && data.selected) || (lessons.value[0] && lessons.value[0].id) || null
    if (!lessons.value.length) error.value = "No drills found. Is the Rally Academy mod enabled?"
  } catch (e) {
    error.value = "Couldn't reach the Rally Academy extension: " + (e && e.message ? e.message : e)
  }
})
</script>

<style scoped lang="scss">
// Readability: everything sits on one dark backing (never straight on the menu scenery),
// cards are opaque, and secondary text uses the light grey. Implemented (auto-graded)
// drills carry the orange accent; coming-soon drills are neutral, not faded.

// LayoutSingle lays its children out in a row: keep everything under the heading in one column.
.ra-page {
  flex: 1 1 auto;
  display: flex;
  flex-direction: column;
  min-height: 0;
  min-width: 0;
  background-color: rgba(var(--bng-off-black-rgb), 0.82);
  border-radius: var(--bng-corners-3);
  color: var(--bng-off-white);
}

.ra-body {
  flex: 1 1 auto;
  display: flex;
  gap: 1rem;
  min-height: 0;
  padding: 0 1rem 1rem;
}

.ra-modules {
  flex: 0 0 auto;
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  padding: 0 1rem 0.75rem;
}

.ra-module {
  display: flex;
  gap: 0.6rem;
  padding: 0.35rem 0.8rem;
  border-radius: var(--bng-corners-2);
  background-color: rgb(var(--bng-cool-gray-800-rgb));
  cursor: pointer;
  &:hover {
    background-color: rgb(var(--bng-cool-gray-700-rgb));
  }
  &.active {
    background-color: var(--bng-orange-500);
    color: var(--bng-off-black);
    .ra-count {
      color: var(--bng-off-black);
    }
  }
  .ra-count {
    color: var(--bng-cool-gray-100);
  }
}

.ra-grid {
  flex: 1 1 auto;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
  grid-auto-rows: min-content;
  gap: 0.5rem;
  overflow-y: auto;
  padding-right: 0.5rem;
}

.ra-group-label {
  grid-column: 1 / -1;
  margin-top: 0.75rem;
  font-size: 1.25em;
  font-weight: 600;
  color: var(--bng-off-white);
}

.ra-card {
  padding: 0.75rem;
  border-radius: var(--bng-corners-2);
  background-color: rgb(var(--bng-cool-gray-800-rgb));
  border: 2px solid rgb(var(--bng-cool-gray-700-rgb));
  border-left: 4px solid var(--bng-orange-500);
  cursor: pointer;
  &.soon {
    background-color: rgb(var(--bng-cool-gray-900-rgb));
    border-left-color: rgb(var(--bng-cool-gray-600-rgb));
  }
  &:hover {
    background-color: rgb(var(--bng-cool-gray-700-rgb));
  }
  &.selected {
    border-color: var(--bng-orange);
    border-left-color: var(--bng-orange);
  }
}

.ra-card-title {
  font-weight: 600;
  color: var(--bng-off-white);
}

.ra-card-sub,
.ra-status {
  font-size: 0.85em;
  color: var(--bng-cool-gray-100);
}

.ra-card-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  align-items: center;
  margin-top: 0.4rem;
}

.ra-tag {
  font-size: 0.75em;
  font-weight: 600;
  padding: 0.05rem 0.45rem;
  border-radius: var(--bng-corners-1);
  &.ready {
    background-color: var(--bng-orange-500);
    color: var(--bng-off-black);
  }
  &.soon {
    background-color: var(--bng-cool-gray-100);
    color: var(--bng-off-black);
  }
  &.parked {
    border: 1px solid var(--bng-cool-gray-100);
    color: var(--bng-off-white);
  }
}

.ra-details {
  flex: 0 0 24rem;
  display: flex;
  flex-direction: column;
  padding: 1rem;
  border-radius: var(--bng-corners-2);
  background-color: rgb(var(--bng-cool-gray-900-rgb));
  border: 1px solid rgb(var(--bng-cool-gray-700-rgb));
  overflow-y: auto;
  p {
    margin: 0 0 0.5rem;
    line-height: 1.45;
    color: var(--bng-off-white);
  }
}

.ra-details-title {
  font-size: 1.4em;
  font-weight: 600;
}

.ra-details-meta {
  color: var(--bng-cool-gray-100);
  margin-bottom: 0.75rem;
}

.ra-soon-note {
  margin-bottom: 0.75rem;
  padding: 0.5rem 0.75rem;
  border-radius: var(--bng-corners-1);
  background-color: rgb(var(--bng-cool-gray-800-rgb));
  border-left: 4px solid var(--bng-cool-gray-100);
  line-height: 1.4;
}

.ra-section {
  margin-top: 0.5rem;
  font-size: 0.8em;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--bng-orange-400);
}

.ra-parked-note {
  color: var(--bng-orange-400);
}

.ra-actions {
  margin-top: auto;
  display: flex;
  gap: 0.5rem;
  padding-top: 1rem;
}

.ra-error {
  padding: 2rem;
  color: var(--bng-add-red-400);
}
</style>
