<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import PilotFaqsHeader from './PilotFaqsHeader.vue';
import FaqCardList from './FaqCardList.vue';
import FaqPagerFooter from './FaqPagerFooter.vue';
import CreateFaqDialog from './CreateFaqDialog.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import BulkSelectBar from 'dashboard/components-next/bulk-action/BulkSelectBar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const records = useMapGetter('pilot/faqs/getRecords');
const meta = useMapGetter('pilot/faqs/getMeta');
const uiFlags = useMapGetter('pilot/faqs/getUIFlags');
const lastError = useMapGetter('pilot/faqs/getLastError');
const assistants = useMapGetter('pilot/assistants/getRecords');
const assistantUiFlags = useMapGetter('pilot/assistants/getUIFlags');
const pendingCount = useMapGetter('pilot/faqs/getPendingCount');

const dialogRef = ref(null);
const dialogMode = ref('create');
const dialogInitial = ref(null);
const dialogServerError = ref('');

const activeAssistantId = ref(null);
const searchTerm = ref('');
const statusFilter = ref('');
const currentPage = ref(1);
const bulkSelectedIds = ref(new Set());

const isPendingRoute = computed(() => route.name === 'pilot_faqs_pending');

const tabs = computed(() => [
  {
    key: 'approved',
    label: t('PILOT.FAQS.STATUS.APPROVED'),
  },
  {
    key: 'pending',
    label: t('PILOT.FAQS.STATUS.PENDING'),
    count: pendingCount.value,
  },
]);

const activeTabIndex = computed(() => (isPendingRoute.value ? 1 : 0));

const onTabChanged = tab => {
  if (tab.key === 'pending') {
    router.push({ name: 'pilot_faqs_pending' });
  } else {
    router.push({ name: 'pilot_faqs' });
  }
};

const isLoading = computed(() => uiFlags.value.isFetching);
const isSubmitting = computed(
  () => uiFlags.value.isCreating || uiFlags.value.isUpdating
);
const hasError = computed(() => Boolean(lastError.value));

const totalCount = computed(() => meta.value.total_count || 0);
const totalPages = computed(() => meta.value.total_pages || 0);
const perPage = computed(() => meta.value.per_page || 25);

const readUrlState = () => {
  const q = route.query || {};
  const pageNum = Number(q.page) || 1;
  const assistantParam = q.assistantId ? Number(q.assistantId) : null;
  return {
    page: pageNum > 0 ? pageNum : 1,
    assistantId: Number.isFinite(assistantParam) ? assistantParam : null,
    search: typeof q.search === 'string' ? q.search : '',
    status: isPendingRoute.value ? 'pending' : 'approved',
  };
};

const syncUrl = () => {
  const next = { ...(route.query || {}) };
  if (currentPage.value > 1) next.page = String(currentPage.value);
  else delete next.page;
  if (activeAssistantId.value)
    next.assistantId = String(activeAssistantId.value);
  else delete next.assistantId;
  if (searchTerm.value) next.search = searchTerm.value;
  else delete next.search;

  router.replace({ query: next }).catch(() => {});
};

const fetchCurrent = async () => {
  if (!activeAssistantId.value) return;
  const currentStatus = isPendingRoute.value ? 'pending' : 'approved';
  store.dispatch('pilot/faqs/setAssistant', activeAssistantId.value);
  store.dispatch('pilot/faqs/setSearch', searchTerm.value);
  store.dispatch('pilot/faqs/setStatus', currentStatus);
  try {
    await store.dispatch('pilot/faqs/fetchPage', {
      assistantId: activeAssistantId.value,
      page: currentPage.value,
      search: searchTerm.value,
      status: currentStatus,
    });
    store.dispatch('pilot/faqs/fetchPendingCount', {
      assistantId: activeAssistantId.value,
    });
  } catch (_e) {
    // Error state surfaced via lastError getter.
  }
};

const pickDefaultAssistantId = () => {
  if (activeAssistantId.value) return;
  const first = assistants.value?.[0];
  if (first) activeAssistantId.value = first.id;
};

onMounted(async () => {
  const initial = readUrlState();
  currentPage.value = initial.page;
  activeAssistantId.value = initial.assistantId;
  searchTerm.value = initial.search;
  statusFilter.value = initial.status;

  if (!assistants.value?.length && !assistantUiFlags.value.isFetching) {
    try {
      await store.dispatch('pilot/assistants/fetch');
    } catch (_e) {
      // Surface via store error getters; UI handles missing assistants.
    }
  }
  pickDefaultAssistantId();
  syncUrl();
  await fetchCurrent();
});

watch(
  () => assistants.value?.length,
  () => {
    if (!activeAssistantId.value) {
      pickDefaultAssistantId();
      if (activeAssistantId.value) {
        syncUrl();
        fetchCurrent();
      }
    }
  }
);

watch(
  () => route.name,
  async () => {
    currentPage.value = 1;
    bulkSelectedIds.value = new Set();
    await fetchCurrent();
  }
);

const onAssistantChange = id => {
  if (id === activeAssistantId.value) return;
  activeAssistantId.value = id ?? null;
  currentPage.value = 1;
  syncUrl();
  fetchCurrent();
};

const onSearchChange = value => {
  if (value === searchTerm.value) return;
  searchTerm.value = value || '';
  currentPage.value = 1;
  syncUrl();
  fetchCurrent();
};

const onPageChange = page => {
  if (page === currentPage.value) return;
  currentPage.value = page;
  syncUrl();
  fetchCurrent();
};

const onRetry = () => {
  fetchCurrent();
};

const openCreate = () => {
  dialogMode.value = 'create';
  dialogInitial.value = null;
  dialogServerError.value = '';
  dialogRef.value?.open();
};

const openEdit = row => {
  dialogMode.value = 'edit';
  dialogInitial.value = {
    id: row.id,
    question: row.question,
    answer: row.answer,
  };
  dialogServerError.value = '';
  dialogRef.value?.open();
};

const extractServerMessage = err => {
  const data = err?.response?.data;
  if (!data) return t('PILOT.FAQS.ERROR.SAVE');
  if (typeof data === 'string') return data;
  if (data.error) return data.error;
  if (data.message) return data.message;
  if (Array.isArray(data.errors)) return data.errors.join(', ');
  return t('PILOT.FAQS.ERROR.SAVE');
};

const onDialogSubmit = async payload => {
  dialogServerError.value = '';
  try {
    if (dialogMode.value === 'edit' && dialogInitial.value?.id) {
      await store.dispatch('pilot/faqs/updateRow', {
        id: dialogInitial.value.id,
        question: payload.question,
        answer: payload.answer,
      });
    } else {
      await store.dispatch('pilot/faqs/createRow', {
        assistantId: activeAssistantId.value,
        question: payload.question,
        answer: payload.answer,
      });
      if (currentPage.value !== 1) {
        currentPage.value = 1;
        syncUrl();
        await fetchCurrent();
      }
    }
    dialogRef.value?.close();
  } catch (err) {
    dialogServerError.value = extractServerMessage(err);
  }
};

const onDelete = async row => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('PILOT.FAQS.CARD.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('pilot/faqs/destroyRow', row.id);
    if (records.value.length === 0 && currentPage.value > 1) {
      currentPage.value -= 1;
      syncUrl();
    }
    await fetchCurrent();
  } catch (_e) {
    // Surfaced via lastError getter.
  }
};

const onApprove = async row => {
  try {
    await store.dispatch('pilot/faqs/updateRow', {
      id: row.id,
      assistantId: activeAssistantId.value,
      status: 'approved',
    });
    useAlert('Response approved');
    await fetchCurrent();
  } catch (err) {
    useAlert(t('PILOT.FAQS.ERROR.SAVE'));
  }
};

const onSelectCard = (id, checked) => {
  const next = new Set(bulkSelectedIds.value);
  if (checked) {
    next.add(id);
  } else {
    next.delete(id);
  }
  bulkSelectedIds.value = next;
};

const onUpdateBulkSelection = nextSet => {
  bulkSelectedIds.value = nextSet;
};

const handleBulkApprove = async () => {
  if (bulkSelectedIds.value.size === 0) return;
  try {
    await store.dispatch(
      'pilot/faqs/bulkApprove',
      Array.from(bulkSelectedIds.value)
    );
    useAlert('Responses approved');
    bulkSelectedIds.value = new Set();
    await fetchCurrent();
  } catch (err) {
    useAlert('Failed to bulk approve');
  }
};

const handleBulkDelete = async () => {
  if (bulkSelectedIds.value.size === 0) return;
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('PILOT.FAQS.CARD.DELETE_CONFIRM'))) return;
  try {
    await Promise.all(
      Array.from(bulkSelectedIds.value).map(id =>
        store.dispatch('pilot/faqs/destroyRow', id)
      )
    );
    useAlert('Responses deleted');
    bulkSelectedIds.value = new Set();
    await fetchCurrent();
  } catch (err) {
    useAlert('Failed to delete responses');
  }
};

const navigateToApproved = () => {
  router.push({ name: 'pilot_faqs' });
};
</script>

<template>
  <section
    class="flex flex-col flex-1 min-h-0 gap-4 p-6 overflow-y-auto w-full max-w-5xl mx-auto"
  >
    <!-- Discovery Blue Banner on Approved Route -->
    <Banner
      v-if="!isPendingRoute && pendingCount > 0"
      color="blue"
      :action-label="t('PILOT.FAQS.PENDING_BANNER_ACTION')"
      @action="router.push({ name: 'pilot_faqs_pending' })"
    >
      {{ t('PILOT.FAQS.PENDING_BANNER') }}
    </Banner>

    <PilotFaqsHeader
      :assistant-id="activeAssistantId"
      :search="searchTerm"
      :is-pending="isPendingRoute"
      @update:assistant-id="onAssistantChange"
      @update:search="onSearchChange"
      @create="openCreate"
      @back="navigateToApproved"
    />

    <!-- Navigation Tabs for Approved vs Unapproved (Pending) -->
    <TabBar
      :tabs="tabs"
      :initial-active-tab="activeTabIndex"
      class="self-start mb-2"
      @tab-changed="onTabChanged"
    />

    <!-- Sticky Bulk Selection Bar in Pending Route -->
    <BulkSelectBar
      v-if="isPendingRoute && records.length > 0 && !isLoading"
      :model-value="bulkSelectedIds"
      :all-items="records"
      select-all-label="Select all FAQs"
      :selected-count-label="`${bulkSelectedIds.size} FAQs selected`"
      class="mb-2"
      @update:model-value="onUpdateBulkSelection"
    >
      <template #secondaryActions>
        <Button
          label="Approve selected"
          icon="i-lucide-check"
          variant="ghost"
          color="blue"
          :disabled="bulkSelectedIds.size === 0"
          @click="handleBulkApprove"
        />
      </template>
      <template #actions>
        <Button
          label="Delete selected"
          icon="i-lucide-trash"
          variant="faded"
          color="ruby"
          :disabled="bulkSelectedIds.size === 0"
          @click="handleBulkDelete"
        />
      </template>
    </BulkSelectBar>

    <FaqCardList
      :rows="records"
      :is-loading="isLoading"
      :has-error="hasError"
      :show-menu="!isPendingRoute"
      :show-actions="isPendingRoute"
      :selectable="isPendingRoute"
      :selected-ids="bulkSelectedIds"
      @edit="openEdit"
      @delete="onDelete"
      @approve="onApprove"
      @select="onSelectCard"
      @retry="onRetry"
      @create="openCreate"
    />

    <FaqPagerFooter
      v-if="!isLoading && !hasError && totalCount > 0"
      :page="currentPage"
      :per-page="perPage"
      :total-count="totalCount"
      :total-pages="totalPages"
      @update:page="onPageChange"
    />

    <CreateFaqDialog
      ref="dialogRef"
      :mode="dialogMode"
      :initial="dialogInitial"
      :is-submitting="isSubmitting"
      :server-error="dialogServerError"
      @submit="onDialogSubmit"
    />
  </section>
</template>
