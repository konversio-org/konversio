require 'net/http'
require 'uri'
require 'cgi'

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
    class CrawlJob < ApplicationJob
      queue_as :low

      # Backoff schedule (interval seconds, poll count) — D1.
      POLL_SCHEDULE = [
        [5, 12],   # first minute
        [15, 36],  # next 9 minutes
        [60, 20]   # next 20 minutes — total cap 30 minutes
      ].freeze

      sidekiq_retries_exhausted do |msg, _exception|
        document_id = msg['args'].first
        document = ::Pilot::Document.find_by(id: document_id)
        next if document.blank?

        document.update_columns(
          status: ::Pilot::Document.statuses[:failed],
          metadata: (document.metadata || {}).merge('error_message' => 'crawl_retries_exhausted')
        )
      end

      def perform(document_id)
        @document = ::Pilot::Document.find_by(id: document_id)
        return if @document.blank?

        # PDFs are ingested synchronously via the existing service.
        return ingest_pdf if @document.pdf_document?

        # No Firecrawl key → single-page fallback (matches the spec scenario
        # "URL ingestion fallback to simple page crawl").
        return ingest_via_fallback if firecrawl_api_key.blank?

        run_crawl
      end

      private

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
          mark_failed(result&.error_code || 'pdf_ingestion_failed')
        end
      end

      def ingest_via_fallback
        result = ::Custom::Pilot::DocumentIngestionService.new(document: @document, account: @document.account).perform
        if result&.success?
          @document.update!(content: result.content, status: :available, sync_status: :synced)
        else
          mark_failed(result&.error_code || 'ingestion_failed')
        end
      end

      def mark_failed(error_message)
        @document.update!(
          status: :failed,
          metadata: (@document.metadata || {}).merge('error_message' => error_message)
        )
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
  end
end
