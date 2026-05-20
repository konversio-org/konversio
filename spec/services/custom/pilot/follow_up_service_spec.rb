require 'rails_helper'

RSpec.describe Custom::Pilot::FollowUpService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    account.update!(pilot_enabled: true, pilot_follow_up_enabled: true)
    create(:message, conversation: conversation, account: account, message_type: :incoming, content: 'I have a problem.')
  end

  describe '#perform' do
    it 'raises FeatureDisabledError when the follow_up flag is off' do
      account.update!(pilot_follow_up_enabled: false)
      service = described_class.new(conversation: conversation)
      expect { service.perform }.to raise_error(described_class::FeatureDisabledError)
    end

    it 'delegates to Pilot::FollowUpService and returns up to 3 suggestions' do
      fake = instance_double(::Pilot::FollowUpService)
      allow(::Pilot::FollowUpService).to receive(:new).and_return(fake)
      allow(fake).to receive(:perform).and_return({ message: "Could you share your order number?\nWhen did you order?\nWhich product was it?" })

      service = described_class.new(conversation: conversation)
      result = service.perform
      expect(result).to be_an(Array)
      expect(result.length).to eq(3)
    end

    it 'strips bullet/number prefixes from suggestions' do
      fake = instance_double(::Pilot::FollowUpService,
                             perform: { message: "1. First?\n- Second?\n* Third?" })
      allow(::Pilot::FollowUpService).to receive(:new).and_return(fake)

      service = described_class.new(conversation: conversation)
      expect(service.perform).to eq(['First?', 'Second?', 'Third?'])
    end

    it 'dispatches follow_up_completed telemetry on success' do
      fake = instance_double(::Pilot::FollowUpService, perform: { message: "Q1?\nQ2?" })
      allow(::Pilot::FollowUpService).to receive(:new).and_return(fake)

      service = described_class.new(conversation: conversation)
      expect(service).to receive(:dispatch_event).with(:follow_up_started, anything)
      expect(service).to receive(:dispatch_event).with(:follow_up_completed, hash_including(:suggestion_count))
      service.perform
    end
  end
end
