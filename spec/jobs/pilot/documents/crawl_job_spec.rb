require 'rails_helper'

RSpec.describe Pilot::Documents::CrawlJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:seed_url) { 'https://example.com/help' }
  let(:document) do
    create(:pilot_document, assistant: assistant, account: account, external_link: seed_url, status: :in_progress, content: nil)
  end

  let(:crawl_service) { instance_double(Custom::Pilot::DocumentCrawlService) }

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('PILOT_FIRECRAWL_API_KEY', nil).and_return('firecrawl-key')
    allow(Custom::Pilot::DocumentCrawlService).to receive(:new).and_return(crawl_service)
    # Stub the private sleep so the polling backoff doesn't actually wait.
    allow_any_instance_of(described_class).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
    allow(Pilot::DocumentResponseBuilderJob).to receive(:perform_later)
  end

  describe '#perform' do
    it 'starts the crawl, persists the job id, and fans out result pages' do
      start_result = Custom::Pilot::DocumentCrawlService::StartResult.new(success: true, job_id: 'fc-123')
      pages = [
        { url: 'https://example.com/help', title: 'Help home', markdown: '# Help home' },
        { url: 'https://example.com/help/refunds', title: 'Refunds', markdown: '# Refunds' },
        { url: 'https://example.com/help/shipping', title: 'Shipping', markdown: '# Shipping' }
      ]
      poll_result = Custom::Pilot::DocumentCrawlService::PollResult.new(status: :completed, pages: pages)

      expect(crawl_service).to receive(:start).with(seed_url).and_return(start_result)
      expect(crawl_service).to receive(:poll).with('fc-123').and_return(poll_result)

      document_id = document.id # force creation
      expect do
        described_class.perform_now(document_id)
      end.to change { assistant.documents.count }.by(2)

      document.reload
      expect(document.status).to eq('available')
      expect(document.content).to eq('# Help home')
      expect(document.name).to eq('Help home')
      expect(document.metadata['crawl_job_id']).to eq('fc-123')

      child_urls = assistant.documents.where.not(id: document.id).pluck(:external_link)
      expect(child_urls).to contain_exactly('https://example.com/help/refunds', 'https://example.com/help/shipping')
    end

    it 'creates child rows when the seed URL is not in the crawl result' do
      start_result = Custom::Pilot::DocumentCrawlService::StartResult.new(success: true, job_id: 'fc-123')
      pages = [
        { url: 'https://example.com/help/refunds', title: 'Refunds', markdown: '# Refunds' }
      ]
      poll_result = Custom::Pilot::DocumentCrawlService::PollResult.new(status: :completed, pages: pages)

      allow(crawl_service).to receive(:start).and_return(start_result)
      allow(crawl_service).to receive(:poll).and_return(poll_result)

      # Seed URL fallback: when Firecrawl doesn't return the seed page,
      # the job fetches <title> directly. Stub it to return a real HTML
      # title so we also assert that branch.
      stub_request(:get, document.external_link)
        .to_return(status: 200, body: '<html><head><title>Refund Help Center</title></head></html>')

      described_class.perform_now(document.id)

      document.reload
      expect(document.status).to eq('available')
      expect(document.name).to eq('Refund Help Center')
      expect(assistant.documents.where(external_link: 'https://example.com/help/refunds')).to exist
    end

    it 'falls back gracefully when the seed-URL <title> fetch errors' do
      start_result = Custom::Pilot::DocumentCrawlService::StartResult.new(success: true, job_id: 'fc-123')
      pages = [
        { url: 'https://example.com/help/refunds', title: 'Refunds', markdown: '# Refunds' }
      ]
      poll_result = Custom::Pilot::DocumentCrawlService::PollResult.new(status: :completed, pages: pages)

      allow(crawl_service).to receive(:start).and_return(start_result)
      allow(crawl_service).to receive(:poll).and_return(poll_result)

      stub_request(:get, document.external_link).to_return(status: 500)

      original_name = document.name
      described_class.perform_now(document.id)

      document.reload
      expect(document.status).to eq('available')
      expect(document.name).to eq(original_name)
    end

    it 'marks the seed document failed on a 4xx crawl-start error' do
      start_result = Custom::Pilot::DocumentCrawlService::StartResult.new(success: false, error_code: 'crawl_start_4xx',
                                                                          error_message: 'HTTP 400')

      allow(crawl_service).to receive(:start).and_return(start_result)

      described_class.perform_now(document.id)
      document.reload
      expect(document.status).to eq('failed')
      expect(document.metadata['error_message']).to include('crawl_start_4xx')
    end

    it 'marks the seed document failed on poll timeout' do
      start_result = Custom::Pilot::DocumentCrawlService::StartResult.new(success: true, job_id: 'fc-123')
      in_progress = Custom::Pilot::DocumentCrawlService::PollResult.new(status: :in_progress, pages: [])

      allow(crawl_service).to receive(:start).and_return(start_result)
      allow(crawl_service).to receive(:poll).and_return(in_progress)

      described_class.perform_now(document.id)

      document.reload
      expect(document.status).to eq('failed')
      expect(document.metadata['error_message']).to eq('crawl_timeout')
    end

    it 'marks the seed document failed when the crawl returns zero pages' do
      start_result = Custom::Pilot::DocumentCrawlService::StartResult.new(success: true, job_id: 'fc-123')
      empty = Custom::Pilot::DocumentCrawlService::PollResult.new(status: :failed, pages: [], error_code: 'crawl_empty')

      allow(crawl_service).to receive(:start).and_return(start_result)
      allow(crawl_service).to receive(:poll).and_return(empty)

      described_class.perform_now(document.id)

      document.reload
      expect(document.status).to eq('failed')
      expect(document.metadata['error_message']).to eq('crawl_empty')
    end

    it 'falls back to single-page ingestion when PILOT_FIRECRAWL_API_KEY is not configured' do
      allow(GlobalConfigService).to receive(:load).with('PILOT_FIRECRAWL_API_KEY', nil).and_return(nil)
      fallback_result = Custom::Pilot::DocumentIngestionService::Result.new(success: true, content: 'fallback body')
      ingestion = instance_double(Custom::Pilot::DocumentIngestionService, perform: fallback_result)
      allow(Custom::Pilot::DocumentIngestionService).to receive(:new).and_return(ingestion)

      expect(crawl_service).not_to receive(:start)

      described_class.perform_now(document.id)

      document.reload
      expect(document.status).to eq('available')
      expect(document.content).to eq('fallback body')
    end

    it 'retries transient ingestion errors with the configured backoff and finally marks sync_status failed' do
      # No Firecrawl key → fallback path which goes through DocumentIngestionService.
      allow(GlobalConfigService).to receive(:load).with('PILOT_FIRECRAWL_API_KEY', nil).and_return(nil)

      transient = Custom::Pilot::DocumentIngestionService::TransientFetchError.new(
        'HTTP 503', error_code: 'ingestion.http_503'
      )
      ingestion = instance_double(Custom::Pilot::DocumentIngestionService)
      allow(Custom::Pilot::DocumentIngestionService).to receive(:new).and_return(ingestion)
      allow(ingestion).to receive(:perform).and_raise(transient)

      # ActiveJob's retry_on issues `perform` four times total
      # (initial + 3 retries). We exercise the path by performing
      # synchronously via the test adapter and counting the calls.
      perform_enqueued_jobs do
        described_class.perform_later(document.id)
      end

      expect(ingestion).to have_received(:perform).at_least(4).times
      document.reload
      expect(document.sync_status).to eq('failed')
      expect(document.metadata['error']).to eq('ingestion.http_503')
      expect(document.status).to eq('in_progress')
    end

    it 'marks sync_status failed immediately on a permanent ingestion failure (no retry)' do
      allow(GlobalConfigService).to receive(:load).with('PILOT_FIRECRAWL_API_KEY', nil).and_return(nil)

      permanent_result = Custom::Pilot::DocumentIngestionService::Result.new(
        success: false, error_code: 'ingestion.http_404', error_message: 'HTTP 404'
      )
      ingestion = instance_double(Custom::Pilot::DocumentIngestionService, perform: permanent_result)
      allow(Custom::Pilot::DocumentIngestionService).to receive(:new).and_return(ingestion)

      described_class.perform_now(document.id)

      # Single invocation — a returned (non-raising) permanent Result does
      # NOT trigger retry_on, so the LLM service isn't called a second
      # time.
      expect(ingestion).to have_received(:perform).once
      document.reload
      expect(document.sync_status).to eq('failed')
      expect(document.metadata['error']).to eq('ingestion.http_404')
      expect(document.status).to eq('in_progress')
    end

    it 'retries timeouts as transient failures' do
      allow(GlobalConfigService).to receive(:load).with('PILOT_FIRECRAWL_API_KEY', nil).and_return(nil)

      timeout_err = Custom::Pilot::DocumentIngestionService::TransientFetchError.new(
        'timeout', error_code: 'ingestion.timeout'
      )
      ingestion = instance_double(Custom::Pilot::DocumentIngestionService)
      allow(Custom::Pilot::DocumentIngestionService).to receive(:new).and_return(ingestion)
      allow(ingestion).to receive(:perform).and_raise(timeout_err)

      perform_enqueued_jobs do
        described_class.perform_later(document.id)
      end

      expect(ingestion).to have_received(:perform).at_least(4).times
      document.reload
      expect(document.sync_status).to eq('failed')
      expect(document.metadata['error']).to eq('ingestion.timeout')
    end

    it 'captures unexpected exceptions via the StandardError safety net' do
      allow(GlobalConfigService).to receive(:load).with('PILOT_FIRECRAWL_API_KEY', nil).and_return(nil)

      ingestion = instance_double(Custom::Pilot::DocumentIngestionService)
      allow(Custom::Pilot::DocumentIngestionService).to receive(:new).and_return(ingestion)
      allow(ingestion).to receive(:perform).and_raise(ArgumentError, 'parser crashed')

      described_class.perform_now(document.id)

      document.reload
      expect(document.sync_status).to eq('failed')
      expect(document.metadata['error']).to include('ArgumentError')
      expect(document.metadata['error']).to include('parser crashed')
    end

    it 'ingests PDF documents synchronously without hitting Firecrawl' do
      pdf_doc = create(:pilot_document, assistant: assistant, account: account, external_link: 'PDF: doc',
                                        status: :in_progress, content: nil)
      allow(pdf_doc).to receive(:pdf_document?).and_return(true)
      allow(Pilot::Document).to receive(:find_by).with(id: pdf_doc.id).and_return(pdf_doc)

      pdf_result = Custom::Pilot::DocumentIngestionService::Result.new(success: true, content: 'pdf body')
      ingestion = instance_double(Custom::Pilot::DocumentIngestionService, perform: pdf_result)
      allow(Custom::Pilot::DocumentIngestionService).to receive(:new).and_return(ingestion)

      expect(crawl_service).not_to receive(:start)

      described_class.perform_now(pdf_doc.id)

      pdf_doc.reload
      expect(pdf_doc.status).to eq('available')
      expect(pdf_doc.content).to eq('pdf body')
    end
  end

  # §13 follow-up: webhook signature verification on the inbound bulk-crawl
  # webhook is not covered. The routes table declares
  # `post 'webhooks/firecrawl'` but no controller exists yet. When that
  # controller lands, add a request-spec context that drives the endpoint
  # with (a) a valid signature, (b) a tampered signature, (c) a payload
  # whose assistant_id does not belong to the signing account — asserting
  # 401/403 on the negative paths and no Pilot::Document rows created.
  pending 'TODO: webhooks/firecrawl signature + assistant scoping coverage when the controller lands'
end
