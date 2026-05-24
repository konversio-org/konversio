<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import PilotEventsAPI from 'dashboard/api/pilot/events';
import Button from 'dashboard/components-next/button/Button.vue';
import PilotPagerFooter from 'dashboard/components-next/pilot/tools/PilotPagerFooter.vue';

const { t } = useI18n();

const DEFAULT_META = {
  current_page: 1,
  per_page: 25,
  total_count: 0,
  total_pages: 0,
};

const events = ref([]);
const meta = ref({ ...DEFAULT_META });
const currentPage = ref(1);
const isLoading = ref(false);
const error = ref(null);

const hasEvents = computed(() => events.value.length > 0);
const errorMessage = computed(() => {
  if (!error.value) return '';
  return (
    error.value?.response?.data?.error ||
    error.value?.message ||
    t('PILOT.ACTIVITY.ERROR.GENERIC')
  );
});

const formatTime = value => {
  if (!value) return '';
  return new Date(value).toLocaleString();
};

const formatPayload = payload => JSON.stringify(payload || {}, null, 2);

const relatedEntity = event => {
  if (!event.related_entity_type || !event.related_entity_id) {
    return t('PILOT.ACTIVITY.TABLE.NO_ENTITY');
  }

  return `${event.related_entity_type} #${event.related_entity_id}`;
};

const fetchEvents = async (page = currentPage.value) => {
  isLoading.value = true;
  error.value = null;
  try {
    const { data } = await PilotEventsAPI.list({ page });
    events.value = Array.isArray(data?.data) ? data.data : [];
    meta.value = { ...DEFAULT_META, ...(data?.meta || {}) };
    currentPage.value = meta.value.current_page || page;
  } catch (err) {
    error.value = err;
  } finally {
    isLoading.value = false;
  }
};

const onPageChange = page => {
  currentPage.value = page;
  fetchEvents(page);
};

onMounted(() => fetchEvents(1));
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6">
      <div class="w-full max-w-6xl mx-auto">
        <div class="flex items-center justify-between w-full h-20 gap-3">
          <h1 class="text-heading-md font-medium text-n-slate-12 truncate">
            {{ t('PILOT.ACTIVITY.HEADER.TITLE') }}
          </h1>
          <Button
            :label="t('PILOT.ACTIVITY.HEADER.REFRESH')"
            icon="i-lucide-refresh-cw"
            size="sm"
            color="slate"
            variant="outline"
            :is-loading="isLoading"
            @click="fetchEvents(currentPage)"
          />
        </div>
      </div>
    </header>

    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full max-w-6xl mx-auto py-2 flex flex-col gap-3">
        <div
          v-if="errorMessage && !isLoading"
          class="flex items-start justify-between gap-3 p-3 rounded-lg bg-n-ruby-3 border border-n-ruby-6 text-sm text-n-ruby-11"
          role="alert"
        >
          <span class="flex-1">{{ errorMessage }}</span>
          <button
            type="button"
            class="text-xs font-medium underline hover:text-n-ruby-12"
            @click="fetchEvents(currentPage)"
          >
            {{ t('PILOT.ACTIVITY.ERROR.RETRY') }}
          </button>
        </div>

        <div
          v-if="isLoading && !hasEvents"
          class="flex items-center justify-center h-40 text-sm text-n-slate-11"
        >
          {{ t('PILOT.ACTIVITY.LOADING') }}
        </div>

        <div
          v-else-if="!hasEvents && !errorMessage"
          class="flex flex-col items-center justify-center h-56 gap-2 text-center border border-dashed rounded-lg border-n-weak bg-n-alpha-1"
        >
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t('PILOT.ACTIVITY.EMPTY.TITLE') }}
          </h2>
          <p class="text-sm text-n-slate-11">
            {{ t('PILOT.ACTIVITY.EMPTY.BODY') }}
          </p>
        </div>

        <div
          v-else
          class="overflow-hidden border rounded-lg border-n-weak bg-n-solid-1"
        >
          <table class="w-full text-sm table-fixed">
            <thead class="bg-n-alpha-1 text-n-slate-11">
              <tr class="border-b border-n-weak">
                <th class="w-48 px-4 py-3 text-left font-medium">
                  {{ t('PILOT.ACTIVITY.TABLE.TIME') }}
                </th>
                <th class="w-64 px-4 py-3 text-left font-medium">
                  {{ t('PILOT.ACTIVITY.TABLE.EVENT') }}
                </th>
                <th class="w-48 px-4 py-3 text-left font-medium">
                  {{ t('PILOT.ACTIVITY.TABLE.ENTITY') }}
                </th>
                <th class="px-4 py-3 text-left font-medium">
                  {{ t('PILOT.ACTIVITY.TABLE.PAYLOAD') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="event in events"
                :key="event.id"
                class="border-b border-n-weak last:border-b-0 align-top"
              >
                <td class="px-4 py-3 text-n-slate-11">
                  {{ formatTime(event.created_at) }}
                </td>
                <td class="px-4 py-3">
                  <span
                    class="inline-flex max-w-full items-center rounded-md bg-n-alpha-1 px-2 py-1 font-mono text-xs text-n-slate-12"
                  >
                    <span class="truncate">{{ event.event_name }}</span>
                  </span>
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ relatedEntity(event) }}
                </td>
                <td class="px-4 py-3">
                  <div
                    class="max-h-28 overflow-auto whitespace-pre-wrap break-words rounded-md bg-n-alpha-1 p-2 font-mono text-xs leading-5 text-n-slate-11"
                  >
                    {{ formatPayload(event.payload) }}
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <PilotPagerFooter
          v-if="!isLoading && !errorMessage && meta.total_count > 0"
          :page="currentPage"
          :per-page="meta.per_page"
          :total-count="meta.total_count"
          :total-pages="meta.total_pages"
          @update:page="onPageChange"
        />
      </div>
    </main>
  </section>
</template>
