<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import AssistantPicker from 'dashboard/components-next/pilot/shared/AssistantPicker.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import DocumentList from './DocumentList.vue';
import AddDocumentDialog from './AddDocumentDialog.vue';
import DocumentsPagerFooter from './DocumentsPagerFooter.vue';

const { t } = useI18n();
const store = useStore();

const records = useMapGetter('pilot/documents/getRecords');
const meta = useMapGetter('pilot/documents/getMeta');
const uiFlags = useMapGetter('pilot/documents/getUIFlags');
const lastError = useMapGetter('pilot/documents/getLastError');
const activeAssistantId = useMapGetter('pilot/assistants/getActiveId');
const assistants = useMapGetter('pilot/assistants/getRecords');

const STATUS_FILTERS = [
  { value: null, key: 'ALL' },
  { value: 'available', key: 'AVAILABLE' },
  { value: 'in_progress', key: 'IN_PROGRESS' },
  { value: 'failed', key: 'FAILED' },
];

const selectedAssistantId = ref(activeAssistantId.value);
const selectedStatus = ref(null);
const addDialogRef = ref(null);

const isLoading = computed(() => uiFlags.value.isFetching);

const errorMessage = computed(() => {
  const err = lastError.value;
  if (!err) return '';
  return (
    err?.response?.data?.message ||
    err?.response?.data?.error ||
    err?.message ||
    t('PILOT_DOCUMENTS.ERROR.GENERIC')
  );
});

const fetchDocuments = (page = 1) => {
  store.dispatch('pilot/documents/setAssistant', selectedAssistantId.value);
  store.dispatch('pilot/documents/setStatus', selectedStatus.value);
  return store
    .dispatch('pilot/documents/fetch', {
      assistantId: selectedAssistantId.value,
      status: selectedStatus.value,
      page,
    })
    .catch(() => {});
};

onMounted(async () => {
  if (!assistants.value.length) {
    try {
      await store.dispatch('pilot/assistants/fetch');
    } catch (_e) {
      // surfaced via error banner
    }
  }
  if (!selectedAssistantId.value && assistants.value.length) {
    selectedAssistantId.value = assistants.value[0].id;
  }
  fetchDocuments(1);
});

watch(selectedAssistantId, () => fetchDocuments(1));
watch(selectedStatus, () => fetchDocuments(1));

const onAdd = () => addDialogRef.value?.open();

const onDocumentCreated = async () => {
  useAlert(t('PILOT_DOCUMENTS.TOAST.CREATED'));
  await fetchDocuments(1);
};

const onDelete = async id => {
  try {
    await store.dispatch('pilot/documents/delete', id);
    useAlert(t('PILOT_DOCUMENTS.TOAST.DELETED'));
    if (records.value.length === 0 && meta.value.current_page > 1) {
      fetchDocuments(meta.value.current_page - 1);
    }
  } catch (_e) {
    useAlert(t('PILOT_DOCUMENTS.TOAST.DELETE_FAILED'));
  }
};

const onPageChange = page => fetchDocuments(page);

const onStatusChange = value => {
  selectedStatus.value = value;
};

const isStatusActive = value => selectedStatus.value === value;
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6">
      <div class="w-full max-w-5xl mx-auto">
        <div
          class="flex items-center justify-between w-full h-20 gap-3 flex-wrap"
        >
          <div class="flex items-center gap-4 min-w-0">
            <h1 class="text-heading-1 text-n-slate-12 truncate">
              {{ t('PILOT_DOCUMENTS.HEADER.TITLE') }}
            </h1>
            <div class="min-w-[12rem] max-w-xs">
              <AssistantPicker v-model="selectedAssistantId" />
            </div>
          </div>
          <Button
            :label="t('PILOT_DOCUMENTS.HEADER.ADD_BUTTON')"
            icon="i-lucide-plus"
            size="sm"
            @click="onAdd"
          />
        </div>
        <nav
          :aria-label="t('PILOT_DOCUMENTS.STATUS_FILTER.ARIA')"
          class="flex items-center gap-2 pb-3 flex-wrap"
        >
          <button
            v-for="filter in STATUS_FILTERS"
            :key="filter.key"
            type="button"
            class="text-xs font-medium inline-flex items-center h-7 px-3 rounded-full border transition-colors"
            :class="
              isStatusActive(filter.value)
                ? 'bg-n-slate-12 text-n-solid-1 border-n-slate-12'
                : 'bg-n-solid-2 text-n-slate-11 border-n-container hover:bg-n-alpha-1'
            "
            @click="onStatusChange(filter.value)"
          >
            {{ t(`PILOT_DOCUMENTS.STATUS_FILTER.${filter.key}`) }}
          </button>
        </nav>
      </div>
    </header>
    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full max-w-5xl mx-auto py-2 flex flex-col gap-3">
        <div
          v-if="errorMessage && !isLoading"
          class="flex items-start justify-between gap-3 p-3 rounded-lg bg-n-ruby-3 border border-n-ruby-6 text-sm text-n-ruby-11"
          role="alert"
        >
          <span class="flex-1">{{ errorMessage }}</span>
          <button
            type="button"
            class="text-xs font-medium underline hover:text-n-ruby-12"
            @click="fetchDocuments(meta.current_page || 1)"
          >
            {{ t('PILOT_DOCUMENTS.ERROR.RETRY') }}
          </button>
        </div>

        <DocumentList
          :documents="records"
          :is-loading="isLoading"
          :has-error="!!errorMessage"
          @delete="onDelete"
          @add="onAdd"
        />

        <DocumentsPagerFooter
          v-if="meta.total_count > 0"
          :current-page="meta.current_page"
          :total-pages="meta.total_pages"
          :total-count="meta.total_count"
          :page-size="records.length"
          @update:page="onPageChange"
        />
      </div>
    </main>

    <AddDocumentDialog
      ref="addDialogRef"
      :assistant-id="selectedAssistantId"
      @created="onDocumentCreated"
    />
  </section>
</template>
