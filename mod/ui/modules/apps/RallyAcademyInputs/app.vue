<template>
  <!-- Rally Academy input trace (ADR 0012): throttle (green) and brake (red) over time, like a sim's input telemetry.
       Live from the car's own input stream; once a run is graded, its whole trace with its gates marked until the next
       one starts. Fills whatever size the layout gives it. -->
  <div class="ra-inputs">
    <canvas ref="canvas"></canvas>
    <span class="ra-key">
      <i class="thr"></i>throttle <i class="brk"></i>brake<span class="ra-mode">{{ showingRun ? " · last run" : " · live" }}</span>
    </span>
  </div>
</template>

<script setup>
import { computed, nextTick, ref, watch } from "vue"
import { useAcademyState } from "../RallyAcademy/hud.js"
import { drawLive, drawRun, runTraceOf, useLiveInputs } from "../RallyAcademy/trace.js"

const { state } = useAcademyState("inputs")
const canvas = ref(null)
const runTrace = computed(() => runTraceOf(state.trace))
const showingRun = computed(() => (state.phase === "review" || state.phase === "scored") && !!runTrace.value)

useLiveInputs((buffer, now) => {
  if (!showingRun.value) drawLive(canvas.value, buffer, now)
})
watch([runTrace, showingRun], () => nextTick(() => showingRun.value && drawRun(canvas.value, runTrace.value)))
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
