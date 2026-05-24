<script setup>
import { computed, onMounted, ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import AssistantPicker from 'dashboard/components-next/pilot/shared/AssistantPicker.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();

const activeAssistantId = useMapGetter('pilot/assistants/getActiveId');
const assistants = useMapGetter('pilot/assistants/getRecords');
const uiFlags = useMapGetter('pilot/autopilot/getUIFlags');

const selectedAssistantId = ref(activeAssistantId.value);
const messageText = ref('');
const history = ref([]);
const error = ref('');
const messagesContainerRef = ref(null);

const isSending = computed(() => uiFlags.value.isSendingPlayground);

const clearHistory = () => {
  history.value = [];
  error.value = '';
};

onMounted(async () => {
  if (!assistants.value.length) {
    try {
      await store.dispatch('pilot/assistants/fetch');
    } catch (_e) {
      // Handled
    }
  }
  if (!selectedAssistantId.value && assistants.value.length) {
    selectedAssistantId.value = assistants.value[0].id;
    store.dispatch('pilot/assistants/setActive', assistants.value[0].id);
  }
});

watch(selectedAssistantId, () => {
  if (selectedAssistantId.value) {
    store.dispatch('pilot/assistants/setActive', selectedAssistantId.value);
    clearHistory();
  }
});

watch(activeAssistantId, newId => {
  if (newId && newId !== selectedAssistantId.value) {
    selectedAssistantId.value = newId;
    clearHistory();
  }
});

const scrollToBottom = () => {
  nextTick(() => {
    if (messagesContainerRef.value) {
      messagesContainerRef.value.scrollTop =
        messagesContainerRef.value.scrollHeight;
    }
  });
};

const sendMessage = async () => {
  const currentMsg = messageText.value.trim();
  if (!currentMsg || isSending.value) return;

  error.value = '';

  // De-duplication check: if the latest history item has content == currentMsg and role == 'user',
  // we do NOT append a duplicate message in the history list.
  let apiHistory = [...history.value];
  const lastHistoryItem = apiHistory[apiHistory.length - 1];
  if (
    !lastHistoryItem ||
    lastHistoryItem.role !== 'user' ||
    lastHistoryItem.content !== currentMsg
  ) {
    history.value.push({ role: 'user', content: currentMsg });
    apiHistory = [...history.value];
  }

  const payload = {
    messageContent: currentMsg,
    messageHistory: apiHistory.map(h => ({ role: h.role, content: h.content })),
  };

  messageText.value = '';
  scrollToBottom();

  try {
    const res = await store.dispatch('pilot/autopilot/sendPlaygroundMessage', {
      assistantId: selectedAssistantId.value,
      messageContent: payload.messageContent,
      messageHistory: payload.messageHistory,
    });
    if (res && res.reply) {
      history.value.push({ role: 'assistant', content: res.reply });
    }
  } catch (err) {
    error.value =
      err?.response?.data?.error || err?.message || 'Inference failed';
  } finally {
    scrollToBottom();
  }
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header
      class="sticky top-0 z-10 px-6 border-b border-n-weak bg-n-surface-1"
    >
      <div class="w-full max-w-5xl mx-auto py-4">
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <div class="flex flex-wrap items-center gap-x-3 gap-y-2 min-w-0">
            <div v-if="assistants.length > 0" class="min-w-48 max-w-64">
              <AssistantPicker v-model="selectedAssistantId" />
            </div>
            <span
              v-if="assistants.length > 0"
              aria-hidden="true"
              class="h-5 w-px bg-n-weak"
            />
            <h1 class="text-heading-md font-medium text-n-slate-12 truncate">
              {{ t('PILOT.PLAYGROUND.HEADER.TITLE') }}
            </h1>
          </div>
          <Button
            v-if="history.length > 0"
            :label="t('PILOT.PLAYGROUND.HEADER.CLEAR_BUTTON')"
            icon="i-lucide-trash-2"
            size="sm"
            variant="faded"
            color="slate"
            @click="clearHistory"
          />
        </div>
      </div>
    </header>

    <main
      class="flex-1 overflow-hidden flex flex-col max-w-5xl w-full mx-auto p-6 gap-4"
    >
      <!-- Error alert -->
      <div
        v-if="error"
        class="p-3 rounded-lg bg-n-ruby-3 border border-n-ruby-6 text-sm text-n-ruby-11 shrink-0"
        role="alert"
      >
        {{ error }}
      </div>

      <!-- Messages Pane -->
      <div
        ref="messagesContainerRef"
        class="flex-1 overflow-y-auto bg-n-solid-1 border border-n-weak rounded-xl p-6 flex flex-col gap-4 min-h-0"
      >
        <div
          v-if="history.length === 0"
          class="flex-1 flex flex-col items-center justify-center text-center text-n-slate-11 gap-2"
        >
          <div
            class="size-12 rounded-lg bg-n-alpha-1 flex items-center justify-center"
          >
            <span class="i-lucide-terminal size-6" />
          </div>
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('PILOT.PLAYGROUND.EMPTY.TITLE') }}
          </h3>
          <p class="text-xs text-n-slate-10 max-w-xs leading-normal">
            {{ t('PILOT.PLAYGROUND.EMPTY.BODY') }}
          </p>
        </div>

        <template v-else>
          <div
            v-for="(msg, index) in history"
            :key="index"
            class="flex flex-col max-w-[80%]"
            :class="
              msg.role === 'user'
                ? 'self-end items-end'
                : 'self-start items-start'
            "
          >
            <div class="text-xxs font-medium text-n-slate-10 mb-1">
              {{
                msg.role === 'user'
                  ? t('PILOT.PLAYGROUND.ROLE.USER')
                  : t('PILOT.PLAYGROUND.ROLE.ASSISTANT')
              }}
            </div>
            <div
              class="p-3 rounded-lg text-sm leading-relaxed whitespace-pre-wrap break-words"
              :class="
                msg.role === 'user'
                  ? 'bg-n-slate-12 text-n-solid-1'
                  : 'bg-n-alpha-1 border border-n-weak text-n-slate-12'
              "
            >
              {{ msg.content }}
            </div>
          </div>
        </template>

        <!-- Thinking State -->
        <div
          v-if="isSending"
          class="self-start flex flex-col max-w-[80%] items-start"
        >
          <div class="text-xxs font-medium text-n-slate-10 mb-1">
            {{ t('PILOT.PLAYGROUND.ROLE.ASSISTANT') }}
          </div>
          <div
            class="p-3 rounded-lg bg-n-alpha-1 border border-n-weak flex items-center gap-2"
          >
            <span
              class="i-lucide-loader-2 size-4 animate-spin text-n-slate-10"
            />
            <span class="text-xs text-n-slate-10 font-medium">{{
              t('PILOT.PLAYGROUND.STATUS.THINKING')
            }}</span>
          </div>
        </div>
      </div>

      <!-- Input Form -->
      <form class="flex gap-2 items-end shrink-0" @submit.prevent="sendMessage">
        <textarea
          v-model="messageText"
          rows="1"
          class="flex-1 p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:border-n-blue-9 resize-none max-h-32"
          :placeholder="t('PILOT.PLAYGROUND.INPUT.PLACEHOLDER')"
          :disabled="isSending"
          @keydown.enter.prevent="sendMessage"
        />
        <Button
          type="submit"
          icon="i-lucide-send"
          color="blue"
          class="h-11 shrink-0"
          :is-loading="isSending"
          :disabled="!messageText.trim()"
        />
      </form>
    </main>
  </section>
</template>
