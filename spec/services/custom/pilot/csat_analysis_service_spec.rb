require 'rails_helper'

RSpec.describe Custom::Pilot::CsatAnalysisService do
  let(:account) { create(:account) }

  before do
    account.enable_features!(:pilot, :pilot_csat_analysis)
  end

  describe '#perform' do
    it 'raises FeatureDisabledError when the csat_analysis flag is off' do
      account.disable_features!(:pilot_csat_analysis)
      service = described_class.new(feedback_message: 'slow refund', account: account)
      expect { service.perform }.to raise_error(described_class::FeatureDisabledError)
    end

    it 'returns a structured hash with sentiment, themes, escalation_recommended' do
      fake_adapter = instance_double(described_class::AdHocTaskService)
      allow(described_class::AdHocTaskService).to receive(:new).and_return(fake_adapter)
      allow(fake_adapter).to receive(:perform).and_return(
        { message: '{"sentiment":"negative","themes":["refund","slow"],"escalation_recommended":true}' }
      )

      service = described_class.new(feedback_message: 'It took ages to get a refund', account: account)
      result = service.perform

      expect(result).to eq(
        sentiment: 'negative',
        themes: %w[refund slow],
        escalation_recommended: true
      )
    end

    it 'falls back to neutral sentiment if the LLM returns non-JSON' do
      fake_adapter = instance_double(described_class::AdHocTaskService, perform: { message: 'not json' })
      allow(described_class::AdHocTaskService).to receive(:new).and_return(fake_adapter)

      service = described_class.new(feedback_message: 'something', account: account)
      expect(service.perform[:sentiment]).to eq('neutral')
    end

    it 'dispatches csat_analysis_completed telemetry on success' do
      fake_adapter = instance_double(described_class::AdHocTaskService,
                                     perform: { message: '{"sentiment":"positive","themes":[],"escalation_recommended":false}' })
      allow(described_class::AdHocTaskService).to receive(:new).and_return(fake_adapter)

      service = described_class.new(feedback_message: 'great', account: account)
      expect(service).to receive(:dispatch_event).with(:csat_analysis_started)
      expect(service).to receive(:dispatch_event).with(:csat_analysis_completed, hash_including(:sentiment))
      service.perform
    end
  end
end
