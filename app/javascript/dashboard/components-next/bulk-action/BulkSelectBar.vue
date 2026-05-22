<script setup>
import { computed } from 'vue';
import Checkbox from '../checkbox/Checkbox.vue';

const props = defineProps({
  modelValue: {
    type: Set,
    required: true,
  },
  allItems: {
    type: Array,
    default: () => [],
  },
  selectAllLabel: {
    type: String,
    default: '',
  },
  selectedCountLabel: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:modelValue']);

const isAllSelected = computed(() => {
  if (props.allItems.length === 0) return false;
  return props.allItems.every(item => props.modelValue.has(item.id));
});

const isIndeterminate = computed(() => {
  return props.modelValue.size > 0 && !isAllSelected.value;
});

const handleSelectAllChange = checked => {
  const nextSet = new Set(props.modelValue);
  if (checked) {
    props.allItems.forEach(item => nextSet.add(item.id));
  } else {
    props.allItems.forEach(item => nextSet.delete(item.id));
  }
  emit('update:modelValue', nextSet);
};
</script>

<template>
  <div
    class="flex items-center gap-3 bg-n-solid-1 border border-n-weak rounded-xl px-4 py-2.5 shadow-sm w-full"
  >
    <Checkbox
      :model-value="isAllSelected"
      :indeterminate="isIndeterminate"
      @change="handleSelectAllChange"
    />
    <span class="text-sm font-medium text-n-slate-12">
      {{ modelValue.size > 0 ? selectedCountLabel : selectAllLabel }}
    </span>
    <div class="flex items-center gap-1.5">
      <slot name="secondary-actions" />
      <slot name="secondaryActions" />
    </div>
    <div class="flex items-center gap-2 ml-auto">
      <slot name="actions" />
    </div>
  </div>
</template>
