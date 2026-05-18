<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useAccount } from 'dashboard/composables/useAccount';
import { useBriefing } from 'dashboard/composables/pilot/useBriefing';
import { useSummary } from 'dashboard/composables/pilot/useSummary';
import { useCopilotDrawer } from 'dashboard/composables/pilot/useCopilotDrawer';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PilotSparkleIcon from 'dashboard/components-next/pilot/PilotSparkleIcon.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';

// Menu structure mirrors Chatwoot Enterprise Captain's three-item layout:
// Suggest a reply / Summarize the conversation / Ask Copilot. Conceptual
// design only — no upstream code copied. The earlier "Suggest follow-up"
// entry and standalone "Rewrite" entry have been removed for 1:1 parity;
// their backends (useFollowUp, useRewrite) remain available for future
// re-use but are no longer surfaced through this menu.

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

const briefing = useBriefing();
const summary = useSummary();
const copilotDrawer = useCopilotDrawer();

const isOpen = ref(false);
const closeMenu = () => {
  isOpen.value = false;
};
const toggleMenu = () => {
  if (props.disabled) return;
  if (isOpen.value) closeMenu();
  else isOpen.value = true;
};

const isMasterEnabled = computed(() =>
  Boolean(currentAccount.value?.pilot_enabled)
);

const anyLoading = computed(
  () => briefing.loading.value || summary.loading.value
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
        // Open the preview surface immediately so the thinking state
        // is visible while the API call is in flight (matches Captain's
        // editor-swap UX). ReplyBox owns the panel state and renders
        // PilotPreviewPanel in place of the composer until Accept or
        // Dismiss is fired.
        emitter.emit(BUS_EVENTS.PILOT_PREVIEW_START, {
          actionKey: 'briefing',
          targetMode: REPLY_EDITOR_MODES.REPLY,
        });
        const draft = await briefing.generate(props.conversationId);
        if (draft) {
          emitter.emit(BUS_EVENTS.PILOT_PREVIEW_READY, { content: draft });
        } else {
          emitter.emit(BUS_EVENTS.PILOT_PREVIEW_ERROR, {
            errorMessage: briefing.error.value || '',
          });
        }
      },
    });
  }

  if (account.pilot_summary_enabled) {
    list.push({
      key: 'summary',
      label: t('PILOT.SUMMARY.BUTTON_LABEL'),
      icon: 'i-ph-note-fill',
      handler: async () => {
        emitter.emit(BUS_EVENTS.PILOT_PREVIEW_START, {
          actionKey: 'summary',
          // Summary is an INTERNAL artefact — Accept lands in Private
          // Note, never in Reply.
          targetMode: REPLY_EDITOR_MODES.NOTE,
        });
        const result = await summary.generate(props.conversationId);
        if (result) {
          // LLM occasionally emits a leading blank line that ProseMirror
          // keeps as an empty paragraph above the first heading.
          const trimmed = result.replace(/^\s+/, '');
          emitter.emit(BUS_EVENTS.PILOT_PREVIEW_READY, { content: trimmed });
        } else {
          emitter.emit(BUS_EVENTS.PILOT_PREVIEW_ERROR, {
            errorMessage: summary.error.value || '',
          });
        }
      },
    });
  }

  if (account.pilot_copilot_enabled) {
    list.push({
      key: 'ask_copilot',
      label: t('PILOT.ACTIONS_MENU_ASK_COPILOT'),
      icon: 'i-ph-sparkle',
      handler: () => {
        // Captain's "Ask Copilot" surfaces a free-form chat assistant
        // scoped to the current conversation. Konversio's equivalent
        // is the Copilot drawer (sidebar surface); openBoundToConversation
        // pre-seeds the conversation_id so the first thread message
        // carries it through.
        copilotDrawer.openBoundToConversation(props.conversationId);
      },
    });
  }

  return list;
});

const isVisible = computed(
  () => isMasterEnabled.value && actions.value.length > 0
);

const onActionClick = async action => {
  if (action.disabled || anyLoading.value) return;
  closeMenu();
  await action.handler();
};

const firstError = computed(() => briefing.error.value || summary.error.value);
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
      :disabled="disabled || anyLoading"
      :is-loading="anyLoading"
      class="text-woot-500 hover:enabled:!text-n-amber-9 hover:enabled:!bg-n-amber-3"
      :aria-label="
        anyLoading
          ? t('PILOT.ACTIONS_MENU_LOADING_LABEL')
          : t('PILOT.ACTIONS_MENU_LABEL')
      "
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
        :disabled="action.disabled"
        class="flex w-full items-center gap-2 px-4 py-2 text-left text-sm text-n-slate-12 hover:bg-n-slate-3 disabled:opacity-50 disabled:cursor-not-allowed"
        @click="onActionClick(action)"
      >
        <span class="inline-block size-4" :class="[action.icon]" />
        {{ action.label }}
      </button>
    </div>

    <span v-if="firstError" class="text-xs text-n-ruby-9" role="alert">
      {{ firstError }}
    </span>
  </div>
</template>
