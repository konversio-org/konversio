<script setup>
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import AssistantPicker from 'dashboard/components-next/pilot/shared/AssistantPicker.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PilotAssistantsAPI from 'dashboard/api/pilot/assistants';

const { t } = useI18n();
const store = useStore();

const activeAssistantId = useMapGetter('pilot/assistants/getActiveId');
const assistants = useMapGetter('pilot/assistants/getRecords');
const scenarios = useMapGetter('pilot/autopilot/getScenarios');
const uiFlags = useMapGetter('pilot/autopilot/getUIFlags');

const isEditing = ref(false);
const editingScenarioId = ref(null);
const title = ref('');
const description = ref('');
const instruction = ref('');
const enabled = ref(true);

const instructionTextareaRef = ref(null);
const availableTools = ref([]);
const isFetchingTools = ref(false);
const error = ref('');

const selectedAssistantId = ref(activeAssistantId.value);

const fetchScenarios = async () => {
  if (!selectedAssistantId.value) return;
  try {
    await store.dispatch(
      'pilot/autopilot/fetchScenarios',
      selectedAssistantId.value
    );
  } catch (_e) {
    // handled via UI
  }
};

const fetchTools = async () => {
  isFetchingTools.value = true;
  try {
    const { data } = await PilotAssistantsAPI.getTools();
    availableTools.value = data || [];
  } catch (_e) {
    availableTools.value = [];
  } finally {
    isFetchingTools.value = false;
  }
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
  fetchScenarios();
  fetchTools();
});

watch(selectedAssistantId, () => {
  if (selectedAssistantId.value) {
    store.dispatch('pilot/assistants/setActive', selectedAssistantId.value);
    fetchScenarios();
  }
});

watch(activeAssistantId, newId => {
  if (newId && newId !== selectedAssistantId.value) {
    selectedAssistantId.value = newId;
  }
});

const onAdd = () => {
  isEditing.value = true;
  editingScenarioId.value = null;
  title.value = '';
  description.value = '';
  instruction.value = '';
  enabled.value = true;
  error.value = '';
};

const onEdit = scenario => {
  isEditing.value = true;
  editingScenarioId.value = scenario.id;
  title.value = scenario.title || '';
  description.value = scenario.description || '';
  instruction.value = scenario.instruction || '';
  enabled.value = scenario.enabled !== false;
  error.value = '';
};

const onDelete = async id => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('PILOT.SCENARIOS.CONFIRM_DELETE'))) return;
  try {
    await store.dispatch('pilot/autopilot/deleteScenario', {
      assistantId: selectedAssistantId.value,
      id,
    });
    useAlert(t('PILOT.SCENARIOS.TOAST.DELETED'));
  } catch (err) {
    useAlert(t('PILOT.SCENARIOS.TOAST.DELETE_FAILED'));
  }
};

const insertTool = (slug, label) => {
  const textarea = instructionTextareaRef.value;
  if (!textarea) return;
  const start = textarea.selectionStart;
  const end = textarea.selectionEnd;
  const text = instruction.value;
  const toolRef = `[${label}](tool://${slug})`;
  instruction.value = text.substring(0, start) + toolRef + text.substring(end);
  textarea.focus();
  setTimeout(() => {
    textarea.selectionEnd = start + toolRef.length;
    textarea.selectionStart = textarea.selectionEnd;
  }, 0);
};

const save = async () => {
  if (
    !title.value.trim() ||
    !description.value.trim() ||
    !instruction.value.trim()
  ) {
    error.value = t('PILOT.SCENARIOS.ERRORS.FIELDS_REQUIRED');
    return;
  }
  error.value = '';

  const payload = {
    title: title.value.trim(),
    description: description.value.trim(),
    instruction: instruction.value.trim(),
    enabled: enabled.value,
  };

  try {
    if (editingScenarioId.value) {
      await store.dispatch('pilot/autopilot/updateScenario', {
        assistantId: selectedAssistantId.value,
        id: editingScenarioId.value,
        scenario: payload,
      });
      useAlert(t('PILOT.SCENARIOS.TOAST.UPDATED'));
    } else {
      await store.dispatch('pilot/autopilot/createScenario', {
        assistantId: selectedAssistantId.value,
        scenario: payload,
      });
      useAlert(t('PILOT.SCENARIOS.TOAST.CREATED'));
    }
    isEditing.value = false;
  } catch (err) {
    error.value =
      err?.response?.data?.message ||
      err?.message ||
      t('PILOT.SCENARIOS.ERRORS.SAVE_FAILED');
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
              {{ t('PILOT.SCENARIOS.HEADER.TITLE') }}
            </h1>
          </div>
          <Button
            v-if="!isEditing && selectedAssistantId"
            :label="t('PILOT.SCENARIOS.HEADER.ADD_BUTTON')"
            icon="i-lucide-plus"
            size="sm"
            @click="onAdd"
          />
        </div>
      </div>
    </header>

    <main class="flex-1 px-6 overflow-y-auto py-6">
      <div class="w-full max-w-5xl mx-auto">
        <!-- Error alert -->
        <div
          v-if="error"
          class="mb-4 p-3 rounded-lg bg-n-ruby-3 border border-n-ruby-6 text-sm text-n-ruby-11"
          role="alert"
        >
          {{ error }}
        </div>

        <!-- Editor panel -->
        <div
          v-if="isEditing"
          class="bg-n-solid-1 border border-n-weak rounded-xl p-6 flex flex-col gap-6"
        >
          <div
            class="flex items-center justify-between border-b border-n-weak pb-4"
          >
            <h2 class="text-md font-medium text-n-slate-12">
              {{
                editingScenarioId
                  ? t('PILOT.SCENARIOS.FORM.EDIT_TITLE')
                  : t('PILOT.SCENARIOS.FORM.CREATE_TITLE')
              }}
            </h2>
            <Button
              type="button"
              variant="faded"
              color="slate"
              size="sm"
              :label="t('PILOT.SCENARIOS.FORM.CANCEL')"
              @click="isEditing = false"
            />
          </div>

          <div class="grid grid-cols-1 gap-4">
            <div class="flex flex-col gap-1.5">
              <label
                for="scenario-title"
                class="text-sm font-medium text-n-slate-12"
              >
                {{ t('PILOT.SCENARIOS.FORM.TITLE_LABEL') }}
              </label>
              <input
                id="scenario-title"
                v-model="title"
                type="text"
                class="w-full h-10 px-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:border-n-blue-9"
                :placeholder="t('PILOT.SCENARIOS.FORM.TITLE_PLACEHOLDER')"
              />
            </div>

            <div class="flex flex-col gap-1.5">
              <label
                for="scenario-desc"
                class="text-sm font-medium text-n-slate-12"
              >
                {{ t('PILOT.SCENARIOS.FORM.DESC_LABEL') }}
              </label>
              <input
                id="scenario-desc"
                v-model="description"
                type="text"
                class="w-full h-10 px-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:border-n-blue-9"
                :placeholder="t('PILOT.SCENARIOS.FORM.DESC_PLACEHOLDER')"
              />
            </div>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <div class="flex flex-col gap-1.5 md:col-span-2">
                <label
                  for="scenario-instructions"
                  class="text-sm font-medium text-n-slate-12"
                >
                  {{ t('PILOT.SCENARIOS.FORM.INSTRUCTIONS_LABEL') }}
                </label>
                <textarea
                  id="scenario-instructions"
                  ref="instructionTextareaRef"
                  v-model="instruction"
                  rows="8"
                  class="w-full p-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:border-n-blue-9 resize-y font-mono"
                  :placeholder="
                    t('PILOT.SCENARIOS.FORM.INSTRUCTIONS_PLACEHOLDER')
                  "
                />
              </div>

              <!-- Helper tools sidebox -->
              <div
                class="flex flex-col gap-3 p-4 bg-n-alpha-1 border border-n-weak rounded-lg self-start"
              >
                <h4
                  class="text-xs font-semibold text-n-slate-11 uppercase tracking-wider"
                >
                  {{ t('PILOT.SCENARIOS.FORM.TOOLS_HELPER') }}
                </h4>
                <p class="text-xs text-n-slate-10 leading-normal">
                  {{ t('PILOT.SCENARIOS.FORM.TOOLS_HELPER_DESC') }}
                </p>
                <div class="flex flex-col gap-2 max-h-48 overflow-y-auto mt-2">
                  <div
                    v-for="tool in availableTools"
                    :key="tool.slug"
                    class="flex items-center justify-between p-2 rounded bg-n-solid-1 border border-n-container hover:bg-n-alpha-1 cursor-pointer transition-colors"
                    @click="insertTool(tool.slug, tool.title || tool.slug)"
                  >
                    <span class="text-xs font-medium text-n-slate-12 truncate">
                      {{ tool.title || tool.slug }}
                    </span>
                    <Icon
                      icon="i-lucide-arrow-left-to-line"
                      class="size-3 text-n-slate-9 shrink-0"
                    />
                  </div>
                  <p
                    v-if="!availableTools.length"
                    class="text-xs text-n-slate-9 italic"
                  >
                    {{ t('PILOT.SCENARIOS.FORM.NO_TOOLS_AVAILABLE') }}
                  </p>
                </div>
              </div>
            </div>

            <label class="flex items-center gap-3 cursor-pointer mt-2">
              <input
                v-model="enabled"
                type="checkbox"
                class="rounded border-n-container text-n-blue-9 focus:ring-n-blue-9"
              />
              <span class="text-sm text-n-slate-12 font-medium">{{
                t('PILOT.SCENARIOS.FORM.ENABLED_LABEL')
              }}</span>
            </label>
          </div>

          <div
            class="flex items-center justify-end gap-3 border-t border-n-weak pt-4"
          >
            <Button
              type="button"
              variant="faded"
              color="slate"
              :label="t('PILOT.SCENARIOS.FORM.CANCEL')"
              @click="isEditing = false"
            />
            <Button
              type="button"
              :label="t('PILOT.SCENARIOS.FORM.SAVE')"
              :is-loading="
                uiFlags.isCreatingScenario || uiFlags.isUpdatingScenario
              "
              @click="save"
            />
          </div>
        </div>

        <!-- Scenarios list -->
        <div
          v-else-if="scenarios.length > 0"
          class="grid grid-cols-1 md:grid-cols-2 gap-4"
        >
          <div
            v-for="scenario in scenarios"
            :key="scenario.id"
            class="bg-n-solid-1 border border-n-weak rounded-xl p-5 flex flex-col justify-between hover:shadow-sm transition-shadow gap-4"
          >
            <div class="flex flex-col gap-2">
              <div class="flex items-start justify-between gap-2">
                <h3
                  class="text-sm font-semibold text-n-slate-12 leading-none truncate"
                >
                  {{ scenario.title }}
                </h3>
                <span
                  class="inline-flex items-center px-1.5 py-0.5 rounded text-xxs font-medium"
                  :class="
                    scenario.enabled
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-slate-3 text-n-slate-11'
                  "
                >
                  {{
                    scenario.enabled
                      ? t('PILOT.SCENARIOS.STATUS.ENABLED')
                      : t('PILOT.SCENARIOS.STATUS.DISABLED')
                  }}
                </span>
              </div>
              <p class="text-xs text-n-slate-11 line-clamp-2">
                {{ scenario.description }}
              </p>
            </div>

            <!-- Footer with tools info & actions -->
            <div
              class="flex items-center justify-between border-t border-n-weak pt-3"
            >
              <div class="flex items-center gap-1.5">
                <Icon icon="i-lucide-wrench" class="size-3.5 text-n-slate-10" />
                <span class="text-xs text-n-slate-10 font-medium">
                  {{ scenario.tools?.length || 0 }}
                  {{ t('PILOT.SCENARIOS.TABLE.TOOLS_COUNT') }}
                </span>
              </div>

              <div class="flex items-center gap-2">
                <Button
                  variant="ghost"
                  color="slate"
                  size="xs"
                  :label="t('PILOT.SCENARIOS.ACTIONS.EDIT')"
                  @click="onEdit(scenario)"
                />
                <Button
                  variant="ghost"
                  color="ruby"
                  size="xs"
                  :label="t('PILOT.SCENARIOS.ACTIONS.DELETE')"
                  @click="onDelete(scenario.id)"
                />
              </div>
            </div>
          </div>
        </div>

        <!-- Empty state -->
        <div
          v-else
          class="flex flex-col items-center justify-center text-center p-12 bg-n-solid-1 border border-dashed border-n-weak rounded-xl gap-4"
        >
          <div
            class="size-12 rounded-lg bg-n-alpha-1 flex items-center justify-center text-n-slate-11"
          >
            <span class="i-lucide-workflow size-6" />
          </div>
          <div class="flex flex-col gap-1">
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ t('PILOT.SCENARIOS.EMPTY.TITLE') }}
            </h3>
            <p class="text-xs text-n-slate-11 max-w-sm leading-relaxed">
              {{ t('PILOT.SCENARIOS.EMPTY.BODY') }}
            </p>
          </div>
          <Button
            v-if="selectedAssistantId"
            :label="t('PILOT.SCENARIOS.EMPTY.CREATE_BUTTON')"
            size="sm"
            @click="onAdd"
          />
        </div>
      </div>
    </main>
  </section>
</template>
