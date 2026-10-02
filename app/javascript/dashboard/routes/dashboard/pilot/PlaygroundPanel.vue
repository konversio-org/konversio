<script setup>
import { computed, onMounted, ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import AssistantPicker from 'dashboard/components-next/pilot/shared/AssistantPicker.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import PlaygroundRunReport from './PlaygroundRunReport.vue';
import {
  usePlaygroundSession,
  KNOWLEDGE_TEXT_LIMIT,
} from './usePlaygroundSession';

const { t } = useI18n();

// Render the assistant's markdown the same way customer channels do
// (MessageFormatter -> sanitized HTML via markdown-it), so the Playground
// previews what the user will actually see instead of raw `*` markup.
const formatAssistantMessage = content =>
  new MessageFormatter(content || '').formattedMessage;

// Readable label for the "Tools used" line: `custom_nationality_check` ->
// `Nationality Check`, `search_documentation` -> `Search Documentation`.
const humanizeTool = name =>
  String(name)
    .replace(/^custom_/, '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, char => char.toUpperCase());

const store = useStore();

const activeAssistantId = useMapGetter('pilot/assistants/getActiveId');
const assistants = useMapGetter('pilot/assistants/getRecords');
const uiFlags = useMapGetter('pilot/autopilot/getUIFlags');

const {
  includedScenarioIds,
  temporaryScenarios,
  guidelines,
  guardrails,
  knowledge,
  activeScenarios,
  characterCount,
  knowledgeExceedsLimit,
  temporaryErrors,
  isTemporaryValid,
  playgroundConfig,
  load,
  toggleScenario,
  addTemporaryScenario,
  removeTemporaryScenario,
  addGuideline,
  addGuardrail,
} = usePlaygroundSession();

const selectedAssistantId = ref(activeAssistantId.value);
const messageText = ref('');
const history = ref([]);
const error = ref('');
const configErrors = ref({});
const showSetup = ref(false);
const activeTab = ref('knowledge');
const newGuideline = ref('');
const newGuardrail = ref('');
const messagesContainerRef = ref(null);

const TABS = ['knowledge', 'scenarios', 'guidelines', 'guardrails'];

const isSending = computed(() => uiFlags.value.isSendingPlayground);

const configErrorEntries = computed(() =>
  Object.entries(configErrors.value).flatMap(([field, messages]) =>
    (Array.isArray(messages) ? messages : [messages]).map(message => ({
      field,
      message,
    }))
  )
);

const clearHistory = () => {
  history.value = [];
  error.value = '';
  configErrors.value = {};
};

const selectAssistant = async id => {
  if (!id) return;
  await load(id);
};

const addGuidelineEntry = () => {
  addGuideline(newGuideline.value);
  newGuideline.value = '';
};

const addGuardrailEntry = () => {
  addGuardrail(newGuardrail.value);
  newGuardrail.value = '';
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
  await selectAssistant(selectedAssistantId.value);
});

watch(selectedAssistantId, async newId => {
  if (newId) {
    store.dispatch('pilot/assistants/setActive', newId);
    clearHistory();
    await selectAssistant(newId);
  }
});

watch(activeAssistantId, async newId => {
  if (newId && newId !== selectedAssistantId.value) {
    selectedAssistantId.value = newId;
    clearHistory();
    await selectAssistant(newId);
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
  configErrors.value = {};

  if (!isTemporaryValid.value) {
    error.value = t('PILOT.PLAYGROUND.SETUP.INVALID_TEMPORARY');
    return;
  }
  if (knowledgeExceedsLimit.value) {
    error.value = t('PILOT.PLAYGROUND.SETUP.KNOWLEDGE_TOO_LONG');
    return;
  }

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

  messageText.value = '';
  scrollToBottom();

  try {
    const res = await store.dispatch('pilot/autopilot/sendPlaygroundMessage', {
      assistantId: selectedAssistantId.value,
      messageContent: currentMsg,
      messageHistory: apiHistory.map(h => ({
        role: h.role,
        content: h.content,
      })),
      playgroundConfig: playgroundConfig.value || undefined,
    });
    if (res && res.reply) {
      history.value.push({
        role: 'assistant',
        content: res.reply,
        tools: Array.isArray(res.invoked_tool_names)
          ? res.invoked_tool_names
          : [],
        runReport: res.run_report || null,
      });
    }
  } catch (err) {
    const data = err?.response?.data;
    if (data?.errors) configErrors.value = data.errors;
    error.value =
      data?.error || err?.message || t('PILOT.PLAYGROUND.ERRORS.INFERENCE');
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
          <div class="flex items-center gap-2">
            <Button
              :label="t('PILOT.PLAYGROUND.SETUP.TOGGLE')"
              icon="i-lucide-settings-2"
              size="sm"
              variant="faded"
              color="slate"
              @click="showSetup = !showSetup"
            />
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
      </div>
    </header>

    <main
      class="flex-1 overflow-hidden flex flex-col max-w-5xl w-full mx-auto p-6 gap-4"
    >
      <!-- Test-setup panel -->
      <section
        v-if="showSetup"
        class="shrink-0 rounded-xl border border-n-weak bg-n-solid-1"
      >
        <nav class="flex gap-1 border-b border-n-weak px-2 pt-2">
          <button
            v-for="tab in TABS"
            :key="tab"
            type="button"
            class="px-3 py-1.5 text-xs font-medium rounded-t-lg"
            :class="
              activeTab === tab
                ? 'bg-n-alpha-1 text-n-slate-12'
                : 'text-n-slate-10'
            "
            @click="activeTab = tab"
          >
            {{ t(`PILOT.PLAYGROUND.SETUP.TABS.${tab.toUpperCase()}`) }}
          </button>
        </nav>

        <div class="p-4 text-sm text-n-slate-12">
          <!-- Knowledge -->
          <div v-if="activeTab === 'knowledge'" class="flex flex-col gap-2">
            <label class="flex items-center gap-2 text-xs text-n-slate-11">
              <input v-model="knowledge.included" type="checkbox" />
              {{ t('PILOT.PLAYGROUND.SETUP.KNOWLEDGE.INCLUDE') }}
            </label>
            <textarea
              v-model="knowledge.text"
              rows="4"
              class="p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:border-n-blue-9 resize-y"
              :placeholder="t('PILOT.PLAYGROUND.SETUP.KNOWLEDGE.PLACEHOLDER')"
            />
            <div class="flex items-center justify-between text-xxs">
              <span class="text-n-slate-10">
                {{
                  t('PILOT.PLAYGROUND.SETUP.KNOWLEDGE.COUNTER', {
                    count: characterCount,
                    limit: KNOWLEDGE_TEXT_LIMIT,
                  })
                }}
              </span>
              <span v-if="knowledgeExceedsLimit" class="text-n-ruby-11">
                {{ t('PILOT.PLAYGROUND.SETUP.KNOWLEDGE.TOO_LONG') }}
              </span>
            </div>
          </div>

          <!-- Scenarios -->
          <div
            v-else-if="activeTab === 'scenarios'"
            class="flex flex-col gap-3"
          >
            <div v-if="activeScenarios.length" class="flex flex-col gap-1.5">
              <label
                v-for="scenario in activeScenarios"
                :key="scenario.id"
                class="flex items-center gap-2 text-xs text-n-slate-11"
              >
                <input
                  type="checkbox"
                  :checked="includedScenarioIds.includes(scenario.id)"
                  @change="toggleScenario(scenario.id, $event.target.checked)"
                />
                {{ scenario.title }}
              </label>
            </div>
            <p v-else class="text-xxs text-n-slate-10">
              {{ t('PILOT.PLAYGROUND.SETUP.SCENARIOS.NONE') }}
            </p>

            <div
              v-for="(draft, index) in temporaryScenarios"
              :key="draft.clientId"
              class="rounded-lg border border-n-weak p-3 flex flex-col gap-2"
            >
              <div class="flex items-center justify-between">
                <span class="text-xxs font-medium text-n-slate-10">
                  {{
                    t('PILOT.PLAYGROUND.SETUP.SCENARIOS.TEMPORARY_LABEL', {
                      index: index + 1,
                    })
                  }}
                </span>
                <button
                  type="button"
                  class="i-lucide-trash-2 size-4 text-n-slate-10"
                  :aria-label="t('PILOT.PLAYGROUND.SETUP.SCENARIOS.REMOVE')"
                  @click="removeTemporaryScenario(index)"
                />
              </div>
              <input
                v-model="draft.title"
                class="p-2 rounded-lg border bg-n-solid-1 text-sm"
                :class="
                  temporaryErrors[index]?.title
                    ? 'border-n-ruby-9'
                    : 'border-n-container'
                "
                :placeholder="
                  t('PILOT.PLAYGROUND.SETUP.SCENARIOS.TITLE_PLACEHOLDER')
                "
              />
              <input
                v-model="draft.description"
                class="p-2 rounded-lg border bg-n-solid-1 text-sm"
                :class="
                  temporaryErrors[index]?.description
                    ? 'border-n-ruby-9'
                    : 'border-n-container'
                "
                :placeholder="
                  t('PILOT.PLAYGROUND.SETUP.SCENARIOS.DESCRIPTION_PLACEHOLDER')
                "
              />
              <textarea
                v-model="draft.instruction"
                rows="2"
                class="p-2 rounded-lg border bg-n-solid-1 text-sm resize-y"
                :class="
                  temporaryErrors[index]?.instruction
                    ? 'border-n-ruby-9'
                    : 'border-n-container'
                "
                :placeholder="
                  t('PILOT.PLAYGROUND.SETUP.SCENARIOS.INSTRUCTION_PLACEHOLDER')
                "
              />
            </div>

            <Button
              :label="t('PILOT.PLAYGROUND.SETUP.SCENARIOS.ADD')"
              icon="i-lucide-plus"
              size="sm"
              variant="faded"
              color="slate"
              @click="addTemporaryScenario"
            />
          </div>

          <!-- Guidelines -->
          <div
            v-else-if="activeTab === 'guidelines'"
            class="flex flex-col gap-2"
          >
            <label
              v-for="entry in guidelines"
              :key="entry.value"
              class="flex items-center gap-2 text-xs text-n-slate-11"
            >
              <input v-model="entry.included" type="checkbox" />
              {{ entry.value }}
            </label>
            <div class="flex gap-2">
              <input
                v-model="newGuideline"
                class="flex-1 p-2 rounded-lg border border-n-container bg-n-solid-1 text-sm"
                :placeholder="t('PILOT.PLAYGROUND.SETUP.RULES.ADD_PLACEHOLDER')"
                @keydown.enter.prevent="addGuidelineEntry"
              />
              <Button
                :label="t('PILOT.PLAYGROUND.SETUP.RULES.ADD')"
                size="sm"
                variant="faded"
                color="slate"
                @click="addGuidelineEntry"
              />
            </div>
          </div>

          <!-- Guardrails -->
          <div v-else class="flex flex-col gap-2">
            <label
              v-for="entry in guardrails"
              :key="entry.value"
              class="flex items-center gap-2 text-xs text-n-slate-11"
            >
              <input v-model="entry.included" type="checkbox" />
              {{ entry.value }}
            </label>
            <div class="flex gap-2">
              <input
                v-model="newGuardrail"
                class="flex-1 p-2 rounded-lg border border-n-container bg-n-solid-1 text-sm"
                :placeholder="t('PILOT.PLAYGROUND.SETUP.RULES.ADD_PLACEHOLDER')"
                @keydown.enter.prevent="addGuardrailEntry"
              />
              <Button
                :label="t('PILOT.PLAYGROUND.SETUP.RULES.ADD')"
                size="sm"
                variant="faded"
                color="slate"
                @click="addGuardrailEntry"
              />
            </div>
          </div>
        </div>
      </section>

      <!-- Error alert -->
      <div
        v-if="error"
        class="p-3 rounded-lg bg-n-ruby-3 border border-n-ruby-6 text-sm text-n-ruby-11 shrink-0"
        role="alert"
      >
        {{ error }}
      </div>

      <div
        v-if="configErrorEntries.length"
        class="p-3 rounded-lg bg-n-ruby-3 border border-n-ruby-6 text-xs text-n-ruby-11 shrink-0"
        role="alert"
      >
        <p
          v-for="entry in configErrorEntries"
          :key="`${entry.field}:${entry.message}`"
        >
          {{ `${entry.field}: ${entry.message}` }}
        </p>
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
              class="p-3 rounded-lg text-sm leading-relaxed break-words"
              :class="
                msg.role === 'user'
                  ? 'bg-n-slate-12 text-n-solid-1 whitespace-pre-wrap'
                  : 'bg-n-alpha-1 border border-n-weak text-n-slate-12'
              "
            >
              <span
                v-if="msg.role === 'assistant'"
                v-dompurify-html="formatAssistantMessage(msg.content)"
                class="prose prose-bubble max-w-none"
              />
              <template v-else>{{ msg.content }}</template>
            </div>

            <!-- Tools-used metadata (assistant only): visible confirmation of
                 which tools actually fired for this answer. -->
            <div
              v-if="msg.role === 'assistant' && msg.tools && msg.tools.length"
              class="flex flex-wrap items-center gap-1.5 mt-1.5"
            >
              <span class="text-xxs text-n-slate-10">
                {{ t('PILOT.PLAYGROUND.TOOLS.LABEL') }}
              </span>
              <span
                v-for="tool in msg.tools"
                :key="tool"
                class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-full bg-n-alpha-1 text-xxs font-medium text-n-slate-11"
              >
                <span aria-hidden="true" class="i-lucide-wrench size-3" />
                {{ humanizeTool(tool) }}
              </span>
            </div>

            <PlaygroundRunReport
              v-if="msg.role === 'assistant' && msg.runReport"
              :report="msg.runReport"
            />
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
        <!--
          h-11 matches the send button height; mb-0 clears a base textarea
          margin-bottom that, with the form's `items-end`, aligned the input's
          margin box (not its visible edge) to the bottom — leaving the send
          button hanging ~16px below the field.
        -->
        <textarea
          v-model="messageText"
          rows="1"
          class="flex-1 p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:border-n-blue-9 resize-none h-11 mb-0"
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
