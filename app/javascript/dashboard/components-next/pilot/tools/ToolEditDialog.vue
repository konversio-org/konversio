<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';

import AuthConfigFields from './AuthConfigFields.vue';
import ParamSchemaEditor from './ParamSchemaEditor.vue';
import LiquidTemplateField from './LiquidTemplateField.vue';

const props = defineProps({
  mode: {
    type: String,
    default: 'create',
    validator: v => ['create', 'edit'].includes(v),
  },
  tool: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['close', 'success']);

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const paramEditorRef = ref(null);

const form = ref({
  title: '',
  description: '',
  endpoint_url: '',
  http_method: 'GET',
  auth_type: 'none',
  auth_config: {},
  param_schema: [],
  request_template: '',
  response_template: '',
  enabled: true,
});

const errors = ref({});
const serverFieldErrors = ref({});
const serverParamErrors = ref({});
const generalError = ref('');

const isSaving = computed(() => store.getters['pilotCustomTools/getSaving']);
const isTesting = computed(() => store.getters['pilotCustomTools/getTesting']);

const isSavingDisabled = computed(() => {
  return form.value.title.length > 55;
});

const titleMessage = computed(() => {
  if (form.value.title.length > 55) {
    return t('PILOT.TOOLS.DIALOG.FIELD_TITLE_MAX_LEN');
  }
  return errors.value.title || serverFieldErrors.value.title || '';
});

const titleMessageType = computed(() => {
  if (
    form.value.title.length > 55 ||
    errors.value.title ||
    serverFieldErrors.value.title
  ) {
    return 'error';
  }
  return 'info';
});

const urlMessage = computed(() => {
  return (
    errors.value.endpoint_url || serverFieldErrors.value.endpoint_url || ''
  );
});

const urlMessageType = computed(() => {
  if (errors.value.endpoint_url || serverFieldErrors.value.endpoint_url) {
    return 'error';
  }
  return 'info';
});

const isTestDisabled = computed(() => {
  const urlHasTemplate = form.value.endpoint_url.includes('{{');
  const hasRequestTemplate = !!(
    form.value.request_template && form.value.request_template.trim()
  );
  return urlHasTemplate || hasRequestTemplate;
});

const testStatus = ref(null); // 'success' | 'error' | null
const testMessage = ref('');
const testErrorCode = ref('');

const testStatusConfig = computed(() => {
  if (testStatus.value === 'success') {
    return {
      classes: 'bg-n-teal-1 border border-n-teal-8 text-n-teal-10',
      icon: 'checkmark-outline',
    };
  }

  if (testStatus.value === 'error') {
    switch (testErrorCode.value) {
      case 'tool.timeout':
        return {
          classes: 'bg-amber-50 border border-amber-500 text-amber-800',
          icon: 'alert-outline',
        };
      case 'tool.host_not_allowed':
      case 'tool.private_ip_denied':
        return {
          classes: 'bg-red-50 border border-red-500 text-red-800',
          icon: 'lock-shield-outline',
        };
      case 'tool.disabled':
        return {
          classes: 'bg-n-slate-1 border border-n-slate-6 text-n-slate-11',
          icon: 'dismiss-outline',
        };
      case 'tool.parse_error':
        return {
          classes: 'bg-purple-50 border border-purple-500 text-purple-800',
          icon: 'alert-outline',
        };
      default:
        return {
          classes: 'bg-n-ruby-1 border border-n-ruby-8 text-n-ruby-9',
          icon: 'dismiss-outline',
        };
    }
  }

  return null;
});

watch(
  () => props.tool,
  newTool => {
    if (newTool && props.mode === 'edit') {
      form.value = {
        title: newTool.title || '',
        description: newTool.description || '',
        endpoint_url: newTool.endpoint_url || '',
        http_method: newTool.http_method || 'GET',
        auth_type: newTool.auth_type || 'none',
        auth_config: newTool.auth_config ? { ...newTool.auth_config } : {},
        param_schema: newTool.param_schema
          ? JSON.parse(JSON.stringify(newTool.param_schema))
          : [],
        request_template: newTool.request_template || '',
        response_template: newTool.response_template || '',
        enabled: newTool.enabled !== false,
      };
    } else {
      form.value = {
        title: '',
        description: '',
        endpoint_url: '',
        http_method: 'GET',
        auth_type: 'none',
        auth_config: {},
        param_schema: [],
        request_template: '',
        response_template: '',
        enabled: true,
      };
    }
    errors.value = {};
    serverFieldErrors.value = {};
    serverParamErrors.value = {};
    generalError.value = '';
    testStatus.value = null;
    testMessage.value = '';
    testErrorCode.value = '';
  },
  { immediate: true }
);

const open = () => {
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
  emit('close');
};

const validateForm = () => {
  errors.value = {};
  serverFieldErrors.value = {};
  serverParamErrors.value = {};
  generalError.value = '';

  let isValid = true;

  if (!form.value.title || !form.value.title.trim()) {
    errors.value.title = t('PILOT.TOOLS.DIALOG.FIELD_TITLE_REQUIRED');
    isValid = false;
  }

  if (!form.value.endpoint_url || !form.value.endpoint_url.trim()) {
    errors.value.endpoint_url = t('PILOT.TOOLS.DIALOG.FIELD_URL_REQUIRED');
    isValid = false;
  }

  if (paramEditorRef.value) {
    const isParamValid = paramEditorRef.value.validate();
    if (!isParamValid) {
      isValid = false;
    }
  }

  return isValid;
};

const onTest = async () => {
  testStatus.value = null;
  testMessage.value = '';
  testErrorCode.value = '';

  try {
    const data = await store.dispatch('pilotCustomTools/runTest', {
      id: props.tool?.id,
      draft: form.value,
    });

    if (data.success) {
      testStatus.value = 'success';
      testMessage.value = t('PILOT.TOOLS.DIALOG.TEST_SUCCESS', {
        status: '200',
      });
    } else {
      testStatus.value = 'error';
      testErrorCode.value = data.error || 'tool.http_error';
      const mappedMsg =
        t(`PILOT.TOOLS.ERRORS.${data.error}`) ||
        data.message ||
        'Unknown error';
      testMessage.value = t('PILOT.TOOLS.DIALOG.TEST_ERROR', {
        message: mappedMsg,
      });
    }
  } catch (err) {
    testStatus.value = 'error';
    testErrorCode.value = 'tool.http_error';
    const responseData = err?.response?.data;
    const msg = responseData?.message || err.message || 'Connection failed';
    testMessage.value = t('PILOT.TOOLS.DIALOG.TEST_ERROR', { message: msg });
  }
};

const onSubmit = async () => {
  if (!validateForm()) return;

  try {
    if (props.mode === 'create') {
      await store.dispatch('pilotCustomTools/createRow', form.value);
    } else {
      await store.dispatch('pilotCustomTools/updateRow', {
        id: props.tool.id,
        ...form.value,
      });
    }
    emit('success');
    close();
  } catch (err) {
    const responseData = err?.response?.data;
    if (responseData && responseData.errors) {
      responseData.errors.forEach(errorItem => {
        if (
          errorItem.param_index !== undefined &&
          errorItem.param_index !== null
        ) {
          serverParamErrors.value[errorItem.param_index] = errorItem.message;
        } else if (errorItem.field) {
          serverFieldErrors.value[errorItem.field] = errorItem.message;
        }
      });
    } else {
      const errorMsg =
        responseData?.message ||
        err.message ||
        (props.mode === 'create'
          ? t('PILOT.TOOLS.DIALOG.TOAST.CREATE_ERROR')
          : t('PILOT.TOOLS.DIALOG.TOAST.UPDATE_ERROR'));
      generalError.value = errorMsg;
    }
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    :title="
      mode === 'create'
        ? t('PILOT.TOOLS.DIALOG.CREATE_TITLE')
        : t('PILOT.TOOLS.DIALOG.EDIT_TITLE')
    "
    @close="close"
    @confirm="onSubmit"
  >
    <!-- Server general error banner -->
    <div
      v-if="generalError"
      class="p-3 bg-n-ruby-1 border border-n-ruby-8 rounded-lg text-sm text-n-ruby-9"
    >
      {{ generalError }}
    </div>

    <!-- Scrollable Dialog Body -->
    <div class="max-h-[60vh] overflow-y-auto pr-2 flex flex-col gap-5">
      <!-- Enabled toggle -->
      <div
        class="flex items-center justify-between pb-3 border-b border-n-weak"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('PILOT.TOOLS.DIALOG.ENABLED_LABEL') }}
        </span>
        <Switch v-model="form.enabled" />
      </div>

      <!-- Display Name -->
      <Input
        v-model="form.title"
        type="text"
        :label="t('PILOT.TOOLS.DIALOG.FIELD_TITLE')"
        :placeholder="t('PILOT.TOOLS.DIALOG.FIELD_TITLE_PLACEHOLDER')"
        :message="titleMessage"
        :message-type="titleMessageType"
      />

      <!-- Description -->
      <div class="flex flex-col gap-1">
        <label class="mb-0.5 text-heading-3 text-n-slate-12">
          {{ t('PILOT.TOOLS.DIALOG.FIELD_DESCRIPTION') }}
        </label>
        <textarea
          v-model="form.description"
          rows="2"
          :placeholder="t('PILOT.TOOLS.DIALOG.FIELD_DESCRIPTION_PLACEHOLDER')"
          class="block w-full text-sm reset-base outline outline-1 border-none border-0 outline-offset-[-1px] rounded-lg bg-n-alpha-black2 placeholder:text-n-slate-10 dark:placeholder:text-n-slate-10 disabled:cursor-not-allowed disabled:opacity-50 text-n-slate-12 outline-n-weak focus:outline-n-brand focus:outline-offset-[-1px] !px-3 !py-2.5 resize-y transition-all duration-500 ease-in-out"
        />
      </div>

      <!-- Method + URL inline pair -->
      <div class="flex gap-4">
        <div class="w-[28%] min-w-[100px] flex flex-col gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('PILOT.TOOLS.DIALOG.FIELD_METHOD') }}
          </label>
          <select
            v-model="form.http_method"
            class="block w-full h-10 reset-base text-sm font-mono !mb-0 outline outline-1 border-none border-0 outline-offset-[-1px] rounded-lg bg-n-alpha-black2 text-n-slate-12 outline-n-weak focus:outline-n-brand px-3 cursor-pointer"
          >
            <option value="GET">
              {{ t('PILOT.TOOLS.DIALOG.FIELD_METHOD_GET') }}
            </option>
            <option value="POST">
              {{ t('PILOT.TOOLS.DIALOG.FIELD_METHOD_POST') }}
            </option>
          </select>
        </div>
        <div class="flex-1">
          <Input
            v-model="form.endpoint_url"
            type="text"
            :label="t('PILOT.TOOLS.DIALOG.FIELD_URL')"
            :placeholder="t('PILOT.TOOLS.DIALOG.FIELD_URL_PLACEHOLDER')"
            :message="urlMessage"
            :message-type="urlMessageType"
          />
        </div>
      </div>

      <!-- Auth Type -->
      <div class="flex flex-col gap-1">
        <label class="mb-0.5 text-heading-3 text-n-slate-12">
          {{ t('PILOT.TOOLS.DIALOG.FIELD_AUTH_TYPE') }}
        </label>
        <select
          v-model="form.auth_type"
          class="block w-full h-10 reset-base text-sm !mb-0 outline outline-1 border-none border-0 outline-offset-[-1px] rounded-lg bg-n-alpha-black2 text-n-slate-12 outline-n-weak focus:outline-n-brand px-3 cursor-pointer"
          @change="form.auth_config = {}"
        >
          <option value="none">
            {{ t('PILOT.TOOLS.DIALOG.FIELD_AUTH_TYPE_NONE') }}
          </option>
          <option value="bearer">
            {{ t('PILOT.TOOLS.DIALOG.FIELD_AUTH_TYPE_BEARER') }}
          </option>
          <option value="basic">
            {{ t('PILOT.TOOLS.DIALOG.FIELD_AUTH_TYPE_BASIC') }}
          </option>
          <option value="api_key">
            {{ t('PILOT.TOOLS.DIALOG.FIELD_AUTH_TYPE_API_KEY') }}
          </option>
        </select>
      </div>

      <!-- Auth Config Fields -->
      <AuthConfigFields
        v-if="form.auth_type !== 'none'"
        v-model="form.auth_config"
        :auth-type="form.auth_type"
      />

      <!-- Parameters Editor -->
      <ParamSchemaEditor
        ref="paramEditorRef"
        v-model="form.param_schema"
        :server-errors="serverParamErrors"
      />

      <!-- Request Template (POST only) -->
      <LiquidTemplateField
        v-if="form.http_method === 'POST'"
        v-model="form.request_template"
        :label="t('PILOT.TOOLS.DIALOG.FIELD_REQUEST_TEMPLATE')"
        :placeholder="
          t('PILOT.TOOLS.DIALOG.FIELD_REQUEST_TEMPLATE_PLACEHOLDER')
        "
      />

      <!-- Response Template -->
      <LiquidTemplateField
        v-model="form.response_template"
        :label="t('PILOT.TOOLS.DIALOG.FIELD_RESPONSE_TEMPLATE')"
        :placeholder="
          t('PILOT.TOOLS.DIALOG.FIELD_RESPONSE_TEMPLATE_PLACEHOLDER')
        "
      />
    </div>

    <!-- Custom Footer Overrides -->
    <template #footer>
      <div class="flex flex-col gap-4 w-full">
        <!-- Test Section -->
        <div class="flex flex-col gap-2 pt-2 border-t border-n-weak">
          <div class="flex items-center gap-3">
            <Button
              type="button"
              variant="faded"
              color="slate"
              :label="t('PILOT.TOOLS.DIALOG.TEST_BUTTON')"
              :disabled="isTestDisabled || isTesting"
              :is-loading="isTesting"
              class="w-auto"
              @click="onTest"
            />
            <!-- Test Result Pill -->
            <div
              v-if="testStatus"
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium"
              :class="testStatusConfig.classes"
            >
              <FluentIcon :icon="testStatusConfig.icon" size="14" />
              <span>{{ testMessage }}</span>
            </div>
          </div>
          <p v-if="isTestDisabled" class="text-xs text-n-slate-10 mb-0">
            {{ t('PILOT.TOOLS.DIALOG.TEST_DISABLED_HINT') }}
          </p>
        </div>

        <!-- Cancel / Submit Buttons -->
        <div
          class="flex items-center justify-end gap-3 pt-4 border-t border-n-weak w-full"
        >
          <Button
            type="button"
            variant="faded"
            color="slate"
            :label="t('PILOT.TOOLS.DIALOG.CANCEL')"
            class="w-auto"
            @click="close"
          />
          <Button
            type="submit"
            color="blue"
            :label="
              mode === 'create'
                ? t('PILOT.TOOLS.DIALOG.SUBMIT_CREATE')
                : t('PILOT.TOOLS.DIALOG.SUBMIT_EDIT')
            "
            class="w-auto"
            :is-loading="isSaving"
            :disabled="isSaving || isSavingDisabled"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>
