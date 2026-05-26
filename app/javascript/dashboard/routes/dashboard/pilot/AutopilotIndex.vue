<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';

import AssistantPicker from 'dashboard/components-next/pilot/shared/AssistantPicker.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import {
  DropdownContainer,
  DropdownBody,
  DropdownSection,
  DropdownItem,
} from 'dashboard/components-next/dropdown-menu/base';
import AssistantEditor from './AssistantEditor.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const assistants = useMapGetter('pilot/assistants/getRecords');
const activeAssistantId = useMapGetter('pilot/assistants/getActiveId');
const uiFlags = useMapGetter('pilot/assistants/getUIFlags');

const activeTabKey = ref('settings');
const showEditor = ref(false);
const editingAssistant = ref(null);

const activeAssistant = computed(
  () => assistants.value.find(a => a.id === activeAssistantId.value) || null
);
const editorAssistant = computed(() => {
  if (showEditor.value) return editingAssistant.value;
  if (activeTabKey.value === 'settings') return activeAssistant.value;
  return null;
});
const shouldShowEditor = computed(
  () => !!editorAssistant.value || showEditor.value
);

const tabs = computed(() => {
  const list = [
    {
      key: 'settings',
      label: t('PILOT.SETTINGS.TABS.ACTIVE_SETTINGS'),
    },
  ];
  if (assistants.value.length > 0) {
    list.push({
      key: 'all',
      label: t('PILOT.SETTINGS.TABS.ALL_ASSISTANTS'),
    });
  }
  return list;
});

const activeTabIndex = computed(() =>
  tabs.value.findIndex(tab => tab.key === activeTabKey.value)
);

const onTabChanged = tab => {
  activeTabKey.value = tab.key;
  if (tab.key === 'settings') {
    showEditor.value = false;
    editingAssistant.value = null;
  }
};

onMounted(async () => {
  if (!assistants.value.length && !uiFlags.value.isFetching) {
    try {
      await store.dispatch('pilot/assistants/fetch');
    } catch (_e) {
      // Handled via store/ui
    }
  }
  if (!activeAssistantId.value && assistants.value.length) {
    store.dispatch('pilot/assistants/setActive', assistants.value[0].id);
  }
});

const onCreateNew = () => {
  editingAssistant.value = null;
  showEditor.value = true;
  activeTabKey.value = 'settings';
};

const onEdit = assistant => {
  editingAssistant.value = assistant;
  showEditor.value = true;
  activeTabKey.value = 'settings';
};

const onDelete = async id => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('PILOT.SETTINGS.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('pilot/assistants/delete', id);
    useAlert(t('PILOT.SETTINGS.TOAST.DELETED'));
    if (activeAssistantId.value === id) {
      const remaining = assistants.value;
      if (remaining.length) {
        store.dispatch('pilot/assistants/setActive', remaining[0].id);
      }
    }
  } catch (_e) {
    useAlert(t('PILOT.SETTINGS.ERRORS.DELETE_FAILED'));
  }
};

const onSelectActive = id => {
  store.dispatch('pilot/assistants/setActive', id);
  activeTabKey.value = 'settings';
  showEditor.value = false;
  editingAssistant.value = null;
};

const onViewInboxes = id => {
  router.push(accountScopedRoute('pilot_inboxes', {}, { assistant_id: id }));
};

const onSaved = () => {
  showEditor.value = false;
  editingAssistant.value = null;
  store.dispatch('pilot/assistants/fetch');
};

const onCancel = () => {
  showEditor.value = false;
  editingAssistant.value = null;
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6 border-b border-n-weak">
      <div class="w-full max-w-5xl mx-auto flex flex-col gap-4 py-4">
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <div class="flex flex-wrap items-center gap-x-3 gap-y-2 min-w-0">
            <div v-if="assistants.length > 0" class="min-w-48 max-w-64">
              <AssistantPicker
                :model-value="activeAssistantId"
                @update:model-value="onSelectActive"
              />
            </div>
            <span
              v-if="assistants.length > 0"
              aria-hidden="true"
              class="h-5 w-px bg-n-weak"
            />
            <h1 class="text-heading-md font-medium text-n-slate-12 truncate">
              {{ t('PILOT.SETTINGS.HEADER.TITLE') }}
            </h1>
          </div>
          <Button
            :label="t('PILOT.SETTINGS.HEADER.CREATE_BUTTON')"
            icon="i-lucide-plus"
            size="sm"
            @click="onCreateNew"
          />
        </div>

        <TabBar
          v-if="assistants.length > 0"
          :tabs="tabs"
          :initial-active-tab="activeTabIndex"
          class="self-start"
          @tab-changed="onTabChanged"
        />
      </div>
    </header>

    <main class="flex-1 px-6 overflow-y-auto py-6">
      <div class="w-full max-w-5xl mx-auto">
        <!-- Zero State -->
        <div
          v-if="
            !shouldShowEditor && assistants.length === 0 && !uiFlags.isFetching
          "
          class="flex flex-col items-center justify-center text-center p-12 bg-n-solid-1 border border-dashed border-n-weak rounded-xl gap-4"
        >
          <div
            class="size-12 rounded-lg bg-n-alpha-1 flex items-center justify-center text-n-slate-11"
          >
            <span class="i-lucide-bot size-6" />
          </div>
          <div class="flex flex-col gap-1">
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ t('PILOT.SETTINGS.EMPTY.TITLE') }}
            </h3>
            <p class="text-xs text-n-slate-11 max-w-sm leading-relaxed">
              {{ t('PILOT.SETTINGS.EMPTY.BODY') }}
            </p>
          </div>
          <Button
            :label="t('PILOT.SETTINGS.EMPTY.CREATE_BUTTON')"
            size="sm"
            @click="onCreateNew"
          />
        </div>

        <!-- Editor Mode (Creating or Editing specific assistant) -->
        <div v-else-if="shouldShowEditor">
          <AssistantEditor
            :assistant="editorAssistant"
            @saved="onSaved"
            @cancel="onCancel"
          />
        </div>

        <!-- All Assistants List Tab -->
        <div v-else-if="activeTabKey === 'all'" class="flex flex-col gap-4">
          <div
            class="bg-n-solid-1 border border-n-weak rounded-xl overflow-visible"
          >
            <table class="w-full text-left border-collapse text-sm">
              <thead>
                <tr class="border-b border-n-weak bg-n-alpha-1">
                  <th class="p-4 font-medium text-n-slate-11">
                    {{ t('PILOT.SETTINGS.TABLE.NAME') }}
                  </th>
                  <th class="p-4 font-medium text-n-slate-11">
                    {{ t('PILOT.SETTINGS.TABLE.DESCRIPTION') }}
                  </th>
                  <th class="p-4 font-medium text-n-slate-11">
                    {{ t('PILOT.SETTINGS.TABLE.STATUS') }}
                  </th>
                  <th class="p-4 font-medium text-n-slate-11 text-right">
                    {{ t('PILOT.SETTINGS.TABLE.ACTIONS') }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr
                  v-for="item in assistants"
                  :key="item.id"
                  class="hover:bg-n-alpha-1"
                >
                  <td class="p-4 font-medium text-n-slate-12">
                    {{ item.name }}
                  </td>
                  <td class="p-4 text-n-slate-11 max-w-xs truncate">
                    {{ item.description || '-' }}
                  </td>
                  <td class="p-4">
                    <span
                      v-if="item.id === activeAssistantId"
                      class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-n-teal-3 text-n-teal-11"
                    >
                      {{ t('PILOT.SETTINGS.STATUS.ACTIVE') }}
                    </span>
                    <span
                      v-else
                      class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-n-slate-3 text-n-slate-11"
                    >
                      {{ t('PILOT.SETTINGS.STATUS.INACTIVE') }}
                    </span>
                  </td>
                  <td class="p-4 text-right">
                    <div class="inline-flex justify-end">
                      <DropdownContainer>
                        <template #trigger="{ toggle }">
                          <Button
                            variant="ghost"
                            color="slate"
                            size="xs"
                            icon="i-lucide-ellipsis-vertical"
                            :aria-label="t('PILOT.SETTINGS.TABLE.ACTIONS')"
                            @click="toggle"
                          />
                        </template>
                        <DropdownBody class="right-0 min-w-52 z-50">
                          <DropdownSection>
                            <DropdownItem
                              v-if="item.id !== activeAssistantId"
                              :click="() => onSelectActive(item.id)"
                            >
                              <template #label>
                                <span
                                  class="flex items-center gap-3 w-full text-left rtl:text-right"
                                >
                                  <span
                                    class="i-lucide-check-circle size-4 text-n-slate-11"
                                    aria-hidden="true"
                                  />
                                  {{ t('PILOT.SETTINGS.ACTIONS.SET_ACTIVE') }}
                                </span>
                              </template>
                            </DropdownItem>
                            <DropdownItem :click="() => onViewInboxes(item.id)">
                              <template #label>
                                <span
                                  class="flex items-center gap-3 w-full text-left rtl:text-right"
                                >
                                  <span
                                    class="i-lucide-inbox size-4 text-n-slate-11"
                                    aria-hidden="true"
                                  />
                                  {{ t('PILOT.SETTINGS.ACTIONS.VIEW_INBOXES') }}
                                </span>
                              </template>
                            </DropdownItem>
                            <DropdownItem :click="() => onEdit(item)">
                              <template #label>
                                <span
                                  class="flex items-center gap-3 w-full text-left rtl:text-right"
                                >
                                  <span
                                    class="i-lucide-pencil size-4 text-n-slate-11"
                                    aria-hidden="true"
                                  />
                                  {{ t('PILOT.SETTINGS.ACTIONS.EDIT') }}
                                </span>
                              </template>
                            </DropdownItem>
                            <DropdownItem :click="() => onDelete(item.id)">
                              <template #label>
                                <span
                                  class="flex items-center gap-3 w-full text-n-ruby-11 text-left rtl:text-right"
                                >
                                  <span
                                    class="i-lucide-trash-2 size-4 text-n-ruby-11"
                                    aria-hidden="true"
                                  />
                                  {{ t('PILOT.SETTINGS.ACTIONS.DELETE') }}
                                </span>
                              </template>
                            </DropdownItem>
                          </DropdownSection>
                        </DropdownBody>
                      </DropdownContainer>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </main>
  </section>
</template>
