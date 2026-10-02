require 'rails_helper'

RSpec.describe Pilot::OnboardingHelpCenter::BootstrapService do
  let(:account) do
    create(:account, name: 'Acme Inc', locale: 'fr', custom_attributes: {
             'website' => 'acme.com',
             'brand_info' => {
               'title' => 'Acme Corp',
               'colors' => [{ 'hex' => '#ff5733' }],
               'slogan' => 'Support done right',
               'logos' => [{ 'url' => 'https://acme.com/logo.png' }]
             }
           })
  end
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:service) { described_class.new(account, user) }

  before do
    allow(Pilot::OnboardingHelpCenter::PlanJob).to receive(:perform_later)
    allow(SafeFetch).to receive(:fetch)
  end

  describe '#perform' do
    it 'creates a branded portal, links the web widget, and starts generation' do
      create(:channel_widget, account: account)

      portal = service.perform

      expect(portal).to be_persisted
      expect(portal.name).to eq('Acme Corp')
      expect(portal.page_title).to eq('Acme Corp')
      expect(portal.color).to eq('#ff5733')
      expect(portal.header_text).to eq('Support done right')
      expect(portal.homepage_link).to eq('https://acme.com')
      expect(portal.default_locale).to eq('fr')
      expect(portal.channel_web_widget).to be_present
      expect(account.reload.custom_attributes[Pilot::OnboardingHelpCenter::GENERATION_KEY]).to be_present
      expect(Pilot::OnboardingHelpCenter::PlanJob).to have_received(:perform_later).with(account.id, portal.id, user.id, anything)
    end

    it 'falls back to the default color for an invalid brand color' do
      account.custom_attributes['brand_info']['colors'] = [{ 'hex' => 'nope' }]
      account.save!

      expect(service.perform.color).to eq(Pilot::OnboardingHelpCenter::BootstrapService::DEFAULT_COLOR)
    end

    it 'picks a unique slug when the natural slug is taken' do
      create(:portal, account: create(:account), slug: 'acme-corp')

      expect(service.perform.slug).not_to eq('acme-corp')
    end

    it 'reuses an existing portal without starting a new generation' do
      existing = create(:portal, account: account)

      expect(service.perform).to eq(existing)
      expect(account.reload.custom_attributes[Pilot::OnboardingHelpCenter::GENERATION_KEY]).to be_nil
      expect(Pilot::OnboardingHelpCenter::PlanJob).not_to have_received(:perform_later)
    end

    it 'attaches a logo downloaded through the SSRF-safe layer' do
      tempfile = Tempfile.new(['logo', '.png'])
      result = SafeFetch::Result.new(tempfile: tempfile, filename: 'logo.png', content_type: 'image/png')
      allow(SafeFetch).to receive(:fetch).and_yield(result)

      portal = service.perform

      expect(portal.logo).to be_attached
    end

    it 'does not fail portal creation when the logo download fails' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError, 'boom')

      portal = service.perform

      expect(portal).to be_persisted
      expect(portal.logo).not_to be_attached
    end

    it 'does nothing when no website is known' do
      account.custom_attributes.delete('website')
      account.custom_attributes['brand_info'] = { 'title' => 'Acme Corp' }
      account.save!

      expect(service.perform).to be_nil
      expect(account.portals.count).to eq(0)
      expect(Pilot::OnboardingHelpCenter::PlanJob).not_to have_received(:perform_later)
    end
  end
end
