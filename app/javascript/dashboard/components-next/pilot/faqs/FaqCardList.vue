<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import FaqCard from './FaqCard.vue';

defineProps({
  rows: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  hasError: { type: Boolean, default: false },
  skeletonCount: { type: Number, default: 10 },
  showMenu: { type: Boolean, default: true },
  showActions: { type: Boolean, default: false },
  selectable: { type: Boolean, default: false },
  selectedIds: { type: Set, default: () => new Set() },
});

const emit = defineEmits([
  'edit',
  'delete',
  'retry',
  'create',
  'approve',
  'select',
]);

const { t } = useI18n();

const onEdit = row => emit('edit', row);
const onDelete = row => emit('delete', row);
const onRetry = () => emit('retry');
const onCreate = () => emit('create');
const onApprove = row => emit('approve', row);
const onSelect = (id, checked) => emit('select', id, checked);
</script>

<template>
  <section class="flex flex-col gap-3">
    <div
      v-if="hasError && !isLoading"
      role="alert"
      class="flex items-center justify-between gap-4 p-4 rounded-xl border border-n-ruby-7 bg-n-ruby-3 text-n-ruby-11"
    >
      <span class="text-sm">{{ t('PILOT.FAQS.ERROR.LOAD') }}</span>
      <Button
        :label="t('PILOT.FAQS.ERROR.RETRY')"
        size="sm"
        variant="faded"
        color="ruby"
        @click="onRetry"
      />
    </div>

    <template v-if="isLoading">
      <div
        v-for="i in skeletonCount"
        :key="`faq-skeleton-${i}`"
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-2 border border-n-weak animate-pulse"
      >
        <div class="h-4 w-1/3 rounded bg-n-alpha-1" />
        <div class="flex flex-col gap-2">
          <div class="h-3 w-full rounded bg-n-alpha-1" />
          <div class="h-3 w-5/6 rounded bg-n-alpha-1" />
        </div>
        <div class="flex gap-2">
          <div class="h-4 w-20 rounded-full bg-n-alpha-1" />
          <div class="h-4 w-24 rounded-full bg-n-alpha-1" />
        </div>
      </div>
    </template>

    <template v-else-if="!hasError && rows.length === 0">
      <div
        class="flex flex-col items-center justify-center gap-3 p-12 rounded-xl border border-dashed border-n-weak text-center"
      >
        <span
          aria-hidden="true"
          class="i-lucide-message-square-text size-10 text-n-slate-9"
        />
        <h3 class="text-heading-sm text-n-slate-12">
          {{ t('PILOT.FAQS.EMPTY_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-10 max-w-md">
          {{ t('PILOT.FAQS.EMPTY_BODY') }}
        </p>
        <Button
          :label="t('PILOT.FAQS.EMPTY_CTA')"
          icon="i-lucide-plus"
          color="blue"
          @click="onCreate"
        />
      </div>
    </template>

    <template v-else-if="!hasError">
      <FaqCard
        v-for="row in rows"
        :key="row.id"
        :row="row"
        :show-menu="showMenu"
        :show-actions="showActions"
        :selectable="selectable"
        :is-selected="selectedIds.has(row.id)"
        @edit="onEdit"
        @delete="onDelete"
        @approve="onApprove"
        @select="onSelect"
      />
    </template>
  </section>
</template>
