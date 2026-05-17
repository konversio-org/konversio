<script setup>
import { useI18n } from 'vue-i18n';

const props = defineProps({
  threads: {
    type: Array,
    default: () => [],
  },
  activeThreadId: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits(['select', 'new']);

const { t } = useI18n();

const isActive = thread => String(thread.id) === String(props.activeThreadId);
</script>

<template>
  <aside
    class="flex flex-col gap-1 px-2 py-3 border-b border-n-weak max-h-40 overflow-y-auto"
  >
    <div class="flex items-center justify-between px-1 mb-1">
      <span class="text-xs font-medium text-n-slate-11 uppercase tracking-wide">
        {{ t('PILOT.COPILOT.THREADS') }}
      </span>
      <button
        type="button"
        class="flex items-center gap-1 text-xs text-n-violet-9 hover:text-n-violet-11"
        @click="emit('new')"
      >
        <span class="i-lucide-plus size-3" />
        {{ t('PILOT.COPILOT.NEW_THREAD') }}
      </button>
    </div>
    <div v-if="threads.length === 0" class="text-xs text-n-slate-10 px-2 py-1">
      {{ t('PILOT.COPILOT.NO_THREADS') }}
    </div>
    <button
      v-for="thread in threads"
      :key="thread.id"
      type="button"
      class="text-left text-sm px-2 py-1.5 rounded-md truncate"
      :class="
        isActive(thread)
          ? 'bg-n-violet-3 text-n-violet-12'
          : 'text-n-slate-12 hover:bg-n-alpha-2'
      "
      @click="emit('select', thread.id)"
    >
      {{ thread.title || t('PILOT.COPILOT.UNTITLED_THREAD') }}
    </button>
  </aside>
</template>
