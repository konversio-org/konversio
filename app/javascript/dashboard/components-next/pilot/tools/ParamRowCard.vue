<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';

const props = defineProps({
  modelValue: {
    type: Object,
    required: false,
    default: () => ({
      name: '',
      type: 'string',
      description: '',
      required: false,
    }),
  },
  index: {
    type: Number,
    required: true,
  },
  serverError: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:modelValue', 'delete']);

const { t } = useI18n();

const hasError = ref(false);
const errorMsg = ref('');
const isWiggling = ref(false);

const triggerWiggle = () => {
  isWiggling.value = true;
  setTimeout(() => {
    isWiggling.value = false;
  }, 500);
};

const validate = () => {
  if (!props.modelValue.name || !props.modelValue.name.trim()) {
    hasError.value = true;
    errorMsg.value = t('PILOT.TOOLS.DIALOG.FIELD_PARAM_NAME_REQUIRED');
    triggerWiggle();
    return false;
  }
  hasError.value = false;
  errorMsg.value = '';
  return true;
};

const handleFieldChange = (field, val) => {
  hasError.value = false;
  errorMsg.value = '';
  emit('update:modelValue', {
    ...props.modelValue,
    [field]: val,
  });
};

watch(
  () => props.serverError,
  newError => {
    if (newError) {
      hasError.value = true;
      errorMsg.value = newError;
      triggerWiggle();
    }
  },
  { immediate: true }
);

const types = ['string', 'number', 'integer', 'boolean', 'array', 'object'];

defineExpose({
  validate,
  hasError,
});
</script>

<template>
  <div
    class="relative p-4 border rounded-xl bg-n-alpha-black2 flex flex-col gap-3 transition-all duration-300"
    :class="[
      hasError
        ? 'border-n-ruby-8 bg-n-ruby-1'
        : 'border-n-weak hover:border-n-slate-6',
      isWiggling ? 'animate-wiggle' : '',
    ]"
  >
    <!-- Trash button top-right -->
    <button
      type="button"
      class="absolute right-3 top-3 text-n-slate-10 hover:text-n-ruby-9 transition-colors focus:outline-none"
      @click="emit('delete')"
    >
      <FluentIcon icon="dismiss" size="18" />
    </button>

    <!-- Row 1: Name and Type -->
    <div class="flex gap-4 mr-6">
      <div class="flex-1">
        <Input
          :model-value="modelValue.name"
          type="text"
          :label="t('PILOT.TOOLS.DIALOG.FIELD_PARAM_NAME')"
          :placeholder="t('PILOT.TOOLS.DIALOG.FIELD_PARAM_NAME_PLACEHOLDER')"
          :message="hasError ? errorMsg : ''"
          message-type="error"
          @update:model-value="handleFieldChange('name', $event)"
        />
      </div>
      <div class="w-1/3 min-w-[120px] flex flex-col gap-1">
        <label class="mb-0.5 text-heading-3 text-n-slate-12">
          {{ t('PILOT.TOOLS.DIALOG.FIELD_PARAM_TYPE') }}
        </label>
        <select
          :value="modelValue.type"
          class="block w-full h-10 reset-base text-sm !mb-0 outline outline-1 border-none border-0 outline-offset-[-1px] rounded-lg bg-n-alpha-black2 text-n-slate-12 outline-n-weak focus:outline-n-brand px-3 cursor-pointer"
          @change="handleFieldChange('type', $event.target.value)"
        >
          <option v-for="tType in types" :key="tType" :value="tType">
            {{ tType }}
          </option>
        </select>
      </div>
    </div>

    <!-- Row 2: Description -->
    <div>
      <Input
        :model-value="modelValue.description"
        type="text"
        :label="t('PILOT.TOOLS.DIALOG.FIELD_PARAM_DESC')"
        :placeholder="t('PILOT.TOOLS.DIALOG.FIELD_PARAM_DESC_PLACEHOLDER')"
        @update:model-value="handleFieldChange('description', $event)"
      />
    </div>

    <!-- Row 3: Required Checkbox -->
    <div class="flex items-center gap-2 mt-1">
      <input
        :id="`param-req-${index}`"
        type="checkbox"
        :checked="modelValue.required"
        class="rounded border-n-weak text-n-brand focus:ring-n-brand bg-transparent cursor-pointer w-4 h-4"
        @change="handleFieldChange('required', $event.target.checked)"
      />
      <label
        :for="`param-req-${index}`"
        class="text-sm text-n-slate-12 cursor-pointer select-none"
      >
        {{ t('PILOT.TOOLS.DIALOG.FIELD_PARAM_REQUIRED') }}
      </label>
    </div>
  </div>
</template>
