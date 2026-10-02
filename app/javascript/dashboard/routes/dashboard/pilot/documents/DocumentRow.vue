<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { dynamicTime } from 'shared/helpers/timeHelper';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  DropdownContainer,
  DropdownBody,
  DropdownSection,
  DropdownItem,
} from 'dashboard/components-next/dropdown-menu/base';

const props = defineProps({
  document: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['delete', 'refresh']);

const { t } = useI18n();

const STATUS_STYLES = {
  available: {
    dot: 'bg-n-teal-9',
    pill: 'bg-n-teal-3 text-n-teal-11',
    animated: false,
  },
  in_progress: {
    dot: 'bg-n-amber-9',
    pill: 'bg-n-amber-3 text-n-amber-11',
    animated: true,
  },
  failed: {
    dot: 'bg-n-ruby-9',
    pill: 'bg-n-ruby-3 text-n-ruby-11',
    animated: false,
  },
};

const statusKey = computed(() => props.document.status || 'in_progress');
const statusStyle = computed(
  () => STATUS_STYLES[statusKey.value] || STATUS_STYLES.in_progress
);
const statusLabel = computed(() =>
  t(`PILOT_DOCUMENTS.STATUS.${statusKey.value.toUpperCase()}`)
);

const isFileBacked = computed(() =>
  ['pdf', 'markdown'].includes(props.document.source_type)
);
const isExternalLink = computed(
  () => Boolean(props.document.external_link) && !isFileBacked.value
);
const linkHref = computed(() => props.document.external_link || null);

const isCrawling = computed(
  () =>
    props.document.status === 'in_progress' &&
    Boolean(props.document.external_link) &&
    !props.document.external_link.startsWith('PDF:')
);

const subtitle = computed(() => {
  if (isCrawling.value) {
    return t('PILOT_DOCUMENTS.CRAWL.IN_PROGRESS_HINT');
  }
  return props.document.external_link || '';
});

const responseCount = computed(
  () => Number(props.document.response_count) || 0
);

const relativeTime = computed(() => {
  const ts = props.document.created_at;
  if (!ts) return '';
  return dynamicTime(ts);
});

const SYNC_STYLES = {
  syncing: { pill: 'bg-n-amber-3 text-n-amber-11', animated: true },
  synced: { pill: 'bg-n-teal-3 text-n-teal-11', animated: false },
  failed: { pill: 'bg-n-ruby-3 text-n-ruby-11', animated: false },
};

const syncStatusKey = computed(
  () => props.document.sync_status || props.document.status || null
);
const syncStyle = computed(() => SYNC_STYLES[syncStatusKey.value] || null);
const syncLabel = computed(() =>
  syncStyle.value
    ? t(`PILOT_DOCUMENTS.SYNC.${syncStatusKey.value.toUpperCase()}`)
    : ''
);

const syncTooltip = computed(() => {
  if (props.document.sync_status !== 'failed') return '';
  const category = props.document.last_sync_failure_category;
  return category
    ? t('PILOT_DOCUMENTS.SYNC.FAILED_REASON', { reason: category })
    : '';
});

const lastSyncedAt = computed(() => {
  const ts = props.document.last_synced_at;
  if (!ts) return '';
  return dynamicTime(ts);
});

const canRefresh = computed(
  () =>
    props.document.status === 'available' &&
    !isFileBacked.value &&
    props.document.sync_status !== 'syncing'
);

const onDelete = () => emit('delete', props.document.id);
const onRefresh = () => emit('refresh', props.document.id);
</script>

<template>
  <CardLayout layout="row">
    <div class="flex items-start gap-4 w-full min-w-0">
      <span
        class="mt-1.5 inline-block size-2.5 rounded-full flex-shrink-0"
        :class="[statusStyle.dot, statusStyle.animated && 'animate-pulse']"
        :aria-label="statusLabel"
      />
      <div class="flex flex-col flex-1 min-w-0 gap-1.5">
        <div class="flex items-center gap-2 flex-wrap">
          <a
            v-if="isExternalLink"
            :href="linkHref"
            target="_blank"
            rel="noopener noreferrer"
            class="text-sm font-medium text-n-slate-12 hover:text-n-blue-11 truncate max-w-md"
            :title="document.name"
          >
            {{ document.name }}
          </a>
          <span
            v-else
            class="text-sm font-medium text-n-slate-12 truncate max-w-md"
            :title="document.name"
          >
            {{ document.name }}
          </span>
          <span
            class="text-xs font-medium inline-flex items-center h-5 px-2 rounded-md"
            :class="statusStyle.pill"
          >
            {{ statusLabel }}
          </span>
          <span
            v-if="syncStyle"
            :title="syncTooltip"
            class="text-xs font-medium inline-flex items-center gap-1 h-5 px-2 rounded-md"
            :class="[syncStyle.pill, syncStyle.animated && 'animate-pulse']"
          >
            <Icon icon="i-lucide-refresh-cw" class="size-3" />
            {{ syncLabel }}
          </span>
        </div>
        <p v-if="subtitle" class="text-sm text-n-slate-11 truncate">
          {{ subtitle }}
        </p>
        <div class="flex items-center gap-2 text-xs text-n-slate-10 flex-wrap">
          <span
            class="inline-flex items-center gap-1 h-5 px-2 rounded-md bg-n-alpha-2 text-n-slate-11"
          >
            <Icon icon="i-lucide-message-square-text" class="size-3" />
            {{
              t('PILOT_DOCUMENTS.ROW.FAQS_GENERATED', {
                count: responseCount,
              })
            }}
          </span>
          <span v-if="lastSyncedAt">
            {{ t('PILOT_DOCUMENTS.ROW.LAST_SYNCED', { time: lastSyncedAt }) }}
          </span>
          <span v-else-if="relativeTime">{{ relativeTime }}</span>
        </div>
      </div>
      <DropdownContainer>
        <template #trigger="{ toggle }">
          <button
            type="button"
            :aria-label="t('PILOT_DOCUMENTS.ROW.MENU_ARIA')"
            class="p-1.5 rounded-md text-n-slate-11 hover:bg-n-alpha-2 flex-shrink-0"
            @click="toggle"
          >
            <span class="i-lucide-more-horizontal size-4" aria-hidden="true" />
          </button>
        </template>
        <DropdownBody class="min-w-40 z-50">
          <DropdownSection>
            <DropdownItem :click="onRefresh" :disabled="!canRefresh">
              <template #label>
                <span
                  class="flex items-center gap-3 w-full text-left rtl:text-right"
                  :class="canRefresh ? 'text-n-slate-12' : 'text-n-slate-9'"
                >
                  <Icon
                    icon="i-lucide-refresh-cw"
                    class="size-4"
                    :class="canRefresh ? 'text-n-slate-11' : 'text-n-slate-9'"
                  />
                  {{ t('PILOT_DOCUMENTS.ROW.MENU.REFRESH') }}
                </span>
              </template>
            </DropdownItem>
            <DropdownItem :click="onDelete">
              <template #label>
                <span
                  class="flex items-center gap-3 w-full text-n-ruby-11 text-left rtl:text-right"
                >
                  <Icon icon="i-lucide-trash-2" class="size-4 text-n-ruby-11" />
                  {{ t('PILOT_DOCUMENTS.ROW.MENU.DELETE') }}
                </span>
              </template>
            </DropdownItem>
          </DropdownSection>
        </DropdownBody>
      </DropdownContainer>
    </div>
  </CardLayout>
</template>
