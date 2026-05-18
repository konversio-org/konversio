require 'rails_helper'

RSpec.describe Custom::Pilot::RewriteService do
  let(:account) { create(:account) }

  before do
    account.update!(pilot_enabled: true, pilot_rewrite_enabled: true)
  end

  describe '#perform' do
    it 'raises FeatureDisabledError when the rewrite flag is off' do
      account.update!(pilot_rewrite_enabled: false)
      service = described_class.new(text: 'hello', tone: 'friendly', account: account)
      expect { service.perform }.to raise_error(described_class::FeatureDisabledError)
    end

    it 'raises ArgumentError for an invalid tone' do
      service = described_class.new(text: 'hello', tone: 'passive_aggressive', account: account)
      expect { service.perform }.to raise_error(ArgumentError, /Invalid tone/)
    end

    it 'accepts all spec-defined tones' do
      fake = instance_double(::Pilot::RewriteService, perform: { message: 'rewritten' })
      allow(::Pilot::RewriteService).to receive(:new).and_return(fake)

      described_class::ALLOWED_TONES.each do |tone|
        service = described_class.new(text: 'hello', tone: tone, account: account)
        expect(service.perform).to eq('rewritten')
      end
    end

    it 'maps the Pilot tone enum to the underlying MIT operation' do
      fake = instance_double(::Pilot::RewriteService, perform: { message: 'rewritten' })
      expect(::Pilot::RewriteService).to receive(:new)
        .with(account: account, content: 'hi', operation: 'professional')
        .and_return(fake)

      described_class.new(text: 'hi', tone: 'formal', account: account).perform
    end

    it 'dispatches rewrite_completed telemetry on success' do
      fake = instance_double(::Pilot::RewriteService, perform: { message: 'rewritten' })
      allow(::Pilot::RewriteService).to receive(:new).and_return(fake)

      service = described_class.new(text: 'hi', tone: 'friendly', account: account)
      expect(service).to receive(:dispatch_event).with(:rewrite_started, hash_including(:tone))
      expect(service).to receive(:dispatch_event).with(:rewrite_completed, hash_including(:tone))
      service.perform
    end
  end
end
