require 'rails_helper'

RSpec.describe Custom::Pilot::RewriteService do
  let(:account) { create(:account) }

  before do
    account.enable_features!(:pilot, :pilot_rewrite)
  end

  describe '#perform' do
    it 'raises FeatureDisabledError when the rewrite flag is off' do
      account.disable_features!(:pilot_rewrite)
      service = described_class.new(text: 'hello', operation: 'friendly', account: account)
      expect { service.perform }.to raise_error(described_class::FeatureDisabledError)
    end

    it 'raises ArgumentError for an invalid operation' do
      service = described_class.new(text: 'hello', operation: 'passive_aggressive', account: account)
      expect { service.perform }.to raise_error(ArgumentError, /Invalid operation/)
    end

    it 'accepts all allowed operations' do
      fake = instance_double(Pilot::RewriteService, perform: { message: 'rewritten' })
      allow(Pilot::RewriteService).to receive(:new).and_return(fake)

      described_class::ALLOWED_OPERATIONS.each do |operation|
        service = described_class.new(text: 'hello', operation: operation, account: account)
        expect(service.perform).to eq('rewritten')
      end
    end

    it 'maps the Pilot tone enum to the underlying MIT operation' do
      fake = instance_double(Pilot::RewriteService, perform: { message: 'rewritten' })
      expect(Pilot::RewriteService).to receive(:new)
        .with(account: account, content: 'hi', operation: 'professional')
        .and_return(fake)

      described_class.new(text: 'hi', operation: 'formal', account: account).perform
    end

    it 'forwards improve as-is to the MIT service' do
      fake = instance_double(Pilot::RewriteService, perform: { message: 'rewritten' })
      expect(Pilot::RewriteService).to receive(:new)
        .with(account: account, content: 'hi', operation: 'improve')
        .and_return(fake)

      described_class.new(text: 'hi', operation: 'improve', account: account).perform
    end

    it 'forwards fix_spelling_grammar as-is to the MIT service' do
      fake = instance_double(Pilot::RewriteService, perform: { message: 'rewritten' })
      expect(Pilot::RewriteService).to receive(:new)
        .with(account: account, content: 'hi', operation: 'fix_spelling_grammar')
        .and_return(fake)

      described_class.new(text: 'hi', operation: 'fix_spelling_grammar', account: account).perform
    end

    it 'dispatches rewrite_completed telemetry on success' do
      fake = instance_double(Pilot::RewriteService, perform: { message: 'rewritten' })
      allow(Pilot::RewriteService).to receive(:new).and_return(fake)

      service = described_class.new(text: 'hi', operation: 'friendly', account: account)
      expect(service).to receive(:dispatch_event).with(:rewrite_started, hash_including(:operation))
      expect(service).to receive(:dispatch_event).with(:rewrite_completed, hash_including(:operation))
      service.perform
    end
  end
end
