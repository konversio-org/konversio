<script setup>
import { computed } from 'vue';

const props = defineProps({
  session: { type: Object, default: null },
  isLoading: { type: Boolean, default: false },
});

const citedSources = computed(() => props.session?.cited_sources || []);
const usedFaqs = computed(() => props.session?.used_faqs || []);
const scenarios = computed(() => props.session?.scenarios || []);

// Humanized run steps: every tool call made during the turn, in order. Message
// bodies and raw tool outputs are deliberately not surfaced.
const steps = computed(() =>
  (props.session?.run_context || []).flatMap(entry =>
    (entry.tool_calls || []).map(call => ({
      name: call.name || call.function?.name || 'tool',
      args: call.arguments ?? call.function?.arguments ?? {},
    }))
  )
);

const hasSources = computed(
  () => citedSources.value.length || usedFaqs.value.length
);
</script>

<template>
  <div
    class="w-80 p-4 text-sm bg-n-surface-1"
    data-testid="pilot-session-panel"
  >
    <p v-if="isLoading" class="text-n-slate-11">
      {{ $t('PILOT.PILOT_SESSION.LOADING') }}
    </p>

    <p v-else-if="!session" class="text-n-slate-11">
      {{ $t('PILOT.PILOT_SESSION.EMPTY') }}
    </p>

    <div v-else class="flex flex-col gap-4">
      <section>
        <h4 class="mb-2 font-semibold text-n-slate-12">
          {{ $t('PILOT.PILOT_SESSION.SOURCES') }}
        </h4>
        <p v-if="!hasSources" class="text-n-slate-11">
          {{ $t('PILOT.PILOT_SESSION.NO_SOURCES') }}
        </p>
        <ul v-else class="flex flex-col gap-1">
          <li v-for="source in citedSources" :key="`doc-${source.id}`">
            <a
              v-if="source.link"
              :href="source.link"
              target="_blank"
              rel="noopener noreferrer"
              class="text-n-brand hover:underline"
            >
              {{ source.title }}
            </a>
            <span v-else class="text-n-slate-12">{{ source.title }}</span>
          </li>
          <li
            v-for="faq in usedFaqs"
            :key="`faq-${faq.id}`"
            class="text-n-slate-12"
          >
            {{ faq.title }}
          </li>
        </ul>
      </section>

      <section v-if="scenarios.length">
        <h4 class="mb-2 font-semibold text-n-slate-12">
          {{ $t('PILOT.PILOT_SESSION.SCENARIOS') }}
        </h4>
        <ul class="flex flex-col gap-1">
          <li
            v-for="scenario in scenarios"
            :key="scenario.id"
            class="text-n-slate-12"
          >
            {{ scenario.title }}
          </li>
        </ul>
      </section>

      <section>
        <h4 class="mb-2 font-semibold text-n-slate-12">
          {{ $t('PILOT.PILOT_SESSION.STEPS') }}
        </h4>
        <p v-if="!steps.length" class="text-n-slate-11">
          {{ $t('PILOT.PILOT_SESSION.NO_STEPS') }}
        </p>
        <ol v-else class="flex flex-col gap-1">
          <li
            v-for="(step, index) in steps"
            :key="`step-${index}`"
            class="text-n-slate-12"
          >
            {{
              $t('PILOT.PILOT_SESSION.TOOL_CALL', {
                tool: step.name,
              })
            }}
            <span
              v-if="Object.keys(step.args || {}).length"
              class="text-n-slate-11"
            >
              {{ JSON.stringify(step.args) }}
            </span>
          </li>
        </ol>
      </section>
    </div>
  </div>
</template>
