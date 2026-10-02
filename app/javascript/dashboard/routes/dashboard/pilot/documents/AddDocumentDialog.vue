<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  assistantId: {
    type: [Number, String, null],
    default: null,
  },
});

const emit = defineEmits(['created']);

const { t } = useI18n();
const store = useStore();

const uiFlags = useMapGetter('pilot/documents/getUIFlags');

const MARKDOWN_MAX_CHARS = 10000;

const dialogRef = ref(null);
const fileInputRef = ref(null);
const markdownInputRef = ref(null);
const activeTab = ref('url');
const urlValue = ref('');
const fileValue = ref(null);
const markdownFileValue = ref(null);
const markdownContentValue = ref('');
const fileDragOver = ref(false);
const serverError = ref('');

const TABS = [
  { id: 'url', key: 'URL' },
  { id: 'pdf', key: 'PDF' },
  { id: 'markdown', key: 'MARKDOWN' },
];

const isSubmitting = computed(() => uiFlags.value.isCreating);

const isUrlValid = computed(() => {
  const trimmed = urlValue.value.trim();
  if (!trimmed) return false;
  try {
    const u = new URL(trimmed);
    return u.protocol === 'http:' || u.protocol === 'https:';
  } catch (_e) {
    return false;
  }
});

const isPdfValid = computed(() => {
  if (!fileValue.value) return false;
  return /\.pdf$/i.test(fileValue.value.name);
});

const isMarkdownFileValid = computed(() => {
  if (!markdownFileValue.value) return false;
  return /\.md$/i.test(markdownFileValue.value.name);
});

const markdownContentLength = computed(() => markdownContentValue.value.length);

const isMarkdownContentValid = computed(
  () =>
    markdownContentValue.value.trim().length > 0 &&
    markdownContentLength.value <= MARKDOWN_MAX_CHARS
);

const isMarkdownValid = computed(
  () => isMarkdownFileValid.value || isMarkdownContentValid.value
);

const canSubmit = computed(() => {
  if (!props.assistantId) return false;
  if (isSubmitting.value) return false;
  if (activeTab.value === 'url') return isUrlValid.value;
  if (activeTab.value === 'pdf') return isPdfValid.value;
  return isMarkdownValid.value;
});

const reset = () => {
  urlValue.value = '';
  fileValue.value = null;
  markdownFileValue.value = null;
  markdownContentValue.value = '';
  fileDragOver.value = false;
  serverError.value = '';
  activeTab.value = 'url';
  if (fileInputRef.value) fileInputRef.value.value = '';
  if (markdownInputRef.value) markdownInputRef.value.value = '';
};

const open = () => {
  reset();
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

defineExpose({ open, close });

watch(activeTab, () => {
  serverError.value = '';
});

const onFileSelected = event => {
  const file = event.target.files?.[0];
  if (file) fileValue.value = file;
};

const onMarkdownFileSelected = event => {
  const file = event.target.files?.[0];
  if (file) markdownFileValue.value = file;
};

const onDrop = event => {
  event.preventDefault();
  fileDragOver.value = false;
  const file = event.dataTransfer?.files?.[0];
  if (file) fileValue.value = file;
};

const onDragOver = event => {
  event.preventDefault();
  fileDragOver.value = true;
};

const onDragLeave = () => {
  fileDragOver.value = false;
};

const extractServerError = err => {
  const data = err?.response?.data;
  if (!data) return '';
  if (typeof data === 'string') return data;
  if (data.message) return data.message;
  if (data.error) return data.error;
  if (Array.isArray(data.errors)) return data.errors.join(', ');
  if (data.errors && typeof data.errors === 'object') {
    return Object.entries(data.errors)
      .map(([k, v]) => `${k}: ${Array.isArray(v) ? v.join(', ') : v}`)
      .join('; ');
  }
  return '';
};

const submit = async () => {
  if (!canSubmit.value) return;
  serverError.value = '';
  const payload = { assistantId: props.assistantId };
  if (activeTab.value === 'url') {
    payload.externalLink = urlValue.value.trim();
  } else if (activeTab.value === 'pdf') {
    payload.pdfFile = fileValue.value;
  } else if (markdownFileValue.value) {
    payload.markdownFile = markdownFileValue.value;
  } else {
    payload.markdownContent = markdownContentValue.value;
  }
  try {
    await store.dispatch('pilot/documents/create', payload);
    emit('created');
    close();
  } catch (err) {
    const message = extractServerError(err);
    serverError.value =
      message || t('PILOT_DOCUMENTS.DIALOG.ERRORS.SUBMIT_FAILED');
  }
};

const setTab = id => {
  activeTab.value = id;
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="lg"
    :show-cancel-button="false"
    :show-confirm-button="false"
    :title="t('PILOT_DOCUMENTS.DIALOG.TITLE')"
    :description="t('PILOT_DOCUMENTS.DIALOG.DESCRIPTION')"
  >
    <div class="flex flex-col gap-4">
      <div
        class="inline-flex p-1 rounded-lg bg-n-alpha-1 w-fit gap-1"
        role="tablist"
      >
        <button
          v-for="tab in TABS"
          :key="tab.id"
          type="button"
          role="tab"
          :aria-selected="activeTab === tab.id"
          class="text-sm font-medium px-3 py-1 rounded-md transition-colors"
          :class="
            activeTab === tab.id
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="setTab(tab.id)"
        >
          {{ t(`PILOT_DOCUMENTS.DIALOG.TABS.${tab.key}`) }}
        </button>
      </div>

      <div v-if="activeTab === 'url'" class="flex flex-col gap-2">
        <label
          for="pilot-document-url"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('PILOT_DOCUMENTS.DIALOG.URL.LABEL') }}
        </label>
        <input
          id="pilot-document-url"
          v-model="urlValue"
          type="url"
          autocomplete="off"
          :placeholder="t('PILOT_DOCUMENTS.DIALOG.URL.PLACEHOLDER')"
          class="w-full h-10 px-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-blue-9"
        />
        <p
          v-if="urlValue && !isUrlValid"
          class="text-xs text-n-ruby-11"
          role="alert"
        >
          {{ t('PILOT_DOCUMENTS.DIALOG.URL.INVALID') }}
        </p>
      </div>

      <div v-else-if="activeTab === 'pdf'" class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('PILOT_DOCUMENTS.DIALOG.PDF.LABEL') }}
        </span>
        <label
          class="flex flex-col items-center justify-center gap-2 p-6 rounded-lg border-2 border-dashed cursor-pointer transition-colors"
          :class="
            fileDragOver
              ? 'border-n-blue-9 bg-n-blue-3'
              : 'border-n-container bg-n-solid-1 hover:border-n-slate-9'
          "
          @drop="onDrop"
          @dragover="onDragOver"
          @dragleave="onDragLeave"
        >
          <Icon icon="i-lucide-upload-cloud" class="size-8 text-n-slate-10" />
          <span class="text-sm text-n-slate-11 text-center">
            {{ t('PILOT_DOCUMENTS.DIALOG.PDF.DROPZONE') }}
          </span>
          <input
            ref="fileInputRef"
            type="file"
            accept=".pdf,application/pdf"
            class="sr-only"
            @change="onFileSelected"
          />
        </label>
        <div
          v-if="fileValue"
          class="flex items-center justify-between gap-2 p-2 rounded-md bg-n-alpha-1"
        >
          <span
            class="flex items-center gap-2 text-sm text-n-slate-12 truncate"
          >
            <Icon icon="i-lucide-file-text" class="size-4 text-n-slate-10" />
            <span class="truncate">{{ fileValue.name }}</span>
          </span>
          <button
            type="button"
            class="text-xs text-n-slate-11 hover:text-n-ruby-11"
            @click="fileValue = null"
          >
            {{ t('PILOT_DOCUMENTS.DIALOG.PDF.REMOVE') }}
          </button>
        </div>
        <p
          v-if="fileValue && !isPdfValid"
          class="text-xs text-n-ruby-11"
          role="alert"
        >
          {{ t('PILOT_DOCUMENTS.DIALOG.PDF.INVALID') }}
        </p>
      </div>

      <div v-else class="flex flex-col gap-3">
        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('PILOT_DOCUMENTS.DIALOG.MARKDOWN.LABEL') }}
          </span>
          <label
            class="flex flex-col items-center justify-center gap-2 p-5 rounded-lg border-2 border-dashed cursor-pointer transition-colors border-n-container bg-n-solid-1 hover:border-n-slate-9"
          >
            <Icon icon="i-lucide-file-code" class="size-8 text-n-slate-10" />
            <span class="text-sm text-n-slate-11 text-center">
              {{ t('PILOT_DOCUMENTS.DIALOG.MARKDOWN.DROPZONE') }}
            </span>
            <input
              ref="markdownInputRef"
              type="file"
              accept=".md,text/markdown,text/plain"
              class="sr-only"
              @change="onMarkdownFileSelected"
            />
          </label>
          <div
            v-if="markdownFileValue"
            class="flex items-center justify-between gap-2 p-2 rounded-md bg-n-alpha-1"
          >
            <span
              class="flex items-center gap-2 text-sm text-n-slate-12 truncate"
            >
              <Icon icon="i-lucide-file-text" class="size-4 text-n-slate-10" />
              <span class="truncate">{{ markdownFileValue.name }}</span>
            </span>
            <button
              type="button"
              class="text-xs text-n-slate-11 hover:text-n-ruby-11"
              @click="markdownFileValue = null"
            >
              {{ t('PILOT_DOCUMENTS.DIALOG.MARKDOWN.REMOVE') }}
            </button>
          </div>
          <p
            v-if="markdownFileValue && !isMarkdownFileValid"
            class="text-xs text-n-ruby-11"
            role="alert"
          >
            {{ t('PILOT_DOCUMENTS.DIALOG.MARKDOWN.INVALID_FILE') }}
          </p>
        </div>

        <div v-if="!markdownFileValue" class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('PILOT_DOCUMENTS.DIALOG.MARKDOWN.OR_PASTE') }}
          </span>
          <textarea
            v-model="markdownContentValue"
            rows="5"
            :placeholder="t('PILOT_DOCUMENTS.DIALOG.MARKDOWN.PLACEHOLDER')"
            class="w-full p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-blue-9"
          />
          <p
            class="text-xs"
            :class="
              markdownContentLength > MARKDOWN_MAX_CHARS
                ? 'text-n-ruby-11'
                : 'text-n-slate-10'
            "
          >
            {{
              t('PILOT_DOCUMENTS.DIALOG.MARKDOWN.COUNTER', {
                count: markdownContentLength,
                max: MARKDOWN_MAX_CHARS,
              })
            }}
          </p>
        </div>
      </div>

      <p v-if="!props.assistantId" class="text-xs text-n-amber-11" role="alert">
        {{ t('PILOT_DOCUMENTS.DIALOG.ERRORS.NO_ASSISTANT') }}
      </p>

      <p v-if="serverError" class="text-xs text-n-ruby-11" role="alert">
        {{ serverError }}
      </p>
    </div>

    <template #footer>
      <div class="flex items-center justify-end gap-3 w-full">
        <Button
          type="button"
          variant="faded"
          color="slate"
          :label="t('PILOT_DOCUMENTS.DIALOG.BUTTONS.CANCEL')"
          @click="close"
        />
        <Button
          type="button"
          :label="
            activeTab === 'url'
              ? t('PILOT_DOCUMENTS.DIALOG.BUTTONS.ADD_URL')
              : activeTab === 'pdf'
                ? t('PILOT_DOCUMENTS.DIALOG.BUTTONS.UPLOAD')
                : t('PILOT_DOCUMENTS.DIALOG.BUTTONS.ADD_MARKDOWN')
          "
          :is-loading="isSubmitting"
          :disabled="!canSubmit"
          @click="submit"
        />
      </div>
    </template>
  </Dialog>
</template>
