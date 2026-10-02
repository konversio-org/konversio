<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  report: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const isExpanded = ref(false);

const handler = computed(() => props.report?.handler || {});
const events = computed(() => props.report?.events || []);
const isTemporary = computed(() => handler.value.temporary === true);

const formatDuration = ms =>
  `${Number(ms) || 0} ${t('PILOT.PLAYGROUND.RUN_REPORT.MILLISECONDS')}`;

const formatArguments = args => {
  if (!args || Object.keys(args).length === 0) return '';
  try {
    return JSON.stringify(args, null, 2);
  } catch (_e) {
    return String(args);
  }
};
</script>

<template>
  <div
    class="mt-2 w-full rounded-lg border border-n-weak bg-n-solid-1 text-xxs text-n-slate-11"
  >
    <button
      type="button"
      class="flex w-full items-center justify-between gap-2 px-3 py-2 text-left"
      :aria-expanded="isExpanded"
      @click="isExpanded = !isExpanded"
    >
      <span class="flex flex-wrap items-center gap-1.5">
        <span
          class="i-lucide-activity size-3.5 text-n-slate-10"
          aria-hidden="true"
        />
        <span class="text-n-slate-11">
          {{ t('PILOT.PLAYGROUND.RUN_REPORT.HANDLED_BY') }}
        </span>
        <span class="font-medium text-n-slate-12">{{ handler.name }}</span>
        <span
          v-if="isTemporary"
          class="rounded-full bg-n-amber-3 px-1.5 py-0.5 text-xxs font-medium text-n-amber-11"
        >
          {{ t('PILOT.PLAYGROUND.RUN_REPORT.TEMPORARY_BADGE') }}
        </span>
      </span>
      <span class="flex items-center gap-1.5 text-n-slate-10">
        <span>{{ formatDuration(report.duration_ms) }}</span>
        <span
          class="size-3.5"
          :class="isExpanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          aria-hidden="true"
        />
      </span>
    </button>

    <div v-if="isExpanded" class="border-t border-n-weak px-3 py-2">
      <p class="mb-2 flex items-center gap-1.5 text-xxs text-n-slate-10">
        <span class="i-lucide-book-open size-3.5" aria-hidden="true" />
        {{
          report.knowledge_attached
            ? t('PILOT.PLAYGROUND.RUN_REPORT.KNOWLEDGE_ATTACHED')
            : t('PILOT.PLAYGROUND.RUN_REPORT.KNOWLEDGE_NONE')
        }}
      </p>

      <ol class="flex flex-col gap-2">
        <li
          v-for="(event, index) in events"
          :key="index"
          class="rounded-md border border-n-weak bg-n-alpha-1 p-2"
        >
          <template v-if="event.type === 'tool'">
            <div class="flex items-center gap-1.5">
              <span
                class="i-lucide-wrench size-3.5 text-n-slate-10"
                aria-hidden="true"
              />
              <span class="font-medium text-n-slate-12">{{ event.tool }}</span>
              <span
                class="rounded-full px-1.5 py-0.5 text-xxs font-medium"
                :class="
                  event.status === 'failed'
                    ? 'bg-n-ruby-3 text-n-ruby-11'
                    : 'bg-n-alpha-2 text-n-slate-11'
                "
              >
                {{
                  t(
                    `PILOT.PLAYGROUND.RUN_REPORT.STATUS.${(
                      event.status || ''
                    ).toUpperCase()}`
                  )
                }}
              </span>
            </div>
            <div
              v-if="formatArguments(event.arguments)"
              class="mt-1 whitespace-pre-wrap break-words font-mono text-xxs text-n-slate-10"
            >
              {{ formatArguments(event.arguments) }}
            </div>
            <p
              v-if="event.result_preview"
              class="mt-1 whitespace-pre-wrap break-words text-n-slate-11"
            >
              {{ event.result_preview }}
            </p>
          </template>

          <template v-else-if="event.type === 'handoff'">
            <div class="flex flex-wrap items-center gap-1.5">
              <span
                class="i-lucide-corner-down-right size-3.5 text-n-slate-10"
                aria-hidden="true"
              />
              <span class="font-medium text-n-slate-12">{{
                event.from.name
              }}</span>
              <span class="i-lucide-arrow-right size-3 text-n-slate-10" />
              <span class="font-medium text-n-slate-12">{{
                event.to.name
              }}</span>
              <span
                v-if="event.to.temporary"
                class="rounded-full bg-n-amber-3 px-1.5 py-0.5 text-xxs font-medium text-n-amber-11"
              >
                {{ t('PILOT.PLAYGROUND.RUN_REPORT.TEMPORARY_BADGE') }}
              </span>
            </div>
            <p
              v-if="event.reason_preview"
              class="mt-1 whitespace-pre-wrap break-words text-n-slate-11"
            >
              {{ event.reason_preview }}
            </p>
          </template>
        </li>
      </ol>

      <p v-if="!events.length" class="text-xxs text-n-slate-10">
        {{ t('PILOT.PLAYGROUND.RUN_REPORT.NO_EVENTS') }}
      </p>
    </div>
  </div>
</template>
