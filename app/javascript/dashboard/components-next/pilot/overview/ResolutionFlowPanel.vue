<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  flow: {
    type: Object,
    default: () => ({ nodes: [], links: [], handoff_reasons: [] }),
  },
});

const { t } = useI18n();

const NODE_LABEL_KEYS = {
  involved: 'PILOT.OVERVIEW.FLOW.INVOLVED',
  autonomous: 'PILOT.OVERVIEW.FLOW.AUTONOMOUS',
  handed_off: 'PILOT.OVERVIEW.FLOW.HANDED_OFF',
  closed_with_team: 'PILOT.OVERVIEW.FLOW.CLOSED_WITH_TEAM',
  stayed_closed: 'PILOT.OVERVIEW.FLOW.STAYED_CLOSED',
  reopened: 'PILOT.OVERVIEW.FLOW.REOPENED',
  other_reasons: 'PILOT.OVERVIEW.FLOW.OTHER_REASONS',
};

const REASON_LABEL_KEYS = {
  customer_escalation: 'PILOT.OVERVIEW.FLOW.REASON_CUSTOMER_ESCALATION',
  knowledge_gap: 'PILOT.OVERVIEW.FLOW.REASON_KNOWLEDGE_GAP',
  policy_refusal: 'PILOT.OVERVIEW.FLOW.REASON_POLICY_REFUSAL',
  system_failure: 'PILOT.OVERVIEW.FLOW.REASON_SYSTEM_FAILURE',
  quota_exhausted: 'PILOT.OVERVIEW.FLOW.REASON_QUOTA_EXHAUSTED',
  other: 'PILOT.OVERVIEW.FLOW.REASON_OTHER',
  uncategorized: 'PILOT.OVERVIEW.FLOW.UNCATEGORIZED',
};

const isEmpty = computed(() => !props.flow?.nodes?.length);

const involvedTotal = computed(
  () => props.flow?.nodes?.find(node => node.id === 'involved')?.value || 0
);

const nodeValue = id =>
  props.flow?.nodes?.find(node => node.id === id)?.value || 0;

const nodeLabel = id => {
  if (NODE_LABEL_KEYS[id]) return t(NODE_LABEL_KEYS[id]);
  if (id.startsWith('reason_')) {
    const category = id.replace('reason_', '');
    return REASON_LABEL_KEYS[category]
      ? t(REASON_LABEL_KEYS[category])
      : category;
  }
  return id;
};

const branchWidth = value => {
  if (!involvedTotal.value) return '0%';
  return `${Math.max((value / involvedTotal.value) * 100, 2)}%`;
};

const firstLevel = computed(() =>
  ['autonomous', 'handed_off', 'closed_with_team'].map(id => ({
    id,
    value: nodeValue(id),
  }))
);

const secondLevel = computed(() => {
  const list = [
    {
      id: 'stayed_closed',
      value: nodeValue('stayed_closed'),
      parent: 'autonomous',
    },
    { id: 'reopened', value: nodeValue('reopened'), parent: 'autonomous' },
  ];
  (props.flow?.links || [])
    .filter(link => link.source === 'handed_off')
    .forEach(link =>
      list.push({ id: link.target, value: link.value, parent: 'handed_off' })
    );
  return list;
});

const reasonLabel = category =>
  REASON_LABEL_KEYS[category] ? t(REASON_LABEL_KEYS[category]) : category;
</script>

<template>
  <section
    class="flex flex-col gap-4 rounded-xl border border-n-weak bg-n-solid-2 p-4"
  >
    <h3 class="text-sm font-medium text-n-slate-12">
      {{ $t('PILOT.OVERVIEW.FLOW.TITLE') }}
    </h3>

    <p v-if="isEmpty" class="py-6 text-center text-sm text-n-slate-10">
      {{ $t('PILOT.OVERVIEW.FLOW.EMPTY') }}
    </p>

    <template v-else>
      <div class="flex flex-col gap-3">
        <div class="flex flex-col gap-1">
          <div class="flex justify-between text-sm">
            <span class="text-n-slate-12">{{ nodeLabel('involved') }}</span>
            <span class="font-medium text-n-slate-12">{{ involvedTotal }}</span>
          </div>
          <div class="h-2 w-full rounded bg-n-brand" />
        </div>

        <div
          v-for="branch in firstLevel"
          :key="branch.id"
          class="ms-4 flex flex-col gap-1"
        >
          <div class="flex justify-between text-sm">
            <span class="text-n-slate-11">{{ nodeLabel(branch.id) }}</span>
            <span class="text-n-slate-12">{{ branch.value }}</span>
          </div>
          <div
            class="h-2 rounded bg-n-alpha-3"
            :style="{ width: branchWidth(branch.value) }"
          />

          <div
            v-for="child in secondLevel.filter(
              entry => entry.parent === branch.id
            )"
            :key="child.id"
            class="ms-4 flex justify-between text-xs text-n-slate-10"
          >
            <span>{{ nodeLabel(child.id) }}</span>
            <span>{{ child.value }}</span>
          </div>
        </div>
      </div>

      <div v-if="flow.handoff_reasons?.length" class="flex flex-col gap-2">
        <h4 class="text-xs font-medium uppercase tracking-wide text-n-slate-10">
          {{ $t('PILOT.OVERVIEW.FLOW.REASONS_TITLE') }}
        </h4>
        <div
          v-for="reason in flow.handoff_reasons"
          :key="reason.category"
          class="flex items-center gap-2 text-sm"
        >
          <span class="w-40 truncate text-n-slate-11">
            {{ reasonLabel(reason.category) }}
          </span>
          <div class="h-2 flex-1 rounded bg-n-alpha-1">
            <div
              class="h-2 rounded bg-n-brand"
              :style="{ width: `${reason.percentage}%` }"
            />
          </div>
          <span class="w-16 text-end text-xs text-n-slate-10">
            {{ reason.count }} · {{ reason.percentage }}%
          </span>
        </div>
      </div>
    </template>
  </section>
</template>
