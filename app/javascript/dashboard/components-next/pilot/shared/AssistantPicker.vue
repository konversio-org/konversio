<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Icon from 'next/icon/Icon.vue';
import {
  DropdownContainer,
  DropdownBody,
  DropdownSection,
  DropdownItem,
} from 'next/dropdown-menu/base';

const props = defineProps({
  modelValue: {
    type: [Number, String, null],
    default: null,
  },
  assistants: {
    type: Array,
    default: null,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const store = useStore();
const storeRecords = useMapGetter('pilot/assistants/getRecords');
const uiFlags = useMapGetter('pilot/assistants/getUIFlags');

const items = computed(() =>
  Array.isArray(props.assistants) ? props.assistants : storeRecords.value
);

const selectedId = computed(() =>
  props.modelValue == null ? null : Number(props.modelValue)
);

const selected = computed(
  () => items.value.find(a => a.id === selectedId.value) || null
);

const triggerLabel = computed(
  () => selected.value?.name || t('PILOT_ASSISTANT_PICKER.LABEL_FALLBACK')
);

const hasItems = computed(() => items.value.length > 0);

onMounted(() => {
  if (
    props.assistants === null &&
    !storeRecords.value.length &&
    !uiFlags.value.isFetching
  ) {
    store.dispatch('pilot/assistants/fetch').catch(() => {});
  }
});

const onSelect = id => {
  emit('update:modelValue', id);
};
</script>

<template>
  <DropdownContainer>
    <template #trigger="{ toggle, isOpen }">
      <button
        type="button"
        :aria-label="t('PILOT_ASSISTANT_PICKER.ARIA_LABEL')"
        aria-haspopup="listbox"
        class="flex items-center gap-2 justify-between w-full rounded-lg px-2 py-1.5 hover:bg-n-alpha-1"
        :class="[isOpen && 'bg-n-alpha-1']"
        @click="toggle"
      >
        <span
          class="text-sm font-medium leading-5 text-n-slate-12 truncate"
          aria-live="polite"
        >
          {{ triggerLabel }}
        </span>
        <span
          aria-hidden="true"
          class="i-lucide-chevron-down size-4 text-n-slate-10 flex-shrink-0"
        />
      </button>
    </template>
    <DropdownBody class="min-w-64 z-50">
      <DropdownSection v-if="hasItems">
        <DropdownItem
          v-for="assistant in items"
          :id="`pilot-assistant-${assistant.id}`"
          :key="assistant.id"
          class="cursor-pointer"
          @click="onSelect(assistant.id)"
        >
          <template #label>
            <span
              class="text-n-slate-12 truncate min-w-0 flex-1 text-left rtl:text-right"
              :title="assistant.name"
            >
              {{ assistant.name }}
            </span>
            <Icon
              v-show="assistant.id === selectedId"
              icon="i-lucide-check"
              class="text-n-teal-11 size-5"
            />
          </template>
        </DropdownItem>
      </DropdownSection>
      <DropdownSection v-else>
        <li class="px-2 py-2 text-sm text-n-slate-11 text-left rtl:text-right">
          {{ t('PILOT_ASSISTANT_PICKER.EMPTY') }}
        </li>
      </DropdownSection>
    </DropdownBody>
  </DropdownContainer>
</template>
