<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useBriefing } from 'dashboard/composables/pilot/useBriefing';
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

const emit = defineEmits(['draft']);

const { t } = useI18n();
const currentAccount = useMapGetter('getCurrentAccount');

const briefing = useBriefing();

const isEnabled = computed(() => {
  const account = currentAccount.value || {};
  const features = account.features || {};
  return Boolean(features.pilot && features.pilot_briefing);
});

const buttonLabel = computed(() =>
  briefing.loading.value
    ? t('PILOT.BRIEFING.LOADING')
    : t('PILOT.BRIEFING.BUTTON_LABEL')
);

const onClick = async () => {
  if (props.disabled || briefing.loading.value) return;
  const draft = await briefing.generate(props.conversationId);
  if (draft) emit('draft', draft);
};
</script>

<template>
  <div v-if="isEnabled" class="flex flex-col items-end gap-1">
    <NextButton
      ghost
      sm
      icon="i-ph-sparkle-fill"
      :disabled="disabled || briefing.loading.value"
      :label="buttonLabel"
      class="text-n-violet-9 hover:enabled:!bg-n-violet-3"
      @click="onClick"
    />
    <span
      v-if="briefing.error.value"
      class="text-xs text-n-ruby-9"
      role="alert"
    >
      {{ briefing.error.value || $t('PILOT.BRIEFING.ERROR') }}
    </span>
  </div>
</template>
