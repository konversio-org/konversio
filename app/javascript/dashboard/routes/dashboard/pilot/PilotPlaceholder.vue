<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

const route = useRoute();
const { t } = useI18n();

const sectionLabel = computed(() => {
  const meta = route.meta || {};
  return meta.pilotSection ? t(meta.pilotSection) : t('SIDEBAR.PILOT');
});
</script>

<template>
  <section
    class="flex flex-col items-center justify-center flex-1 gap-2 p-8 text-center"
  >
    <span class="i-ph-robot size-12 text-n-slate-9" />
    <h1 class="text-heading-md text-n-slate-12">
      {{ sectionLabel }}
    </h1>
    <p class="text-body-medium text-n-slate-10">
      {{ t('SIDEBAR.PILOT_PLACEHOLDER_BODY') }}
    </p>
  </section>
</template>
