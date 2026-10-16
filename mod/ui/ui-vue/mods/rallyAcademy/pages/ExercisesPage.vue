<template>
  <div class="ra-exercises">
    <div class="ra-grid">
      <template v-for="m in modules" :key="m.letter">
        <div class="ra-group-label">
          <span>{{ m.letter }} · {{ m.name }}</span>
          <span class="ra-group-count">{{ m.passed }}/{{ m.lessons.length }} blocks passed</span>
        </div>
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
      <div class="ra-rally-mode">
        <div class="ra-rally-title">Full rally stages</div>
        <div>
          For complete stages, use the game's own <strong>Rally</strong> mode (main menu → More... →
          Rally): real stages with co-driver pacenotes, recce, time controls, and gold/silver/bronze
          against reference times. The drills above build the car control those stages need.
        </div>
      </div>
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
      <p v-if="chosen.environment && chosen.environment.areaHint" class="ra-hint">{{ chosen.environment.areaHint }}</p>
      <div class="ra-section">Your progress</div>
      <p>{{ progressText(chosen) }}</p>
      <p v-if="chosen.parked" class="ra-parked-note">{{ chosen.parked }}</p>
      <div class="ra-actions">
        <BngButton :accent="isAuto(chosen) ? ACCENTS.main : ACCENTS.secondary" :disabled="starting" @click="start">
          {{ starting ? "Loading…" : isAuto(chosen) ? "Start drill" : "Practise (Pass/Miss)" }}
        </BngButton>
        <BngButton v-if="showBack" :accent="ACCENTS.secondary" @click="$emit('back')">Back</BngButton>
      </div>
      <p v-if="startError" class="ra-error">{{ startError }}</p>
    </aside>
  </div>
</template>

<script setup>
import { computed, ref, watch } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { academy, groupByModule, isAuto, moduleName, progressOf } from "../academy.js"

const props = defineProps({
  lessons: { type: Array, default: () => [] },
  progress: { type: Object, default: () => ({}) },
  selected: { type: String, default: null },
  showBack: { type: Boolean, default: true }, // the pause menu has its own back
})
defineEmits(["back"])

const chosenId = ref(props.selected)
watch(
  () => props.selected,
  id => { if (!chosenId.value) chosenId.value = id },
)
const starting = ref(false)
const startError = ref("")

const modules = computed(() => groupByModule(props.lessons, props.progress))
const chosen = computed(
  () => props.lessons.find(l => l.id === chosenId.value) || props.lessons[0] || null,
)

function statusText(lesson) {
  const p = progressOf(props.progress, lesson)
  if (!p || !p.totalAttempts) return "Not started"
  if (p.lastSessionPassed) return "Block passed"
  return `${p.totalPasses}/${p.totalAttempts} passed`
}

function progressText(lesson) {
  const p = progressOf(props.progress, lesson)
  const a = lesson.assessment
  const target = `Target: ${a.requiredPasses} of ${a.attempts} in a block.`
  if (!p || !p.totalAttempts) return `Not tried yet. ${target}`
  const best = p.bestTime ? ` Best time ${p.bestTime.toFixed(2)} s.` : ""
  return `${p.totalPasses} passes from ${p.totalAttempts} attempts.${best} ${target}`
}

async function start() {
  if (!chosen.value || starting.value) return
  starting.value = true
  startError.value = ""
  const ok = await academy("startDrill", chosen.value.id)
  if (!ok) {
    starting.value = false
    startError.value = "Couldn't start that drill. Check beamng.log for rallyAcademy lines."
  }
}
</script>

<style scoped lang="scss">
.ra-exercises {
  flex: 1 1 auto;
  display: flex;
  gap: 1rem;
  min-height: 0;
  height: 100%;
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
  display: flex;
  align-items: baseline;
  gap: 1rem;
  margin-top: 0.75rem;
  font-size: 1.25em;
  font-weight: 600;
  color: var(--bng-off-white);
  .ra-group-count {
    font-size: 0.7em;
    font-weight: 400;
    color: var(--bng-cool-gray-100);
  }
}

.ra-rally-mode {
  grid-column: 1 / -1;
  margin-top: 1rem;
  padding: 0.75rem 1rem;
  border-radius: var(--bng-corners-2);
  background-color: rgb(var(--bng-cool-gray-900-rgb));
  border: 1px solid rgb(var(--bng-cool-gray-700-rgb));
  border-left: 4px solid var(--bng-orange-400);
  line-height: 1.45;
  color: var(--bng-off-white);
  .ra-rally-title {
    font-weight: 600;
    margin-bottom: 0.25rem;
  }
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

.ra-hint {
  font-size: 0.9em;
  color: var(--bng-cool-gray-100) !important;
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

.ra-details .ra-error {
  color: var(--bng-add-red-400);
}
</style>
