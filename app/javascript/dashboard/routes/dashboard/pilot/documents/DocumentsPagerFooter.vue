<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  currentPage: {
    type: Number,
    default: 1,
  },
  totalPages: {
    type: Number,
    default: 1,
  },
  totalCount: {
    type: Number,
    default: 0,
  },
  pageSize: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['update:page']);

const { t } = useI18n();

const PER_PAGE_FALLBACK = 25;

const safeTotalPages = computed(() => Math.max(1, props.totalPages || 1));
const safeCurrentPage = computed(() =>
  Math.min(Math.max(1, props.currentPage || 1), safeTotalPages.value)
);

const rangeStart = computed(() => {
  if (!props.totalCount) return 0;
  const per = props.pageSize || PER_PAGE_FALLBACK;
  return (safeCurrentPage.value - 1) * per + 1;
});

const rangeEnd = computed(() => {
  if (!props.totalCount) return 0;
  const per = props.pageSize || PER_PAGE_FALLBACK;
  return Math.min(safeCurrentPage.value * per, props.totalCount);
});

const canGoPrev = computed(() => safeCurrentPage.value > 1);
const canGoNext = computed(() => safeCurrentPage.value < safeTotalPages.value);
const canGoFirst = canGoPrev;
const canGoLast = canGoNext;

const goTo = page => {
  const target = Math.min(Math.max(1, page), safeTotalPages.value);
  if (target === safeCurrentPage.value) return;
  emit('update:page', target);
};
</script>

<template>
  <footer
    class="flex items-center justify-between gap-3 py-3 px-1 text-xs text-n-slate-11 flex-wrap"
  >
    <span>
      {{
        t('PILOT_DOCUMENTS.PAGER.RANGE', {
          start: rangeStart,
          end: rangeEnd,
          total: totalCount,
        })
      }}
    </span>
    <nav
      class="flex items-center gap-1"
      :aria-label="t('PILOT_DOCUMENTS.PAGER.ARIA')"
    >
      <button
        type="button"
        :aria-label="t('PILOT_DOCUMENTS.PAGER.FIRST')"
        class="h-7 w-7 inline-flex items-center justify-center rounded-md border border-n-container bg-n-solid-2 disabled:opacity-50 hover:enabled:bg-n-alpha-1"
        :disabled="!canGoFirst"
        @click="goTo(1)"
      >
        <span class="i-lucide-chevrons-left size-3.5" aria-hidden="true" />
      </button>
      <button
        type="button"
        :aria-label="t('PILOT_DOCUMENTS.PAGER.PREV')"
        class="h-7 w-7 inline-flex items-center justify-center rounded-md border border-n-container bg-n-solid-2 disabled:opacity-50 hover:enabled:bg-n-alpha-1"
        :disabled="!canGoPrev"
        @click="goTo(safeCurrentPage - 1)"
      >
        <span class="i-lucide-chevron-left size-3.5" aria-hidden="true" />
      </button>
      <span class="px-2 text-n-slate-12 font-medium">
        {{
          t('PILOT_DOCUMENTS.PAGER.PAGE_OF', {
            page: safeCurrentPage,
            total: safeTotalPages,
          })
        }}
      </span>
      <button
        type="button"
        :aria-label="t('PILOT_DOCUMENTS.PAGER.NEXT')"
        class="h-7 w-7 inline-flex items-center justify-center rounded-md border border-n-container bg-n-solid-2 disabled:opacity-50 hover:enabled:bg-n-alpha-1"
        :disabled="!canGoNext"
        @click="goTo(safeCurrentPage + 1)"
      >
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
      </button>
      <button
        type="button"
        :aria-label="t('PILOT_DOCUMENTS.PAGER.LAST')"
        class="h-7 w-7 inline-flex items-center justify-center rounded-md border border-n-container bg-n-solid-2 disabled:opacity-50 hover:enabled:bg-n-alpha-1"
        :disabled="!canGoLast"
        @click="goTo(safeTotalPages)"
      >
        <span class="i-lucide-chevrons-right size-3.5" aria-hidden="true" />
      </button>
    </nav>
  </footer>
</template>
