<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useAccount } from 'dashboard/composables/useAccount';
import { useBriefing } from 'dashboard/composables/pilot/useBriefing';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PilotSparkleIcon from 'dashboard/components-next/pilot/PilotSparkleIcon.vue';

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
const { currentAccount } = useAccount();

const briefing = useBriefing();

const isOpen = ref(false);
const closeMenu = () => {
  isOpen.value = false;
};
const toggleMenu = () => {
  if (props.disabled) return;
  isOpen.value = !isOpen.value;
};

// Master gate: every sub-feature requires pilot_enabled AND its own flag.
// As more sub-features ship, push their menu items into `actions` below.
const isMasterEnabled = computed(() =>
  Boolean(currentAccount.value?.pilot_enabled)
);

const actions = computed(() => {
  const account = currentAccount.value || {};
  const list = [];

  if (account.pilot_briefing_enabled) {
    list.push({
      key: 'briefing',
      label: t('PILOT.BRIEFING.BUTTON_LABEL'),
      icon: 'i-ph-chat-text',
      handler: async () => {
        const draft = await briefing.generate(props.conversationId);
        if (draft) emit('draft', draft);
      },
    });
  }

  // Future sub-features (Summary, Rewrite, Follow-up, Copilot) plug in here
  // as each ships; UI shell stays stable.

  return list;
});

const isVisible = computed(
  () => isMasterEnabled.value && actions.value.length > 0
);

const onActionClick = async action => {
  closeMenu();
  if (briefing.loading.value) return;
  await action.handler();
};
</script>

<template>
  <div
    v-if="isVisible"
    v-on-click-outside="closeMenu"
    class="relative flex flex-col items-end gap-1"
  >
    <NextButton
      ghost
      sm
      :disabled="disabled || briefing.loading.value"
      class="text-woot-500 hover:enabled:!text-n-amber-9 hover:enabled:!bg-n-amber-3"
      :aria-label="t('PILOT.ACTIONS_MENU_LABEL')"
      :aria-expanded="isOpen"
      @click="toggleMenu"
    >
      <template #icon>
        <PilotSparkleIcon class="size-4" />
      </template>
    </NextButton>

    <div
      v-if="isOpen"
      role="menu"
      class="absolute bottom-full right-0 mb-2 min-w-56 rounded-lg border border-n-strong bg-n-solid-3 py-2 shadow-lg z-50"
    >
      <button
        v-for="action in actions"
        :key="action.key"
        type="button"
        role="menuitem"
        class="flex w-full items-center gap-2 px-4 py-2 text-left text-sm text-n-slate-12 hover:bg-n-slate-3"
        @click="onActionClick(action)"
      >
        <span class="inline-block size-4" :class="[action.icon]" />
        {{ action.label }}
      </button>
    </div>

    <span
      v-if="briefing.error.value"
      class="text-xs text-n-ruby-9"
      role="alert"
    >
      {{ briefing.error.value || t('PILOT.BRIEFING.ERROR') }}
    </span>
  </div>
</template>
