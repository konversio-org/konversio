import { mount } from '@vue/test-utils';
import WhatsappManualSetup from '../WhatsappManualSetup.vue';

const api = vi.hoisted(() => ({
  previewManualSetup: vi.fn(),
  connectManualSetup: vi.fn(),
  getManualWebhookStatus: vi.fn(),
  setupManualWebhook: vi.fn(),
}));

const pollControls = vi.hoisted(() => ({
  resume: vi.fn(),
  pause: vi.fn(),
  callback: null,
}));

vi.mock('dashboard/api/channel/whatsappChannel', () => ({ default: api }));
vi.mock('@vueuse/core', () => ({
  useTimeoutPoll: callback => {
    pollControls.callback = callback;
    return { resume: pollControls.resume, pause: pollControls.pause };
  },
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
  I18nT: true,
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'new_inbox', params: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));
vi.mock('vuex', () => ({ useStore: () => ({ dispatch: vi.fn() }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: text => text }),
}));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(),
}));

const mountComponent = () =>
  mount(WhatsappManualSetup, {
    shallow: true,
    global: { stubs: { I18nT: true, ManualSetupVideo: true } },
  });

describe('WhatsappManualSetup', () => {
  beforeAll(() => {
    Element.prototype.scrollIntoView = vi.fn();
  });

  beforeEach(() => {
    Object.values(api).forEach(fn => fn.mockReset());
    pollControls.resume.mockReset();
    pollControls.pause.mockReset();
    pollControls.callback = null;
  });

  describe('step gating', () => {
    it('starts on the guidance step without calling the API', () => {
      const wrapper = mountComponent();

      expect(wrapper.vm.currentStep).toBe(1);
      expect(api.previewManualSetup).not.toHaveBeenCalled();
      expect(api.connectManualSetup).not.toHaveBeenCalled();
    });

    it('blocks advancing past the IDs step until WABA and phone IDs are set', () => {
      const wrapper = mountComponent();
      wrapper.vm.currentStep = 2;

      wrapper.vm.continueFromIds();
      expect(wrapper.vm.currentStep).toBe(2);
      expect(wrapper.vm.errorMessage).toBe(
        'INBOX_MGMT.ADD.WHATSAPP.MANUAL_SETUP.ERRORS.IDS_REQUIRED'
      );

      wrapper.vm.form.wabaId = 'waba';
      wrapper.vm.form.phoneNumberId = 'phone';
      wrapper.vm.continueFromIds();
      expect(wrapper.vm.currentStep).toBe(3);
    });

    it('requires all credential fields before calling preview', async () => {
      const wrapper = mountComponent();
      wrapper.vm.currentStep = 3;

      await wrapper.vm.verifyDetails();
      expect(api.previewManualSetup).not.toHaveBeenCalled();
      expect(wrapper.vm.errorMessage).toBe(
        'INBOX_MGMT.ADD.WHATSAPP.MANUAL_SETUP.ERRORS.REQUIRED'
      );
    });

    it('previews valid credentials and advances to the review step', async () => {
      api.previewManualSetup.mockResolvedValue({
        data: {
          verified_name: 'Acme',
          display_phone_number: '+15550001111',
          phone_number_id: 'phone',
          waba_id: 'waba',
          suggested_inbox_name: 'Acme WhatsApp',
        },
      });
      const wrapper = mountComponent();
      wrapper.vm.form.wabaId = 'waba';
      wrapper.vm.form.phoneNumberId = 'phone';
      wrapper.vm.form.accessToken = 'token';

      await wrapper.vm.verifyDetails();

      expect(api.previewManualSetup).toHaveBeenCalledWith({
        waba_id: 'waba',
        phone_number_id: 'phone',
        access_token: 'token',
      });
      expect(wrapper.vm.currentStep).toBe(4);
      expect(wrapper.vm.form.inboxName).toBe('Acme WhatsApp');
    });
  });

  describe('verification polling', () => {
    const connect = async wrapper => {
      wrapper.vm.form.wabaId = 'waba';
      wrapper.vm.form.phoneNumberId = 'phone';
      wrapper.vm.form.accessToken = 'token';
      api.connectManualSetup.mockResolvedValue({
        data: {
          id: 42,
          number_access: true,
          template_access: true,
          webhook_error: 'not configured',
        },
      });
      await wrapper.vm.connectNumber();
    };

    it('starts polling after connect and stops once every check passes', async () => {
      const wrapper = mountComponent();
      await connect(wrapper);
      expect(wrapper.vm.currentStep).toBe(5);
      expect(pollControls.resume).toHaveBeenCalled();

      api.getManualWebhookStatus.mockResolvedValue({
        data: {
          callback_configured: true,
          callback_url: 'https://example.test/webhooks/whatsapp/+15550001111',
          subscription_verified: true,
        },
      });
      await pollControls.callback();

      expect(api.getManualWebhookStatus).toHaveBeenCalledWith(42);
      expect(wrapper.vm.connection.callbackConfigured).toBe(true);
      expect(wrapper.vm.connection.subscriptionVerified).toBe(true);
      expect(pollControls.pause).toHaveBeenCalled();
    });

    it('stops polling after the bounded number of attempts', async () => {
      const wrapper = mountComponent();
      await connect(wrapper);

      api.getManualWebhookStatus.mockResolvedValue({
        data: {
          callback_configured: false,
          callback_url: '',
          subscription_verified: false,
        },
      });

      for (let i = 0; i < 5; i += 1) {
        // eslint-disable-next-line no-await-in-loop
        await pollControls.callback();
      }

      expect(wrapper.vm.pollAttempts).toBe(5);
      expect(pollControls.pause).toHaveBeenCalled();
    });
  });
});
