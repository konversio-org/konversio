<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useAccount } from 'dashboard/composables/useAccount';
import { useBriefing } from 'dashboard/composables/pilot/useBriefing';
import { useSummary } from 'dashboard/composables/pilot/useSummary';
import { useRewrite } from 'dashboard/composables/pilot/useRewrite';
import { useCopilotDrawer } from 'dashboard/composables/pilot/useCopilotDrawer';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PilotSparkleIcon from 'dashboard/components-next/pilot/PilotSparkleIcon.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';

// Menu layout: rewrite actions (Improve / Change tone / Fix grammar) sit
// above the Captain three-item layout (Suggest a reply / Summarize / Ask
// Copilot). Rewrite items are gated on `pilot_rewrite_enabled` and a
// non-empty draft. "Change tone" expands the menu inline to show the five
// spec-defined Pilot tones; picking one closes the menu.

const props = defineProps({
  conversationId: {
    type: [Number, String],
    default: null,
  },
  editorContent: {
    type: String,
    default: '',
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
const rewrite = useRewrite();
const copilotDrawer = useCopilotDrawer();

const isOpen = ref(false);
const toneSubmenuOpen = ref(false);

const TONES = ['friendly', 'formal', 'concise', 'empathetic', 'assertive'];

const closeMenu = () => {
  isOpen.value = false;
  toneSubmenuOpen.value = false;
};
const toggleMenu = () => {
  if (props.disabled) return;
  if (isOpen.value) closeMenu();
  else isOpen.value = true;
};

const isMasterEnabled = computed(() =>
  Boolean(currentAccount.value?.pilot_enabled)
);

const hasDraft = computed(() => (props.editorContent || '').trim().length > 0);

const rewriteAllowed = computed(() => {
  const account = currentAccount.value || {};
  return Boolean(account.pilot_rewrite_enabled) && hasDraft.value;
});

const anyLoading = computed(
  () => briefing.loading.value || summary.loading.value || rewrite.loading.value
);

const runRewrite = async operation => {
  emitter.emit(BUS_EVENTS.PILOT_PREVIEW_START, {
    actionKey: `rewrite:${operation}`,
    targetMode: REPLY_EDITOR_MODES.REPLY,
  });
  const result = await rewrite.generate({
    text: props.editorContent,
    operation,
  });
  if (result) {
    emitter.emit(BUS_EVENTS.PILOT_PREVIEW_READY, { content: result });
  } else {
    emitter.emit(BUS_EVENTS.PILOT_PREVIEW_ERROR, {
      errorMessage: rewrite.error.value || '',
    });
  }
};

const actions = computed(() => {
  const account = currentAccount.value || {};
  const list = [];

  if (rewriteAllowed.value) {
    list.push({
      key: 'improve_reply',
      label: t('PILOT.ACTIONS_MENU_IMPROVE_REPLY'),
      icon: 'i-ph-magic-wand',
      handler: () => runRewrite('improve'),
    });
    list.push({
      key: 'change_tone',
      label: t('PILOT.ACTIONS_MENU_CHANGE_TONE'),
      icon: 'i-ph-faders-horizontal',
      hasSubmenu: true,
      handler: () => {
        toneSubmenuOpen.value = true;
      },
    });
    list.push({
      key: 'fix_grammar',
      label: t('PILOT.ACTIONS_MENU_FIX_GRAMMAR'),
      icon: 'i-ph-check-circle',
      handler: () => runRewrite('fix_spelling_grammar'),
    });
  }

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

const toneItems = computed(() =>
  TONES.map(tone => ({
    key: `tone_${tone}`,
    label: t(`PILOT.REWRITE.TONES.${tone.toUpperCase()}`),
    icon: 'i-ph-faders-horizontal',
    handler: () => runRewrite(tone),
  }))
);

const isVisible = computed(
  () => isMasterEnabled.value && actions.value.length > 0
);

const onActionClick = async action => {
  if (action.disabled || anyLoading.value) return;
  // "Change tone" toggles the submenu and keeps the menu open;
  // every other action closes the menu before firing.
  if (action.hasSubmenu) {
    action.handler();
    return;
  }
  closeMenu();
  await action.handler();
};

const onBackClick = () => {
  toneSubmenuOpen.value = false;
};

const firstError = computed(
  () => briefing.error.value || summary.error.value || rewrite.error.value
);
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
      <template v-if="!toneSubmenuOpen">
        <button
          v-for="action in actions"
          :key="action.key"
          type="button"
          role="menuitem"
          :disabled="action.disabled"
          class="flex w-full items-center justify-between gap-2 px-4 py-2 text-left text-sm text-n-slate-12 hover:bg-n-slate-3 disabled:opacity-50 disabled:cursor-not-allowed"
          @click="onActionClick(action)"
        >
          <span class="flex items-center gap-2">
            <span class="inline-block size-4" :class="[action.icon]" />
            {{ action.label }}
          </span>
          <span
            v-if="action.hasSubmenu"
            class="inline-block size-3 i-ph-caret-right text-n-slate-10"
          />
        </button>
      </template>
      <template v-else>
        <button
          type="button"
          role="menuitem"
          class="flex w-full items-center gap-2 px-4 py-2 text-left text-sm text-n-slate-11 hover:bg-n-slate-3"
          @click="onBackClick"
        >
          <span class="inline-block size-3 i-ph-caret-left" />
          {{ t('PILOT.ACTIONS_MENU_BACK') }}
        </button>
        <div class="my-1 border-t border-n-strong" />
        <button
          v-for="tone in toneItems"
          :key="tone.key"
          type="button"
          role="menuitem"
          class="flex w-full items-center gap-2 px-4 py-2 text-left text-sm text-n-slate-12 hover:bg-n-slate-3"
          @click="onActionClick(tone)"
        >
          <span class="inline-block size-4" :class="[tone.icon]" />
          {{ tone.label }}
        </button>
      </template>
    </div>

    <span v-if="firstError" class="text-xs text-n-ruby-9" role="alert">
      {{ firstError }}
    </span>
  </div>
</template>
