<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  messages: {
    type: Array,
    default: () => [],
  },
  isAwaitingResponse: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const scrollContainer = ref(null);
const expandedThinking = ref({});

const messageTypeLabel = type => {
  if (type === 0) return 'user';
  if (type === 1) return 'assistant';
  if (type === 2) return 'thinking';
  return 'unknown';
};

const hasMessages = computed(() => props.messages.length > 0);

const scrollToBottom = () => {
  nextTick(() => {
    const el = scrollContainer.value;
    if (el) el.scrollTop = el.scrollHeight;
  });
};

const toggleThinking = id => {
  expandedThinking.value = {
    ...expandedThinking.value,
    [id]: !expandedThinking.value[id],
  };
};

watch(
  () => props.messages.length,
  () => scrollToBottom()
);

watch(
  () => props.isAwaitingResponse,
  () => scrollToBottom()
);
</script>

<template>
  <div
    ref="scrollContainer"
    class="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-3"
  >
    <div
      v-if="!hasMessages && !isAwaitingResponse"
      class="text-n-slate-10 text-sm text-center py-8"
    >
      {{ t('PILOT.COPILOT.EMPTY_STATE') }}
    </div>

    <template v-for="msg in messages" :key="msg.id">
      <!-- User message -->
      <div
        v-if="messageTypeLabel(msg.message_type) === 'user'"
        class="self-end max-w-[85%] rounded-lg bg-n-violet-3 text-n-violet-12 px-3 py-2 text-sm whitespace-pre-wrap break-words"
      >
        {{ msg.message?.content }}
      </div>

      <!-- Assistant message -->
      <div
        v-else-if="messageTypeLabel(msg.message_type) === 'assistant'"
        class="self-start max-w-[85%] rounded-lg bg-n-alpha-2 text-n-slate-12 px-3 py-2 text-sm whitespace-pre-wrap break-words"
      >
        {{ msg.message?.content }}
      </div>

      <!-- Assistant thinking (collapsed by default) -->
      <button
        v-else-if="messageTypeLabel(msg.message_type) === 'thinking'"
        type="button"
        class="self-start max-w-[85%] text-left text-xs text-n-slate-10 italic hover:text-n-slate-12 flex items-start gap-1"
        @click="toggleThinking(msg.id)"
      >
        <span
          class="mt-0.5 flex-shrink-0"
          :class="
            expandedThinking[msg.id]
              ? 'i-lucide-chevron-down'
              : 'i-lucide-chevron-right'
          "
        />
        <span v-if="!expandedThinking[msg.id]" class="line-clamp-1">
          {{ msg.message?.content }}
        </span>
        <span v-else class="whitespace-pre-wrap break-words">
          {{ msg.message?.content }}
        </span>
      </button>
    </template>

    <!-- Pending placeholder while we wait for assistant -->
    <div
      v-if="isAwaitingResponse"
      class="self-start max-w-[85%] rounded-lg bg-n-alpha-2 text-n-slate-10 px-3 py-2 text-sm flex items-center gap-2"
    >
      <span class="i-lucide-loader-2 size-4 animate-spin" />
      <span>{{ t('PILOT.COPILOT.PENDING') }}</span>
    </div>
  </div>
</template>
