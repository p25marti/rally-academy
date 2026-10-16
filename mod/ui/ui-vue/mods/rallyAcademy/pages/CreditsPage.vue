<template>
  <div class="ra-text-page">
    <section class="ra-panel">
      <div class="ra-panel-title">Created by</div>
      <p class="ra-big">{{ info.author || "The Rally Academy authors" }}</p>
      <p class="ra-muted">Developed with help from Claude (Anthropic).</p>
    </section>

    <section class="ra-panel">
      <div class="ra-panel-title">Drill design</div>
      <p>
        The drills are original exercises, not official BeamNG missions. Their structure and
        order draw on real rally-school teaching, including the Team O'Neil and DirtFish rally
        schools, and on the rally school in Richard Burns Rally.
      </p>
      <p class="ra-muted">Rally Academy isn't affiliated with or endorsed by any of them.</p>
    </section>

    <section class="ra-panel">
      <div class="ra-panel-title">Built on</div>
      <p>
        BeamNG.drive by BeamNG GmbH: its maps, cars and physics, and the Vue UI mod system this
        screen is built with.
      </p>
    </section>
  </div>
</template>

<script setup>
defineProps({
  info: { type: Object, default: () => ({}) },
})
</script>

<style scoped lang="scss">
.ra-text-page {
  height: 100%;
  min-height: 0;
  overflow-y: auto;
  padding-right: 0.5rem;
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  grid-auto-rows: min-content;
  gap: 1rem;
  max-width: 80rem;
}

.ra-panel {
  padding: 1rem 1.25rem;
  border-radius: var(--bng-corners-2);
  background-color: rgb(var(--bng-cool-gray-900-rgb));
  border: 1px solid rgb(var(--bng-cool-gray-700-rgb));
  color: var(--bng-off-white);
  line-height: 1.5;
  p {
    margin: 0 0 0.5rem;
  }
}

.ra-panel-title {
  margin-bottom: 0.5rem;
  font-size: 0.8em;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--bng-orange-400);
}

.ra-big {
  font-size: 1.4em;
  font-weight: 600;
}

.ra-muted {
  color: var(--bng-cool-gray-100);
}
</style>
