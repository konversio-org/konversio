<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import PilotAssistantAnalyticsAPI from 'dashboard/api/pilot/assistantAnalytics';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import ReportDrilldownCard from 'dashboard/routes/dashboard/settings/reports/components/ReportDrilldownCard.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  assistantId: { type: [String, Number], required: true },
  metric: { type: String, default: '' },
  metricName: { type: String, default: '' },
  range: { type: String, required: true },
});

const emit = defineEmits(['close']);

const panelRef = ref(null);
const records = ref([]);
const meta = ref(null);
const currentPage = ref(1);
const isFetching = ref(false);
const isFetchingMore = ref(false);
const hasError = ref(false);

let requestToken = 0;

const hasRecords = computed(() => records.value.length > 0);
const hasMore = computed(
  () =>
    meta.value &&
    records.value.length < (meta.value.total_count || 0) &&
    records.value.length > 0
);

const recordKey = record =>
  `${record.record_type}-${record.conversation?.id}-${record.occurred_at}`;

const fetchPage = async page => {
  requestToken += 1;
  const token = requestToken;
  if (page === 1) {
    isFetching.value = true;
  } else {
    isFetchingMore.value = true;
  }
  hasError.value = false;
  try {
    const { data } = await PilotAssistantAnalyticsAPI.drilldown(
      props.assistantId,
      { metric: props.metric, range: props.range, page },
      {}
    );
    if (token !== requestToken) return;
    records.value =
      page === 1 ? data.payload : [...records.value, ...data.payload];
    meta.value = data.meta;
    currentPage.value = data.meta?.current_page || page;
  } catch (_error) {
    if (token !== requestToken) return;
    hasError.value = true;
  } finally {
    if (token === requestToken) {
      isFetching.value = false;
      isFetchingMore.value = false;
    }
  }
};

const loadMore = () => fetchPage(currentPage.value + 1);

onMounted(() => {
  if (props.open) {
    panelRef.value?.open();
    fetchPage(1);
  }
});

watch(
  () => props.open,
  isOpen => {
    if (!isOpen) {
      panelRef.value?.close();
      return;
    }
    panelRef.value?.open();
    records.value = [];
    meta.value = null;
    fetchPage(1);
  }
);

watch(
  () => [props.metric, props.range, props.assistantId],
  () => {
    if (!props.open) return;
    records.value = [];
    meta.value = null;
    fetchPage(1);
  }
);
</script>

<template>
  <SidePanel
    ref="panelRef"
    :title="metricName"
    width="xl"
    @close="emit('close')"
  >
    <div v-if="isFetching" class="flex h-40 items-center justify-center">
      <Spinner />
    </div>

    <div
      v-else-if="hasError"
      class="flex h-40 items-center justify-center text-sm text-n-ruby-11"
    >
      {{ $t('PILOT.OVERVIEW.DRILLDOWN.ERROR') }}
    </div>

    <div
      v-else-if="!hasRecords"
      class="flex h-40 items-center justify-center text-sm text-n-slate-10"
    >
      {{ $t('PILOT.OVERVIEW.DRILLDOWN.EMPTY') }}
    </div>

    <div v-else class="flex flex-col gap-2">
      <ReportDrilldownCard
        v-for="record in records"
        :key="recordKey(record)"
        :record="record"
      />

      <Button
        v-if="hasMore"
        faded
        slate
        size="sm"
        class="mx-auto mt-2"
        :label="$t('PILOT.OVERVIEW.DRILLDOWN.LOAD_MORE')"
        :is-loading="isFetchingMore"
        @click="loadMore"
      />
    </div>
  </SidePanel>
</template>
