<script setup>
import { computed } from 'vue';
import { IFrameHelper } from 'widget/helpers/utils';
import { KONVERSIO_ON_START_CONVERSATION } from '../constants/sdkEvents';
import AvailabilityContainer from 'widget/components/Availability/AvailabilityContainer.vue';
import { useMapGetter } from 'dashboard/composables/store.js';

const props = defineProps({
  availableAgents: { type: Array, default: () => [] },
  hasConversation: { type: Boolean, default: false },
  unreadCount: { type: Number, default: 0 },
});

const emit = defineEmits(['startConversation']);

const widgetColor = useMapGetter('appConfig/getWidgetColor');
const hasUnreadMessages = computed(() => props.unreadCount > 0);

const startConversation = () => {
  emit('startConversation');
  if (!props.hasConversation) {
    IFrameHelper.sendMessage({
      event: 'onEvent',
      eventIdentifier: KONVERSIO_ON_START_CONVERSATION,
      data: { hasConversation: false },
    });
  }
};
</script>

<template>
  <div
    class="flex flex-col gap-3 w-full shadow outline-1 outline outline-n-container rounded-xl bg-n-background dark:bg-n-solid-2 px-5 py-4"
  >
    <AvailabilityContainer :agents="availableAgents" show-header show-avatars />

    <button
      class="inline-flex items-center justify-between gap-2 font-medium text-n-slate-12 text-left"
      :style="{ color: widgetColor }"
      @click="startConversation"
    >
      <span class="truncate">
        {{
          hasUnreadMessages
            ? $t('UNREAD_VIEW.VIEW_MESSAGES_BUTTON')
            : hasConversation
              ? $t('CONTINUE_CONVERSATION')
              : $t('START_CONVERSATION')
        }}
      </span>
      <i class="i-lucide-chevron-right size-5 shrink-0 mt-px" />
    </button>
    <p
      v-if="hasUnreadMessages"
      class="m-0 text-sm leading-5 text-n-slate-11"
      aria-live="polite"
    >
      {{ $t('VIEW_UNREAD_MESSAGES') }}
    </p>
  </div>
</template>
