<script setup>
defineProps({
  // { label, pack } triples for autonomous / assisted / human-only CSAT.
  scores: {
    type: Array,
    default: () => [],
  },
});

const hasValue = pack => pack?.current !== null && pack?.current !== undefined;
</script>

<template>
  <section
    class="flex flex-col gap-4 rounded-xl border border-n-weak bg-n-solid-2 p-4"
  >
    <h3 class="text-sm font-medium text-n-slate-12">
      {{ $t('PILOT.OVERVIEW.CSAT.TITLE') }}
    </h3>

    <div class="grid grid-cols-3 gap-3">
      <div
        v-for="score in scores"
        :key="score.label"
        class="flex flex-col gap-1 rounded-lg bg-n-alpha-1 p-3"
      >
        <span class="text-xs text-n-slate-11">{{ score.label }}</span>
        <span
          v-if="hasValue(score.pack)"
          class="text-xl font-semibold text-n-slate-12"
        >
          {{ score.pack.current.toFixed(2) }}
        </span>
        <span v-else class="text-xs text-n-slate-10">
          {{ $t('PILOT.OVERVIEW.CSAT.NO_RATINGS') }}
        </span>
      </div>
    </div>
  </section>
</template>
