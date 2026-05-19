<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useCopilotDrawer } from 'dashboard/composables/pilot/useCopilotDrawer';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PilotPreferencesAPI from 'dashboard/api/pilot/preferences';
import CopilotThreadList from './CopilotThreadList.vue';
import CopilotMessageList from './CopilotMessageList.vue';

const POLL_INTERVAL_MS = 3000;

const { t } = useI18n();
const store = useStore();
const drawer = useCopilotDrawer();

const threads = useMapGetter('pilot/copilot/getThreads');
const activeThread = useMapGetter('pilot/copilot/getActiveThread');
const activeThreadId = useMapGetter('pilot/copilot/getActiveThreadId');
const messages = useMapGetter('pilot/copilot/getActiveThreadMessages');
const isAwaitingResponse = useMapGetter('pilot/copilot/getIsAwaitingResponse');
const boundConversationId = useMapGetter(
  'pilot/copilot/getBoundConversationId'
);

const inputText = ref('');
const composingNewThread = ref(false);
const pollTimer = ref(null);
const preferences = ref(null);

const SLOT_LABELS = {
  chat: 'Chat',
  embedding: 'Embeddings',
  audio: 'Audio',
};

const slotRows = computed(() => {
  const slots = preferences.value?.active_slots || {};
  return ['chat', 'embedding', 'audio'].map(key => {
    const entry = slots[key];
    const providerLabel = entry?.provider?.label;
    const model = entry?.model;
    const value =
      providerLabel && model ? `${providerLabel} · ${model}` : 'N/A';
    return { key, label: SLOT_LABELS[key], value };
  });
});

const showSlotRows = computed(() =>
  slotRows.value.some(r => r.value !== 'N/A')
);

const fetchPreferences = async () => {
  if (preferences.value) return;
  try {
    const { data } = await PilotPreferencesAPI.fetch();
    preferences.value = data;
  } catch (err) {
    preferences.value = null;
  }
};

const placeholder = computed(() =>
  composingNewThread.value || !activeThreadId.value
    ? t('PILOT.COPILOT.NEW_THREAD_PLACEHOLDER')
    : t('PILOT.COPILOT.REPLY_PLACEHOLDER')
);

const stopPolling = () => {
  if (pollTimer.value) {
    clearInterval(pollTimer.value);
    pollTimer.value = null;
  }
};

const startPollingForActive = () => {
  stopPolling();
  if (!activeThreadId.value) return;
  pollTimer.value = setInterval(() => {
    if (!isAwaitingResponse.value) {
      stopPolling();
      return;
    }
    store.dispatch('pilot/copilot/fetchMessages', activeThreadId.value);
  }, POLL_INTERVAL_MS);
};

watch(isAwaitingResponse, value => {
  if (value) startPollingForActive();
  else stopPolling();
});

watch(
  () => drawer.isOpen.value,
  open => {
    if (!open) {
      stopPolling();
      return;
    }
    // Refresh threads when drawer opens
    store.dispatch('pilot/copilot/fetchThreads');
    fetchPreferences();
    if (activeThreadId.value) {
      store.dispatch('pilot/copilot/fetchMessages', activeThreadId.value);
    } else {
      composingNewThread.value = true;
    }
  }
);

const handleSelectThread = id => {
  composingNewThread.value = false;
  store.dispatch('pilot/copilot/setActiveThread', id);
};

const handleNewThread = () => {
  composingNewThread.value = true;
  store.dispatch('pilot/copilot/setActiveThread', null);
  inputText.value = '';
};

const handleClose = () => {
  drawer.close();
};

const handleSubmit = async () => {
  const content = inputText.value.trim();
  if (!content) return;
  inputText.value = '';
  try {
    if (composingNewThread.value || !activeThreadId.value) {
      await store.dispatch('pilot/copilot/createThread', {
        message: content,
        conversationId: boundConversationId.value || undefined,
      });
      composingNewThread.value = false;
    } else {
      await store.dispatch('pilot/copilot/postMessage', {
        threadId: activeThreadId.value,
        message: content,
        conversationId: boundConversationId.value || undefined,
      });
    }
  } catch (err) {
    // Restore the input so the agent does not lose their text
    inputText.value = content;
  }
};

const handleKeydown = event => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    handleSubmit();
  }
};

onMounted(() => {
  if (drawer.isOpen.value) {
    store.dispatch('pilot/copilot/fetchThreads');
    fetchPreferences();
  }
});

onUnmounted(() => {
  stopPolling();
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-transform duration-200 ease-out"
      enter-from-class="translate-x-full"
      enter-to-class="translate-x-0"
      leave-active-class="transition-transform duration-150 ease-in"
      leave-from-class="translate-x-0"
      leave-to-class="translate-x-full"
    >
      <aside
        v-if="drawer.isOpen.value"
        class="fixed top-0 ltr:right-0 rtl:left-0 h-full w-[420px] max-w-[90vw] z-50 bg-n-background border-l border-n-weak flex flex-col shadow-xl"
        role="dialog"
        :aria-label="t('PILOT.COPILOT.DRAWER_TITLE')"
      >
        <header
          class="flex items-center justify-between px-4 py-3 border-b border-n-weak flex-shrink-0"
        >
          <div class="flex items-center gap-2">
            <span class="i-ph-robot text-n-violet-9 size-5" />
            <span class="font-medium text-n-slate-12">
              {{ t('PILOT.COPILOT.DRAWER_TITLE') }}
            </span>
          </div>
          <NextButton
            ghost
            sm
            icon="i-lucide-x"
            :aria-label="t('PILOT.COPILOT.CLOSE')"
            @click="handleClose"
          />
        </header>

        <div
          v-if="showSlotRows"
          class="px-4 py-2 text-xs text-n-slate-10 border-b border-n-weak space-y-0.5"
        >
          <div v-for="row in slotRows" :key="row.key" class="flex gap-2">
            <span class="text-n-slate-9 w-20 flex-shrink-0">
              {{ row.label }}
            </span>
            <span class="font-mono">{{ row.value }}</span>
          </div>
        </div>

        <div
          v-if="boundConversationId"
          class="px-4 py-2 text-xs text-n-violet-11 bg-n-violet-2 border-b border-n-weak"
        >
          {{
            t('PILOT.COPILOT.BOUND_CONVERSATION_INTRO', {
              id: boundConversationId,
            })
          }}
        </div>

        <CopilotThreadList
          :threads="threads"
          :active-thread-id="activeThreadId"
          @select="handleSelectThread"
          @new="handleNewThread"
        />

        <CopilotMessageList
          :messages="messages"
          :is-awaiting-response="isAwaitingResponse"
        />

        <footer
          class="border-t border-n-weak px-3 py-3 flex flex-col gap-2 flex-shrink-0"
        >
          <textarea
            v-model="inputText"
            :placeholder="placeholder"
            rows="2"
            class="w-full resize-none rounded-md border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:border-n-violet-9"
            @keydown="handleKeydown"
          />
          <div class="flex justify-between items-center">
            <span class="text-xs text-n-slate-10">
              {{
                activeThread?.title
                  ? activeThread.title
                  : t('PILOT.COPILOT.NEW_THREAD')
              }}
            </span>
            <NextButton
              solid
              sm
              :label="t('PILOT.COPILOT.SEND')"
              :disabled="!inputText.trim() || isAwaitingResponse"
              class="bg-n-violet-9 hover:enabled:!bg-n-violet-10"
              @click="handleSubmit"
            />
          </div>
        </footer>
      </aside>
    </Transition>
  </Teleport>
</template>
