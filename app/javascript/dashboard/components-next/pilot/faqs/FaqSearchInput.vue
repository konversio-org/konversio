<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';

const props = defineProps({
  modelValue: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue', 'update:search']);

const { t } = useI18n();

const localValue = ref(props.modelValue);

watch(
  () => props.modelValue,
  next => {
    if (next !== localValue.value) localValue.value = next || '';
  }
);

const emitDebounced = debounce(
  value => {
    emit('update:modelValue', value);
    emit('update:search', value);
  },
  300,
  false
);

const onInput = event => {
  const value = event.target.value;
  localValue.value = value;
  emitDebounced(value);
};
</script>

<template>
  <div class="relative flex items-center w-full min-w-0">
    <span
      aria-hidden="true"
      class="i-lucide-search absolute ltr:left-3 rtl:right-3 top-1/2 -translate-y-1/2 size-4 text-n-slate-10 pointer-events-none"
    />
    <input
      :value="localValue"
      type="search"
      :placeholder="t('PILOT.FAQS.SEARCH_PLACEHOLDER')"
      :aria-label="t('PILOT.FAQS.SEARCH_PLACEHOLDER')"
      class="reset-base block w-full h-10 ltr:pl-10 rtl:pr-10 ltr:pr-3 rtl:pl-3 text-sm rounded-lg outline outline-1 outline-offset-[-1px] outline-n-weak bg-n-alpha-black2 placeholder:text-n-slate-10 text-n-slate-12 focus:outline-n-brand"
      @input="onInput"
    />
  </div>
</template>
