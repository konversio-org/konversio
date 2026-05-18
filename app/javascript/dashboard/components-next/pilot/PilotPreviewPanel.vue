<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';

// In-composer preview surface for Pilot one-shot actions (Suggest a
// reply, Summarize the conversation). Conceptually mirrors the
// editor-swap pattern from Chatwoot Enterprise Captain: the rich-text
// editor is replaced with a thinking-state, then with an editable
// preview the agent can Accept (merge into composer) or Dismiss
// (discard, restore the original editor).
//
// Refinement loop ("make it shorter") is deliberately NOT implemented
// here. Konversio already ships iterative chat via the Copilot drawer
// (Ask Copilot menu item); duplicating that on the composer surface
// would be redundant.

const props = defineProps({
  // 'briefing' | 'summary' — drives the title and the empty-state copy.
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

const emit = defineEmits(['accept', 'dismiss']);

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

const dotDelay1 = { animationDelay: '-0.3s' };
const dotDelay2 = { animationDelay: '-0.15s' };
</script>

<template>
  <div
    class="flex flex-col gap-3 rounded-lg border border-n-iris-7 bg-n-iris-2 p-4"
    role="region"
    :aria-label="
      isSummary
        ? t('PILOT.SUMMARY.PREVIEW_TITLE')
        : t('PILOT.BRIEFING.PREVIEW_TITLE')
    "
  >
    <div class="flex items-center justify-between">
      <h4 v-if="isSummary" class="text-sm font-semibold text-n-iris-11">
        {{ t('PILOT.SUMMARY.PREVIEW_TITLE') }}
      </h4>
      <h4 v-else class="text-sm font-semibold text-n-iris-11">
        {{ t('PILOT.BRIEFING.PREVIEW_TITLE') }}
      </h4>
      <button
        type="button"
        :aria-label="t('PILOT.PREVIEW_DISMISS')"
        class="i-ph-x size-4 text-n-iris-11 hover:text-n-iris-12 cursor-pointer"
        @click="onDismiss"
      />
    </div>

    <!-- Thinking state -->
    <div
      v-if="isGenerating"
      class="flex items-center gap-2 py-6 text-sm text-n-iris-11"
    >
      <span class="flex items-center gap-1">
        <span
          :style="dotDelay1"
          class="size-1.5 rounded-full bg-n-iris-9 animate-bounce"
        />
        <span
          :style="dotDelay2"
          class="size-1.5 rounded-full bg-n-iris-9 animate-bounce"
        />
        <span class="size-1.5 rounded-full bg-n-iris-9 animate-bounce" />
      </span>
      <span v-if="isSummary">{{ t('PILOT.SUMMARY.LOADING') }}</span>
      <span v-else>{{ t('PILOT.BRIEFING.LOADING') }}</span>
    </div>

    <!-- Error state -->
    <div
      v-else-if="errorMessage"
      class="rounded-md border border-n-ruby-7 bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
      role="alert"
    >
      {{ errorMessage }}
    </div>

    <!-- Preview state -->
    <template v-else>
      <textarea
        v-model="draft"
        rows="6"
        class="w-full resize-none rounded-md border border-n-strong bg-n-solid-3 p-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-iris-7"
        :placeholder="t('PILOT.PREVIEW_PLACEHOLDER')"
      />
      <div class="flex items-center justify-end gap-2">
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
          :label="t('PILOT.PREVIEW_ACCEPT')"
          class="!bg-n-iris-9 hover:enabled:!bg-n-iris-10 text-white"
          @click="onAccept"
        />
      </div>
    </template>
  </div>
</template>
