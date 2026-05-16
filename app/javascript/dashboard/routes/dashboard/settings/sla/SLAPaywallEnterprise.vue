<script setup>
import BasePaywallModal from 'dashboard/routes/dashboard/settings/components/BasePaywallModal.vue';

const props = defineProps({
  isSuperAdmin: {
    type: Boolean,
    default: false,
  },
  isOnPilotCloud: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['upgrade']);
const i18nKey = props.isOnPilotCloud ? 'PAYWALL' : 'ENTERPRISE_PAYWALL';
</script>

<template>
  <div class="pb-6 pt-10 flex justify-center">
    <BasePaywallModal
      feature-prefix="SLA"
      :i18n-key="i18nKey"
      :is-on-chatwoot-cloud="isOnPilotCloud"
      :is-super-admin="isSuperAdmin"
      @upgrade="emit('upgrade')"
    />
  </div>
</template>
