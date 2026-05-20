<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import AssistantPicker from 'dashboard/components-next/pilot/shared/AssistantPicker.vue';
import FaqSearchInput from './FaqSearchInput.vue';

const props = defineProps({
  assistantId: { type: [Number, String, null], default: null },
  search: { type: String, default: '' },
});

const emit = defineEmits(['update:assistantId', 'update:search', 'create']);

// NOTE: KNOW_MORE_URL points at the upstream Chatwoot docs placeholder.
// Update once Konversio's own help center for Pilot FAQs is live.
const KNOW_MORE_URL =
  'https://www.chatwoot.com/hc/user-guide/articles/captain-faqs';

const { t } = useI18n();

const onAssistantChange = id => emit('update:assistantId', id);
const onSearchChange = value => emit('update:search', value);
const onCreate = () => emit('create');
</script>

<template>
  <header
    class="flex flex-row flex-wrap items-center justify-between gap-4 pb-4 border-b border-n-weak"
  >
    <div
      class="flex flex-wrap items-center gap-x-3 gap-y-2 min-w-0 flex-shrink"
    >
      <div class="min-w-48 max-w-64">
        <AssistantPicker
          :model-value="props.assistantId"
          @update:model-value="onAssistantChange"
        />
      </div>
      <span aria-hidden="true" class="h-5 w-px bg-n-weak" />
      <h1 class="text-heading-md font-medium text-n-slate-12">
        {{ t('PILOT.FAQS.PAGE_TITLE') }}
      </h1>
      <a
        :href="KNOW_MORE_URL"
        target="_blank"
        rel="noreferrer noopener"
        class="inline-flex items-center gap-1 text-sm text-n-brand hover:underline"
      >
        {{ t('PILOT.FAQS.KNOW_MORE') }}
        <span aria-hidden="true" class="i-lucide-external-link size-3.5" />
      </a>
    </div>
    <div
      class="flex w-full flex-1 items-center justify-end gap-3 min-w-0 sm:w-auto"
    >
      <FaqSearchInput
        :model-value="props.search"
        class="min-w-0 flex-1 sm:max-w-xs"
        @update:search="onSearchChange"
      />
      <Button
        :label="t('PILOT.FAQS.CREATE_NEW')"
        icon="i-lucide-plus"
        color="blue"
        class="flex-shrink-0"
        @click="onCreate"
      />
    </div>
  </header>
</template>
