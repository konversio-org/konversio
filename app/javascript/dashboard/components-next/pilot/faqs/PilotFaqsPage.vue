<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import PilotFaqsHeader from './PilotFaqsHeader.vue';
import FaqCardList from './FaqCardList.vue';
import FaqPagerFooter from './FaqPagerFooter.vue';
import CreateFaqDialog from './CreateFaqDialog.vue';

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

const dialogRef = ref(null);
const dialogMode = ref('create');
const dialogInitial = ref(null);
const dialogServerError = ref('');

const activeAssistantId = ref(null);
const searchTerm = ref('');
const statusFilter = ref('');
const currentPage = ref(1);

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
    status: typeof q.status === 'string' ? q.status : '',
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
  if (statusFilter.value) next.status = statusFilter.value;
  else delete next.status;

  router.replace({ query: next }).catch(() => {});
};

const fetchCurrent = async () => {
  if (!activeAssistantId.value) return;
  store.dispatch('pilot/faqs/setAssistant', activeAssistantId.value);
  store.dispatch('pilot/faqs/setSearch', searchTerm.value);
  store.dispatch('pilot/faqs/setStatus', statusFilter.value);
  try {
    await store.dispatch('pilot/faqs/fetchPage', {
      assistantId: activeAssistantId.value,
      page: currentPage.value,
      search: searchTerm.value,
      status: statusFilter.value,
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
    // If we just emptied the page and we're past page 1, drop back.
    if (records.value.length === 0 && currentPage.value > 1) {
      currentPage.value -= 1;
      syncUrl();
    }
    await fetchCurrent();
  } catch (_e) {
    // Surfaced via lastError getter; no inline UI for delete errors yet.
  }
};
</script>

<template>
  <section class="flex flex-col flex-1 min-h-0 gap-4 p-6 overflow-y-auto">
    <PilotFaqsHeader
      :assistant-id="activeAssistantId"
      :search="searchTerm"
      @update:assistant-id="onAssistantChange"
      @update:search="onSearchChange"
      @create="openCreate"
    />

    <FaqCardList
      :rows="records"
      :is-loading="isLoading"
      :has-error="hasError"
      @edit="openEdit"
      @delete="onDelete"
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
