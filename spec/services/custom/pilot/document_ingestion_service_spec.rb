require 'rails_helper'
require 'webmock/rspec'

RSpec.describe Custom::Pilot::DocumentIngestionService do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }

  describe '#perform' do
    context 'with URL ingestion via simple HTTP' do
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

    context 'with PDF ingestion' do
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
