<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import Switch from 'dashboard/components-next/switch/Switch.vue';
import PilotPreferencesAPI from 'dashboard/api/pilot/preferences';

const { t } = useI18n();

const enabled = ref(false);
const isSaving = ref(false);

const fetchPreferences = async () => {
  try {
    const { data } = await PilotPreferencesAPI.fetch();
    enabled.value = !!data?.false_promise_guard_enabled;
  } catch (_e) {
    // Non-fatal: the toggle keeps its default (off).
  }
};

const onToggle = async () => {
  if (isSaving.value) return;
  const next = !enabled.value;
  enabled.value = next;
  isSaving.value = true;
  try {
    await PilotPreferencesAPI.update({
      pilot_false_promise_guard_enabled: next,
    });
    useAlert(t('PILOT.SETTINGS.PROMISE_GUARD.UPDATED'));
  } catch (_e) {
    enabled.value = !next;
    useAlert(t('PILOT.SETTINGS.PROMISE_GUARD.UPDATE_FAILED'));
  } finally {
    isSaving.value = false;
  }
};

onMounted(fetchPreferences);
</script>

<template>
  <div
    class="flex items-start justify-between gap-4 p-4 bg-n-solid-1 rounded-xl border border-n-weak"
  >
    <div class="flex flex-col gap-1">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('PILOT.SETTINGS.PROMISE_GUARD.TITLE') }}
      </h3>
      <p class="text-xs text-n-slate-11 leading-relaxed max-w-xl">
        {{ t('PILOT.SETTINGS.PROMISE_GUARD.DESCRIPTION') }}
      </p>
    </div>
    <label class="flex items-center shrink-0 cursor-pointer">
      <Switch :model-value="enabled" @update:model-value="onToggle" />
    </label>
  </div>
</template>
