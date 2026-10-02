<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import CampaignsAPI from 'dashboard/api/campaigns';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const campaignId = route.params.campaignId;
const isLoading = ref(true);
const isLoadingContacts = ref(false);
const errorMessage = ref('');
const metrics = ref(null);
const recipients = ref([]);
const statusFilter = ref('');
const page = ref(1);
const totalPages = ref(1);

const metricCards = computed(() => {
  if (!metrics.value) return [];
  return [
    { key: 'audience', value: metrics.value.audience },
    { key: 'sent', value: metrics.value.sent },
    { key: 'delivered', value: metrics.value.delivered },
    { key: 'read', value: metrics.value.read },
    { key: 'failed', value: metrics.value.failed },
    { key: 'skipped', value: metrics.value.skipped },
  ];
});

const statusBreakdown = computed(() => {
  const counts = metrics.value?.status_counts || {};
  return Object.entries(counts).filter(([, count]) => count > 0);
});

const loadMetrics = async () => {
  const { data } = await CampaignsAPI.getWhatsappAnalyticsMetrics(campaignId);
  metrics.value = data;
};

const loadContacts = async () => {
  isLoadingContacts.value = true;
  try {
    const params = { page: page.value };
    if (statusFilter.value) params.status = statusFilter.value;
    const { data } = await CampaignsAPI.getWhatsappAnalyticsContacts(
      campaignId,
      params
    );
    recipients.value = data.payload;
    totalPages.value = data.meta.total_pages;
  } finally {
    isLoadingContacts.value = false;
  }
};

const loadAll = async () => {
  isLoading.value = true;
  errorMessage.value = '';
  try {
    await Promise.all([loadMetrics(), loadContacts()]);
  } catch (error) {
    errorMessage.value =
      error?.response?.data?.error ||
      t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.ERROR');
  } finally {
    isLoading.value = false;
  }
};

const filterByStatus = status => {
  statusFilter.value = status;
  page.value = 1;
  loadContacts().catch(() => {
    useAlert(t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.ERROR'));
  });
};

const goToPage = delta => {
  const next = page.value + delta;
  if (next < 1 || next > totalPages.value) return;
  page.value = next;
  loadContacts().catch(() => {
    useAlert(t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.ERROR'));
  });
};

const goBack = () => {
  router.push({
    name: 'campaigns_whatsapp_index',
    params: { accountId: route.params.accountId },
  });
};

onMounted(loadAll);
</script>

<template>
  <div class="flex flex-col w-full h-full gap-6 p-6 overflow-auto">
    <div class="flex items-center gap-3">
      <Button
        icon="i-lucide-arrow-left"
        variant="faded"
        color="slate"
        size="sm"
        @click="goBack"
      />
      <h1 class="text-lg font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.TITLE') }}
      </h1>
    </div>

    <div
      v-if="isLoading"
      class="flex items-center justify-center py-16 text-n-slate-11"
    >
      <Spinner />
    </div>

    <div v-else-if="errorMessage" class="text-sm text-n-ruby-11">
      {{ errorMessage }}
    </div>

    <template v-else>
      <div class="grid grid-cols-2 gap-4 lg:grid-cols-6">
        <div
          v-for="card in metricCards"
          :key="card.key"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <p class="text-xs text-n-slate-11">
            {{
              t(
                `CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.METRICS.${card.key.toUpperCase()}`
              )
            }}
          </p>
          <p class="mt-1 text-xl font-semibold text-n-slate-12">
            {{ card.value }}
          </p>
        </div>
      </div>

      <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
        <p class="mb-3 text-sm font-medium text-n-slate-12">
          {{ t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.BREAKDOWN') }}
        </p>
        <div class="flex flex-wrap gap-3">
          <span
            v-for="[status, count] in statusBreakdown"
            :key="status"
            class="px-2 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
          >
            {{ status }}: {{ count }}
          </span>
        </div>
      </div>

      <div class="flex gap-2">
        <Button
          v-for="filter in [
            '',
            'sent',
            'delivered',
            'read',
            'skipped',
            'failed',
          ]"
          :key="filter || 'all'"
          :variant="statusFilter === filter ? 'solid' : 'faded'"
          color="slate"
          size="sm"
          @click="filterByStatus(filter)"
        >
          {{
            filter
              ? filter
              : t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.FILTERS.ALL')
          }}
        </Button>
      </div>

      <div class="overflow-hidden border rounded-xl border-n-weak">
        <table class="w-full text-sm">
          <thead class="text-left bg-n-alpha-2 text-n-slate-11">
            <tr>
              <th class="px-4 py-2">
                {{ t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.TABLE.CONTACT') }}
              </th>
              <th class="px-4 py-2">
                {{ t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.TABLE.PHONE') }}
              </th>
              <th class="px-4 py-2">
                {{ t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.TABLE.STATUS') }}
              </th>
              <th class="px-4 py-2">
                {{ t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.TABLE.ERROR') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="recipient in recipients"
              :key="recipient.contact.id"
              class="border-t border-n-weak"
            >
              <td class="px-4 py-2 text-n-slate-12">
                {{ recipient.contact.name }}
              </td>
              <td class="px-4 py-2 text-n-slate-11">
                {{ recipient.contact.phone_number || '—' }}
              </td>
              <td class="px-4 py-2 text-n-slate-11">{{ recipient.status }}</td>
              <td class="px-4 py-2 text-n-slate-11">
                {{ recipient.error_message || '—' }}
              </td>
            </tr>
            <tr v-if="!isLoadingContacts && !recipients.length">
              <td colspan="4" class="px-4 py-6 text-center text-n-slate-11">
                {{ t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.EMPTY') }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="flex items-center justify-end gap-3">
        <Button
          variant="faded"
          color="slate"
          size="sm"
          :disabled="page <= 1"
          @click="goToPage(-1)"
        >
          {{ t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.PREV') }}
        </Button>
        <span class="text-xs text-n-slate-11">
          {{ page }} / {{ totalPages }}
        </span>
        <Button
          variant="faded"
          color="slate"
          size="sm"
          :disabled="page >= totalPages"
          @click="goToPage(1)"
        >
          {{ t('CAMPAIGN.WHATSAPP.ANALYTICS_DASHBOARD.NEXT') }}
        </Button>
      </div>
    </template>
  </div>
</template>
