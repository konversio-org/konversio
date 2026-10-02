<script setup>
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PilotFaqSuggestionsAPI from 'dashboard/api/pilot/faqSuggestions';

const props = defineProps({
  suggestion: { type: Object, default: null },
  isSubmitting: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'approve', 'dismiss', 'close']);

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const dialogRef = ref(null);
const question = ref('');
const answer = ref('');
const questionError = ref('');
const answerError = ref('');
const sources = ref([]);
const isLoadingSources = ref(false);

const resetForm = () => {
  question.value = props.suggestion?.question || '';
  answer.value = props.suggestion?.answer || '';
  questionError.value = '';
  answerError.value = '';
};

const fetchSources = async () => {
  if (!props.suggestion?.id) {
    sources.value = [];
    return;
  }
  isLoadingSources.value = true;
  try {
    const { data } = await PilotFaqSuggestionsAPI.show(props.suggestion.id);
    sources.value = Array.isArray(data?.observations) ? data.observations : [];
  } catch (e) {
    sources.value = [];
  } finally {
    isLoadingSources.value = false;
  }
};

watch(
  () => props.suggestion,
  () => {
    resetForm();
    fetchSources();
  },
  { immediate: true }
);

const open = () => {
  resetForm();
  fetchSources();
  dialogRef.value?.open?.();
};

const close = () => {
  dialogRef.value?.close?.();
};

const validate = () => {
  questionError.value = question.value.trim()
    ? ''
    : t('PILOT.FAQ_SUGGESTIONS.DIALOG.QUESTION_REQUIRED');
  answerError.value = answer.value.trim()
    ? ''
    : t('PILOT.FAQ_SUGGESTIONS.DIALOG.ANSWER_REQUIRED');
  return !questionError.value && !answerError.value;
};

const payload = () => ({
  id: props.suggestion.id,
  question: question.value.trim(),
  answer: answer.value.trim(),
});

const onSave = () => {
  if (!validate()) return;
  emit('save', payload());
};

const onApprove = () => {
  if (!validate()) return;
  emit('approve', payload());
};

const onDismiss = () => {
  emit('dismiss', { id: props.suggestion.id });
};

const goToConversation = observation => {
  const displayId = observation?.conversation?.display_id;
  if (!displayId) return;
  router.push({
    name: 'inbox_conversation',
    params: { accountId: accountId.value, conversation_id: displayId },
  });
  close();
};

const isPristine = computed(
  () =>
    question.value.trim() === (props.suggestion?.question || '') &&
    answer.value.trim() === (props.suggestion?.answer || '')
);

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="2xl"
    :title="t('PILOT.FAQ_SUGGESTIONS.DIALOG.TITLE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="question"
        :label="t('PILOT.FAQ_SUGGESTIONS.DIALOG.QUESTION_LABEL')"
        :placeholder="t('PILOT.FAQ_SUGGESTIONS.DIALOG.QUESTION_PLACEHOLDER')"
        :message="questionError"
        :message-type="questionError ? 'error' : 'info'"
        autofocus
      />
      <div class="flex flex-col gap-1">
        <label
          for="pilot-faq-suggestion-answer"
          class="mb-0.5 text-heading-3 text-n-slate-12"
        >
          {{ t('PILOT.FAQ_SUGGESTIONS.DIALOG.ANSWER_LABEL') }}
        </label>
        <textarea
          id="pilot-faq-suggestion-answer"
          v-model="answer"
          rows="6"
          :placeholder="t('PILOT.FAQ_SUGGESTIONS.DIALOG.ANSWER_PLACEHOLDER')"
          class="block w-full px-3 py-2 text-sm rounded-lg outline outline-1 outline-offset-[-1px] bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-n-brand resize-y min-h-32"
          :class="
            answerError
              ? 'outline-n-ruby-8 focus:outline-n-ruby-9'
              : 'outline-n-weak'
          "
        />
        <p
          v-if="answerError"
          class="min-w-0 mt-1 mb-0 text-label-small text-n-ruby-9"
        >
          {{ answerError }}
        </p>
      </div>

      <div class="flex flex-col gap-2">
        <h4 class="m-0 text-heading-3 text-n-slate-12">
          {{ t('PILOT.FAQ_SUGGESTIONS.DIALOG.SOURCES_TITLE') }}
        </h4>
        <p v-if="isLoadingSources" class="m-0 text-sm text-n-slate-10">
          {{ t('PILOT.FAQ_SUGGESTIONS.DIALOG.SOURCES_LOADING') }}
        </p>
        <p v-else-if="sources.length === 0" class="m-0 text-sm text-n-slate-10">
          {{ t('PILOT.FAQ_SUGGESTIONS.DIALOG.SOURCES_EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-1 m-0 list-none p-0">
          <li v-for="observation in sources" :key="observation.id">
            <button
              type="button"
              class="flex items-center justify-between w-full gap-2 px-3 py-2 text-sm rounded-lg text-n-slate-12 hover:bg-n-alpha-1"
              @click="goToConversation(observation)"
            >
              <span class="truncate">
                {{ observation.generated_question }}
              </span>
              <span
                class="inline-flex items-center gap-1 flex-shrink-0 text-n-slate-10"
              >
                <span aria-hidden="true" class="i-lucide-hash size-3.5" />
                {{ observation.conversation?.display_id }}
              </span>
            </button>
          </li>
        </ul>
      </div>
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="ghost"
          color="ruby"
          :label="t('PILOT.FAQ_SUGGESTIONS.DIALOG.DISMISS')"
          :disabled="isSubmitting"
          type="button"
          @click="onDismiss"
        />
        <div class="flex items-center gap-3">
          <Button
            variant="faded"
            color="slate"
            :label="t('PILOT.FAQ_SUGGESTIONS.DIALOG.SAVE')"
            :disabled="isSubmitting || isPristine"
            type="button"
            @click="onSave"
          />
          <Button
            color="blue"
            :label="t('PILOT.FAQ_SUGGESTIONS.DIALOG.APPROVE')"
            :is-loading="isSubmitting"
            :disabled="isSubmitting"
            type="button"
            @click="onApprove"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>
