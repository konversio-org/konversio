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

      it 'returns a permanent failure result on HTTP 4xx' do
        stub_request(:get, 'https://example.com/help/refunds').to_return(status: 404)

        result = described_class.new(document: document).perform
        expect(result.success?).to be false
        expect(result.error_code).to eq('ingestion.http_404')
      end

      it 'raises a transient error on HTTP 5xx so the caller can retry' do
        stub_request(:get, 'https://example.com/help/refunds').to_return(status: 503)

        expect { described_class.new(document: document).perform }
          .to raise_error(Custom::Pilot::DocumentIngestionService::TransientFetchError) do |err|
            expect(err.error_code).to eq('ingestion.http_503')
          end
      end

      it 'raises a transient error on HTTP 408 (request timeout)' do
        stub_request(:get, 'https://example.com/help/refunds').to_return(status: 408)

        expect { described_class.new(document: document).perform }
          .to raise_error(Custom::Pilot::DocumentIngestionService::TransientFetchError) do |err|
            expect(err.error_code).to eq('ingestion.http_408')
          end
      end

      it 'raises a transient error on HTTP 429 (rate limited)' do
        stub_request(:get, 'https://example.com/help/refunds').to_return(status: 429)

        expect { described_class.new(document: document).perform }
          .to raise_error(Custom::Pilot::DocumentIngestionService::TransientFetchError) do |err|
            expect(err.error_code).to eq('ingestion.http_429')
          end
      end

      it 'raises a transient error on network timeout' do
        stub_request(:get, 'https://example.com/help/refunds').to_timeout

        expect { described_class.new(document: document).perform }
          .to raise_error(Custom::Pilot::DocumentIngestionService::TransientFetchError) do |err|
            expect(err.error_code).to eq('ingestion.timeout')
          end
      end
    end

    context 'with PDF ingestion' do
      let(:document) { create(:pilot_document, assistant: assistant, account: account, external_link: 'PDF: doc_20260517') }

      it 'returns a structured failure when pdf-reader is not installed' do
        # The `require 'pdf-reader'` raises LoadError before pdf_file.download is
        # ever reached, so we only need to drive `pdf_document?` true; the
        # download seam is unreachable in this branch.
        allow(document).to receive(:pdf_document?).and_return(true)
        allow(document.pdf_file).to receive(:attached?).and_return(true)

        service = described_class.new(document: document)
        allow(service).to receive(:require).with('pdf-reader').and_raise(LoadError)

        result = service.perform
        expect(result.success?).to be false
        expect(result.error_code).to eq('ingestion.pdf_reader_missing')
      end
    end
  end
end
