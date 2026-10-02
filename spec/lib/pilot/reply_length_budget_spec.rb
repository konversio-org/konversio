require 'rails_helper'

RSpec.describe Pilot::ReplyLengthBudget do
  let(:account) { create(:account) }

  before do
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe)
  end

  def conversation_on(channel)
    inbox = channel.inbox || create(:inbox, account: account, channel: channel)
    create(:conversation, account: account, inbox: inbox)
  end

  it 'returns nil for a nil conversation' do
    expect(described_class.for(nil)).to be_nil
  end

  it 'caps Instagram direct-message conversations at 1,000 regardless of channel' do
    conversation = conversation_on(create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                                             validate_provider_config: false))
    conversation.update!(additional_attributes: { 'type' => 'instagram_direct_message' })

    expect(described_class.for(conversation)).to eq(1_000)
  end

  it 'resolves Twilio SMS by medium' do
    conversation = conversation_on(create(:channel_twilio_sms, account: account, medium: :sms))

    expect(described_class.for(conversation)).to eq(320)
  end

  it 'lets the Twilio medium override the channel table for WhatsApp' do
    conversation = conversation_on(create(:channel_twilio_sms, account: account, medium: :whatsapp))

    expect(described_class.for(conversation)).to eq(1_600)
  end

  it 'maps each channel type to its required budget' do
    expectations = {
      channel_facebook_page: 2_000,
      channel_instagram: 1_000,
      channel_line: 5_000,
      channel_sms: 320,
      channel_telegram: 4_096,
      channel_tiktok: 6_000,
      channel_whatsapp: 4_096
    }

    expectations.each do |factory, budget|
      channel = if factory == :channel_whatsapp
                  create(factory, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                  validate_provider_config: false)
                else
                  create(factory, account: account)
                end
      expect(described_class.for(conversation_on(channel))).to eq(budget), "expected #{factory} to resolve to #{budget}"
    end
  end

  it 'falls back to 10,000 for channels without a tighter platform constraint' do
    conversation = conversation_on(create(:channel_widget, account: account))

    expect(described_class.for(conversation)).to eq(10_000)
  end
end
