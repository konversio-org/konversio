<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PilotSparkleIcon from 'dashboard/components-next/pilot/PilotSparkleIcon.vue';

// In-composer preview surface for Pilot one-shot actions (Suggest a
// reply, Summarize the conversation). Conceptually mirrors the
// editor-swap pattern from Chatwoot Enterprise Captain: the rich-text
// editor is replaced with a thinking-state, then with an editable
// preview the agent can Accept (merge into composer) or Dismiss
// (discard, restore the original editor).
//
// Layout matches Captain's UX: violet-tinted box for the active state,
// Discard/Accept buttons positioned outside the box below. Cmd/Ctrl +
// Enter on the textarea accepts (matches Captain's keyboard shortcut).

const props = defineProps({
  // 'briefing' | 'summary' — drives the loading copy.
  actionKey: {
    type: String,
    required: true,
  },
  isGenerating: {
    type: Boolean,
    default: false,
  },
  // The generated text. Editable while the panel is open so the agent
  // can tweak before accepting.
  initialContent: {
    type: String,
    default: '',
  },
  errorMessage: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['accept', 'dismiss', 'refine']);

const { t } = useI18n();

// Local mutable copy so the agent can edit the generated content before
// accepting. Reset whenever the upstream content prop changes.
const draft = ref(props.initialContent);
watch(
  () => props.initialContent,
  next => {
    draft.value = next;
  }
);

const isSummary = computed(() => props.actionKey === 'summary');

const acceptDisabled = computed(
  () => props.isGenerating || !draft.value.trim() || !!props.errorMessage
);

const onAccept = () => {
  if (acceptDisabled.value) return;
  emit('accept', draft.value);
};

const onDismiss = () => emit('dismiss');

// Refinement loop: a second input below the generated content lets the
// agent type instructions like "make it shorter" / "ask about their
// refund status". Pressing Enter (or clicking the send button) emits
// 'refine' with the instruction. ReplyBox fires the API call with the
// current draft as previous_output, swaps to the thinking state, then
// replaces draft with the refined content when the response lands.
const refinement = ref('');
const refinementDisabled = computed(
  () => props.isGenerating || !refinement.value.trim()
);
const submitRefinement = () => {
  if (refinementDisabled.value) return;
  emit('refine', { instruction: refinement.value.trim(), draft: draft.value });
  refinement.value = '';
};
const onRefinementKeydown = e => {
  if (e.key === 'Enter' && !e.shiftKey && !e.metaKey && !e.ctrlKey) {
    e.preventDefault();
    submitRefinement();
  }
};

// Keyboard shortcut: Cmd/Ctrl + Enter accepts. Active for the lifetime
// of the panel; removed on unmount so it doesn't leak past the swap.
const handleKey = e => {
  if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
    e.preventDefault();
    onAccept();
  }
};
onMounted(() => document.addEventListener('keydown', handleKey));
onBeforeUnmount(() => document.removeEventListener('keydown', handleKey));
</script>

<template>
  <!-- Single violet region containing the draft, the refinement input,
       and the Discard / Accept actions. Thin dividers separate the
       three zones; everything is visually grouped inside one panel. -->
  <div
    class="rounded-lg bg-n-iris-3 px-4 py-3 text-n-iris-12"
    role="region"
    :aria-label="
      isSummary
        ? t('PILOT.SUMMARY.PREVIEW_TITLE')
        : t('PILOT.BRIEFING.PREVIEW_TITLE')
    "
  >
    <!-- Thinking state -->
    <div
      v-if="isGenerating"
      class="flex items-center gap-2 py-2 text-sm text-n-iris-11"
    >
      <PilotSparkleIcon class="size-4 shrink-0" />
      <span v-if="isSummary">{{ t('PILOT.SUMMARY.LOADING') }}</span>
      <span v-else>{{ t('PILOT.BRIEFING.LOADING') }}</span>
      <span class="ml-1 flex items-center gap-1">
        <span
          class="size-1 rounded-full bg-n-iris-9 animate-bounce [animation-delay:-0.3s]"
        />
        <span
          class="size-1 rounded-full bg-n-iris-9 animate-bounce [animation-delay:-0.15s]"
        />
        <span class="size-1 rounded-full bg-n-iris-9 animate-bounce" />
      </span>
    </div>

    <!-- Error state -->
    <div
      v-else-if="errorMessage"
      class="py-2 text-sm text-n-ruby-11"
      role="alert"
    >
      {{ errorMessage }}
    </div>

    <!-- Preview state: draft → divider → refinement → divider → actions -->
    <template v-else>
      <textarea
        v-model="draft"
        rows="5"
        class="w-full resize-none !outline-none !border-0 !bg-transparent !p-0 !mb-0 !h-auto text-sm text-n-iris-12 placeholder:text-n-iris-10 focus:outline-none focus:ring-0"
        :placeholder="t('PILOT.PREVIEW_PLACEHOLDER')"
      />
      <hr class="my-2 border-t border-n-iris-7" />
      <textarea
        v-model="refinement"
        rows="2"
        class="w-full resize-none !outline-none !border-0 !bg-transparent !p-0 !mb-0 !h-auto text-sm text-n-iris-12 placeholder:text-n-iris-10 focus:outline-none focus:ring-0"
        :placeholder="t('PILOT.PREVIEW_REFINE_PLACEHOLDER')"
        @keydown="onRefinementKeydown"
      />
      <hr class="my-2 border-t border-n-iris-7" />
      <div class="flex items-center justify-between">
        <NextButton
          ghost
          slate
          sm
          :label="t('PILOT.PREVIEW_DISMISS')"
          @click="onDismiss"
        />
        <NextButton
          solid
          sm
          :disabled="acceptDisabled"
          class="!bg-n-iris-9 hover:enabled:!bg-n-iris-10 text-white"
          @click="onAccept"
        >
          <span class="flex items-center gap-1.5">
            <span>{{ t('PILOT.PREVIEW_ACCEPT') }}</span>
            <span class="text-xs opacity-75">{{
              t('PILOT.PREVIEW_ACCEPT_SHORTCUT')
            }}</span>
          </span>
        </NextButton>
      </div>
    </template>
  </div>
</template>
