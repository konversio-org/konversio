<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDistanceToNow } from 'date-fns';

const props = defineProps({
  row: { type: Object, required: true },
});

const emit = defineEmits(['review', 'approve', 'dismiss']);

const { t } = useI18n();

const relativeTime = computed(() => {
  const stamp = props.row?.updated_at || props.row?.created_at;
  if (!stamp) return '';
  try {
    return formatDistanceToNow(new Date(stamp), { addSuffix: true });
  } catch (e) {
    return '';
  }
});

const sourceCountLabel = computed(() =>
  t('PILOT.FAQ_SUGGESTIONS.CARD.SOURCE_COUNT', {
    count: props.row?.source_count || 0,
  })
);
</script>

<template>
  <article
    class="relative flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-2 border border-n-weak hover:border-n-slate-5 transition-all duration-200"
  >
    <header class="flex items-start justify-between gap-3">
      <h3 class="text-heading-sm font-medium text-n-slate-12 leading-snug">
        {{ row.question }}
      </h3>
    </header>

    <p class="m-0 text-body-medium text-n-slate-11 break-words">
      {{ row.answer }}
    </p>

    <footer
      class="flex flex-wrap items-center justify-between gap-4 pt-1 border-t border-n-weak/50 mt-1"
    >
      <div class="flex flex-wrap items-center gap-2">
        <span
          class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-11 font-medium"
        >
          <span aria-hidden="true" class="i-lucide-messages-square size-3.5" />
          {{ sourceCountLabel }}
        </span>
        <span
          v-if="relativeTime"
          class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-11"
        >
          <span aria-hidden="true" class="i-lucide-calendar size-3.5" />
          {{ relativeTime }}
        </span>
      </div>

      <div class="flex items-center gap-4">
        <button
          type="button"
          class="inline-flex items-center gap-1 text-sm font-medium text-n-blue-11 hover:underline transition duration-150"
          @click="emit('approve', row)"
        >
          <span aria-hidden="true" class="i-lucide-circle-check size-4" />
          {{ t('PILOT.FAQ_SUGGESTIONS.CARD.APPROVE') }}
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-1 text-sm font-medium text-n-ruby-11 hover:text-n-ruby-12 transition duration-150"
          @click="emit('dismiss', row)"
        >
          <span aria-hidden="true" class="i-lucide-ban size-4" />
          {{ t('PILOT.FAQ_SUGGESTIONS.CARD.DISMISS') }}
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-1 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 transition duration-150"
          @click="emit('review', row)"
        >
          <span aria-hidden="true" class="i-lucide-square-pen size-4" />
          {{ t('PILOT.FAQ_SUGGESTIONS.CARD.REVIEW') }}
        </button>
      </div>
    </footer>
  </article>
</template>
