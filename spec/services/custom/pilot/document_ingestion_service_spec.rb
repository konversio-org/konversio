require 'rails_helper'
require 'webmock/rspec'

RSpec.describe Custom::Pilot::DocumentIngestionService do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }

  describe '#perform' do
    context 'URL ingestion via simple HTTP (no Firecrawl key)' do
      let(:document) { create(:pilot_document, assistant: assistant, account: account, external_link: 'https://example.com/help/refunds') }

      it 'returns success and stripped body content' do
        stub_request(:get, 'https://example.com/help/refunds')
          .to_return(status: 200, body: '<html><body><h1>Refunds</h1><p>We refund within 30 days.</p></body></html>')

        result = described_class.new(document: document).perform
        expect(result.success?).to be true
        expect(result.content).to include('Refunds')
        expect(result.content).to include('30 days')
        expect(result.content).not_to include('<')
      end

      it 'returns a failure result on HTTP error' do
        stub_request(:get, 'https://example.com/help/refunds').to_return(status: 404)

        result = described_class.new(document: document).perform
        expect(result.success?).to be false
        expect(result.error_code).to eq('ingestion.http_error')
      end
    end

    context 'URL ingestion via Firecrawl when PILOT_FIRECRAWL_API_KEY is set' do
      let(:document) { create(:pilot_document, assistant: assistant, account: account, external_link: 'https://example.com/help/refunds') }

      around do |example|
        original = ENV.fetch('PILOT_FIRECRAWL_API_KEY', nil)
        ENV['PILOT_FIRECRAWL_API_KEY'] = 'firecrawl-key'
        example.run
      ensure
        ENV['PILOT_FIRECRAWL_API_KEY'] = original
      end

      it 'returns success with markdown content from the Firecrawl response' do
        stub_request(:post, 'https://api.firecrawl.dev/v1/scrape')
          .to_return(status: 200, body: { data: { markdown: '# Refunds\n\nWe refund within 30 days.' } }.to_json)

        result = described_class.new(document: document).perform
        expect(result.success?).to be true
        expect(result.content).to include('Refunds')
      end

      it 'returns a failure result on Firecrawl HTTP error' do
        stub_request(:post, 'https://api.firecrawl.dev/v1/scrape').to_return(status: 502)

        result = described_class.new(document: document).perform
        expect(result.success?).to be false
        expect(result.error_code).to eq('ingestion.firecrawl_http_error')
      end
    end

    context 'PDF ingestion' do
      let(:document) { create(:pilot_document, assistant: assistant, account: account, external_link: 'PDF: doc_20260517') }

      it 'returns a structured failure when pdf-reader is not installed' do
        allow(document).to receive(:pdf_document?).and_return(true)
        allow(document.pdf_file).to receive(:attached?).and_return(true)
        allow(document.pdf_file).to receive(:download).and_return('not a pdf')

        # Simulate pdf-reader missing
        service = described_class.new(document: document)
        allow(service).to receive(:require).with('pdf-reader').and_raise(LoadError)

        result = service.perform
        expect(result.success?).to be false
        expect(result.error_code).to eq('ingestion.pdf_reader_missing')
      end
    end
  end
end
