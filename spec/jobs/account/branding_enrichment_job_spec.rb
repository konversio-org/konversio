require 'rails_helper'

RSpec.describe Account::BrandingEnrichmentJob do
  let(:account) do
    create(:account, name: 'Original', custom_attributes: { 'onboarding_step' => 'enrichment' })
  end
  let(:admin) { create(:user, account: account, role: :administrator) }

  before { admin }

  describe '#perform' do
    it 'stores brand info, sets the name from the title, and advances the cursor' do
      result = { domain: 'acme.com', title: 'Acme Corp', colors: [], logos: [], socials: [], email_provider: 'google' }
      allow(WebsiteBrandingService).to receive(:new).with('admin@acme.com').and_return(instance_double(WebsiteBrandingService, perform: result))

      expect do
        described_class.perform_now(account.id, 'admin@acme.com')
      end.to have_enqueued_job(ActionCableBroadcastJob)

      account.reload
      expect(account.name).to eq('Acme Corp')
      expect(account.custom_attributes['brand_info']).to include('domain' => 'acme.com', 'email_provider' => 'google')
      expect(account.custom_attributes['onboarding_step']).to eq('account_details')
    end

    it 'does not overwrite existing brand info' do
      account.update!(custom_attributes: account.custom_attributes.merge('brand_info' => { 'title' => 'Existing' }))
      result = { domain: 'acme.com', title: 'Acme Corp', colors: [], logos: [], socials: [] }
      allow(WebsiteBrandingService).to receive(:new).and_return(instance_double(WebsiteBrandingService, perform: result))

      described_class.perform_now(account.id, 'admin@acme.com')

      expect(account.reload.custom_attributes['brand_info']).to eq('title' => 'Existing')
    end

    it 'advances the cursor even when enrichment returns nothing' do
      allow(WebsiteBrandingService).to receive(:new).and_return(instance_double(WebsiteBrandingService, perform: nil))

      described_class.perform_now(account.id, 'admin@acme.com')

      account.reload
      expect(account.custom_attributes['brand_info']).to be_nil
      expect(account.custom_attributes['onboarding_step']).to eq('account_details')
    end

    it 'does not regress a cursor that already advanced' do
      account.update!(custom_attributes: account.custom_attributes.merge('onboarding_step' => 'inbox_setup'))
      allow(WebsiteBrandingService).to receive(:new).and_return(instance_double(WebsiteBrandingService, perform: nil))

      described_class.perform_now(account.id, 'admin@acme.com')

      expect(account.reload.custom_attributes['onboarding_step']).to eq('inbox_setup')
    end
  end
end
