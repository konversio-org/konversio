<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  mode: {
    type: String,
    default: 'create',
    validator: value => ['create', 'edit'].includes(value),
  },
  initial: { type: Object, default: null },
  isSubmitting: { type: Boolean, default: false },
  serverError: { type: String, default: '' },
});

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();

const dialogRef = ref(null);
const question = ref('');
const answer = ref('');
const questionError = ref('');
const answerError = ref('');

const isEdit = computed(() => props.mode === 'edit');
const title = computed(() =>
  isEdit.value
    ? t('PILOT.FAQS.DIALOG.EDIT_TITLE')
    : t('PILOT.FAQS.DIALOG.CREATE_TITLE')
);

const resetForm = () => {
  question.value = props.initial?.question || '';
  answer.value = props.initial?.answer || '';
  questionError.value = '';
  answerError.value = '';
};

watch(
  () => props.initial,
  () => {
    resetForm();
  },
  { immediate: true }
);

const open = () => {
  resetForm();
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

const onClose = () => {
  emit('close');
};

const validate = () => {
  questionError.value = question.value.trim()
    ? ''
    : t('PILOT.FAQS.DIALOG.QUESTION_REQUIRED');
  answerError.value = answer.value.trim()
    ? ''
    : t('PILOT.FAQS.DIALOG.ANSWER_REQUIRED');
  return !questionError.value && !answerError.value;
};

const onConfirm = () => {
  if (!validate()) return;
  emit('submit', {
    question: question.value.trim(),
    answer: answer.value.trim(),
  });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="2xl"
    :title="title"
    :confirm-button-label="t('PILOT.FAQS.DIALOG.SAVE')"
    :cancel-button-label="t('PILOT.FAQS.DIALOG.CANCEL')"
    :is-loading="isSubmitting"
    @confirm="onConfirm"
    @close="onClose"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="question"
        :label="t('PILOT.FAQS.DIALOG.QUESTION_LABEL')"
        :placeholder="t('PILOT.FAQS.DIALOG.QUESTION_PLACEHOLDER')"
        :message="questionError"
        :message-type="questionError ? 'error' : 'info'"
        autofocus
      />
      <div class="flex flex-col gap-1">
        <label
          for="pilot-faq-answer"
          class="mb-0.5 text-heading-3 text-n-slate-12"
        >
          {{ t('PILOT.FAQS.DIALOG.ANSWER_LABEL') }}
        </label>
        <textarea
          id="pilot-faq-answer"
          v-model="answer"
          rows="6"
          :placeholder="t('PILOT.FAQS.DIALOG.ANSWER_PLACEHOLDER')"
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
      <p
        v-if="serverError"
        role="alert"
        class="px-3 py-2 text-sm rounded-md bg-n-ruby-3 text-n-ruby-11 border border-n-ruby-7"
      >
        {{ serverError }}
      </p>
    </div>
  </Dialog>
</template>
