<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  isAdmin: { type: Boolean, default: false },
});

const emit = defineEmits(['create']);

const { t } = useI18n();

const onCreate = () => emit('create');
</script>

<template>
  <header
    class="flex flex-row flex-wrap items-center justify-between gap-4 pb-4 border-b border-n-weak"
  >
    <div class="flex flex-col gap-1 text-start">
      <h1 class="text-heading-md font-medium text-n-slate-12">
        {{ t('PILOT.TOOLS.PAGE_TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-10 mb-0 leading-normal">
        {{ t('PILOT.TOOLS.SCOPE_HINT') }}
      </p>
    </div>
    <div v-if="isAdmin" class="flex items-center justify-end gap-3">
      <Button
        :label="t('PILOT.TOOLS.CREATE_BUTTON')"
        icon="i-lucide-plus"
        color="blue"
        class="flex-shrink-0"
        @click="onCreate"
      />
    </div>
  </header>
</template>
