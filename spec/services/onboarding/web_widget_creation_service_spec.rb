require 'rails_helper'

RSpec.describe Onboarding::WebWidgetCreationService do
  let(:account) do
    create(:account, name: 'Acme Inc', custom_attributes: {
             'website' => 'acme.com',
             'brand_info' => {
               'title' => 'Acme Corp',
               'colors' => [{ 'hex' => '#ff5733' }],
               'slogan' => 'Support done right'
             }
           })
  end
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:service) { described_class.new(account, user) }

  describe '#perform' do
    it 'creates a web widget channel and inbox with brand-derived presentation' do
      inbox = service.perform

      expect(inbox).to be_persisted
      expect(inbox.channel).to be_a(Channel::WebWidget)
      expect(inbox.channel.website_url).to eq('acme.com')
      expect(inbox.channel.widget_color).to eq('#ff5733')
      expect(inbox.channel.welcome_title).to eq('Acme Corp')
      expect(inbox.channel.welcome_tagline).to eq('Support done right')
      expect(inbox.members).to include(user)
    end

    it 'truncates an over-long welcome tagline' do
      account.custom_attributes['brand_info']['slogan'] = 'a' * 400
      account.save!

      expect(service.perform.channel.welcome_tagline.length).to eq(255)
    end

    it 'falls back to a default color when no valid brand color is present' do
      account.custom_attributes['brand_info']['colors'] = [{ 'hex' => 'not-a-color' }]
      account.save!

      expect(service.perform.channel.widget_color).to eq(Onboarding::WebWidgetCreationService::DEFAULT_WIDGET_COLOR)
    end

    it 'reuses an existing web widget inbox' do
      existing = create(:channel_widget, account: account).inbox

      expect(service.perform).to eq(existing)
      expect(account.inboxes.where(channel_type: 'Channel::WebWidget').count).to eq(1)
    end

    it 'skips provisioning when no website is known' do
      account.custom_attributes.delete('website')
      account.custom_attributes['brand_info'] = {}
      account.save!

      expect(service.perform).to be_nil
      expect(account.inboxes.where(channel_type: 'Channel::WebWidget').count).to eq(0)
    end

    it 'swallows provisioning failures' do
      allow(account.web_widgets).to receive(:create!).and_raise(StandardError, 'boom')

      expect(service.perform).to be_nil
    end
  end
end
