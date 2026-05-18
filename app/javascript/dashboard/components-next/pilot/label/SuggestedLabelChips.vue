<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const currentAccount = useMapGetter('getCurrentAccount');
const accountLabels = useMapGetter('labels/getLabels');

// Locally remove chips that the user has just applied so the UI
// reacts instantly without waiting for a backend refresh.
const dismissedLabelIds = ref(new Set());

const isEnabled = computed(() => {
  const account = currentAccount.value || {};
  return Boolean(
    account.pilot_enabled && account.pilot_label_suggestion_enabled
  );
});

const suggestedIds = computed(
  () => props.conversation?.suggested_label_ids || []
);

const appliedLabelTitles = computed(() => {
  return new Set(
    (props.conversation?.labels || []).map(l =>
      typeof l === 'string' ? l : l.title
    )
  );
});

const chips = computed(() => {
  if (!isEnabled.value) return [];
  return suggestedIds.value
    .filter(id => !dismissedLabelIds.value.has(id))
    .map(id => (accountLabels.value || []).find(l => l.id === id))
    .filter(label => label && !appliedLabelTitles.value.has(label.title));
});

const applyLabel = async label => {
  const conversationId = props.conversation?.id;
  if (!conversationId || !label?.title) return;
  dismissedLabelIds.value.add(label.id);

  const currentTitles = (props.conversation?.labels || []).map(l =>
    typeof l === 'string' ? l : l.title
  );
  const nextTitles = Array.from(new Set([...currentTitles, label.title]));

  try {
    await store.dispatch('updateConversationLabels', {
      conversationId,
      labels: nextTitles,
    });
  } catch (e) {
    // re-show the chip if the API call failed
    dismissedLabelIds.value.delete(label.id);
  }
};
</script>

<template>
  <div
    v-if="isEnabled && chips.length"
    class="flex flex-wrap gap-2 items-center"
    :aria-label="t('PILOT.LABEL_SUGGESTION.CHIP_TITLE')"
  >
    <span class="text-xs font-medium text-n-slate-11">
      {{ t('PILOT.LABEL_SUGGESTION.CHIP_TITLE') }}
    </span>
    <button
      v-for="label in chips"
      :key="label.id"
      type="button"
      class="inline-flex items-center gap-1 rounded-full border border-n-violet-7 bg-n-violet-2 px-3 py-1 text-xs text-n-violet-11 hover:bg-n-violet-3"
      @click="applyLabel(label)"
    >
      <span class="i-ph-plus size-3" />
      {{ label.title }}
    </button>
  </div>
</template>
