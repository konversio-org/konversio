<script setup>
import { computed } from 'vue';
import { CONVERSATION_STATUS } from 'shared/constants/messages';

const props = defineProps({
  status: { type: String, default: '' },
});

// Status → pill palette. Mirrors the color tokens used by the shared
// Label component (-2/-4/-11 scale) so the chip sits consistently in the
// design system. open=teal, pending=amber, resolved=slate, snoozed=blue.
const STATUS_CONFIG = {
  [CONVERSATION_STATUS.OPEN]: {
    pill: 'bg-n-teal-2 outline-n-teal-4 text-n-teal-11',
    dot: 'bg-n-teal-9',
  },
  [CONVERSATION_STATUS.PENDING]: {
    pill: 'bg-n-amber-2 outline-n-amber-4 text-n-amber-11',
    dot: 'bg-n-amber-9',
  },
  [CONVERSATION_STATUS.RESOLVED]: {
    pill: 'bg-n-slate-3 outline-n-slate-5 text-n-slate-11',
    dot: 'bg-n-slate-9',
  },
  [CONVERSATION_STATUS.SNOOZED]: {
    pill: 'bg-n-blue-2 outline-n-blue-4 text-n-blue-11',
    dot: 'bg-n-blue-9',
  },
};

const config = computed(() => STATUS_CONFIG[props.status]);
</script>

<template>
  <div
    v-if="config"
    class="inline-flex items-center flex-shrink-0 gap-1 px-1.5 h-4 rounded outline outline-1 -outline-offset-1"
    :class="config.pill"
  >
    <span class="rounded-full size-1.5 flex-shrink-0" :class="config.dot" />
    <span class="text-xxs font-medium leading-none whitespace-nowrap">
      {{ $t(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${status}.TEXT`) }}
    </span>
  </div>
</template>
