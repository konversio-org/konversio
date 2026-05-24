<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';

const props = defineProps({
  authType: { type: String, required: true },
  modelValue: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const config = computed({
  get: () => props.modelValue || {},
  set: val => emit('update:modelValue', val),
});

const showSecret = ref(false);
const showPassword = ref(false);

const updateField = (key, value) => {
  config.value = {
    ...config.value,
    [key]: value,
  };
};
</script>

<template>
  <div>
    <div
      v-if="authType !== 'none'"
      class="flex flex-col gap-4 p-4 border border-n-weak rounded-xl bg-n-alpha-black2"
    >
      <!-- Bearer Auth -->
      <div v-if="authType === 'bearer'" class="relative flex flex-col gap-1">
        <Input
          :model-value="config.token || ''"
          :type="showSecret ? 'text' : 'password'"
          :label="t('PILOT.TOOLS.DIALOG.FIELD_AUTH_BEARER_TOKEN')"
          :placeholder="
            t('PILOT.TOOLS.DIALOG.FIELD_AUTH_BEARER_TOKEN_PLACEHOLDER')
          "
          @update:model-value="updateField('token', $event)"
        />
        <button
          type="button"
          class="absolute right-3 top-9 text-n-slate-10 hover:text-n-slate-12 transition-colors focus:outline-none"
          @click="showSecret = !showSecret"
        >
          <FluentIcon
            :icon="showSecret ? 'eye-hide-outline' : 'eye-show-outline'"
            size="18"
          />
        </button>
      </div>

      <!-- Basic Auth -->
      <div v-else-if="authType === 'basic'" class="flex flex-col gap-4">
        <Input
          :model-value="config.username || ''"
          type="text"
          :label="t('PILOT.TOOLS.DIALOG.FIELD_AUTH_BASIC_USER')"
          :placeholder="
            t('PILOT.TOOLS.DIALOG.FIELD_AUTH_BASIC_USER_PLACEHOLDER')
          "
          @update:model-value="updateField('username', $event)"
        />
        <div class="relative flex flex-col gap-1">
          <Input
            :model-value="config.password || ''"
            :type="showPassword ? 'text' : 'password'"
            :label="t('PILOT.TOOLS.DIALOG.FIELD_AUTH_BASIC_PASS')"
            :placeholder="
              t('PILOT.TOOLS.DIALOG.FIELD_AUTH_BASIC_PASS_PLACEHOLDER')
            "
            @update:model-value="updateField('password', $event)"
          />
          <button
            type="button"
            class="absolute right-3 top-9 text-n-slate-10 hover:text-n-slate-12 transition-colors focus:outline-none"
            @click="showPassword = !showPassword"
          >
            <FluentIcon
              :icon="showPassword ? 'eye-hide-outline' : 'eye-show-outline'"
              size="18"
            />
          </button>
        </div>
      </div>

      <!-- API Key Auth -->
      <div v-else-if="authType === 'api_key'" class="flex flex-col gap-4">
        <!-- Placement Radio / Toggle -->
        <div class="flex flex-col gap-2">
          <span class="text-heading-3 text-n-slate-12">
            {{ t('PILOT.TOOLS.DIALOG.FIELD_AUTH_API_KEY_PLACEMENT') }}
          </span>
          <div class="flex gap-4">
            <label
              class="flex items-center gap-2 text-sm text-n-slate-12 cursor-pointer select-none"
            >
              <input
                type="radio"
                value="header"
                :checked="config.placement !== 'query'"
                class="accent-n-brand"
                @change="updateField('placement', 'header')"
              />
              {{ t('PILOT.TOOLS.DIALOG.FIELD_AUTH_API_KEY_PLACEMENT_HEADER') }}
            </label>
            <label
              class="flex items-center gap-2 text-sm text-n-slate-12 cursor-pointer select-none"
            >
              <input
                type="radio"
                value="query"
                :checked="config.placement === 'query'"
                class="accent-n-brand"
                @change="updateField('placement', 'query')"
              />
              {{ t('PILOT.TOOLS.DIALOG.FIELD_AUTH_API_KEY_PLACEMENT_QUERY') }}
            </label>
          </div>
        </div>

        <Input
          :model-value="config.name || ''"
          type="text"
          :label="t('PILOT.TOOLS.DIALOG.FIELD_AUTH_API_KEY_NAME')"
          :placeholder="
            t('PILOT.TOOLS.DIALOG.FIELD_AUTH_API_KEY_NAME_PLACEHOLDER')
          "
          @update:model-value="updateField('name', $event)"
        />

        <div class="relative flex flex-col gap-1">
          <Input
            :model-value="config.value || ''"
            :type="showSecret ? 'text' : 'password'"
            :label="t('PILOT.TOOLS.DIALOG.FIELD_AUTH_API_KEY_VALUE')"
            :placeholder="
              t('PILOT.TOOLS.DIALOG.FIELD_AUTH_API_KEY_VALUE_PLACEHOLDER')
            "
            @update:model-value="updateField('value', $event)"
          />
          <button
            type="button"
            class="absolute right-3 top-9 text-n-slate-10 hover:text-n-slate-12 transition-colors focus:outline-none"
            @click="showSecret = !showSecret"
          >
            <FluentIcon
              :icon="showSecret ? 'eye-hide-outline' : 'eye-show-outline'"
              size="18"
            />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
