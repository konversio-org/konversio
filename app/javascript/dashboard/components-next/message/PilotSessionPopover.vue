<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import Icon from 'next/icon/Icon.vue';
import PilotSessionPanel from './PilotSessionPanel.vue';

const props = defineProps({
  messageId: { type: Number, required: true },
  createdAt: { type: Number, default: null },
});

const store = useStore();
const isOpen = ref(false);

const session = computed(() =>
  store.getters['pilot/agentSessions/getSession'](props.messageId)
);
const isLoading = computed(() =>
  store.getters['pilot/agentSessions/isLoading'](props.messageId)
);

const toggle = () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) {
    store.dispatch('pilot/agentSessions/fetch', {
      messageId: props.messageId,
      createdAt: props.createdAt,
    });
  }
};
</script>

<template>
  <div class="relative inline-flex">
    <button
      type="button"
      class="p-1 rounded hover:bg-n-alpha-2 text-n-slate-11"
      :aria-label="$t('PILOT.PILOT_SESSION.TRIGGER')"
      :title="$t('PILOT.PILOT_SESSION.TRIGGER')"
      data-testid="pilot-session-trigger"
      @click="toggle"
    >
      <Icon icon="i-lucide-info" class="size-4" />
    </button>
    <div
      v-if="isOpen"
      class="absolute bottom-full left-0 z-50 mb-1 border rounded-lg shadow-lg bg-n-surface-1"
    >
      <PilotSessionPanel :session="session" :is-loading="isLoading" />
    </div>
  </div>
</template>
