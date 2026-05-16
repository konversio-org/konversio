import { useConfig } from '../useConfig';

describe('useConfig', () => {
  const originalChatwootConfig = window.konversioConfig;

  beforeEach(() => {
    window.konversioConfig = {
      hostURL: 'https://example.com',
      vapidPublicKey: 'vapid-key',
      enabledLanguages: ['en', 'fr'],
      isEnterprise: 'true',
      enterprisePlanName: 'enterprise',
    };
  });

  afterEach(() => {
    window.konversioConfig = originalChatwootConfig;
  });

  it('returns the correct configuration values', () => {
    const config = useConfig();

    expect(config.hostURL).toBe('https://example.com');
    expect(config.vapidPublicKey).toBe('vapid-key');
    expect(config.enabledLanguages).toEqual(['en', 'fr']);
    expect(config.isEnterprise).toBe(true);
    expect(config.enterprisePlanName).toBe('enterprise');
  });

  it('handles missing configuration values', () => {
    window.konversioConfig = {};
    const config = useConfig();

    expect(config.hostURL).toBeUndefined();
    expect(config.vapidPublicKey).toBeUndefined();
    expect(config.enabledLanguages).toBeUndefined();
    expect(config.isEnterprise).toBe(false);
    expect(config.enterprisePlanName).toBeUndefined();
  });

  it('handles undefined window.konversioConfig', () => {
    window.konversioConfig = undefined;
    const config = useConfig();

    expect(config.hostURL).toBeUndefined();
    expect(config.vapidPublicKey).toBeUndefined();
    expect(config.enabledLanguages).toBeUndefined();
    expect(config.isEnterprise).toBe(false);
    expect(config.enterprisePlanName).toBeUndefined();
  });
});
