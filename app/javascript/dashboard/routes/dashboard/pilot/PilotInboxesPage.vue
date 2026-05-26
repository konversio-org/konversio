<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import AssistantPicker from 'dashboard/components-next/pilot/shared/AssistantPicker.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();

const activeAssistantId = useMapGetter('pilot/assistants/getActiveId');
const assistants = useMapGetter('pilot/assistants/getRecords');
const attachedInboxes = useMapGetter('pilot/autopilot/getInboxes');
const allInboxes = useMapGetter('inboxes/getInboxes');
const uiFlags = useMapGetter('pilot/autopilot/getUIFlags');

const routeAssistantId = () => {
  const id = Number(route.query.assistant_id);
  return Number.isFinite(id) && id > 0 ? id : null;
};

const selectedAssistantId = ref(routeAssistantId() || activeAssistantId.value);
const selectedInboxId = ref(null);
const error = ref('');

const isLoading = computed(() => uiFlags.value.isFetchingInboxes);
const isAttaching = computed(() => uiFlags.value.isCreatingInbox);
const isDetaching = computed(() => uiFlags.value.isDeletingInbox);

const unattachedInboxes = computed(() => {
  const attachedIds = new Set(
    attachedInboxes.value.map(i => i.inbox_id || i.id)
  );
  return allInboxes.value.filter(inbox => !attachedIds.has(inbox.id));
});

const channelTypeLabels = computed(() => ({
  'Channel::FacebookPage': t('INBOX_MGMT.CHANNELS.MESSENGER'),
  'Channel::WebWidget': t('INBOX_MGMT.CHANNELS.WEB_WIDGET'),
  'Channel::TwitterProfile': t('INBOX_MGMT.CHANNELS.TWITTER_PROFILE'),
  'Channel::TwilioSms': t('INBOX_MGMT.CHANNELS.TWILIO_SMS'),
  'Channel::Whatsapp': t('INBOX_MGMT.CHANNELS.WHATSAPP'),
  'Channel::Sms': t('INBOX_MGMT.CHANNELS.SMS'),
  'Channel::Email': t('INBOX_MGMT.CHANNELS.EMAIL'),
  'Channel::Telegram': t('INBOX_MGMT.CHANNELS.TELEGRAM'),
  'Channel::Line': t('INBOX_MGMT.CHANNELS.LINE'),
  'Channel::Api': t('INBOX_MGMT.CHANNELS.API'),
  'Channel::Instagram': t('INBOX_MGMT.CHANNELS.INSTAGRAM'),
  'Channel::Tiktok': t('INBOX_MGMT.CHANNELS.TIKTOK'),
  'Channel::Voice': t('INBOX_MGMT.CHANNELS.VOICE'),
}));

const channelTypeLabel = inbox => {
  const channelType = inbox.channel_type || inbox.channelType;
  const medium = inbox.medium || inbox.inbox?.medium;
  if (channelType === 'Channel::TwilioSms' && medium === 'whatsapp') {
    return t('INBOX_MGMT.CHANNELS.WHATSAPP');
  }

  return channelTypeLabels.value[channelType] || channelType || '-';
};

const fetchAttachedInboxes = async () => {
  if (!selectedAssistantId.value) return;
  try {
    await store.dispatch(
      'pilot/autopilot/fetchInboxes',
      selectedAssistantId.value
    );
  } catch (_e) {
    // Handled
  }
};

const assistantExists = id =>
  assistants.value.some(assistant => assistant.id === id);

const selectAvailableAssistant = () => {
  const requestedId = routeAssistantId();
  let nextAssistantId = null;

  if (requestedId && assistantExists(requestedId)) {
    nextAssistantId = requestedId;
  } else if (
    selectedAssistantId.value &&
    assistantExists(selectedAssistantId.value)
  ) {
    nextAssistantId = selectedAssistantId.value;
  } else if (
    activeAssistantId.value &&
    assistantExists(activeAssistantId.value)
  ) {
    nextAssistantId = activeAssistantId.value;
  } else if (assistants.value.length) {
    nextAssistantId = assistants.value[0].id;
  }

  selectedAssistantId.value = nextAssistantId;
  if (selectedAssistantId.value) {
    store.dispatch('pilot/assistants/setActive', selectedAssistantId.value);
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
  if (!allInboxes.value.length) {
    try {
      await store.dispatch('inboxes/get');
    } catch (_e) {
      // Handled
    }
  }
  selectAvailableAssistant();
  fetchAttachedInboxes();
});

watch(selectedAssistantId, () => {
  if (selectedAssistantId.value) {
    store.dispatch('pilot/assistants/setActive', selectedAssistantId.value);
    fetchAttachedInboxes();
  }
});

watch(activeAssistantId, newId => {
  if (newId && newId !== selectedAssistantId.value) {
    selectedAssistantId.value = newId;
  }
});

const attachInbox = async () => {
  if (!selectedInboxId.value || !selectedAssistantId.value) return;
  error.value = '';
  try {
    await store.dispatch('pilot/autopilot/createInbox', {
      assistantId: selectedAssistantId.value,
      inboxId: selectedInboxId.value,
    });
    useAlert(t('PILOT.INBOXES.TOAST.ATTACHED'));
    selectedInboxId.value = null;
    fetchAttachedInboxes();
  } catch (err) {
    error.value =
      err?.response?.data?.message ||
      err?.message ||
      t('PILOT.INBOXES.ERRORS.ATTACH_FAILED');
  }
};

const detachInbox = async inboxId => {
  if (!selectedAssistantId.value) return;
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('PILOT.INBOXES.CONFIRM_DETACH'))) return;
  error.value = '';
  try {
    await store.dispatch('pilot/autopilot/deleteInbox', {
      assistantId: selectedAssistantId.value,
      inboxId,
    });
    useAlert(t('PILOT.INBOXES.TOAST.DETACHED'));
    fetchAttachedInboxes();
  } catch (err) {
    error.value =
      err?.response?.data?.message ||
      err?.message ||
      t('PILOT.INBOXES.ERRORS.DETACH_FAILED');
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
              {{ t('PILOT.INBOXES.HEADER.TITLE') }}
            </h1>
          </div>
        </div>
      </div>
    </header>

    <main class="flex-1 px-6 overflow-y-auto py-6">
      <div class="w-full max-w-5xl mx-auto flex flex-col gap-6">
        <!-- Error Alert -->
        <div
          v-if="error"
          class="p-3 rounded-lg bg-n-ruby-3 border border-n-ruby-6 text-sm text-n-ruby-11"
          role="alert"
        >
          {{ error }}
        </div>

        <div
          v-if="selectedAssistantId"
          class="grid grid-cols-1 md:grid-cols-3 gap-6"
        >
          <!-- Attach Form -->
          <div
            class="bg-n-solid-1 border border-n-weak rounded-xl p-5 flex flex-col gap-4 self-start"
          >
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ t('PILOT.INBOXES.ATTACH.TITLE') }}
            </h3>
            <p class="text-xs text-n-slate-10 leading-relaxed">
              {{ t('PILOT.INBOXES.ATTACH.BODY') }}
            </p>

            <div class="flex flex-col gap-1.5 mt-2">
              <label
                for="inbox-select"
                class="text-xs font-semibold text-n-slate-11 uppercase tracking-wider"
              >
                {{ t('PILOT.INBOXES.ATTACH.INBOX_LABEL') }}
              </label>
              <select
                id="inbox-select"
                v-model="selectedInboxId"
                class="w-full h-10 px-3 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:border-n-blue-9"
              >
                <option :value="null" disabled>
                  {{ t('PILOT.INBOXES.ATTACH.INBOX_PLACEHOLDER') }}
                </option>
                <option
                  v-for="inbox in unattachedInboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
                  {{ inbox.name + ' (' + channelTypeLabel(inbox) + ')' }}
                </option>
              </select>
            </div>

            <Button
              type="button"
              :label="t('PILOT.INBOXES.ATTACH.SUBMIT_BUTTON')"
              :disabled="!selectedInboxId"
              :is-loading="isAttaching"
              class="w-full mt-2"
              @click="attachInbox"
            />
          </div>

          <!-- Attached List -->
          <div class="md:col-span-2 flex flex-col gap-4">
            <div
              class="bg-n-solid-1 border border-n-weak rounded-xl overflow-hidden"
            >
              <table class="w-full text-left border-collapse text-sm">
                <thead>
                  <tr class="border-b border-n-weak bg-n-alpha-1">
                    <th class="p-4 font-medium text-n-slate-11">
                      {{ t('PILOT.INBOXES.TABLE.INBOX') }}
                    </th>
                    <th class="p-4 font-medium text-n-slate-11">
                      {{ t('PILOT.INBOXES.TABLE.CHANNEL_TYPE') }}
                    </th>
                    <th class="p-4 font-medium text-n-slate-11 text-right">
                      {{ t('PILOT.INBOXES.TABLE.ACTIONS') }}
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-n-weak">
                  <tr
                    v-for="inbox in attachedInboxes"
                    :key="inbox.id"
                    class="hover:bg-n-alpha-1"
                  >
                    <td class="p-4 font-medium text-n-slate-12">
                      {{ inbox.name || inbox.inbox?.name }}
                    </td>
                    <td class="p-4 text-n-slate-11">
                      {{
                        channelTypeLabel({
                          channel_type:
                            inbox.channel_type || inbox.inbox?.channel_type,
                          medium: inbox.medium || inbox.inbox?.medium,
                        })
                      }}
                    </td>
                    <td class="p-4 text-right">
                      <Button
                        variant="ghost"
                        color="ruby"
                        size="xs"
                        :label="t('PILOT.INBOXES.ACTIONS.DETACH')"
                        :is-loading="isDetaching"
                        @click="detachInbox(inbox.inbox_id || inbox.id)"
                      />
                    </td>
                  </tr>
                  <tr v-if="attachedInboxes.length === 0 && !isLoading">
                    <td
                      colspan="3"
                      class="p-8 text-center text-n-slate-10 italic"
                    >
                      {{ t('PILOT.INBOXES.TABLE.EMPTY') }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </main>
  </section>
</template>
