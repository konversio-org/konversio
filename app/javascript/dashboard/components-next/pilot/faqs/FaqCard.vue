<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { formatDistanceToNow } from 'date-fns';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';

const props = defineProps({
  row: { type: Object, required: true },
});

const emit = defineEmits(['edit', 'delete']);

const { t } = useI18n();

const isMenuOpen = ref(false);

const closeMenu = () => {
  isMenuOpen.value = false;
};

const toggleMenu = () => {
  isMenuOpen.value = !isMenuOpen.value;
};

const answerHtml = computed(() => {
  const formatter = new MessageFormatter(props.row?.answer || '');
  return formatter.formattedMessage;
});

const assistantName = computed(() => props.row?.assistant?.name || '');

const documentName = computed(() => props.row?.documentable?.name || '');

const hasDocument = computed(() =>
  Boolean(props.row?.documentable && props.row.documentable.id)
);

const relativeTime = computed(() => {
  const stamp = props.row?.updated_at || props.row?.created_at;
  if (!stamp) return '';
  try {
    return formatDistanceToNow(new Date(stamp), { addSuffix: true });
  } catch (e) {
    return '';
  }
});

const onEdit = () => {
  closeMenu();
  emit('edit', props.row);
};

const onDelete = () => {
  closeMenu();
  emit('delete', props.row);
};
</script>

<template>
  <article
    class="relative flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-2 border border-n-weak"
  >
    <header class="flex items-start justify-between gap-3">
      <h3 class="text-heading-sm font-medium text-n-slate-12 leading-snug">
        {{ row.question }}
      </h3>
      <div v-on-click-outside="closeMenu" class="relative flex-shrink-0">
        <button
          type="button"
          :aria-label="t('PILOT.FAQS.CARD.MENU_LABEL')"
          class="flex items-center justify-center size-7 rounded-md text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-slate-12"
          @click="toggleMenu"
        >
          <span aria-hidden="true" class="i-lucide-more-horizontal size-4" />
        </button>
        <ul
          v-if="isMenuOpen"
          role="menu"
          class="absolute right-0 z-20 mt-1 min-w-32 rounded-lg border border-n-weak bg-n-solid-1 shadow-lg p-1 list-none"
        >
          <li role="none">
            <button
              type="button"
              role="menuitem"
              class="flex items-center w-full gap-2 px-2 py-1.5 text-sm rounded-md text-n-slate-12 hover:bg-n-alpha-1"
              @click="onEdit"
            >
              <span aria-hidden="true" class="i-lucide-pencil size-4" />
              {{ t('PILOT.FAQS.CARD.EDIT') }}
            </button>
          </li>
          <li role="none">
            <button
              type="button"
              role="menuitem"
              class="flex items-center w-full gap-2 px-2 py-1.5 text-sm rounded-md text-n-ruby-11 hover:bg-n-alpha-1"
              @click="onDelete"
            >
              <span aria-hidden="true" class="i-lucide-trash-2 size-4" />
              {{ t('PILOT.FAQS.CARD.DELETE') }}
            </button>
          </li>
        </ul>
      </div>
    </header>

    <div
      v-dompurify-html="answerHtml"
      class="prose-sm break-words text-body-medium text-n-slate-11 max-w-none"
    />

    <footer class="flex flex-wrap items-center gap-2 pt-1">
      <span
        v-if="assistantName"
        class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-11"
      >
        <span aria-hidden="true" class="i-lucide-message-circle size-3.5" />
        {{ assistantName }}
      </span>
      <span
        v-if="hasDocument"
        class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-11 max-w-xs truncate"
        :title="documentName"
      >
        <span aria-hidden="true" class="i-lucide-file-text size-3.5" />
        <span class="truncate">{{ documentName }}</span>
      </span>
      <span
        v-if="relativeTime"
        class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-11"
      >
        <span aria-hidden="true" class="i-lucide-calendar size-3.5" />
        {{ relativeTime }}
      </span>
      <span
        v-if="row.edited"
        class="inline-flex items-center px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-10"
      >
        {{ t('PILOT.FAQS.CARD.EDITED_BADGE') }}
      </span>
    </footer>
  </article>
</template>
