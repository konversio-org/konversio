<script setup>
const RANGES = [
  { value: '7', labelKey: 'PILOT.OVERVIEW.RANGE.LAST_7_DAYS' },
  { value: '30', labelKey: 'PILOT.OVERVIEW.RANGE.LAST_30_DAYS' },
  { value: '90', labelKey: 'PILOT.OVERVIEW.RANGE.LAST_90_DAYS' },
  { value: 'this_week', labelKey: 'PILOT.OVERVIEW.RANGE.THIS_WEEK' },
  { value: 'last_week', labelKey: 'PILOT.OVERVIEW.RANGE.LAST_WEEK' },
  { value: 'this_month', labelKey: 'PILOT.OVERVIEW.RANGE.THIS_MONTH' },
  { value: 'last_month', labelKey: 'PILOT.OVERVIEW.RANGE.LAST_MONTH' },
];

const model = defineModel({ type: String, default: 'this_month' });
</script>

<template>
  <label class="flex items-center gap-2 text-sm text-n-slate-11">
    <span>{{ $t('PILOT.OVERVIEW.RANGE.LABEL') }}</span>
    <select
      v-model="model"
      class="h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
    >
      <option v-for="range in RANGES" :key="range.value" :value="range.value">
        {{ $t(range.labelKey) }}
      </option>
    </select>
  </label>
</template>
