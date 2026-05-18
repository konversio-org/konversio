<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useAccount } from 'dashboard/composables/useAccount';
import { useSummary } from 'dashboard/composables/pilot/useSummary';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    default: null,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const { currentAccount } = useAccount();

const summary = useSummary();
const popoverOpen = ref(false);

const isEnabled = computed(() => {
  const account = currentAccount.value || {};
  return Boolean(account.pilot_enabled && account.pilot_summary_enabled);
});

const formattedSummary = computed(() => {
  if (!summary.summary.value) return '';
  return new MessageFormatter(summary.summary.value).formattedMessage;
});

const closePopover = () => {
  popoverOpen.value = false;
};

const onClick = async () => {
  if (props.disabled || summary.loading.value) return;
  const result = await summary.generate(props.conversationId);
  if (result) popoverOpen.value = true;
};
</script>

<template>
  <div
    v-if="isEnabled"
    v-on-click-outside="closePopover"
    class="relative flex flex-col items-end"
  >
    <NextButton
      ghost
      sm
      icon="i-ph-note-fill"
      :disabled="disabled || summary.loading.value"
      :label="
        summary.loading.value
          ? t('PILOT.SUMMARY.LOADING')
          : t('PILOT.SUMMARY.BUTTON_LABEL')
      "
      class="text-n-violet-9 hover:enabled:!bg-n-violet-3"
      @click="onClick"
    />
    <span v-if="summary.error.value" class="text-xs text-n-ruby-9" role="alert">
      {{ summary.error.value || t('PILOT.SUMMARY.ERROR') }}
    </span>
    <div
      v-if="popoverOpen && summary.summary.value"
      role="dialog"
      :aria-label="t('PILOT.SUMMARY.POPOVER_TITLE')"
      class="absolute top-full right-0 mt-2 w-80 rounded-lg border border-n-strong bg-n-solid-3 p-4 shadow-lg z-50"
    >
      <div class="flex items-center justify-between mb-2">
        <h4 class="text-sm font-semibold text-n-slate-12">
          {{ t('PILOT.SUMMARY.POPOVER_TITLE') }}
        </h4>
        <button
          type="button"
          class="text-xs text-n-slate-11 hover:text-n-slate-12"
          @click="closePopover"
        >
          {{ t('PILOT.SUMMARY.CLOSE') }}
        </button>
      </div>
      <div
        v-dompurify-html="formattedSummary"
        class="prose-sm text-sm text-n-slate-12 break-words"
      />
    </div>
  </div>
</template>
