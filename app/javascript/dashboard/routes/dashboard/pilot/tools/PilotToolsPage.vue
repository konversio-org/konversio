<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';

import PilotToolsHeader from 'dashboard/components-next/pilot/tools/PilotToolsHeader.vue';
import ToolCardList from 'dashboard/components-next/pilot/tools/ToolCardList.vue';
import PilotPagerFooter from 'dashboard/components-next/pilot/tools/PilotPagerFooter.vue';
import ToolEditDialog from 'dashboard/components-next/pilot/tools/ToolEditDialog.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const { isAdmin } = useAdmin();

const rows = useMapGetter('pilot/customTools/getRows');
const meta = useMapGetter('pilot/customTools/getMeta');
const loading = useMapGetter('pilot/customTools/getLoading');
const error = useMapGetter('pilot/customTools/getError');

const dialogRef = ref(null);
const dialogMode = ref('create');
const dialogInitial = ref(null);

const currentPage = ref(1);

const isLoading = computed(() => loading.value);
const hasError = computed(() => Boolean(error.value));

const totalCount = computed(() => meta.value.total_count || 0);
const totalPages = computed(() => meta.value.total_pages || 0);
const perPage = computed(() => meta.value.per_page || 25);

const readUrlState = () => {
  const q = route.query || {};
  const pageNum = Number(q.page) || 1;
  return pageNum > 0 ? pageNum : 1;
};

const syncUrl = () => {
  const next = { ...(route.query || {}) };
  if (currentPage.value > 1) {
    next.page = String(currentPage.value);
  } else {
    delete next.page;
  }
  router.replace({ query: next }).catch(() => {});
};

const fetchCurrent = async () => {
  try {
    await store.dispatch('pilot/customTools/fetchPage', {
      page: currentPage.value,
    });
  } catch (_err) {
    // Error state is captured via store/error getter
  }
};

onMounted(async () => {
  currentPage.value = readUrlState();
  syncUrl();
  await fetchCurrent();
});

watch(
  () => route.query.page,
  newPage => {
    const pageNum = Number(newPage) || 1;
    if (pageNum !== currentPage.value) {
      currentPage.value = pageNum > 0 ? pageNum : 1;
      fetchCurrent();
    }
  }
);

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
  dialogRef.value?.open();
};

const openEdit = row => {
  dialogMode.value = 'edit';
  dialogInitial.value = row;
  dialogRef.value?.open();
};

const onDelete = async row => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('PILOT.TOOLS.CARD.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('pilot/customTools/destroyRow', { id: row.id });
    useAlert(t('PILOT.TOOLS.DIALOG.TOAST.DELETE_SUCCESS'));
    if (rows.value.length === 0 && currentPage.value > 1) {
      currentPage.value -= 1;
      syncUrl();
    }
    await fetchCurrent();
  } catch (_err) {
    useAlert(t('PILOT.TOOLS.DIALOG.TOAST.DELETE_ERROR'));
  }
};

const onSuccess = () => {
  const actionText =
    dialogMode.value === 'create'
      ? t('PILOT.TOOLS.DIALOG.TOAST.CREATE_SUCCESS')
      : t('PILOT.TOOLS.DIALOG.TOAST.UPDATE_SUCCESS');
  useAlert(actionText);
  fetchCurrent();
};
</script>

<template>
  <section
    class="flex flex-col flex-1 min-h-0 gap-4 p-6 overflow-y-auto w-full max-w-5xl mx-auto"
  >
    <PilotToolsHeader :is-admin="isAdmin" @create="openCreate" />

    <ToolCardList
      :rows="rows"
      :is-loading="isLoading"
      :has-error="hasError"
      :is-admin="isAdmin"
      @edit="openEdit"
      @delete="onDelete"
      @retry="onRetry"
      @create="openCreate"
    />

    <PilotPagerFooter
      v-if="!isLoading && !hasError && totalCount > 0"
      :page="currentPage"
      :per-page="perPage"
      :total-count="totalCount"
      :total-pages="totalPages"
      @update:page="onPageChange"
    />

    <ToolEditDialog
      ref="dialogRef"
      :mode="dialogMode"
      :tool="dialogInitial"
      @close="dialogInitial = null"
      @success="onSuccess"
    />
  </section>
</template>
