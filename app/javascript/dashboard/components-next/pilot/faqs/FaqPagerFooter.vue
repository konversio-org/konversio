<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  page: { type: Number, default: 1 },
  perPage: { type: Number, default: 25 },
  totalCount: { type: Number, default: 0 },
  totalPages: { type: Number, default: 0 },
});

const emit = defineEmits(['update:page']);

const { t } = useI18n();

const safePage = computed(() => Math.max(1, props.page || 1));
const safeTotalPages = computed(() => Math.max(1, props.totalPages || 1));
const isFirst = computed(() => safePage.value <= 1);
const isLast = computed(() => safePage.value >= safeTotalPages.value);

const rangeFrom = computed(() => {
  if (!props.totalCount) return 0;
  return (safePage.value - 1) * props.perPage + 1;
});

const rangeTo = computed(() => {
  if (!props.totalCount) return 0;
  return Math.min(safePage.value * props.perPage, props.totalCount);
});

const goTo = target => {
  if (target < 1 || target > safeTotalPages.value) return;
  if (target === safePage.value) return;
  emit('update:page', target);
};
</script>

<template>
  <footer
    class="flex items-center justify-between gap-3 pt-2 text-sm text-n-slate-11"
  >
    <span class="text-n-slate-10">
      {{
        t('PILOT.FAQS.PAGER_RANGE', {
          from: rangeFrom,
          to: rangeTo,
          total: totalCount,
        })
      }}
    </span>
    <nav
      v-if="safeTotalPages > 1"
      class="flex items-center gap-1"
      :aria-label="
        t('PILOT.FAQS.PAGER_OF', {
          page: safePage,
          totalPages: safeTotalPages,
        })
      "
    >
      <button
        type="button"
        :disabled="isFirst"
        class="flex items-center justify-center size-7 rounded-md text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-40 disabled:cursor-not-allowed"
        @click="goTo(1)"
      >
        <span aria-hidden="true" class="i-lucide-chevrons-left size-4" />
      </button>
      <button
        type="button"
        :disabled="isFirst"
        class="flex items-center justify-center size-7 rounded-md text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-40 disabled:cursor-not-allowed"
        @click="goTo(safePage - 1)"
      >
        <span aria-hidden="true" class="i-lucide-chevron-left size-4" />
      </button>
      <span class="px-2 text-n-slate-12">
        {{
          t('PILOT.FAQS.PAGER_OF', {
            page: safePage,
            totalPages: safeTotalPages,
          })
        }}
      </span>
      <button
        type="button"
        :disabled="isLast"
        class="flex items-center justify-center size-7 rounded-md text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-40 disabled:cursor-not-allowed"
        @click="goTo(safePage + 1)"
      >
        <span aria-hidden="true" class="i-lucide-chevron-right size-4" />
      </button>
      <button
        type="button"
        :disabled="isLast"
        class="flex items-center justify-center size-7 rounded-md text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-40 disabled:cursor-not-allowed"
        @click="goTo(safeTotalPages)"
      >
        <span aria-hidden="true" class="i-lucide-chevrons-right size-4" />
      </button>
    </nav>
  </footer>
</template>
