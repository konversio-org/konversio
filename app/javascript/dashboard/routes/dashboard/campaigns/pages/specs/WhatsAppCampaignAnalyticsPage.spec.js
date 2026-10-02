import { shallowMount, flushPromises } from '@vue/test-utils';
import WhatsAppCampaignAnalyticsPage from '../WhatsAppCampaignAnalyticsPage.vue';
import CampaignsAPI from 'dashboard/api/campaigns';

const push = vi.fn();

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1', campaignId: '7' } }),
  useRouter: () => ({ push }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/api/campaigns', () => ({
  default: {
    getWhatsappAnalyticsMetrics: vi.fn(),
    getWhatsappAnalyticsContacts: vi.fn(),
  },
}));

describe('WhatsAppCampaignAnalyticsPage', () => {
  beforeEach(() => {
    CampaignsAPI.getWhatsappAnalyticsMetrics.mockResolvedValue({
      data: {
        audience: 3,
        sent: 2,
        delivered: 1,
        read: 1,
        failed: 1,
        skipped: 1,
        status_counts: { sent: 1, delivered: 1, failed: 1 },
      },
    });
    CampaignsAPI.getWhatsappAnalyticsContacts.mockResolvedValue({
      data: {
        payload: [
          {
            contact: { id: 1, name: 'Bob', phone_number: '+15551234567' },
            status: 'failed',
            error_message: 'window closed',
          },
        ],
        meta: { total_pages: 1, current_page: 1, total_count: 1 },
      },
    });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('renders aggregate metrics and per-contact outcomes', async () => {
    const wrapper = shallowMount(WhatsAppCampaignAnalyticsPage);
    await flushPromises();

    expect(CampaignsAPI.getWhatsappAnalyticsMetrics).toHaveBeenCalledWith('7');
    expect(CampaignsAPI.getWhatsappAnalyticsContacts).toHaveBeenCalledWith(
      '7',
      { page: 1 }
    );

    const text = wrapper.text();
    expect(text).toContain('3');
    expect(text).toContain('Bob');
    expect(text).toContain('window closed');
  });
});
