<script setup>
import { onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCopilotDrawer } from 'dashboard/composables/pilot/useCopilotDrawer';

const router = useRouter();
const { accountScopedRoute } = useAccount();
const drawer = useCopilotDrawer();

onMounted(() => {
  drawer.open();
  router.replace(accountScopedRoute('home'));
});
</script>

<template><span /></template>
