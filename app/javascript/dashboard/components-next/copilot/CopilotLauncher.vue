<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useCopilotDrawer } from 'dashboard/composables/pilot/useCopilotDrawer';
import { usePilot } from 'dashboard/composables/usePilot';
import PilotFaceIcon from 'dashboard/components-next/pilot/PilotFaceIcon.vue';

const route = useRoute();

const { updateUISettings } = useUISettings();
const drawer = useCopilotDrawer();
const { pilotCopilotEnabled } = usePilot();

const isConversationRoute = computed(() => {
  const CONVERSATION_ROUTES = [
    'inbox_conversation',
    'conversation_through_inbox',
    'conversations_through_label',
    'team_conversations_through_label',
    'conversations_through_folders',
    'conversation_through_mentions',
    'conversation_through_unattended',
    'conversation_through_participating',
    'inbox_view_conversation',
  ];
  return CONVERSATION_ROUTES.includes(route.name);
});

const showCopilotLauncher = computed(
  () =>
    pilotCopilotEnabled.value &&
    !drawer.isOpen.value &&
    !isConversationRoute.value
);
const toggleSidebar = () => {
  updateUISettings({
    is_copilot_panel_open: false,
    is_contact_sidebar_open: false,
  });
  drawer.toggle();
};
</script>

<template>
  <div
    v-if="showCopilotLauncher"
    class="fixed bottom-4 ltr:right-4 rtl:left-4 z-50"
  >
    <ButtonGroup
      class="rounded-full bg-n-alpha-2 backdrop-blur-lg p-1 shadow hover:shadow-md"
    >
      <Button
        no-animation
        class="!rounded-full !bg-n-solid-3 dark:!bg-n-alpha-2 transition-all duration-200 ease-out hover:brightness-110"
        lg
        @click="toggleSidebar"
      >
        <template #icon>
          <PilotFaceIcon class="size-7" />
        </template>
      </Button>
    </ButtonGroup>
  </div>
  <template v-else />
</template>
