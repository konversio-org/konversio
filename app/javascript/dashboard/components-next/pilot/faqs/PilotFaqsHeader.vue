<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import FeatureSpotlightPopover from 'dashboard/components-next/feature-spotlight/FeatureSpotlightPopover.vue';
import AssistantPicker from 'dashboard/components-next/pilot/shared/AssistantPicker.vue';
import FaqSearchInput from './FaqSearchInput.vue';

const props = defineProps({
  assistantId: { type: [Number, String, null], default: null },
  search: { type: String, default: '' },
  isPending: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:assistantId',
  'update:search',
  'create',
  'back',
]);

const { t } = useI18n();

const onAssistantChange = id => emit('update:assistantId', id);
const onSearchChange = value => emit('update:search', value);
const onCreate = () => emit('create');
const onBack = () => emit('back');
</script>

<template>
  <header
    class="flex flex-row flex-wrap items-center justify-between gap-4 pb-4 border-b border-n-weak"
  >
    <div
      class="flex flex-wrap items-center gap-x-3 gap-y-2 min-w-0 flex-shrink"
    >
      <!-- Back button in pending mode -->
      <Button
        v-if="isPending"
        icon="i-lucide-arrow-left"
        variant="ghost"
        color="slate"
        class="flex-shrink-0 !p-1.5"
        @click="onBack"
      />

      <div class="min-w-48 max-w-64">
        <AssistantPicker
          :model-value="props.assistantId"
          @update:model-value="onAssistantChange"
        />
      </div>
      <span aria-hidden="true" class="h-5 w-px bg-n-weak" />
      <h1 class="text-heading-md font-medium text-n-slate-12">
        {{ isPending ? 'Pending FAQs' : t('PILOT.FAQS.PAGE_TITLE') }}
      </h1>
      <FeatureSpotlightPopover
        v-if="!isPending"
        :button-label="t('PILOT.FAQS.KNOW_MORE')"
        :note="t('PILOT.FAQS.KNOW_MORE_NOTE')"
        hide-actions
      />
    </div>
    <div
      class="flex w-full flex-1 items-center justify-end gap-3 min-w-0 sm:w-auto"
    >
      <FaqSearchInput
        :model-value="props.search"
        class="min-w-0 flex-1 sm:max-w-xs"
        @update:search="onSearchChange"
      />
      <!-- Create button is only shown in approved mode -->
      <Button
        v-if="!isPending"
        :label="t('PILOT.FAQS.CREATE_NEW')"
        icon="i-lucide-plus"
        color="blue"
        class="flex-shrink-0"
        @click="onCreate"
      />
    </div>
  </header>
</template>
