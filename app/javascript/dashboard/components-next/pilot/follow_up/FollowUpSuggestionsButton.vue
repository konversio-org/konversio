<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useMapGetter } from 'dashboard/composables/store';
import { useFollowUp } from 'dashboard/composables/pilot/useFollowUp';
import NextButton from 'dashboard/components-next/button/Button.vue';

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

const emit = defineEmits(['insert']);

const { t } = useI18n();
const currentAccount = useMapGetter('getCurrentAccount');

const followUp = useFollowUp();
const popoverOpen = ref(false);

const isEnabled = computed(() => {
  const account = currentAccount.value || {};
  return Boolean(account.pilot_enabled && account.pilot_follow_up_enabled);
});

const closePopover = () => {
  popoverOpen.value = false;
};

const onClick = async () => {
  if (props.disabled || followUp.loading.value) return;
  const list = await followUp.generate(props.conversationId);
  if (list && list.length) popoverOpen.value = true;
};

const pickSuggestion = text => {
  emit('insert', text);
  closePopover();
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
      icon="i-ph-question-fill"
      :disabled="disabled || followUp.loading.value"
      :label="
        followUp.loading.value
          ? t('PILOT.FOLLOW_UP.LOADING')
          : t('PILOT.FOLLOW_UP.BUTTON_LABEL')
      "
      class="text-n-violet-9 hover:enabled:!bg-n-violet-3"
      @click="onClick"
    />
    <span
      v-if="followUp.error.value"
      class="text-xs text-n-ruby-9"
      role="alert"
    >
      {{ followUp.error.value || t('PILOT.FOLLOW_UP.ERROR') }}
    </span>
    <div
      v-if="popoverOpen && followUp.suggestions.value.length"
      role="menu"
      :aria-label="t('PILOT.FOLLOW_UP.POPOVER_TITLE')"
      class="absolute bottom-full right-0 mb-2 w-80 rounded-lg border border-n-strong bg-n-solid-3 p-3 shadow-lg z-50 flex flex-col gap-2"
    >
      <h4 class="text-xs font-semibold text-n-slate-11 uppercase">
        {{ t('PILOT.FOLLOW_UP.POPOVER_TITLE') }}
      </h4>
      <button
        v-for="suggestion in followUp.suggestions.value"
        :key="suggestion"
        type="button"
        role="menuitem"
        class="text-left text-sm text-n-slate-12 rounded-md border border-n-strong px-3 py-2 hover:bg-n-slate-3"
        @click="pickSuggestion(suggestion)"
      >
        {{ suggestion }}
      </button>
    </div>
  </div>
</template>
