import { computed, reactive, ref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';

// Mirrors Pilot::Playground::SessionConfig::KNOWLEDGE_TEXT_LIMIT.
export const KNOWLEDGE_TEXT_LIMIT = 10000;

// Persisted rules may be stored as an array or a newline-separated string.
const toRuleEntries = value => {
  const list = Array.isArray(value) ? value : String(value || '').split('\n');
  return list
    .map(entry => String(entry).trim())
    .filter(Boolean)
    .map(entry => ({ value: entry, included: true, persisted: true }));
};

// Client-side identifier for an unsaved scenario draft. Unique per draft so the
// server can derive a stable runtime agent name and reject duplicates.
const generateClientId = () =>
  `draft-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;

const nonEmpty = value => String(value || '').trim().length > 0;

/**
 * Tracks the per-run playground setup (scenario selection, temporary drafts,
 * guideline/guardrail inclusion, knowledge text) and composes the
 * `playground_config` payload posted to the playground endpoint.
 */
export function usePlaygroundSession() {
  const store = useStore();
  const activeAssistantId = useMapGetter('pilot/assistants/getActiveId');
  const activeAssistant = useMapGetter('pilot/assistants/getActiveAssistant');
  const scenarios = useMapGetter('pilot/autopilot/getScenarios');

  const includedScenarioIds = ref([]);
  const temporaryScenarios = ref([]);
  const guidelines = ref([]);
  const guardrails = ref([]);
  const knowledge = reactive({ text: '', included: false });

  const activeScenarios = computed(() =>
    (scenarios.value || []).filter(scenario => scenario.enabled !== false)
  );

  const includedGuidelines = computed(() =>
    guidelines.value.filter(entry => entry.included).map(entry => entry.value)
  );
  const includedGuardrails = computed(() =>
    guardrails.value.filter(entry => entry.included).map(entry => entry.value)
  );

  const characterCount = computed(() => knowledge.text.length);
  const knowledgeExceedsLimit = computed(
    () => characterCount.value > KNOWLEDGE_TEXT_LIMIT
  );

  const temporaryErrors = computed(() =>
    temporaryScenarios.value.map(draft => {
      const errors = {};
      if (!nonEmpty(draft.title)) errors.title = true;
      if (!nonEmpty(draft.description)) errors.description = true;
      if (!nonEmpty(draft.instruction)) errors.instruction = true;
      return errors;
    })
  );
  const isTemporaryValid = computed(() =>
    temporaryErrors.value.every(errors => Object.keys(errors).length === 0)
  );

  const load = async (assistantId = activeAssistantId.value) => {
    if (!assistantId) return;

    await store.dispatch('pilot/autopilot/fetchScenarios', assistantId);

    includedScenarioIds.value = activeScenarios.value.map(
      scenario => scenario.id
    );
    guidelines.value = toRuleEntries(
      activeAssistant.value?.response_guidelines
    );
    guardrails.value = toRuleEntries(activeAssistant.value?.guardrails);
    temporaryScenarios.value = [];
    knowledge.text = '';
    knowledge.included = false;
  };

  const toggleScenario = (id, included) => {
    const ids = new Set(includedScenarioIds.value);
    if (included) {
      ids.add(id);
    } else {
      ids.delete(id);
    }
    includedScenarioIds.value = [...ids];
  };

  const addTemporaryScenario = () => {
    temporaryScenarios.value.push({
      clientId: generateClientId(),
      title: '',
      description: '',
      instruction: '',
    });
  };

  const removeTemporaryScenario = index => {
    temporaryScenarios.value.splice(index, 1);
  };

  const addRule = (list, value) => {
    const trimmed = String(value || '').trim();
    if (!trimmed) return;
    list.value.push({ value: trimmed, included: true, persisted: false });
  };

  const addGuideline = value => addRule(guidelines, value);
  const addGuardrail = value => addRule(guardrails, value);

  const playgroundConfig = computed(() => {
    const config = {};
    const activeIds = activeScenarios.value.map(scenario => scenario.id);

    if (includedScenarioIds.value.length !== activeIds.length) {
      config.scenario_ids = [...includedScenarioIds.value];
    }
    if (temporaryScenarios.value.length) {
      config.temporary_scenarios = temporaryScenarios.value.map(draft => ({
        client_id: draft.clientId,
        title: draft.title.trim(),
        description: draft.description.trim(),
        instruction: draft.instruction.trim(),
      }));
    }
    if (guidelines.value.some(entry => !entry.persisted || !entry.included)) {
      config.response_guidelines = includedGuidelines.value;
    }
    if (guardrails.value.some(entry => !entry.persisted || !entry.included)) {
      config.guardrails = includedGuardrails.value;
    }
    if (knowledge.included && nonEmpty(knowledge.text)) {
      config.knowledge_text = knowledge.text;
    }

    return Object.keys(config).length ? config : null;
  });

  return {
    // state
    includedScenarioIds,
    temporaryScenarios,
    guidelines,
    guardrails,
    knowledge,
    // computed
    activeScenarios,
    includedGuidelines,
    includedGuardrails,
    characterCount,
    knowledgeExceedsLimit,
    temporaryErrors,
    isTemporaryValid,
    playgroundConfig,
    // actions
    load,
    toggleScenario,
    addTemporaryScenario,
    removeTemporaryScenario,
    addGuideline,
    addGuardrail,
  };
}
