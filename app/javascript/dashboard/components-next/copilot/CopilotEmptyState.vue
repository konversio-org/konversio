<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Icon from '../icon/Icon.vue';
import PilotFaceIcon from 'dashboard/components-next/pilot/PilotFaceIcon.vue';

defineProps({
  hasAssistants: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['useSuggestion']);
const { t } = useI18n();
const route = useRoute();

const getCurrentRoute = () => {
  const path = route.path;
  if (path.includes('/conversations')) return 'conversations';
  if (path.includes('/dashboard')) return 'dashboard';
  return 'dashboard';
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

const promptOptions = computed(() => {
  const currentRoute = getCurrentRoute();
  if (currentRoute === 'conversations') return conversationPromptOptions.value;
  return dashboardPromptOptions.value;
});

const handleSuggestion = opt => {
  emit('useSuggestion', opt.prompt);
};
</script>

<template>
  <div class="flex-1 flex flex-col gap-6 px-2">
    <div class="flex flex-col space-y-4 py-4">
      <div
        class="flex size-14 items-center justify-center rounded-2xl bg-n-alpha-2"
      >
        <PilotFaceIcon class="h-10 w-11" />
      </div>
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
          <span>{{ prompt.label }}</span>
          <Icon icon="i-lucide-chevron-right" />
        </button>
      </div>
    </div>
  </div>
</template>
