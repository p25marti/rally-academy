<template>
  <!-- Rally Academy coach (ADR 0012): what to do before a run (the drill's instructions), and how it went after it
       (the medal, what the next one needs, and every check of the grade: the reasons are the coaching). Lua is
       authoritative; this only shows "rallyAcademyState". -->
  <div class="ra-coach">
    <template v-if="lesson">
      <div class="ra-title">{{ lesson.id }} · {{ lesson.title }}<span v-if="lesson.surface" class="ra-surface">{{ lesson.surface }}</span></div>

      <div v-if="vm.grade" class="ra-grade">
        <div class="ra-result">
          <span v-if="vm.grade.tier" class="ra-medal" :class="vm.grade.tier">{{ vm.grade.tier }}</span>
          <span v-else class="ra-medal miss">{{ vm.grade.passed ? "pass" : "miss" }}</span>
          <span v-if="vm.grade.nextTier" class="ra-next">{{ vm.grade.nextTier.name }}: {{ vm.grade.nextTier.text }}</span>
        </div>
        <div v-for="(c, i) in checks" :key="i" class="ra-check" :class="c.ok ? 'ok' : 'fail'">{{ c.ok ? "✓" : "✗" }} {{ c.text }}</div>
      </div>

      <template v-else>
        <p class="ra-instructions">{{ lesson.instructions }}</p>
        <p v-if="success" class="ra-success">{{ success }}</p>
      </template>
    </template>
    <p v-else class="ra-instructions">Pick a drill in the Rally Academy panel.</p>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, reactive } from "vue"
import { useBridge } from "@/bridge"
import { useEvents } from "@/services/events"

const { api } = useBridge()
const events = useEvents()
const vm = reactive({ lesson: null, grade: null, phase: "loading" })

const lesson = computed(() => vm.lesson || null)
// Failed checks first, then the passed ones (an empty Lua list arrives as {}).
const checks = computed(() => {
  const all = vm.grade && Array.isArray(vm.grade.checks) ? vm.grade.checks : []
  return all.filter(c => !c.ok).concat(all.filter(c => c.ok))
})
const success = computed(() => {
  const a = lesson.value && lesson.value.assessment
  return a && a.mode === "automatic" ? a.successDefinition : null
})

function onState(data) {
  // Lua publishes partial updates; `grade = false` clears it.
  for (const k of ["lesson", "grade", "phase"]) if (k in data) vm[k] = data[k] || null
  // A reloaded extension forgets which apps are up: say so again, so the main panel leaves the notes to this one.
  if (data.hudParts && !data.hudParts.coach) api.engineLua("if extensions.rallyAcademy then extensions.rallyAcademy.hudPart('coach', true) end")
}

onMounted(() => {
  events.on("rallyAcademyState", onState)
  api.engineLua("extensions.load('rallyAcademy'); extensions.rallyAcademy.hudPart('coach', true); extensions.rallyAcademy.publish()")
})
onUnmounted(() => api.engineLua("if extensions.rallyAcademy then extensions.rallyAcademy.hudPart('coach', false) end"))
</script>

<style scoped lang="scss">
.ra-coach {
  height: 100%;
  box-sizing: border-box;
  padding: 0.5rem 0.65rem;
  overflow-y: auto;
  background-color: rgba(var(--bng-off-black-rgb), 0.85);
  border-radius: var(--bng-corners-2);
  color: var(--bng-off-white);
  font-size: 0.8rem;
  line-height: 1.35;
}
.ra-title {
  font-weight: 700;
  margin-bottom: 0.3rem;
  .ra-surface {
    margin-left: 0.4rem;
    font-weight: 400;
    color: var(--bng-cool-gray-100);
  }
}
.ra-instructions {
  margin: 0 0 0.4rem;
}
.ra-success {
  margin: 0;
  color: var(--bng-cool-gray-100);
  font-size: 0.75rem;
}
.ra-result {
  display: flex;
  align-items: baseline;
  gap: 0.4rem;
  margin-bottom: 0.3rem;
}
.ra-medal {
  padding: 0 0.4rem;
  border-radius: var(--bng-corners-1);
  font-weight: 700;
  text-transform: uppercase;
  font-size: 0.75rem;
  &.gold { background: #c99a1b; color: #111; }
  &.silver { background: #b8bcc6; color: #111; }
  &.bronze { background: #a8693a; color: #111; }
  &.miss { background: rgba(235, 75, 75, 0.85); color: #fff; }
}
.ra-next {
  color: var(--bng-cool-gray-100);
  font-size: 0.75rem;
}
.ra-check {
  &.ok { color: rgb(150, 220, 160); }
  &.fail { color: rgb(255, 140, 130); }
}
</style>
