<script setup>
import { computed, ref } from 'vue';
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
const closeMenu = () => {
  isOpen.value = false;
};
const toggleMenu = () => {
  if (props.disabled) return;
  isOpen.value = !isOpen.value;
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
        if (draft) emit('draft', draft);
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
        // Summary is an INTERNAL artefact — auto-switch to Private Note
        // so the agent can't accidentally send the summary to the
        // customer. Then insert the markdown into the composer; the
        // ProseMirror editor parses it into rich text.
        emit('requestReplyMode', REPLY_EDITOR_MODES.NOTE);
        emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, result);
        emit('summary', result);
      },
    });
  }

  if (account.pilot_follow_up_enabled) {
    list.push({
      key: 'follow_up',
      label: t('PILOT.FOLLOW_UP.BUTTON_LABEL'),
      icon: 'i-ph-question-fill',
      handler: async () => {
        const suggestions = await followUp.generate(props.conversationId);
        if (suggestions && suggestions.length) emit('followUp', suggestions);
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
  if (action.disabled) return;
  closeMenu();
  if (anyLoading.value) return;
  await action.handler();
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
