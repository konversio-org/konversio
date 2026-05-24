<script setup>
import { computed } from 'vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
  label: { type: String, default: '' },
  placeholder: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);

const value = computed({
  get: () => props.modelValue,
  set: val => emit('update:modelValue', val),
});
</script>

<template>
  <div class="flex flex-col gap-1">
    <label v-if="label" class="mb-0.5 text-heading-3 text-n-slate-12">
      {{ label }}
    </label>
    <textarea
      v-model="value"
      rows="4"
      :placeholder="placeholder"
      class="block w-full font-mono text-sm reset-base outline outline-1 border-none border-0 outline-offset-[-1px] rounded-lg bg-n-alpha-black2 placeholder:text-n-slate-10 dark:placeholder:text-n-slate-10 disabled:cursor-not-allowed disabled:opacity-50 text-n-slate-12 outline-n-weak focus:outline-n-brand focus:outline-offset-[-1px] !px-3 !py-2.5 resize-y transition-all duration-500 ease-in-out"
    />
  </div>
</template>
