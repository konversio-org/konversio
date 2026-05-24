require 'net/http'
require 'uri'
require 'cgi'

# rubocop:disable Style/ClassAndModuleChildren
module Pilot
  module Documents
    # Long-running Sidekiq job that owns the async crawl lifecycle for a
    # single seed `Pilot::Document`. Kicks off Firecrawl `POST /v1/crawl`,
    # polls `GET /v1/crawl/{id}` on a backoff schedule, then fans the result
    # into one document per discovered page.
    #
    # PDF documents bypass the crawl path entirely and are ingested via the
    # existing `Custom::Pilot::DocumentIngestionService` (synchronous PDF
    # text extraction).
    #
    # Failure semantics (mirrors design D7):
    #   - Firecrawl 4xx on start / poll → seed row :failed, `error_message`
    #     set to `"crawl_start_error: <code>"`.
    #   - 30-minute poll timeout → seed row :failed, `error_message:
    #     "crawl_timeout"`.
    #   - Crawl completes with zero pages → seed row :failed,
    #     `error_message: "crawl_empty"`.
    #   - 5xx / network error → raises so Sidekiq retries with default
    #     backoff. Final attempt's `sidekiq_retries_exhausted` marks the
    #     seed row :failed.
    # rubocop:disable Metrics/ClassLength
    class CrawlJob < ApplicationJob
      queue_as :low

      # Backoff schedule (interval seconds, poll count) — D1.
      POLL_SCHEDULE = [
        [5, 12],   # first minute
        [15, 36],  # next 9 minutes
        [60, 20]   # next 20 minutes — total cap 30 minutes
      ].freeze

      # Retry transient ingestion failures with the spec'd backoff
      # schedule: 30s, 2m, 5m (3 retries beyond the initial attempt).
      RETRY_WAITS = [30.seconds, 2.minutes, 5.minutes].freeze
      SOURCE_LOCK_TIMEOUT = 35.minutes
      SOURCE_LOCK_RETRY_WAIT = 1.minute

      retry_on ::Custom::Pilot::DocumentIngestionService::TransientFetchError,
               attempts: RETRY_WAITS.length + 1,
               wait: ->(executions) { RETRY_WAITS[executions - 1] || RETRY_WAITS.last } do |job, error|
        # All retries exhausted — mark the document failed via sync_status
        # (the document remains in_progress per the "Crawl failure leaves
        # status unchanged" spec scenario).
        job.send(:mark_sync_failed_after_retries, error)
      end

      sidekiq_retries_exhausted do |msg, _exception|
        document_id = msg['args'].first
        document = ::Pilot::Document.find_by(id: document_id)
        next if document.blank?

        document.update_columns( # rubocop:disable Rails/SkipsModelValidations
          sync_status: ::Pilot::Document.sync_statuses[:failed],
          metadata: (document.metadata || {}).merge('error' => 'crawl_retries_exhausted')
        )
      end

      def perform(document_id)
        @document = ::Pilot::Document.find_by(id: document_id)
        return if @document.blank?

        with_source_lock do
          perform_with_document
        end
      rescue ::Custom::Pilot::DocumentIngestionService::TransientFetchError
        # Let ActiveJob's retry_on handle this — propagate so the wait
        # schedule kicks in.
        raise
      rescue StandardError => e
        # Safety net per spec: any other exception marks the document
        # failed and records the exception class + message so operators can
        # diagnose later. We intentionally swallow rather than re-raise so
        # the user-visible row reflects the failure instead of a stuck
        # syncing row.
        Rails.logger.error("[pilot.crawl_job] unexpected #{e.class}: #{e.message}")
        mark_sync_failed("#{e.class.name}: #{e.message}") if @document
      end

      private

      def perform_with_document
        # PDFs are ingested synchronously via the existing service.
        return ingest_pdf if @document.pdf_document?

        # No Firecrawl key → single-page fallback (matches the spec scenario
        # "URL ingestion fallback to simple page crawl").
        return ingest_via_fallback if firecrawl_api_key.blank?

        run_crawl
      end

      def with_source_lock
        lock_manager = ::Redis::LockManager.new
        key = source_lock_key
        locked = lock_manager.lock(key, SOURCE_LOCK_TIMEOUT)
        unless locked
          reschedule_locked_source(key)
          return
        end

        yield
      ensure
        lock_manager&.unlock(key) if locked
      end

      def reschedule_locked_source(key)
        Rails.logger.info("[pilot.crawl_job] source lock busy document=#{@document.id} key=#{key}")
        self.class.set(wait: SOURCE_LOCK_RETRY_WAIT).perform_later(@document.id)
      end

      def source_lock_key
        normalized_source = normalize_url(@document.external_link)
        digest = ::Digest::SHA256.hexdigest(normalized_source)
        "pilot:documents:crawl:#{@document.assistant_id}:#{digest}"
      end

      def run_crawl
        start_result = crawl_service.start(@document.external_link)
        unless start_result.success?
          mark_failed("crawl_start_error: #{start_result.error_code}")
          return
        end

        job_id = start_result.job_id
        @document.update!(metadata: (@document.metadata || {}).merge('crawl_job_id' => job_id))

        poll_result = poll_until_done(job_id)
        return if poll_result.nil? # timeout already marked failure

        if poll_result.failed?
          mark_failed(poll_result.error_code || 'crawl_failed')
          return
        end

        fan_out(poll_result.pages)
      end

      def poll_until_done(job_id)
        POLL_SCHEDULE.each do |interval, count|
          count.times do
            sleep(interval)
            result = crawl_service.poll(job_id)
            stream_partial_pages(result.pages) if result.in_progress?
            return result unless result.in_progress?
          end
        end

        mark_failed('crawl_timeout')
        nil
      end

      # Incremental fan-out: insert child docs for any pages Firecrawl has
      # scraped so far, without touching the seed row (which stays
      # :in_progress until the final completed poll). Idempotent via
      # `find_or_create_by(external_link:)` so overlapping polls don't
      # double-insert.
      def stream_partial_pages(pages)
        return if pages.blank?

        seed_link_norm = normalize_url(@document.external_link)
        pages.each do |page|
          next if normalize_url(page[:url]) == seed_link_norm

          upsert_child_document(page)
        end
      end

      def fan_out(pages)
        if pages.empty?
          mark_failed('crawl_empty')
          return
        end

        seed_link_norm = normalize_url(@document.external_link)
        seed_match_idx = pages.index { |p| normalize_url(p[:url]) == seed_link_norm }

        update_seed_row(seed_match_idx ? pages[seed_match_idx] : nil)
        pages.each_with_index do |page, idx|
          next if idx == seed_match_idx

          upsert_child_document(page)
        end

        dispatch_crawled(pages.size)
      end

      def dispatch_crawled(page_count)
        ::Custom::Pilot::EventDispatcher.dispatch(
          'pilot.autopilot.document.crawled',
          {
            account_id: @document.account_id,
            assistant_id: @document.assistant_id,
            document_id: @document.id,
            page_count: page_count
          },
          account: @document.account
        )
      rescue StandardError => e
        Rails.logger.warn("[pilot.crawl_job] dispatch failed: #{e.class}: #{e.message}")
      end

      def update_seed_row(seed_page)
        if seed_page
          @document.update!(
            content: seed_page[:markdown],
            name: seed_page[:title].presence || @document.name,
            status: :available
          )
        else
          # Seed URL wasn't in the crawl set — fetch <title> directly so the
          # row shows a useful name instead of the raw URL. Child rows carry
          # the actual knowledge content.
          fetched_title = fetch_html_title(@document.external_link)
          @document.update!(
            status: :available,
            content: nil,
            name: fetched_title.presence || @document.name
          )
        end
      end

      # Single GET on the seed URL to scrape <title>. Bounded timeout, swallows
      # errors and returns nil — this is a best-effort name-improver, never a
      # blocker on the crawl completing successfully.
      # rubocop:disable Metrics/AbcSize
      def fetch_html_title(url)
        uri = URI.parse(url.to_s)
        return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 10
        http.open_timeout = 5

        response = http.get(uri.request_uri)
        return nil unless response.is_a?(Net::HTTPSuccess)

        match = response.body.to_s.match(%r{<title[^>]*>(.+?)</title>}im)
        return nil unless match

        CGI.unescapeHTML(match[1].to_s).strip.presence
      rescue StandardError => e
        Rails.logger.warn("[pilot.crawl_job] fetch_html_title failed for #{url}: #{e.message}")
        nil
      end
      # rubocop:enable Metrics/AbcSize

      def upsert_child_document(page)
        existing = @document.assistant.documents.find_by(external_link: page[:url])
        if existing
          existing.update!(content: page[:markdown], name: page[:title].presence || existing.name, status: :available)
          return
        end

        @document.assistant.documents.create!(
          account: @document.account,
          external_link: page[:url],
          name: page[:title].presence || page[:url],
          content: page[:markdown],
          status: :available
        )
      end

      def ingest_pdf
        result = ::Custom::Pilot::DocumentIngestionService.new(document: @document, account: @document.account).perform
        if result&.success?
          @document.update!(content: result.content, status: :available, sync_status: :synced)
        else
          # PDF errors are permanent (pdf-reader missing, malformed PDF, etc.).
          mark_sync_failed(result&.error_code || 'pdf_ingestion_failed')
        end
      end

      def ingest_via_fallback
        result = ::Custom::Pilot::DocumentIngestionService.new(document: @document, account: @document.account).perform
        if result&.success?
          @document.update!(content: result.content, status: :available, sync_status: :synced)
        else
          # A returned Result with success=false is a permanent failure
          # (transient cases raise TransientFetchError which the job-level
          # retry_on catches before we reach here).
          mark_sync_failed(result&.error_code || 'ingestion_failed')
        end
      end

      def mark_failed(error_message)
        @document.update!(
          status: :failed,
          metadata: (@document.metadata || {}).merge('error_message' => error_message)
        )
      end

      # Permanent / out-of-retries failure: only sync_status flips to
      # `failed`. `status` stays put so the row remains usable (e.g. an
      # existing `available` document retains its previously-crawled
      # content even though the latest re-sync attempt failed).
      def mark_sync_failed(error_message)
        @document.update!(
          sync_status: :failed,
          metadata: (@document.metadata || {}).merge('error' => error_message.to_s)
        )
      end

      def mark_sync_failed_after_retries(error)
        # retry_on's block does not re-invoke `perform`, so we may not have
        # `@document` set if the job was deserialized fresh on the final
        # tick. Fall back to looking it up via `arguments`.
        @document ||= ::Pilot::Document.find_by(id: arguments.first)
        return if @document.blank?

        code = error.respond_to?(:error_code) ? error.error_code : "#{error.class.name}: #{error.message}"
        mark_sync_failed(code)
      end

      def normalize_url(url)
        url.to_s.sub(%r{/+\z}, '')
      end

      def crawl_service
        @crawl_service ||= ::Custom::Pilot::DocumentCrawlService.new(account: @document.account)
      end

      def firecrawl_api_key
        ::GlobalConfigService.load('PILOT_FIRECRAWL_API_KEY', nil)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
# rubocop:enable Style/ClassAndModuleChildren
