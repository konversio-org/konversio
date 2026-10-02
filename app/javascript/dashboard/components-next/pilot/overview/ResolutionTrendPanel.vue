<script setup>
import { computed, ref } from 'vue';

const props = defineProps({
  trend: {
    type: Object,
    default: () => ({ granularity: 'day', buckets: [] }),
  },
});

const measure = ref('counts');

const isEmpty = computed(() => !props.trend?.buckets?.length);

const maxCount = computed(() =>
  (props.trend?.buckets || []).reduce(
    (max, bucket) => Math.max(max, bucket.involved || 0),
    0
  )
);

const barHeight = value => {
  if (!maxCount.value) return '0%';
  return `${Math.max((value / maxCount.value) * 100, 2)}%`;
};

const rateHeight = rate => {
  if (rate === null || rate === undefined) return '0%';
  return `${Math.max(rate * 100, 2)}%`;
};

const percent = rate =>
  rate === null || rate === undefined ? '—' : `${(rate * 100).toFixed(0)}%`;

const bucketLabel = bucket => {
  if (props.trend?.granularity === 'week') {
    return `${bucket.start_date} → ${bucket.end_date}`;
  }
  return bucket.start_date;
};

const tooltip = bucket => {
  const comparison = bucket.comparison || {};
  const comparisonRate =
    comparison.resolution_rate === null ||
    comparison.resolution_rate === undefined
      ? '—'
      : `${(comparison.resolution_rate * 100).toFixed(0)}%`;
  return `${bucketLabel(bucket)} · ${bucket.involved} involved · ${bucket.autonomous} autonomous · rate ${percent(bucket.resolution_rate)} · previously ${comparisonRate}`;
};
</script>

<template>
  <section
    class="flex flex-col gap-4 rounded-xl border border-n-weak bg-n-solid-2 p-4"
  >
    <div class="flex items-center justify-between">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ $t('PILOT.OVERVIEW.TREND.TITLE') }}
      </h3>
      <div class="flex gap-1 rounded-lg bg-n-alpha-1 p-0.5 text-xs">
        <button
          type="button"
          class="rounded-md px-2 py-1"
          :class="
            measure === 'counts'
              ? 'bg-n-solid-2 text-n-slate-12 shadow-sm'
              : 'text-n-slate-10'
          "
          @click="measure = 'counts'"
        >
          {{ $t('PILOT.OVERVIEW.TREND.MEASURE_COUNTS') }}
        </button>
        <button
          type="button"
          class="rounded-md px-2 py-1"
          :class="
            measure === 'rate'
              ? 'bg-n-solid-2 text-n-slate-12 shadow-sm'
              : 'text-n-slate-10'
          "
          @click="measure = 'rate'"
        >
          {{ $t('PILOT.OVERVIEW.TREND.MEASURE_RATE') }}
        </button>
      </div>
    </div>

    <p v-if="isEmpty" class="py-6 text-center text-sm text-n-slate-10">
      {{ $t('PILOT.OVERVIEW.TREND.EMPTY') }}
    </p>

    <template v-else>
      <div class="flex h-40 items-end gap-1">
        <div
          v-for="bucket in trend.buckets"
          :key="bucket.start_date"
          v-tooltip.top="tooltip(bucket)"
          class="flex min-w-0 flex-1 items-end justify-center gap-0.5"
        >
          <template v-if="measure === 'counts'">
            <div
              class="w-1/2 rounded-t bg-n-alpha-3"
              :style="{ height: barHeight(bucket.involved) }"
            />
            <div
              class="w-1/2 rounded-t bg-n-brand"
              :style="{ height: barHeight(bucket.autonomous) }"
            />
          </template>
          <div
            v-else
            class="w-3/4 rounded-t"
            :class="
              bucket.resolution_rate === null ? 'bg-n-alpha-1' : 'bg-n-brand'
            "
            :style="{ height: rateHeight(bucket.resolution_rate) }"
          />
        </div>
      </div>

      <div class="flex gap-1 text-[10px] text-n-slate-10">
        <span
          v-for="bucket in trend.buckets"
          :key="bucket.start_date"
          class="min-w-0 flex-1 truncate text-center"
        >
          {{ bucket.start_date.slice(5) }}
        </span>
      </div>

      <div
        v-if="measure === 'counts'"
        class="flex items-center gap-4 text-xs text-n-slate-10"
      >
        <span class="flex items-center gap-1">
          <span class="size-2 rounded-sm bg-n-alpha-3" />
          {{ $t('PILOT.OVERVIEW.TREND.INVOLVED') }}
        </span>
        <span class="flex items-center gap-1">
          <span class="size-2 rounded-sm bg-n-brand" />
          {{ $t('PILOT.OVERVIEW.TREND.AUTONOMOUS') }}
        </span>
      </div>
    </template>
  </section>
</template>
