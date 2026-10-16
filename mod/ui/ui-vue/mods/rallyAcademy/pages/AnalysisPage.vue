<template>
  <div class="ra-analysis">
    <div class="ra-metrics">
      <div class="ra-metric">
        <div class="ra-metric-label">Attempts</div>
        <div class="ra-metric-value">{{ totals.attempts }}</div>
      </div>
      <div class="ra-metric">
        <div class="ra-metric-label">Passes</div>
        <div class="ra-metric-value">{{ totals.passes }}</div>
      </div>
      <div class="ra-metric">
        <div class="ra-metric-label">Pass rate</div>
        <div class="ra-metric-value">{{ totals.attempts ? Math.round((100 * totals.passes) / totals.attempts) + "%" : "–" }}</div>
      </div>
      <div class="ra-metric">
        <div class="ra-metric-label">Drills tried</div>
        <div class="ra-metric-value">{{ totals.tried }} <span>/ {{ lessons.length }}</span></div>
      </div>
      <div class="ra-metric">
        <div class="ra-metric-label">Blocks passed</div>
        <div class="ra-metric-value">{{ totals.blocks }} <span>/ {{ lessons.length }}</span></div>
      </div>
    </div>

    <div class="ra-columns">
      <section class="ra-panel ra-modules-panel">
        <div class="ra-panel-title">By module</div>
        <div v-for="m in modules" :key="m.letter" class="ra-module-row">
          <div class="ra-module-name">{{ m.letter }} · {{ m.name }}</div>
          <div class="ra-bar" :title="`${m.tried} of ${m.lessons.length} tried`">
            <div class="ra-bar-tried" :style="{ width: pct(m.tried, m.lessons.length) }"></div>
            <div class="ra-bar-passed" :style="{ width: pct(m.passed, m.lessons.length) }"></div>
          </div>
          <div class="ra-module-nums">{{ m.tried }} tried · {{ m.passed }} passed · {{ m.ready }} auto-graded</div>
        </div>
        <div class="ra-legend">
          <span><i class="ra-swatch passed"></i>Block passed</span>
          <span><i class="ra-swatch tried"></i>Tried</span>
        </div>
      </section>

      <section class="ra-panel ra-table-panel">
        <div class="ra-panel-title">Drills you've tried</div>
        <div v-if="!tried.length" class="ra-empty">
          Nothing recorded yet. Pick a drill on the Exercises tab and press Start; every attempt
          you score shows up here.
        </div>
        <table v-else class="ra-table">
          <thead>
            <tr>
              <th>Drill</th>
              <th>Attempts</th>
              <th>Passes</th>
              <th>Pass rate</th>
              <th>Best time</th>
              <th>Block</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in tried" :key="row.lesson.id">
              <td>{{ row.lesson.id }} · {{ row.lesson.title }}</td>
              <td>{{ row.p.totalAttempts }}</td>
              <td>{{ row.p.totalPasses }}</td>
              <td>{{ Math.round((100 * row.p.totalPasses) / row.p.totalAttempts) }}%</td>
              <td>{{ row.p.bestTime ? row.p.bestTime.toFixed(2) + " s" : "–" }}</td>
              <td :class="{ ok: row.p.lastSessionPassed }">{{ row.p.lastSessionPassed ? "Passed" : "–" }}</td>
            </tr>
          </tbody>
        </table>
        <div class="ra-soon-note">
          <strong>Coming soon:</strong> per-attempt analysis from your telemetry, such as braking
          traces, speed at each gate and lockups over time. Today the mod keeps only your latest
          run's telemetry, so these totals come from your saved progress.
        </div>
      </section>
    </div>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { groupByModule, progressOf } from "../academy.js"

const props = defineProps({
  lessons: { type: Array, default: () => [] },
  progress: { type: Object, default: () => ({}) },
})

const modules = computed(() => groupByModule(props.lessons, props.progress))

const tried = computed(() =>
  props.lessons
    .map(lesson => ({ lesson, p: progressOf(props.progress, lesson) }))
    .filter(row => row.p && row.p.totalAttempts),
)

const totals = computed(() => {
  const t = { attempts: 0, passes: 0, tried: tried.value.length, blocks: 0 }
  for (const row of tried.value) {
    t.attempts += row.p.totalAttempts
    t.passes += row.p.totalPasses
    if (row.p.lastSessionPassed) t.blocks++
  }
  return t
})

const pct = (n, of) => (of ? Math.round((100 * n) / of) + "%" : "0%")
</script>

<style scoped lang="scss">
.ra-analysis {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  height: 100%;
  min-height: 0;
  overflow-y: auto;
  padding-right: 0.5rem;
}

.ra-metrics {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
  gap: 0.5rem;
}

.ra-metric {
  padding: 0.75rem 1rem;
  border-radius: var(--bng-corners-2);
  background-color: rgb(var(--bng-cool-gray-900-rgb));
  border: 1px solid rgb(var(--bng-cool-gray-700-rgb));
  .ra-metric-label {
    font-size: 0.85em;
    color: var(--bng-cool-gray-100);
  }
  .ra-metric-value {
    font-size: 1.8em;
    font-weight: 600;
    color: var(--bng-off-white);
    span {
      font-size: 0.55em;
      font-weight: 400;
      color: var(--bng-cool-gray-100);
    }
  }
}

.ra-columns {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  align-items: flex-start;
}

.ra-panel {
  padding: 1rem;
  border-radius: var(--bng-corners-2);
  background-color: rgb(var(--bng-cool-gray-900-rgb));
  border: 1px solid rgb(var(--bng-cool-gray-700-rgb));
}

.ra-modules-panel {
  flex: 1 1 22rem;
  max-width: 28rem;
}

.ra-table-panel {
  flex: 999 1 24rem;
  min-width: 0;
  overflow-x: auto;
}

.ra-panel-title {
  margin-bottom: 0.75rem;
  font-size: 0.8em;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--bng-orange-400);
}

.ra-module-row {
  margin-bottom: 0.75rem;
}

.ra-module-name {
  color: var(--bng-off-white);
  margin-bottom: 0.25rem;
}

.ra-bar {
  position: relative;
  height: 0.6rem;
  border-radius: var(--bng-corners-1);
  background-color: rgb(var(--bng-cool-gray-700-rgb));
  overflow: hidden;
  > div {
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
  }
  .ra-bar-tried {
    background-color: var(--bng-cool-gray-100);
  }
  .ra-bar-passed {
    background-color: var(--bng-orange-500);
  }
}

.ra-module-nums {
  margin-top: 0.2rem;
  font-size: 0.8em;
  color: var(--bng-cool-gray-100);
}

.ra-legend {
  display: flex;
  gap: 1rem;
  font-size: 0.8em;
  color: var(--bng-cool-gray-100);
  .ra-swatch {
    display: inline-block;
    width: 0.7rem;
    height: 0.7rem;
    margin-right: 0.35rem;
    border-radius: 2px;
    vertical-align: -0.05rem;
    &.passed {
      background-color: var(--bng-orange-500);
    }
    &.tried {
      background-color: var(--bng-cool-gray-100);
    }
  }
}

.ra-table {
  width: 100%;
  border-collapse: collapse;
  color: var(--bng-off-white);
  th {
    text-align: left;
    font-weight: 600;
    font-size: 0.85em;
    color: var(--bng-cool-gray-100);
    padding: 0.35rem 0.5rem;
    border-bottom: 1px solid rgb(var(--bng-cool-gray-700-rgb));
  }
  td {
    padding: 0.4rem 0.5rem;
    border-bottom: 1px solid rgb(var(--bng-cool-gray-800-rgb));
    &.ok {
      color: var(--bng-orange-400);
      font-weight: 600;
    }
  }
}

.ra-empty {
  color: var(--bng-cool-gray-100);
  line-height: 1.45;
}

.ra-soon-note {
  margin-top: 1rem;
  padding: 0.5rem 0.75rem;
  border-radius: var(--bng-corners-1);
  background-color: rgb(var(--bng-cool-gray-800-rgb));
  border-left: 4px solid var(--bng-cool-gray-100);
  line-height: 1.4;
  color: var(--bng-off-white);
}
</style>
