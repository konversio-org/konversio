<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Icon from '../icon/Icon.vue';

defineProps({
  hasAssistants: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['useSuggestion']);
const { t } = useI18n();
const route = useRoute();

const routePromptMap = {
  conversations: [
    {
      label: 'PILOT.COPILOT.PROMPTS.SUMMARIZE.LABEL',
      prompt: 'PILOT.COPILOT.PROMPTS.SUMMARIZE.CONTENT',
    },
    {
      label: 'PILOT.COPILOT.PROMPTS.SUGGEST.LABEL',
      prompt: 'PILOT.COPILOT.PROMPTS.SUGGEST.CONTENT',
    },
    {
      label: 'PILOT.COPILOT.PROMPTS.RATE.LABEL',
      prompt: 'PILOT.COPILOT.PROMPTS.RATE.CONTENT',
    },
  ],
  dashboard: [
    {
      label: 'PILOT.COPILOT.PROMPTS.HIGH_PRIORITY.LABEL',
      prompt: 'PILOT.COPILOT.PROMPTS.HIGH_PRIORITY.CONTENT',
    },
    {
      label: 'PILOT.COPILOT.PROMPTS.LIST_CONTACTS.LABEL',
      prompt: 'PILOT.COPILOT.PROMPTS.LIST_CONTACTS.CONTENT',
    },
  ],
};

const getCurrentRoute = () => {
  const path = route.path;
  if (path.includes('/conversations')) return 'conversations';
  if (path.includes('/dashboard')) return 'dashboard';
  return 'dashboard';
};

const promptOptions = computed(() => {
  const currentRoute = getCurrentRoute();
  return routePromptMap[currentRoute] || routePromptMap.conversations;
});

const handleSuggestion = opt => {
  emit('useSuggestion', t(opt.prompt));
};
</script>

<template>
  <div class="flex-1 flex flex-col gap-6 px-2">
    <div class="flex flex-col space-y-4 py-4">
      <Icon icon="i-woot-pilot" class="text-n-slate-9 text-4xl" />
      <div class="space-y-1">
        <h3 class="text-base font-medium text-n-slate-12 leading-8">
          {{ $t('PILOT.COPILOT.PANEL_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 leading-6">
          {{ $t('PILOT.COPILOT.KICK_OFF_MESSAGE') }}
        </p>
      </div>
    </div>
    <div v-if="!hasAssistants" class="w-full space-y-2">
      <p class="text-sm text-n-slate-11 leading-6">
        {{ $t('PILOT.ASSISTANTS.NO_ASSISTANTS_AVAILABLE') }}
      </p>
      <router-link
        :to="{
          name: 'pilot_assistants_create_index',
          params: {
            accountId: route.params.accountId,
          },
        }"
        class="text-n-slate-11 underline hover:text-n-slate-12"
      >
        {{ $t('PILOT.ASSISTANTS.ADD_NEW') }}
      </router-link>
    </div>
    <div v-else class="w-full space-y-2">
      <span class="text-xs text-n-slate-10 block">
        {{ $t('PILOT.COPILOT.TRY_THESE_PROMPTS') }}
      </span>
      <div class="space-y-1">
        <button
          v-for="prompt in promptOptions"
          :key="prompt.label"
          class="w-full px-3 py-2 rounded-md border border-n-weak bg-n-slate-2 text-n-slate-11 flex items-center justify-between hover:bg-n-slate-3 transition-colors"
          @click="handleSuggestion(prompt)"
        >
          <span>{{ t(prompt.label) }}</span>
          <Icon icon="i-lucide-chevron-right" />
        </button>
      </div>
    </div>
  </div>
</template>
