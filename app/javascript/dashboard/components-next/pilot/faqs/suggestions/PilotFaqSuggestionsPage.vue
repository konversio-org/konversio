<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import AssistantPicker from 'dashboard/components-next/pilot/shared/AssistantPicker.vue';
import FaqSearchInput from '../FaqSearchInput.vue';
import FaqPagerFooter from '../FaqPagerFooter.vue';
import SuggestionCard from './SuggestionCard.vue';
import SuggestionReviewDialog from './SuggestionReviewDialog.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const records = useMapGetter('pilot/faqSuggestions/getRecords');
const meta = useMapGetter('pilot/faqSuggestions/getMeta');
const uiFlags = useMapGetter('pilot/faqSuggestions/getUIFlags');
const lastError = useMapGetter('pilot/faqSuggestions/getLastError');
const assistants = useMapGetter('pilot/assistants/getRecords');
const assistantUiFlags = useMapGetter('pilot/assistants/getUIFlags');

const activeAssistantId = ref(null);
const searchTerm = ref('');
const currentPage = ref(1);

const dialogRef = ref(null);
const dialogSuggestion = ref(null);

const isLoading = computed(() => uiFlags.value.isFetching);
const isSubmitting = computed(() => uiFlags.value.isUpdating);
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
  store.dispatch('pilot/faqSuggestions/setAssistant', activeAssistantId.value);
  store.dispatch('pilot/faqSuggestions/setSearch', searchTerm.value);
  try {
    await store.dispatch('pilot/faqSuggestions/fetchPage', {
      assistantId: activeAssistantId.value,
      page: currentPage.value,
      search: searchTerm.value,
      status: 'open',
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

const refreshAfterRemoval = async () => {
  if (records.value.length === 0 && currentPage.value > 1) {
    currentPage.value -= 1;
    syncUrl();
  }
  await fetchCurrent();
};

const onQuickApprove = async row => {
  try {
    await store.dispatch('pilot/faqSuggestions/approve', { id: row.id });
    useAlert(t('PILOT.FAQ_SUGGESTIONS.SUCCESS.APPROVED'));
    await refreshAfterRemoval();
  } catch (_e) {
    useAlert(t('PILOT.FAQ_SUGGESTIONS.ERROR.APPROVE'));
  }
};

const onDismiss = async row => {
  try {
    await store.dispatch('pilot/faqSuggestions/dismiss', { id: row.id });
    useAlert(t('PILOT.FAQ_SUGGESTIONS.SUCCESS.DISMISSED'));
    await refreshAfterRemoval();
  } catch (_e) {
    useAlert(t('PILOT.FAQ_SUGGESTIONS.ERROR.DISMISS'));
  }
};

const openReview = row => {
  dialogSuggestion.value = row;
  dialogRef.value?.open();
};

const onDialogSave = async ({ id, question, answer }) => {
  try {
    await store.dispatch('pilot/faqSuggestions/saveRow', {
      id,
      question,
      answer,
    });
    useAlert(t('PILOT.FAQ_SUGGESTIONS.SUCCESS.SAVED'));
    dialogRef.value?.close();
  } catch (_e) {
    useAlert(t('PILOT.FAQ_SUGGESTIONS.ERROR.SAVE'));
  }
};

const onDialogApprove = async ({ id, question, answer }) => {
  try {
    await store.dispatch('pilot/faqSuggestions/approve', {
      id,
      question,
      answer,
    });
    useAlert(t('PILOT.FAQ_SUGGESTIONS.SUCCESS.APPROVED'));
    dialogRef.value?.close();
    await refreshAfterRemoval();
  } catch (_e) {
    useAlert(t('PILOT.FAQ_SUGGESTIONS.ERROR.APPROVE'));
  }
};

const onDialogDismiss = async ({ id }) => {
  try {
    await store.dispatch('pilot/faqSuggestions/dismiss', { id });
    useAlert(t('PILOT.FAQ_SUGGESTIONS.SUCCESS.DISMISSED'));
    dialogRef.value?.close();
    await refreshAfterRemoval();
  } catch (_e) {
    useAlert(t('PILOT.FAQ_SUGGESTIONS.ERROR.DISMISS'));
  }
};

const goBack = () => {
  router.push({ name: 'pilot_faqs' });
};
</script>

<template>
  <section
    class="flex flex-col flex-1 min-h-0 gap-4 p-6 overflow-y-auto w-full max-w-5xl mx-auto"
  >
    <header
      class="flex flex-row flex-wrap items-center justify-between gap-4 pb-4 border-b border-n-weak"
    >
      <div class="flex flex-wrap items-center gap-x-3 gap-y-2 min-w-0">
        <Button
          icon="i-lucide-arrow-left"
          variant="ghost"
          color="slate"
          class="flex-shrink-0 !p-1.5"
          @click="goBack"
        />
        <div class="min-w-48 max-w-64">
          <AssistantPicker
            :model-value="activeAssistantId"
            @update:model-value="onAssistantChange"
          />
        </div>
        <span aria-hidden="true" class="h-5 w-px bg-n-weak" />
        <h1 class="text-heading-md font-medium text-n-slate-12">
          {{ t('PILOT.FAQ_SUGGESTIONS.PAGE_TITLE') }}
        </h1>
      </div>
      <div
        class="flex w-full flex-1 items-center justify-end gap-3 min-w-0 sm:w-auto"
      >
        <FaqSearchInput
          :model-value="searchTerm"
          class="min-w-0 flex-1 sm:max-w-xs"
          @update:search="onSearchChange"
        />
      </div>
    </header>

    <div
      v-if="isLoading"
      class="flex items-center justify-center py-12 text-n-slate-10"
    >
      <span
        aria-hidden="true"
        class="i-lucide-loader-circle size-6 animate-spin"
      />
    </div>

    <div v-else-if="hasError" class="flex flex-col items-center gap-3 py-12">
      <p class="m-0 text-sm text-n-slate-11">
        {{ t('PILOT.FAQ_SUGGESTIONS.ERROR.LOAD') }}
      </p>
      <Button
        :label="t('PILOT.FAQ_SUGGESTIONS.ERROR.RETRY')"
        variant="faded"
        color="slate"
        @click="fetchCurrent"
      />
    </div>

    <div
      v-else-if="records.length === 0"
      class="flex flex-col items-center gap-2 py-12"
    >
      <h2 class="m-0 text-heading-2 text-n-slate-12">
        {{ t('PILOT.FAQ_SUGGESTIONS.EMPTY_TITLE') }}
      </h2>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t('PILOT.FAQ_SUGGESTIONS.EMPTY_BODY') }}
      </p>
    </div>

    <div v-else class="flex flex-col gap-3">
      <SuggestionCard
        v-for="row in records"
        :key="row.id"
        :row="row"
        @review="openReview"
        @approve="onQuickApprove"
        @dismiss="onDismiss"
      />
    </div>

    <FaqPagerFooter
      v-if="!isLoading && !hasError && totalCount > 0"
      :page="currentPage"
      :per-page="perPage"
      :total-count="totalCount"
      :total-pages="totalPages"
      @update:page="onPageChange"
    />

    <SuggestionReviewDialog
      ref="dialogRef"
      :suggestion="dialogSuggestion"
      :is-submitting="isSubmitting"
      @save="onDialogSave"
      @approve="onDialogApprove"
      @dismiss="onDialogDismiss"
    />
  </section>
</template>
