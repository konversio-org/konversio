require 'rails_helper'

RSpec.describe Custom::Pilot::SummaryService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    account.enable_features!(:pilot, :pilot_summary)
  end

  describe '#perform' do
    it 'raises FeatureDisabledError when the summary flag is off' do
      account.disable_features!(:pilot_summary)
      service = described_class.new(conversation: conversation)
      expect { service.perform }.to raise_error(described_class::FeatureDisabledError)
    end

    it 'raises FeatureDisabledError when the master flag is off' do
      account.disable_features!(:pilot)
      service = described_class.new(conversation: conversation)
      expect { service.perform }.to raise_error(described_class::FeatureDisabledError)
    end

    it 'delegates to Pilot::SummaryService and returns the summary text' do
      fake = instance_double(Pilot::SummaryService)
      expect(Pilot::SummaryService)
        .to receive(:new)
        .with(
          account: account,
          conversation_display_id: conversation.display_id,
          previous_output: nil,
          refinement_instruction: nil
        )
        .and_return(fake)
      expect(fake).to receive(:perform).and_return({ message: 'A short summary.' })

      service = described_class.new(conversation: conversation)
      expect(service.perform).to eq('A short summary.')
    end

    it 'forwards refinement kwargs through to Pilot::SummaryService' do
      fake = instance_double(Pilot::SummaryService, perform: { message: 'refined' })
      expect(Pilot::SummaryService)
        .to receive(:new)
        .with(
          account: account,
          conversation_display_id: conversation.display_id,
          previous_output: 'older summary text',
          refinement_instruction: 'shorten it'
        )
        .and_return(fake)

      service = described_class.new(
        conversation: conversation,
        previous_output: 'older summary text',
        refinement_instruction: 'shorten it'
      )
      expect(service.perform).to eq('refined')
    end

    it 'dispatches summary_completed telemetry on success' do
      fake = instance_double(Pilot::SummaryService, perform: { message: 'ok' })
      allow(Pilot::SummaryService).to receive(:new).and_return(fake)

      service = described_class.new(conversation: conversation)
      expect(service).to receive(:dispatch_event).with(:summary_started, anything)
      expect(service).to receive(:dispatch_event).with(:summary_completed, hash_including(:summary_length))
      service.perform
    end

    it 'raises Error when the underlying service returns an error hash' do
      fake = instance_double(Pilot::SummaryService, perform: { error: 'upstream down', error_code: 500 })
      allow(Pilot::SummaryService).to receive(:new).and_return(fake)

      service = described_class.new(conversation: conversation)
      expect { service.perform }.to raise_error(described_class::Error, /upstream down/)
    end
  end
end
