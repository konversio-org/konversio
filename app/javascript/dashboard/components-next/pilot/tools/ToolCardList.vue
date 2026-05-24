<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ToolCard from './ToolCard.vue';

defineProps({
  rows: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  hasError: { type: Boolean, default: false },
  skeletonCount: { type: Number, default: 5 },
  isAdmin: { type: Boolean, default: false },
});

const emit = defineEmits(['edit', 'delete', 'create', 'retry']);

const { t } = useI18n();

const onEdit = row => emit('edit', row);
const onDelete = row => emit('delete', row);
const onCreate = () => emit('create');
const onRetry = () => emit('retry');
</script>

<template>
  <section class="flex flex-col gap-3">
    <!-- Error Alert banner -->
    <div
      v-if="hasError && !isLoading"
      role="alert"
      class="flex items-center justify-between gap-4 p-4 rounded-xl border border-n-ruby-7 bg-n-ruby-3 text-n-ruby-11"
    >
      <span class="text-sm">{{ t('PILOT.TOOLS.ERRORS.LOAD_ERROR') }}</span>
      <Button
        :label="t('PILOT.FAQS.ERROR.RETRY')"
        size="sm"
        variant="faded"
        color="ruby"
        @click="onRetry"
      />
    </div>

    <!-- Soft Limit Banner -->
    <div
      v-if="!isLoading && !hasError && rows.length > 10"
      class="p-4 bg-amber-50 dark:bg-amber-950/20 border border-amber-300 dark:border-amber-900 text-amber-800 dark:text-amber-200 rounded-xl flex items-start gap-3 mb-2"
    >
      <span class="i-lucide-alert-triangle size-5 mt-0.5 flex-shrink-0" />
      <p class="text-sm mb-0">
        {{ t('PILOT.TOOLS.SOFT_LIMIT_BANNER') }}
      </p>
    </div>

    <!-- Loading Skeleton state -->
    <template v-if="isLoading">
      <div
        v-for="i in skeletonCount"
        :key="`tool-skeleton-${i}`"
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-2 border border-n-weak animate-pulse"
      >
        <div class="h-4 w-1/3 rounded bg-n-alpha-1" />
        <div class="h-3 w-5/6 rounded bg-n-alpha-1" />
        <div class="flex gap-2 pt-1 border-t border-n-weak/50 mt-1">
          <div class="h-4 w-20 rounded-full bg-n-alpha-1" />
          <div class="h-4 w-24 rounded-full bg-n-alpha-1" />
        </div>
      </div>
    </template>

    <!-- Empty state with spotlight -->
    <template v-else-if="!hasError && rows.length === 0">
      <!-- Feature Spotlight Card -->
      <div
        class="p-6 rounded-xl border border-n-weak bg-n-alpha-1 flex flex-col md:flex-row items-center gap-6 mb-4 text-start"
      >
        <div class="flex-shrink-0">
          <img
            src="dashboard/assets/images/no-chat.svg"
            class="block dark:hidden w-32 h-32"
            alt="Custom Tools Spotlight"
          />
          <img
            src="dashboard/assets/images/no-chat-dark.svg"
            class="hidden dark:block w-32 h-32"
            alt="Custom Tools Spotlight dark"
          />
        </div>
        <div class="flex flex-col gap-2">
          <h3 class="text-lg font-semibold text-n-slate-12">
            {{ t('PILOT.TOOLS.EMPTY.SPOTLIGHT_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 leading-relaxed mb-0">
            {{ t('PILOT.TOOLS.EMPTY.SPOTLIGHT_DESC') }}
          </p>
          <a
            href="https://konversio.org/docs"
            target="_blank"
            rel="noopener noreferrer"
            class="text-sm text-n-brand hover:underline flex items-center gap-1 mt-2 font-medium"
          >
            {{ t('PILOT.TOOLS.EMPTY.LEARN_MORE') }}
            <span class="i-lucide-external-link size-3.5" />
          </a>
        </div>
      </div>

      <!-- Standard Empty CTA Card -->
      <div
        class="flex flex-col items-center justify-center gap-3 p-12 rounded-xl border border-dashed border-n-weak text-center"
      >
        <span
          aria-hidden="true"
          class="i-lucide-wrench size-10 text-n-slate-9"
        />
        <h3 class="text-heading-sm text-n-slate-12">
          {{ t('PILOT.TOOLS.EMPTY.TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-10 max-w-md mb-2">
          {{ t('PILOT.TOOLS.EMPTY.SUBTITLE') }}
        </p>
        <Button
          v-if="isAdmin"
          :label="t('PILOT.TOOLS.EMPTY.CTA')"
          icon="i-lucide-plus"
          color="blue"
          @click="onCreate"
        />
      </div>
    </template>

    <!-- Render List of cards -->
    <template v-else-if="!hasError">
      <ToolCard
        v-for="row in rows"
        :key="row.id"
        :row="row"
        :is-admin="isAdmin"
        @edit="onEdit"
        @delete="onDelete"
      />
    </template>
  </section>
</template>
