<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  label: { type: String, required: true },
  pack: {
    type: Object,
    default: () => ({ current: null, previous: null, trend: null }),
  },
  // count | rate | duration | score | hours
  format: { type: String, default: 'count' },
  // higher-is-better | lower-is-better | neutral
  trendDirection: { type: String, default: 'neutral' },
  estimateHint: { type: String, default: '' },
  drilldownEnabled: { type: Boolean, default: false },
});

const emit = defineEmits(['drilldown']);

const { t } = useI18n();

const hasValue = computed(
  () => props.pack?.current !== null && props.pack?.current !== undefined
);

const formatValue = value => {
  if (value === null || value === undefined) return '';
  switch (props.format) {
    case 'rate':
      return `${(value * 100).toFixed(1)}%`;
    case 'duration':
      return formatTime(value) || `${value}s`;
    case 'hours':
      return `${value}h`;
    case 'score':
      return value.toFixed(2);
    default:
      return `${value}`;
  }
};

const currentDisplay = computed(() => formatValue(props.pack?.current));
const previousDisplay = computed(() =>
  props.pack?.previous === null || props.pack?.previous === undefined
    ? ''
    : t('PILOT.OVERVIEW.METRICS.VS_PREVIOUS', {
        value: formatValue(props.pack.previous),
      })
);

const trendIcon = computed(() => {
  const trend = props.pack?.trend;
  if (trend === null || trend === undefined || trend === 0) return null;
  return trend > 0 ? 'i-lucide-arrow-up-right' : 'i-lucide-arrow-down-right';
});

const trendDisplay = computed(() => {
  const trend = props.pack?.trend;
  if (trend === null || trend === undefined) return '';
  const sign = trend > 0 ? '+' : '';
  if (props.format === 'rate') return `${sign}${(trend * 100).toFixed(1)} pt`;
  if (props.format === 'duration')
    return `${sign}${formatTime(Math.abs(trend)) || `${Math.abs(trend)}s`}`;
  return `${sign}${trend}`;
});

const trendTone = computed(() => {
  const trend = props.pack?.trend;
  if (!trend || props.trendDirection === 'neutral') return 'text-n-slate-10';
  const favorable =
    props.trendDirection === 'higher-is-better' ? trend > 0 : trend < 0;
  return favorable ? 'text-n-teal-11' : 'text-n-ruby-11';
});

const onActivate = () => {
  if (props.drilldownEnabled) emit('drilldown');
};
</script>

<template>
  <article
    class="flex flex-col gap-1 rounded-xl border border-n-weak bg-n-solid-2 p-4"
    :class="{
      'cursor-pointer hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand':
        drilldownEnabled,
    }"
    :role="drilldownEnabled ? 'button' : undefined"
    :tabindex="drilldownEnabled ? 0 : undefined"
    @click="onActivate"
    @keydown.enter.self.prevent="onActivate"
    @keydown.space.self.prevent="onActivate"
  >
    <div class="flex items-center gap-1 text-sm text-n-slate-11">
      <span class="truncate">{{ label }}</span>
      <span
        v-if="estimateHint"
        v-tooltip.top="estimateHint"
        :aria-label="estimateHint"
        class="flex size-4 shrink-0 items-center justify-center text-n-slate-10"
      >
        <Icon icon="i-lucide-info" class="size-3.5" />
      </span>
      <Icon
        v-if="drilldownEnabled"
        icon="i-lucide-chevron-right"
        class="ms-auto size-4 shrink-0 text-n-slate-10"
      />
    </div>

    <template v-if="hasValue">
      <span class="text-2xl font-semibold text-n-slate-12">
        {{ currentDisplay }}
      </span>
      <span class="flex items-center gap-2 text-xs text-n-slate-10">
        <span v-if="previousDisplay">{{ previousDisplay }}</span>
        <span
          v-if="trendIcon"
          class="flex items-center gap-0.5"
          :class="trendTone"
        >
          <Icon :icon="trendIcon" class="size-3" />
          <span>{{ trendDisplay }}</span>
        </span>
      </span>
    </template>
    <template v-else>
      <span class="text-sm text-n-slate-10">
        {{ $t('PILOT.OVERVIEW.METRICS.INSUFFICIENT_HISTORY') }}
      </span>
    </template>
  </article>
</template>
