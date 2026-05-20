require 'net/http'
require 'uri'

module Custom
  module Pilot
    # Wraps Firecrawl's async crawl API for Pilot::Documents::CrawlJob.
    #
    # `#start(seed_url)` kicks off `POST /v1/crawl` with the configured safety
    # knobs and returns the Firecrawl job id. `#poll(job_id)` checks
    # `GET /v1/crawl/{id}` and returns a Result describing the current status.
    #
    # Errors are surfaced via explicit `error_code` values so the calling job
    # can branch on permanent vs. transient failures:
    #   - `crawl_start_4xx`  — bad request / quota / auth (permanent → :failed)
    #   - `crawl_start_5xx`  — server side; raises so Sidekiq retries
    #   - `crawl_timeout`    — job polled past the cap (set by the caller)
    #   - `crawl_empty`      — crawl completed with zero pages
    #   - `crawl_parse_error`— JSON parse failure
    class DocumentCrawlService < BaseService
      StartResult = Struct.new(:success, :job_id, :error_code, :error_message, keyword_init: true) do
        def success?
          success == true
        end
      end

      PollResult = Struct.new(:status, :pages, :error_code, :error_message, keyword_init: true) do
        def in_progress?
          status == :in_progress
        end

        def completed?
          status == :completed
        end

        def failed?
          status == :failed
        end
      end

      DEFAULT_TIMEOUT_SECONDS = 30
      # Page-count cap is the real governor; depth is set effectively
      # unbounded so Firecrawl walks the whole site within the page cap.
      DEFAULT_LIMIT = 500
      DEFAULT_MAX_DEPTH = 50

      def start(seed_url)
        uri = URI.parse('https://api.firecrawl.dev/v1/crawl')
        http = build_http(uri)

        req = Net::HTTP::Post.new(uri.request_uri,
                                  'Authorization' => "Bearer #{firecrawl_api_key}",
                                  'Content-Type' => 'application/json')
        req.body = request_body(seed_url).to_json

        response = http.request(req)

        if response.is_a?(Net::HTTPSuccess)
          parsed = JSON.parse(response.body)
          job_id = parsed['id'] || parsed.dig('data', 'id')
          return StartResult.new(success: true, job_id: job_id) if job_id.present?

          StartResult.new(success: false, error_code: 'crawl_parse_error', error_message: 'Firecrawl /v1/crawl returned no job id')
        elsif response.code.to_i.between?(400, 499)
          StartResult.new(success: false, error_code: 'crawl_start_4xx', error_message: "Firecrawl HTTP #{response.code}: #{response.body}")
        else
          raise "crawl_start_5xx: Firecrawl HTTP #{response.code}"
        end
      rescue JSON::ParserError => e
        StartResult.new(success: false, error_code: 'crawl_parse_error', error_message: e.message)
      end

      def poll(job_id)
        uri = URI.parse("https://api.firecrawl.dev/v1/crawl/#{job_id}")
        http = build_http(uri)

        req = Net::HTTP::Get.new(uri.request_uri, 'Authorization' => "Bearer #{firecrawl_api_key}")
        response = http.request(req)

        unless response.is_a?(Net::HTTPSuccess)
          raise "crawl_poll_http_error: Firecrawl HTTP #{response.code}" if response.code.to_i >= 500

          return PollResult.new(status: :failed, pages: [], error_code: 'crawl_start_4xx',
                                error_message: "Firecrawl HTTP #{response.code}")
        end

        parsed = JSON.parse(response.body)
        firecrawl_status = parsed['status'].to_s

        case firecrawl_status
        when 'completed'
          pages = extract_pages(parsed)
          if pages.empty?
            return PollResult.new(status: :failed, pages: [], error_code: 'crawl_empty',
                                  error_message: 'Firecrawl crawl completed with zero pages')
          end

          PollResult.new(status: :completed, pages: pages)
        when 'failed'
          PollResult.new(status: :failed, pages: [], error_code: 'crawl_start_4xx',
                         error_message: parsed['error'].to_s.presence || 'Firecrawl reported status=failed')
        else
          # Firecrawl populates `data` progressively during `scraping` — surface
          # the partial set so the job can fan out child docs incrementally.
          PollResult.new(status: :in_progress, pages: extract_pages(parsed))
        end
      rescue JSON::ParserError => e
        PollResult.new(status: :failed, pages: [], error_code: 'crawl_parse_error', error_message: e.message)
      end

      private

      def build_http(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = DEFAULT_TIMEOUT_SECONDS
        http
      end

      def request_body(seed_url)
        {
          url: seed_url,
          limit: crawl_limit,
          maxDepth: crawl_max_depth,
          ignoreSitemap: false,
          scrapeOptions: {
            formats: ['markdown'],
            onlyMainContent: false,
            excludeTags: ['iframe']
          }
        }
      end

      def crawl_limit
        Integer(GlobalConfigService.load('PILOT_FIRECRAWL_CRAWL_LIMIT', DEFAULT_LIMIT))
      end

      def crawl_max_depth
        Integer(GlobalConfigService.load('PILOT_FIRECRAWL_CRAWL_MAX_DEPTH', DEFAULT_MAX_DEPTH))
      end

      def extract_pages(parsed)
        Array(parsed['data']).filter_map do |entry|
          markdown = entry['markdown'].presence || entry.dig('content', 'markdown').presence
          metadata = entry['metadata'] || {}
          url = metadata['sourceURL'].presence ||
                metadata['url'].presence ||
                entry['url'].presence ||
                entry['sourceURL'].presence
          next if url.blank? || markdown.blank?

          title = metadata['title'].presence ||
                  metadata['ogTitle'].presence ||
                  url

          { url: url, title: title, markdown: markdown }
        end
      end

      def firecrawl_api_key
        GlobalConfigService.load('PILOT_FIRECRAWL_API_KEY', nil)
      end
    end
  end
end
