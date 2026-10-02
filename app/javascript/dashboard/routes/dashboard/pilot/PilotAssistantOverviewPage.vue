<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';

import PilotAssistantAnalyticsAPI from 'dashboard/api/pilot/assistantAnalytics';
import OverviewRangeSelector from 'dashboard/components-next/pilot/overview/OverviewRangeSelector.vue';
import OverviewMetricCard from 'dashboard/components-next/pilot/overview/OverviewMetricCard.vue';
import OverviewSummaryCard from 'dashboard/components-next/pilot/overview/OverviewSummaryCard.vue';
import ResolutionFlowPanel from 'dashboard/components-next/pilot/overview/ResolutionFlowPanel.vue';
import ResolutionTrendPanel from 'dashboard/components-next/pilot/overview/ResolutionTrendPanel.vue';
import CsatComparisonPanel from 'dashboard/components-next/pilot/overview/CsatComparisonPanel.vue';
import OverviewDrilldownDrawer from 'dashboard/components-next/pilot/overview/OverviewDrilldownDrawer.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const DRILLDOWN_METRICS = [
  'conversations_involved',
  'autonomous_resolution_rate',
  'handoff_rate',
  'reopen_after_resolution_rate',
];

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const { isAdmin } = useAdmin();

const assistants = useMapGetter('pilot/assistants/getRecords');
const currentUser = useMapGetter('getCurrentUser');

const range = ref('this_month');
const overview = ref(null);
const flow = ref(null);
const trend = ref(null);
const summaryPoints = ref([]);
const isLoading = ref(false);
const isSummaryLoading = ref(false);
const hasError = ref(false);
const hasSummaryError = ref(false);
const drilldownMetric = ref(null);

let reportController = null;
let summaryController = null;
let fetchToken = 0;

const assistantId = computed(() => route.params.assistantId);
const assistant = computed(
  () =>
    assistants.value.find(record => record.id === Number(assistantId.value)) ||
    null
);
const metrics = computed(() => overview.value?.metrics || {});

const metricCards = computed(() => [
  {
    key: 'conversations_involved',
    label: t('PILOT.OVERVIEW.METRICS.CONVERSATIONS_INVOLVED'),
    format: 'count',
    trendDirection: 'neutral',
  },
  {
    key: 'autonomous_resolutions',
    label: t('PILOT.OVERVIEW.METRICS.AUTONOMOUS_RESOLUTIONS'),
    format: 'count',
    trendDirection: 'higher-is-better',
  },
  {
    key: 'autonomous_resolution_rate',
    label: t('PILOT.OVERVIEW.METRICS.AUTONOMOUS_RESOLUTION_RATE'),
    format: 'rate',
    trendDirection: 'higher-is-better',
  },
  {
    key: 'handoffs',
    label: t('PILOT.OVERVIEW.METRICS.HANDOFFS'),
    format: 'count',
    trendDirection: 'neutral',
  },
  {
    key: 'handoff_rate',
    label: t('PILOT.OVERVIEW.METRICS.HANDOFF_RATE'),
    format: 'rate',
    trendDirection: 'lower-is-better',
  },
  {
    key: 'estimated_hours_saved',
    label: t('PILOT.OVERVIEW.METRICS.ESTIMATED_HOURS_SAVED'),
    format: 'hours',
    trendDirection: 'higher-is-better',
    estimateHint: t('PILOT.OVERVIEW.METRICS.ESTIMATED_HOURS_SAVED_HINT'),
  },
  {
    key: 'conversation_depth',
    label: t('PILOT.OVERVIEW.METRICS.CONVERSATION_DEPTH'),
    format: 'score',
    trendDirection: 'neutral',
  },
  {
    key: 'reopen_after_resolution_rate',
    label: t('PILOT.OVERVIEW.METRICS.REOPEN_RATE'),
    format: 'rate',
    trendDirection: 'lower-is-better',
  },
  {
    key: 'durable_resolution_rate',
    label: t('PILOT.OVERVIEW.METRICS.DURABLE_RESOLUTION_RATE'),
    format: 'rate',
    trendDirection: 'higher-is-better',
  },
  {
    key: 'median_resolution_seconds',
    label: t('PILOT.OVERVIEW.METRICS.MEDIAN_RESOLUTION_TIME'),
    format: 'duration',
    trendDirection: 'lower-is-better',
  },
]);

const csatScores = computed(() => [
  {
    label: t('PILOT.OVERVIEW.CSAT.AUTONOMOUS'),
    pack: metrics.value.autonomous_csat,
  },
  {
    label: t('PILOT.OVERVIEW.CSAT.ASSISTED'),
    pack: metrics.value.assisted_csat,
  },
  {
    label: t('PILOT.OVERVIEW.CSAT.HUMAN_ONLY'),
    pack: metrics.value.human_only_csat,
  },
]);

const drilldownMetricName = computed(() => {
  const card = metricCards.value.find(
    entry => entry.key === drilldownMetric.value
  );
  return card?.label || '';
});

const canDrilldown = key => isAdmin.value && DRILLDOWN_METRICS.includes(key);

const openDrilldown = key => {
  if (!canDrilldown(key)) return;
  drilldownMetric.value = key;
};

const closeDrilldown = () => {
  drilldownMetric.value = null;
};

const abortInFlight = () => {
  reportController?.abort();
  summaryController?.abort();
  reportController = null;
  summaryController = null;
};

const fetchReports = async () => {
  fetchToken += 1;
  const token = fetchToken;
  abortInFlight();
  reportController = new AbortController();
  isLoading.value = true;
  hasError.value = false;
  try {
    const [overviewResponse, flowResponse, trendResponse] = await Promise.all([
      PilotAssistantAnalyticsAPI.overview(assistantId.value, range.value, {
        signal: reportController.signal,
      }),
      PilotAssistantAnalyticsAPI.resolutionFlow(
        assistantId.value,
        range.value,
        {
          signal: reportController.signal,
        }
      ),
      PilotAssistantAnalyticsAPI.resolutionTrend(
        assistantId.value,
        range.value,
        {
          signal: reportController.signal,
        }
      ),
    ]);
    if (token !== fetchToken) return;
    overview.value = overviewResponse.data;
    flow.value = flowResponse.data;
    trend.value = trendResponse.data;
  } catch (error) {
    if (error?.code === 'ERR_CANCELED' || token !== fetchToken) return;
    hasError.value = true;
  } finally {
    if (token === fetchToken) isLoading.value = false;
  }
};

const fetchSummary = async () => {
  const token = fetchToken;
  summaryController = new AbortController();
  isSummaryLoading.value = true;
  hasSummaryError.value = false;
  try {
    const { data } = await PilotAssistantAnalyticsAPI.overviewSummary(
      assistantId.value,
      range.value,
      { signal: summaryController.signal }
    );
    if (token !== fetchToken) return;
    summaryPoints.value = data.points || [];
  } catch (error) {
    if (error?.code === 'ERR_CANCELED' || token !== fetchToken) return;
    summaryPoints.value = [];
    hasSummaryError.value = true;
  } finally {
    if (token === fetchToken) isSummaryLoading.value = false;
  }
};

const refetchAll = () => {
  fetchReports();
  fetchSummary();
};

watch([range, assistantId], refetchAll);

onMounted(async () => {
  if (!assistants.value.length) {
    try {
      await store.dispatch('pilot/assistants/fetch');
    } catch (_e) {
      // Handled via store/ui
    }
  }
  refetchAll();
});

onBeforeUnmount(abortInFlight);
</script>

<template>
  <section class="flex h-full w-full flex-col overflow-hidden bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6">
      <div class="mx-auto w-full max-w-6xl">
        <div class="flex h-20 w-full items-center justify-between gap-3">
          <div class="min-w-0">
            <h1 class="truncate text-heading-md font-medium text-n-slate-12">
              {{ t('PILOT.OVERVIEW.HEADER.TITLE') }}
            </h1>
            <p v-if="assistant" class="truncate text-sm text-n-slate-11">
              {{
                t('PILOT.OVERVIEW.HEADER.SUBTITLE', { name: assistant.name })
              }}
            </p>
          </div>
          <OverviewRangeSelector v-model="range" />
        </div>
      </div>
    </header>

    <main class="flex-1 overflow-y-auto px-6">
      <div class="mx-auto flex w-full max-w-6xl flex-col gap-4 py-2">
        <div v-if="isLoading" class="flex h-40 items-center justify-center">
          <Spinner />
        </div>

        <div
          v-else-if="hasError"
          class="flex items-center justify-between gap-3 rounded-lg border border-n-ruby-6 bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
          role="alert"
        >
          <span>{{ t('PILOT.OVERVIEW.ERROR.GENERIC') }}</span>
          <Button
            size="sm"
            color="ruby"
            variant="outline"
            :label="t('PILOT.OVERVIEW.ERROR.RETRY')"
            @click="refetchAll"
          />
        </div>

        <template v-if="overview">
          <OverviewSummaryCard
            :points="summaryPoints"
            :is-loading="isSummaryLoading"
            :has-error="hasSummaryError"
            :user-name="currentUser?.name || ''"
          />

          <div class="grid grid-cols-2 gap-3 xl:grid-cols-5">
            <OverviewMetricCard
              v-for="card in metricCards"
              :key="card.key"
              :label="card.label"
              :pack="metrics[card.key]"
              :format="card.format"
              :trend-direction="card.trendDirection"
              :estimate-hint="card.estimateHint || ''"
              :drilldown-enabled="canDrilldown(card.key)"
              @drilldown="openDrilldown(card.key)"
            />
          </div>

          <CsatComparisonPanel :scores="csatScores" />

          <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
            <ResolutionFlowPanel :flow="flow" />
            <ResolutionTrendPanel :trend="trend" />
          </div>
        </template>
      </div>
    </main>

    <OverviewDrilldownDrawer
      :open="drilldownMetric !== null"
      :assistant-id="assistantId"
      :metric="drilldownMetric || ''"
      :metric-name="drilldownMetricName"
      :range="range"
      @close="closeDrilldown"
    />
  </section>
</template>
