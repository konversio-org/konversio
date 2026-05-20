<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import DocumentRow from './DocumentRow.vue';

defineProps({
  documents: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  hasError: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['delete', 'add']);

const { t } = useI18n();

const onDelete = id => emit('delete', id);
const onAdd = () => emit('add');
</script>

<template>
  <div class="flex flex-col gap-3">
    <template v-if="isLoading">
      <div
        v-for="i in 3"
        :key="`skeleton-${i}`"
        class="w-full h-24 rounded-xl bg-n-alpha-1 animate-pulse"
        aria-hidden="true"
      />
    </template>

    <template v-else-if="!documents.length && !hasError">
      <div
        class="flex flex-col items-center justify-center gap-3 py-16 px-6 rounded-xl border border-dashed border-n-container bg-n-solid-2 text-center"
      >
        <span class="i-ph-file-text size-10 text-n-slate-9" />
        <div class="flex flex-col gap-1">
          <h2 class="text-heading-md text-n-slate-12">
            {{ t('PILOT_DOCUMENTS.EMPTY.TITLE') }}
          </h2>
          <p class="text-sm text-n-slate-10 max-w-md">
            {{ t('PILOT_DOCUMENTS.EMPTY.DESCRIPTION') }}
          </p>
        </div>
        <Button
          :label="t('PILOT_DOCUMENTS.EMPTY.CTA')"
          icon="i-lucide-plus"
          size="sm"
          @click="onAdd"
        />
      </div>
    </template>

    <template v-else>
      <DocumentRow
        v-for="document in documents"
        :key="document.id"
        :document="document"
        @delete="onDelete"
      />
    </template>
  </div>
</template>
