require 'rails_helper'

RSpec.describe Custom::Pilot::LabelSuggestionService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:billing_label) { create(:label, account: account, title: 'billing') }
  let!(:refund_label) { create(:label, account: account, title: 'refund') }
  let!(:other_label) { create(:label, account: account, title: 'spam') }

  before do
    account.update!(pilot_enabled: true, pilot_label_suggestion_enabled: true)
  end

  describe '#perform' do
    it 'raises FeatureDisabledError when the label_suggestion flag is off' do
      account.update!(pilot_label_suggestion_enabled: false)
      service = described_class.new(conversation: conversation)
      expect { service.perform }.to raise_error(described_class::FeatureDisabledError)
    end

    it 'returns label ids matching the LLM-suggested titles' do
      fake = instance_double(::Pilot::LabelSuggestionService,
                             perform: { message: 'billing, refund' })
      allow(::Pilot::LabelSuggestionService).to receive(:new).and_return(fake)

      service = described_class.new(conversation: conversation)
      result = service.perform

      expect(result).to contain_exactly(billing_label.id, refund_label.id)
      expect(result).not_to include(other_label.id)
    end

    it 'returns an empty array when the underlying service returns nil' do
      allow(::Pilot::LabelSuggestionService).to receive(:new)
        .and_return(instance_double(::Pilot::LabelSuggestionService, perform: nil))

      service = described_class.new(conversation: conversation)
      expect(service.perform).to eq([])
    end

    it 'dispatches label_suggestion_completed telemetry on success' do
      fake = instance_double(::Pilot::LabelSuggestionService, perform: { message: 'billing' })
      allow(::Pilot::LabelSuggestionService).to receive(:new).and_return(fake)

      service = described_class.new(conversation: conversation)
      expect(service).to receive(:dispatch_event).with(:label_suggestion_started, anything)
      expect(service).to receive(:dispatch_event).with(:label_suggestion_completed, hash_including(:label_count))
      service.perform
    end
  end
end
