require 'rails_helper'

RSpec.describe Pilot::Documents::RefreshService do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:document) do
    create(:pilot_document,
           assistant: assistant,
           account: account,
           external_link: 'https://example.com/help',
           status: :available,
           sync_status: :synced,
           content: 'stored body',
           last_synced_at: 1.day.ago)
  end

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('PILOT_FIRECRAWL_API_KEY', nil).and_return(nil)
    document # force creation before clearing its after_commit enqueues
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def stub_fetch(result)
    service = instance_double(Custom::Pilot::DocumentIngestionService, perform: result)
    allow(Custom::Pilot::DocumentIngestionService).to receive(:new).and_return(service)
  end

  def success_result(content)
    Custom::Pilot::DocumentIngestionService::Result.new(success: true, content: content)
  end

  def failure_result(error_code, category, transient: false)
    Custom::Pilot::DocumentIngestionService::Result.new(
      success: false, error_code: error_code, failure_category: category, transient: transient
    )
  end

  def fingerprint(content)
    Digest::SHA256.hexdigest(content.gsub(/\s+/, ' ').strip)
  end

  def builder_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == Pilot::DocumentResponseBuilderJob }
  end

  describe '#perform' do
    it 'skips file-backed documents' do
      document.update!(external_link: 'MD: notes.md')

      result = described_class.new(document).perform

      expect(result).to be_skipped
    end

    context 'when the fingerprint matches the freshly fetched content' do
      before { document.update!(content_fingerprint: fingerprint('stored body')) }

      it 'does not write content, rebuild knowledge, or emit an updated outcome' do
        stub_fetch(success_result('stored   body'))

        result = described_class.new(document).perform

        expect(result).to be_unchanged
        expect(document.reload.content).to eq('stored body')
        expect(builder_jobs).to be_empty
        expect(document.sync_status).to eq('synced')
        expect(document.last_sync_attempted_at).to be_present
      end
    end

    context 'when the fingerprint differs' do
      before { document.update!(content_fingerprint: fingerprint('stored body')) }

      it 'updates content and name and triggers the knowledge rebuild' do
        service = described_class.new(document)
        allow(service).to receive(:fetch).and_return(
          Pilot::Documents::RefreshService::FetchResult.new(success: true, content: 'updated body', title: 'New Title')
        )

        result = service.perform

        expect(result).to be_updated
        document.reload
        expect(document.content).to eq('updated body')
        expect(document.name).to eq('New Title')
        expect(document.content_fingerprint).to eq(fingerprint('updated body'))
        expect(builder_jobs.size).to eq(1)
      end
    end

    context 'when there is no stored fingerprint' do
      before { document.update!(content_fingerprint: nil) }

      it 'records the fingerprint as a baseline without an update signal' do
        stub_fetch(success_result('stored body'))

        result = described_class.new(document).perform

        expect(result).to be_baseline
        document.reload
        expect(document.content_fingerprint).to eq(fingerprint('stored body'))
        expect(document.content).to eq('stored body')
        expect(builder_jobs).to be_empty
      end
    end

    context 'with a permanent failure' do
      it 'marks the document failed and keeps the previous content' do
        stub_fetch(failure_result('ingestion.http_404', :not_found))

        result = described_class.new(document).perform

        expect(result).to be_failed
        expect(result.failure_category).to eq(:not_found)
        document.reload
        expect(document.sync_status).to eq('failed')
        expect(document.last_sync_failure_category).to eq('not_found')
        expect(document.content).to eq('stored body')
      end
    end

    context 'with an empty response body' do
      it 'classifies the failure as permanent empty body' do
        stub_fetch(success_result('   '))

        result = described_class.new(document).perform

        expect(result).to be_failed
        expect(result.failure_category).to eq(:empty_body)
        expect(document.reload.sync_status).to eq('failed')
      end
    end

    context 'with a transient failure' do
      it 'raises a transient error for a 5xx result' do
        stub_fetch(failure_result('ingestion.http_503', :server_error, transient: true))

        expect { described_class.new(document).perform }
          .to raise_error(Pilot::Documents::RefreshService::TransientRefreshError) { |e| expect(e.failure_category).to eq(:server_error) }

        expect(document.reload.sync_status).to eq('synced')
      end

      it 'raises a transient error for a timeout raised by the ingestion service' do
        error = Custom::Pilot::DocumentIngestionService::TransientFetchError.new(
          'timeout', error_code: 'ingestion.timeout', failure_category: :timeout
        )
        service = instance_double(Custom::Pilot::DocumentIngestionService)
        allow(Custom::Pilot::DocumentIngestionService).to receive(:new).and_return(service)
        allow(service).to receive(:perform).and_raise(error)

        expect { described_class.new(document).perform }
          .to raise_error(Pilot::Documents::RefreshService::TransientRefreshError) { |e| expect(e.failure_category).to eq(:timeout) }

        expect(document.reload.sync_status).to eq('synced')
      end
    end

    context 'when Firecrawl is configured' do
      before do
        allow(GlobalConfigService).to receive(:load).with('PILOT_FIRECRAWL_API_KEY', nil).and_return('fc-key')
      end

      it 'uses the single-page scrape path' do
        scrape = instance_double(
          Custom::Pilot::DocumentCrawlService,
          scrape: Custom::Pilot::DocumentCrawlService::ScrapeResult.new(success: true, content: 'scraped body', title: 'Scraped')
        )
        allow(Custom::Pilot::DocumentCrawlService).to receive(:new).and_return(scrape)
        allow(Custom::Pilot::DocumentIngestionService).to receive(:new)

        result = described_class.new(document).perform

        expect(result).to be_baseline
        expect(scrape).to have_received(:scrape).with(document.external_link)
        expect(Custom::Pilot::DocumentIngestionService).not_to have_received(:new)
      end
    end
  end
end
