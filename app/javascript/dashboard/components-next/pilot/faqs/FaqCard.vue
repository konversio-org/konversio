<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { formatDistanceToNow } from 'date-fns';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import Checkbox from '../../checkbox/Checkbox.vue';

const props = defineProps({
  row: { type: Object, required: true },
  showMenu: { type: Boolean, default: true },
  showActions: { type: Boolean, default: false },
  selectable: { type: Boolean, default: false },
  isSelected: { type: Boolean, default: false },
});

const emit = defineEmits(['edit', 'delete', 'approve', 'select']);

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

const onApprove = () => {
  closeMenu();
  emit('approve', props.row);
};

const handleSelectChange = checked => {
  emit('select', props.row.id, checked);
};
</script>

<template>
  <article
    class="relative flex gap-4 p-4 rounded-xl bg-n-alpha-2 border border-n-weak hover:border-n-slate-5 transition-all duration-200"
  >
    <!-- Checkbox for Bulk Select -->
    <div v-if="selectable" class="flex items-start pt-1">
      <Checkbox :model-value="isSelected" @change="handleSelectChange" />
    </div>

    <div class="flex flex-col flex-1 gap-3 min-w-0">
      <header class="flex items-start justify-between gap-3">
        <h3 class="text-heading-sm font-medium text-n-slate-12 leading-snug">
          {{ row.question }}
        </h3>
        <div v-on-click-outside="closeMenu" class="relative flex-shrink-0">
          <button
            v-if="showMenu"
            type="button"
            :aria-label="t('PILOT.FAQS.CARD.MENU_LABEL')"
            class="flex items-center justify-center size-7 rounded-md text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-slate-12"
            @click="toggleMenu"
          >
            <span aria-hidden="true" class="i-lucide-more-horizontal size-4" />
          </button>
          <ul
            v-if="isMenuOpen && showMenu"
            role="menu"
            class="absolute right-0 z-20 mt-1 min-w-32 rounded-lg border border-n-weak bg-n-solid-1 shadow-lg p-1 list-none"
          >
            <li v-if="row.status === 'pending'" role="none">
              <button
                type="button"
                role="menuitem"
                class="flex items-center w-full gap-2 px-2 py-1.5 text-sm rounded-md text-n-blue-11 hover:bg-n-alpha-1 font-medium"
                @click="onApprove"
              >
                <span aria-hidden="true" class="i-lucide-circle-check size-4" />
                {{ t('PILOT.FAQS.CARD.APPROVE') }}
              </button>
            </li>
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

      <footer
        class="flex flex-wrap items-center justify-between gap-4 pt-1 border-t border-n-weak/50 mt-1"
      >
        <!-- Metadata and source info -->
        <div class="flex flex-wrap items-center gap-2">
          <!-- Approved-only attribution -->
          <span
            v-if="row.status === 'approved' && assistantName"
            class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-11 font-medium"
          >
            <span aria-hidden="true" class="i-lucide-message-circle size-3.5" />
            {{ assistantName }}
          </span>

          <!-- Document source chip (visible on both states) -->
          <span
            v-if="hasDocument"
            class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-11 max-w-xs truncate"
            :title="documentName"
          >
            <span aria-hidden="true" class="i-lucide-file-text size-3.5" />
            <span class="truncate">{{ documentName }}</span>
          </span>

          <!-- Timestamp (visible on both states) -->
          <span
            v-if="relativeTime"
            class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-11"
          >
            <span aria-hidden="true" class="i-lucide-calendar size-3.5" />
            {{ relativeTime }}
          </span>

          <!-- Edited badge -->
          <span
            v-if="row.edited"
            class="inline-flex items-center px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-10"
          >
            {{ t('PILOT.FAQS.CARD.EDITED_BADGE') }}
          </span>
        </div>

        <!-- Inline Actions (Visible in Pending Mode when showActions is true) -->
        <div v-if="showActions" class="flex items-center gap-4">
          <button
            v-if="row.status === 'pending'"
            type="button"
            class="inline-flex items-center gap-1 text-sm font-medium text-n-blue-11 hover:underline transition duration-150"
            @click="onApprove"
          >
            <span aria-hidden="true" class="i-lucide-circle-check size-4" />
            {{ t('PILOT.FAQS.CARD.APPROVE') }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-1 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 transition duration-150"
            @click="onEdit"
          >
            <span aria-hidden="true" class="i-lucide-pencil size-4" />
            {{ t('PILOT.FAQS.CARD.EDIT') }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-1 text-sm font-medium text-n-ruby-11 hover:text-n-ruby-12 transition duration-150"
            @click="onDelete"
          >
            <span aria-hidden="true" class="i-lucide-trash-2 size-4" />
            {{ t('PILOT.FAQS.CARD.DELETE') }}
          </button>
        </div>
      </footer>
    </div>
  </article>
</template>
