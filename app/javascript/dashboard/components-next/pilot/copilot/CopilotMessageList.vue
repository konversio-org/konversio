<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import PilotFaceIcon from 'dashboard/components-next/pilot/PilotFaceIcon.vue';

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

const emit = defineEmits(['useSuggestion']);

const { t } = useI18n();
const route = useRoute();
const scrollContainer = ref(null);
const expandedStepGroups = ref({});

const messageTypeLabel = type => {
  if (type === 0) return 'user';
  if (type === 1) return 'assistant';
  if (type === 2) return 'thinking';
  return 'unknown';
};

const hasMessages = computed(() => props.messages.length > 0);

const renderItems = computed(() => {
  const items = [];
  let pendingSteps = [];
  const flushSteps = anchorId => {
    if (!pendingSteps.length) return;
    items.push({
      kind: 'steps',
      id: `steps-${anchorId}`,
      steps: pendingSteps,
    });
    pendingSteps = [];
  };
  props.messages.forEach(msg => {
    const label = messageTypeLabel(msg.message_type);
    if (label === 'thinking') {
      pendingSteps.push(msg);
    } else if (label === 'assistant') {
      flushSteps(msg.id);
      items.push({ kind: 'assistant', id: msg.id, msg });
    } else if (label === 'user') {
      flushSteps(`before-${msg.id}`);
      items.push({ kind: 'user', id: msg.id, msg });
    }
  });
  flushSteps('trailing');
  return items;
});

const toggleStepGroup = id => {
  expandedStepGroups.value = {
    ...expandedStepGroups.value,
    [id]: !expandedStepGroups.value[id],
  };
};
const conversationPromptOptions = computed(() => [
  {
    label: t('PILOT.COPILOT.PROMPTS.SUMMARIZE.LABEL'),
    prompt: t('PILOT.COPILOT.PROMPTS.SUMMARIZE.CONTENT'),
  },
  {
    label: t('PILOT.COPILOT.PROMPTS.SUGGEST.LABEL'),
    prompt: t('PILOT.COPILOT.PROMPTS.SUGGEST.CONTENT'),
  },
  {
    label: t('PILOT.COPILOT.PROMPTS.RATE.LABEL'),
    prompt: t('PILOT.COPILOT.PROMPTS.RATE.CONTENT'),
  },
]);

const dashboardPromptOptions = computed(() => [
  {
    label: t('PILOT.COPILOT.PROMPTS.HIGH_PRIORITY.LABEL'),
    prompt: t('PILOT.COPILOT.PROMPTS.HIGH_PRIORITY.CONTENT'),
  },
  {
    label: t('PILOT.COPILOT.PROMPTS.LIST_CONTACTS.LABEL'),
    prompt: t('PILOT.COPILOT.PROMPTS.LIST_CONTACTS.CONTENT'),
  },
]);

const promptOptions = computed(() =>
  route.path.includes('/conversations')
    ? conversationPromptOptions.value
    : dashboardPromptOptions.value
);

const scrollToBottom = () => {
  nextTick(() => {
    const el = scrollContainer.value;
    if (el) el.scrollTop = el.scrollHeight;
  });
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
      class="flex flex-1 flex-col justify-between gap-8 py-4"
    >
      <div class="flex flex-col gap-4">
        <div
          class="flex size-14 items-center justify-center rounded-2xl bg-n-alpha-2"
        >
          <PilotFaceIcon class="h-10 w-11" />
        </div>
        <div class="space-y-1">
          <h3 class="text-base font-medium leading-7 text-n-slate-12">
            {{ t('PILOT.COPILOT.PANEL_TITLE') }}
          </h3>
          <p class="text-sm leading-6 text-n-slate-11">
            {{ t('PILOT.COPILOT.KICK_OFF_MESSAGE') }}
          </p>
        </div>
      </div>

      <div class="space-y-2">
        <span class="block text-xs text-n-slate-10">
          {{ t('PILOT.COPILOT.TRY_THESE_PROMPTS') }}
        </span>
        <div class="space-y-1">
          <button
            v-for="prompt in promptOptions"
            :key="prompt.label"
            type="button"
            class="flex w-full items-center justify-between rounded-md border border-n-weak bg-n-slate-2 px-3 py-2 text-left text-sm text-n-slate-11 transition-colors hover:bg-n-slate-3 hover:text-n-slate-12"
            @click="emit('useSuggestion', prompt.prompt)"
          >
            <span>{{ prompt.label }}</span>
            <span class="i-lucide-chevron-right size-4 flex-shrink-0" />
          </button>
        </div>
      </div>
    </div>

    <template v-for="item in renderItems" :key="item.id">
      <!-- User message -->
      <div
        v-if="item.kind === 'user'"
        class="self-end max-w-[85%] rounded-lg bg-n-violet-3 text-n-violet-12 px-3 py-2 text-sm whitespace-pre-wrap break-words"
      >
        {{ item.msg.message?.content }}
      </div>

      <!-- Assistant message -->
      <div
        v-else-if="item.kind === 'assistant'"
        class="self-start max-w-[85%] rounded-lg bg-n-alpha-2 text-n-slate-12 px-3 py-2 text-sm whitespace-pre-wrap break-words"
      >
        {{ item.msg.message?.content }}
      </div>

      <!-- Grouped steps (one per user→assistant exchange) -->
      <div
        v-else-if="item.kind === 'steps'"
        class="self-stretch rounded-md border border-n-weak bg-n-alpha-1 text-sm"
      >
        <button
          type="button"
          class="w-full flex items-center gap-2 px-3 py-2 text-left text-n-slate-11 hover:text-n-slate-12"
          @click="toggleStepGroup(item.id)"
        >
          <span
            class="size-4 flex-shrink-0"
            :class="
              expandedStepGroups[item.id]
                ? 'i-lucide-chevron-down'
                : 'i-lucide-chevron-right'
            "
          />
          <span>{{ t('PILOT.COPILOT.SHOW_STEPS') }}</span>
          <span
            class="ml-1 inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-n-alpha-2 text-xs text-n-slate-11"
          >
            {{ item.steps.length }}
          </span>
        </button>
        <ul
          v-if="expandedStepGroups[item.id]"
          class="border-t border-n-weak px-3 py-2 space-y-1.5"
        >
          <li
            v-for="step in item.steps"
            :key="step.id"
            class="flex items-start gap-2 text-xs text-n-slate-11"
          >
            <span class="i-lucide-sparkles size-3.5 mt-0.5 flex-shrink-0" />
            <span class="whitespace-pre-wrap break-words">
              {{ step.message?.content }}
            </span>
          </li>
        </ul>
      </div>
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
