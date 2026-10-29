<template>
  <!-- Rally Academy input trace (ADR 0012): throttle (green), brake (red) and handbrake (blue) over time, like a sim's
       input telemetry, and the steering in a lane under them (left up). Live from the car's own input stream; once a
       run is graded, its whole trace with its gates marked until the next one starts. Fills whatever size the layout
       gives it. -->
  <div class="ra-inputs">
    <canvas ref="canvas"></canvas>
    <div class="ra-key">
      <i class="thr"></i>throttle <i class="brk"></i>brake <i class="hb"></i>handbrake <i class="st"></i>steering
      <span class="ra-mode">{{ showingRun ? " · last run" : " · live" }}</span>
    </div>
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
  display: flex;
  flex-direction: column;
  height: 100%;
  box-sizing: border-box;
  padding: 0.3rem 0.3rem 0.15rem;
  background-color: rgba(var(--bng-off-black-rgb), 0.75);
  border-radius: var(--bng-corners-2);
  canvas {
    display: block;
    width: 100%;
    flex: 1;
    min-height: 0;
  }
  .ra-key {
    flex: none;
    text-align: right;
    font-size: 0.7rem;
    line-height: 1.2rem;
    color: var(--bng-cool-gray-100);
    i {
      display: inline-block;
      width: 0.7rem;
      height: 0.18rem;
      margin: 0 0.25rem 0.15rem 0.5rem;
      vertical-align: middle;
      &.thr { background: rgb(80, 200, 110); }
      &.brk { background: rgb(235, 75, 75); }
      &.hb { background: rgb(90, 160, 255); }
      &.st { background: rgb(235, 235, 235); }
    }
  }
}
</style>
