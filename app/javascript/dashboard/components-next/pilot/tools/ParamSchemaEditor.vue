<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ParamRowCard from './ParamRowCard.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';

const props = defineProps({
  modelValue: {
    type: Array,
    default: () => [],
  },
  serverErrors: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const rowRefs = ref([]);

const setRowRef = (el, idx) => {
  if (el) {
    rowRefs.value[idx] = el;
  }
};

const addParameter = () => {
  const updated = [
    ...props.modelValue,
    { name: '', type: 'string', description: '', required: false },
  ];
  emit('update:modelValue', updated);
};

const deleteParameter = index => {
  const updated = [...props.modelValue];
  updated.splice(index, 1);
  emit('update:modelValue', updated);
  rowRefs.value.splice(index, 1);
};

const handleParamChange = (index, value) => {
  const updated = [...props.modelValue];
  updated[index] = value;
  emit('update:modelValue', updated);
};

const validate = () => {
  let allValid = true;
  for (let i = 0; i < props.modelValue.length; i += 1) {
    const rowEl = rowRefs.value[i];
    if (rowEl && typeof rowEl.validate === 'function') {
      const isValid = rowEl.validate();
      if (!isValid) {
        allValid = false;
      }
    }
  }
  return allValid;
};

defineExpose({
  validate,
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex items-center justify-between">
      <span class="text-heading-3 text-n-slate-12">
        {{ t('PILOT.TOOLS.DIALOG.FIELD_PARAMS_HEADER') }}
      </span>
    </div>

    <!-- Parameter list -->
    <div v-if="modelValue.length > 0" class="flex flex-col gap-3">
      <ParamRowCard
        v-for="(param, index) in modelValue"
        :key="index"
        :ref="el => setRowRef(el, index)"
        :model-value="param"
        :index="index"
        :server-error="serverErrors[index] || ''"
        @update:model-value="handleParamChange(index, $event)"
        @delete="deleteParameter(index)"
      />
    </div>

    <!-- Add Parameter button -->
    <button
      type="button"
      class="flex items-center justify-center gap-2 h-10 px-4 rounded-xl border border-dashed border-n-weak hover:border-n-slate-6 text-sm text-n-slate-11 hover:text-n-slate-12 bg-transparent transition-colors focus:outline-none"
      @click="addParameter"
    >
      <FluentIcon icon="add" size="16" />
      {{ t('PILOT.TOOLS.DIALOG.FIELD_PARAMS_ADD') }}
    </button>
  </div>
</template>
