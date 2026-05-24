<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  assistant: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['saved', 'cancel']);

const { t } = useI18n();
const store = useStore();
const currentAccount = useMapGetter('getCurrentAccount');
const customTools = useMapGetter('pilot/customTools/getRows');
const customToolsLoading = useMapGetter('pilot/customTools/getLoading');

const isEdit = computed(() => !!props.assistant);
const isSubmitting = ref(false);
const error = ref('');
const isToolsEnabled = computed(
  () => !!currentAccount.value?.pilot_tools_enabled
);
const enabledCustomTools = computed(() =>
  customTools.value.filter(tool => tool.enabled)
);

const name = ref('');
const description = ref('');
const responseGuidelines = ref('');
const guardrails = ref('');
const selectedToolSlugs = ref([]);

// config fields
const productName = ref('');
const featureFaq = ref(true);
const featureMemory = ref(false);
const featureContactAttributes = ref(false);
const featureCitation = ref(true);
const welcomeMessage = ref('');
const handoffMessage = ref('');
const resolutionMessage = ref('');
const instructions = ref('');
const temperature = ref(0.1);

const loadAssistantData = () => {
  if (props.assistant) {
    name.value = props.assistant.name || '';
    description.value = props.assistant.description || '';
    responseGuidelines.value = props.assistant.response_guidelines || '';
    guardrails.value = props.assistant.guardrails || '';

    const config = props.assistant.config || {};
    productName.value = config.product_name || '';
    featureFaq.value = config.feature_faq !== false;
    featureMemory.value = !!config.feature_memory;
    featureContactAttributes.value = !!config.feature_contact_attributes;
    featureCitation.value = config.feature_citation !== false;
    welcomeMessage.value = config.welcome_message || '';
    handoffMessage.value = config.handoff_message || '';
    resolutionMessage.value = config.resolution_message || '';
    instructions.value = config.instructions || '';
    temperature.value =
      config.temperature != null ? Number(config.temperature) : 0.1;
    selectedToolSlugs.value = Array.isArray(props.assistant.enabled_tool_slugs)
      ? [...props.assistant.enabled_tool_slugs]
      : [];
  } else {
    name.value = '';
    description.value = '';
    responseGuidelines.value = '';
    guardrails.value = '';
    productName.value = '';
    featureFaq.value = true;
    featureMemory.value = false;
    featureContactAttributes.value = false;
    featureCitation.value = true;
    welcomeMessage.value = '';
    handoffMessage.value = '';
    resolutionMessage.value = '';
    instructions.value = '';
    temperature.value = 0.1;
    selectedToolSlugs.value = [];
  }
};

const fetchCustomTools = () => {
  store.dispatch('pilot/customTools/fetchPage', { page: 1 }).catch(() => {});
};

watch(() => props.assistant, loadAssistantData, { immediate: true });
watch(
  isToolsEnabled,
  enabled => {
    if (enabled) fetchCustomTools();
  },
  { immediate: true }
);

const submit = async () => {
  if (!name.value.trim()) {
    error.value = t('PILOT.SETTINGS.ERRORS.NAME_REQUIRED');
    return;
  }
  error.value = '';
  isSubmitting.value = true;

  const payload = {
    name: name.value.trim(),
    description: description.value.trim(),
    response_guidelines: responseGuidelines.value.trim(),
    guardrails: guardrails.value.trim(),
    enabled_tool_slugs: selectedToolSlugs.value,
    config: {
      product_name: productName.value.trim(),
      feature_faq: featureFaq.value,
      feature_memory: featureMemory.value,
      feature_contact_attributes: featureContactAttributes.value,
      feature_citation: featureCitation.value,
      welcome_message: welcomeMessage.value.trim(),
      handoff_message: handoffMessage.value.trim(),
      resolution_message: resolutionMessage.value.trim(),
      instructions: instructions.value.trim(),
      temperature: Number(temperature.value),
    },
  };

  try {
    if (isEdit.value) {
      await store.dispatch('pilot/assistants/update', {
        id: props.assistant.id,
        ...payload,
      });
      useAlert(t('PILOT.SETTINGS.TOAST.UPDATED'));
    } else {
      const newAssistant = await store.dispatch(
        'pilot/assistants/create',
        payload
      );
      store.dispatch('pilot/assistants/setActive', newAssistant.id);
      useAlert(t('PILOT.SETTINGS.TOAST.CREATED'));
    }
    emit('saved');
  } catch (err) {
    error.value =
      err?.response?.data?.message ||
      err?.message ||
      t('PILOT.SETTINGS.ERRORS.SAVE_FAILED');
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <form
    class="flex flex-col gap-6 w-full bg-n-solid-1 rounded-xl border border-n-weak p-6"
    @submit.prevent="submit"
  >
    <div class="flex items-center justify-between border-b border-n-weak pb-4">
      <h2 class="text-lg font-medium text-n-slate-12">
        {{
          isEdit
            ? t('PILOT.SETTINGS.FORM.EDIT_TITLE')
            : t('PILOT.SETTINGS.FORM.CREATE_TITLE')
        }}
      </h2>
      <Button
        v-if="!isEdit"
        type="button"
        variant="faded"
        color="slate"
        size="sm"
        :label="t('PILOT.SETTINGS.FORM.CANCEL')"
        @click="emit('cancel')"
      />
    </div>

    <div
      v-if="error"
      class="p-3 rounded-lg bg-n-ruby-3 border border-n-ruby-6 text-sm text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </div>

    <!-- Basic Details -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div class="flex flex-col gap-1.5">
        <label for="assistant-name" class="text-sm font-medium text-n-slate-12">
          {{ t('PILOT.SETTINGS.FORM.NAME_LABEL') }}
        </label>
        <input
          id="assistant-name"
          v-model="name"
          type="text"
          required
          class="w-full h-10 px-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-blue-9"
          :placeholder="t('PILOT.SETTINGS.FORM.NAME_PLACEHOLDER')"
        />
      </div>

      <div class="flex flex-col gap-1.5">
        <label
          for="assistant-product"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('PILOT.SETTINGS.FORM.PRODUCT_LABEL') }}
        </label>
        <input
          id="assistant-product"
          v-model="productName"
          type="text"
          class="w-full h-10 px-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-blue-9"
          :placeholder="t('PILOT.SETTINGS.FORM.PRODUCT_PLACEHOLDER')"
        />
      </div>
    </div>

    <div class="flex flex-col gap-1.5">
      <label for="assistant-desc" class="text-sm font-medium text-n-slate-12">
        {{ t('PILOT.SETTINGS.FORM.DESC_LABEL') }}
      </label>
      <textarea
        id="assistant-desc"
        v-model="description"
        rows="2"
        class="w-full p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-blue-9 resize-y"
        :placeholder="t('PILOT.SETTINGS.FORM.DESC_PLACEHOLDER')"
      />
    </div>

    <!-- LLM Behavior & Configuration -->
    <div class="flex flex-col gap-4 border-t border-n-weak pt-4">
      <h3 class="text-md font-medium text-n-slate-12">
        {{ t('PILOT.SETTINGS.FORM.BEHAVIOR_SECTION') }}
      </h3>

      <div class="flex flex-col gap-1.5">
        <label
          for="assistant-instructions"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('PILOT.SETTINGS.FORM.INSTRUCTIONS_LABEL') }}
        </label>
        <textarea
          id="assistant-instructions"
          v-model="instructions"
          rows="4"
          class="w-full p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-blue-9 resize-y font-mono"
          :placeholder="t('PILOT.SETTINGS.FORM.INSTRUCTIONS_PLACEHOLDER')"
        />
      </div>

      <div class="flex flex-col gap-1.5">
        <label
          for="assistant-guidelines"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('PILOT.SETTINGS.FORM.GUIDELINES_LABEL') }}
        </label>
        <textarea
          id="assistant-guidelines"
          v-model="responseGuidelines"
          rows="3"
          class="w-full p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-blue-9 resize-y"
          :placeholder="t('PILOT.SETTINGS.FORM.GUIDELINES_PLACEHOLDER')"
        />
      </div>

      <div class="flex flex-col gap-1.5">
        <label
          for="assistant-guardrails"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('PILOT.SETTINGS.FORM.GUARDRAILS_LABEL') }}
        </label>
        <textarea
          id="assistant-guardrails"
          v-model="guardrails"
          rows="3"
          class="w-full p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-blue-9 resize-y"
          :placeholder="t('PILOT.SETTINGS.FORM.GUARDRAILS_PLACEHOLDER')"
        />
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="flex flex-col gap-1.5">
          <label
            for="assistant-temp"
            class="text-sm font-medium text-n-slate-12"
          >
            {{
              t('PILOT.SETTINGS.FORM.TEMPERATURE_LABEL') +
              ' (' +
              temperature +
              ')'
            }}
          </label>
          <input
            id="assistant-temp"
            v-model="temperature"
            type="range"
            min="0"
            max="1.5"
            step="0.05"
            class="w-full h-2 bg-n-alpha-1 rounded-lg appearance-none cursor-pointer"
          />
        </div>
      </div>
    </div>

    <!-- Messages & Toggles -->
    <div class="flex flex-col gap-4 border-t border-n-weak pt-4">
      <h3 class="text-md font-medium text-n-slate-12">
        {{ t('PILOT.SETTINGS.FORM.MESSAGES_SECTION') }}
      </h3>

      <div class="flex flex-col gap-1.5">
        <label
          for="assistant-welcome"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('PILOT.SETTINGS.FORM.WELCOME_LABEL') }}
        </label>
        <textarea
          id="assistant-welcome"
          v-model="welcomeMessage"
          rows="2"
          class="w-full p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-blue-9 resize-y"
          :placeholder="t('PILOT.SETTINGS.FORM.WELCOME_PLACEHOLDER')"
        />
      </div>

      <div class="flex flex-col gap-1.5">
        <label
          for="assistant-handoff"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('PILOT.SETTINGS.FORM.HANDOFF_LABEL') }}
        </label>
        <textarea
          id="assistant-handoff"
          v-model="handoffMessage"
          rows="2"
          class="w-full p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-blue-9 resize-y"
          :placeholder="t('PILOT.SETTINGS.FORM.HANDOFF_PLACEHOLDER')"
        />
      </div>

      <div class="flex flex-col gap-1.5">
        <label
          for="assistant-resolution"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('PILOT.SETTINGS.FORM.RESOLUTION_LABEL') }}
        </label>
        <textarea
          id="assistant-resolution"
          v-model="resolutionMessage"
          rows="2"
          class="w-full p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-blue-9 resize-y"
          :placeholder="t('PILOT.SETTINGS.FORM.RESOLUTION_PLACEHOLDER')"
        />
      </div>
    </div>

    <div
      v-if="isToolsEnabled"
      class="flex flex-col gap-4 border-t border-n-weak pt-4"
    >
      <div class="flex flex-col gap-1">
        <h3 class="text-md font-medium text-n-slate-12">
          {{ t('PILOT.SETTINGS.FORM.TOOLS_SECTION') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ t('PILOT.SETTINGS.FORM.TOOLS_SECTION_DESC') }}
        </p>
      </div>

      <div v-if="customToolsLoading" class="text-sm text-n-slate-11">
        {{ t('PILOT.SETTINGS.FORM.TOOLS_LOADING') }}
      </div>

      <div
        v-else-if="enabledCustomTools.length === 0"
        class="text-sm text-n-slate-11"
      >
        {{ t('PILOT.SETTINGS.FORM.TOOLS_EMPTY') }}
      </div>

      <div v-else class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <label
          v-for="tool in enabledCustomTools"
          :key="tool.id"
          class="flex items-start gap-3 cursor-pointer rounded-lg border border-n-container p-3"
        >
          <input
            v-model="selectedToolSlugs"
            :value="tool.slug"
            type="checkbox"
            class="mt-1 rounded border-n-container text-n-blue-9 focus:ring-n-blue-9"
          />
          <span class="min-w-0 flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12 truncate">
              {{ tool.title }}
            </span>
            <span class="text-xs text-n-slate-11 font-mono truncate">
              {{ tool.slug }}
            </span>
          </span>
        </label>
      </div>
    </div>

    <!-- Feature Flags / Toggles -->
    <div class="flex flex-col gap-4 border-t border-n-weak pt-4">
      <h3 class="text-md font-medium text-n-slate-12">
        {{ t('PILOT.SETTINGS.FORM.FEATURES_SECTION') }}
      </h3>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <label class="flex items-center gap-3 cursor-pointer">
          <input
            v-model="featureFaq"
            type="checkbox"
            class="rounded border-n-container text-n-blue-9 focus:ring-n-blue-9"
          />
          <span class="text-sm text-n-slate-12 font-medium">{{
            t('PILOT.SETTINGS.FORM.FEATURE_FAQ')
          }}</span>
        </label>

        <label class="flex items-center gap-3 cursor-pointer">
          <input
            v-model="featureMemory"
            type="checkbox"
            class="rounded border-n-container text-n-blue-9 focus:ring-n-blue-9"
          />
          <span class="text-sm text-n-slate-12 font-medium">{{
            t('PILOT.SETTINGS.FORM.FEATURE_MEMORY')
          }}</span>
        </label>

        <label class="flex items-center gap-3 cursor-pointer">
          <input
            v-model="featureContactAttributes"
            type="checkbox"
            class="rounded border-n-container text-n-blue-9 focus:ring-n-blue-9"
          />
          <span class="text-sm text-n-slate-12 font-medium">{{
            t('PILOT.SETTINGS.FORM.FEATURE_CONTACT_ATTRIBUTES')
          }}</span>
        </label>

        <label class="flex items-center gap-3 cursor-pointer">
          <input
            v-model="featureCitation"
            type="checkbox"
            class="rounded border-n-container text-n-blue-9 focus:ring-n-blue-9"
          />
          <span class="text-sm text-n-slate-12 font-medium">{{
            t('PILOT.SETTINGS.FORM.FEATURE_CITATION')
          }}</span>
        </label>
      </div>
    </div>

    <div
      class="flex items-center justify-end gap-3 border-t border-n-weak pt-4"
    >
      <Button
        type="submit"
        :label="
          isEdit
            ? t('PILOT.SETTINGS.FORM.SAVE')
            : t('PILOT.SETTINGS.FORM.CREATE')
        "
        :is-loading="isSubmitting"
      />
    </div>
  </form>
</template>
