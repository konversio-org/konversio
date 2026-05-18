<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useAccount } from 'dashboard/composables/useAccount';
import { useBriefing } from 'dashboard/composables/pilot/useBriefing';
import { useSummary } from 'dashboard/composables/pilot/useSummary';
import { useFollowUp } from 'dashboard/composables/pilot/useFollowUp';
import { useRewrite } from 'dashboard/composables/pilot/useRewrite';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PilotSparkleIcon from 'dashboard/components-next/pilot/PilotSparkleIcon.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';

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

const emit = defineEmits([
  'draft',
  'summary',
  'followUp',
  'rewrite',
  'requestReplyMode',
]);

const { t } = useI18n();
const { currentAccount } = useAccount();

const briefing = useBriefing();
const summary = useSummary();
const followUp = useFollowUp();
const rewrite = useRewrite();

const isOpen = ref(false);
// When non-empty, the menu surface shows a "pick a follow-up to ask" panel
// instead of the default action list. Reset whenever the menu closes so
// re-opening always starts at the default actions.
const followUpResults = ref([]);
// Sticky flag that survives a result-set reset: when the agent picks a
// suggestion, the popover closes immediately; surfacing the "No more
// suggestions" empty state would be wrong. We only render empty-state
// copy when generate() completed with zero results AND the agent hasn't
// already accepted one.
const followUpEmpty = ref(false);

const closeMenu = () => {
  isOpen.value = false;
  followUpResults.value = [];
  followUpEmpty.value = false;
};
const toggleMenu = () => {
  if (props.disabled) return;
  if (isOpen.value) closeMenu();
  else isOpen.value = true;
};

// Master gate: every sub-feature requires pilot_enabled AND its own flag.
const isMasterEnabled = computed(() =>
  Boolean(currentAccount.value?.pilot_enabled)
);

const anyLoading = computed(
  () =>
    briefing.loading.value ||
    summary.loading.value ||
    followUp.loading.value ||
    rewrite.loading.value
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
        if (!draft) return;
        // Briefing is a customer-facing reply — always land in Reply mode,
        // even if the agent currently has Private Note selected. Same
        // watcher-flush pattern as summary: switch mode, wait one tick for
        // ReplyBox's replyType watcher to swap drafts, then push the draft.
        emit('requestReplyMode', REPLY_EDITOR_MODES.REPLY);
        await nextTick();
        emit('draft', draft);
      },
    });
  }

  if (account.pilot_summary_enabled) {
    list.push({
      key: 'summary',
      label: t('PILOT.SUMMARY.BUTTON_LABEL'),
      icon: 'i-ph-note-fill',
      handler: async () => {
        const result = await summary.generate(props.conversationId);
        if (!result) return;
        // LLM output sometimes begins with a stray blank line, which
        // ProseMirror keeps as an empty paragraph above the first heading.
        const trimmed = result.replace(/^\s+/, '');
        // Summary is an INTERNAL artefact — auto-switch to Private Note
        // so the agent can't accidentally send the summary to the
        // customer. Wait one tick so ReplyBox's replyType watcher flushes
        // (saves the prior Reply draft + loads the empty Note draft) before
        // we insert; otherwise the summary lands in the still-active Reply
        // draft and the Note tab shows empty.
        emit('requestReplyMode', REPLY_EDITOR_MODES.NOTE);
        await nextTick();
        emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, trimmed);
        emit('summary', trimmed);
      },
    });
  }

  if (account.pilot_follow_up_enabled) {
    list.push({
      key: 'follow_up',
      label: t('PILOT.FOLLOW_UP.BUTTON_LABEL'),
      icon: 'i-ph-question-fill',
      // The popover stays open during generation so the loading spinner
      // (driven by `anyLoading` on the trigger button) and the result
      // panel both anchor to the same surface — single mental model for
      // the agent.
      keepMenuOpen: true,
      handler: async () => {
        const suggestions = await followUp.generate(props.conversationId);
        // Guard: agent may have clicked outside while the request was
        // in flight. Don't repopulate state into a closed surface.
        if (!isOpen.value) return;
        if (suggestions && suggestions.length) {
          // Cap at 3 — the LLM occasionally over-produces and we want a
          // tight, scannable list.
          followUpResults.value = suggestions.slice(0, 3);
          emit('followUp', suggestions);
        } else {
          followUpEmpty.value = true;
        }
      },
    });
  }

  if (account.pilot_rewrite_enabled) {
    list.push({
      key: 'rewrite',
      label: t('PILOT.REWRITE.BUTTON_LABEL'),
      icon: 'i-ph-pencil-line-fill',
      disabled: !props.editorContent,
      handler: async () => {
        if (!props.editorContent) return;
        // Default to friendly tone from the menu entry; the dedicated
        // RewriteToolbar component offers the full tone picker.
        const result = await rewrite.generate({
          text: props.editorContent,
          tone: 'friendly',
        });
        if (result) emit('rewrite', result);
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
  // Actions that show in-menu results (currently only follow-up) keep
  // the popover open through generation so the loading state and the
  // resulting panel share the same anchor.
  if (!action.keepMenuOpen) closeMenu();
  await action.handler();
};

const onFollowUpPick = async text => {
  // Follow-up questions are customer-facing — force Reply mode even if
  // the agent currently has Private Note selected, then insert via the
  // shared editor bus (same channel Summary uses). The await nextTick()
  // lets ReplyBox's replyType watcher flush draft state before the
  // insert lands; without it the question would write into the wrong
  // draft slot (the exact bug we hit on Summary, fixed by db1010c88).
  emit('requestReplyMode', REPLY_EDITOR_MODES.REPLY);
  await nextTick();
  emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, text);
  closeMenu();
};

const firstError = computed(
  () =>
    briefing.error.value ||
    summary.error.value ||
    followUp.error.value ||
    rewrite.error.value
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
      class="absolute bottom-full right-0 mb-2 rounded-lg border border-n-strong bg-n-solid-3 py-2 shadow-lg z-50"
      :class="[followUpResults.length || followUpEmpty ? 'w-80' : 'min-w-56']"
    >
      <template v-if="followUpResults.length">
        <div
          class="px-4 pt-1 pb-2 text-xs font-semibold uppercase text-n-slate-11"
        >
          {{ t('PILOT.FOLLOW_UP.POPOVER_TITLE') }}
        </div>
        <button
          v-for="(suggestion, idx) in followUpResults"
          :key="idx"
          type="button"
          role="menuitem"
          class="group flex w-full items-start gap-2 px-4 py-2 text-left text-sm text-n-slate-12 hover:bg-n-slate-3"
          @click="onFollowUpPick(suggestion)"
        >
          <span
            class="i-ph-question-fill mt-0.5 inline-block size-4 shrink-0 text-n-violet-9"
          />
          <span class="flex-1 leading-snug">{{ suggestion }}</span>
          <span
            class="i-ph-arrow-right mt-0.5 inline-block size-4 shrink-0 text-n-slate-11 opacity-0 transition-opacity group-hover:opacity-100"
          />
        </button>
      </template>

      <template v-else-if="followUpEmpty">
        <div class="px-4 py-2 text-sm text-n-slate-11">
          {{ t('PILOT.FOLLOW_UP.EMPTY') }}
        </div>
      </template>

      <template v-else>
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
      </template>
    </div>

    <span v-if="firstError" class="text-xs text-n-ruby-9" role="alert">
      {{ firstError }}
    </span>
  </div>
</template>
