require 'net/http'
require 'uri'

module Custom
  module Pilot
    # Fetches the body of a `Pilot::Document` from its source.
    #
    # Dispatch:
    #   - PDF documents → `pdf-reader` extraction (single document in, single
    #     document out).
    #   - URL documents → in-process HTTP fetch with HTML stripping
    #     (single-page fallback used when `PILOT_FIRECRAWL_API_KEY` is not
    #     configured). The multi-page Firecrawl crawl path lives in
    #     `Pilot::Documents::CrawlJob` + `Custom::Pilot::DocumentCrawlService`.
    #
    # Returns a Result struct describing success/failure and the fetched
    # content so the caller can persist it. Transient failures (HTTP 5xx,
    # 408, 429, timeouts, connection errors) are surfaced via
    # `TransientFetchError` so the caller (`Pilot::Documents::CrawlJob`) can
    # raise + retry. Permanent failures (other 4xx, parse, malformed URL)
    # return a Result with `success: false` so the caller marks the document
    # `sync_status = "failed"` without retrying.
    class DocumentIngestionService < BaseService
      class TransientFetchError < StandardError
        attr_reader :error_code

        def initialize(message, error_code:)
          super(message)
          @error_code = error_code
        end
      end

      Result = Struct.new(:success, :content, :error_code, :error_message, keyword_init: true) do
        def success?
          success == true
        end
      end

      DEFAULT_TIMEOUT_SECONDS = 30
      MAX_CONTENT_BYTES = 500_000

      # HTTP status codes that should retry. Everything else in the 4xx
      # range is considered permanent (the upstream told us "no" with
      # finality; retrying won't change the answer).
      TRANSIENT_HTTP_STATUSES = [408, 429].freeze

      attr_reader :document

      def initialize(document:, account: nil)
        @document = document
        super(account: account || document&.account)
      end

      def perform
        if document.pdf_document? && document.pdf_file.attached?
          ingest_pdf
        else
          ingest_url
        end
      rescue TransientFetchError
        # Propagate so `Pilot::Documents::CrawlJob` can hit ActiveJob retries.
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.document_ingestion] #{e.class}: #{e.message}")
        Result.new(success: false, error_code: 'ingestion.unexpected', error_message: e.message)
      end

      private

      def ingest_url
        url = document.external_link.to_s
        return failure('ingestion.missing_url', 'No external_link to ingest') if url.blank?

        ingest_via_simple_http(url)
      end

      def ingest_via_simple_http(url)
        uri = parse_uri(url)
        return failure('ingestion.invalid_url', "Cannot parse URL: #{url}") if uri.nil?

        response = http_get(uri)
        return classify_http_failure(response) unless response.is_a?(Net::HTTPSuccess)

        Result.new(success: true, content: truncate(strip_html(response.body.to_s)))
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT => e
        raise TransientFetchError.new("Timeout fetching URL: #{e.message}", error_code: 'ingestion.timeout')
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
        raise TransientFetchError.new("Connection error: #{e.message}", error_code: 'ingestion.connection_error')
      end

      def http_get(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = DEFAULT_TIMEOUT_SECONDS
        http.open_timeout = DEFAULT_TIMEOUT_SECONDS
        http.get(uri.request_uri)
      end

      def parse_uri(url)
        uri = URI.parse(url)
        return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        uri
      rescue URI::InvalidURIError
        nil
      end

      def classify_http_failure(response)
        code = response.code.to_i
        raise TransientFetchError.new("HTTP #{code}", error_code: "ingestion.http_#{code}") if code >= 500 || TRANSIENT_HTTP_STATUSES.include?(code)

        failure("ingestion.http_#{code}", "HTTP #{code}")
      end

      def ingest_pdf
        require 'pdf-reader'
        text = ::PDF::Reader.new(StringIO.new(document.pdf_file.download)).pages.map(&:text).join("\n\n")
        return failure('ingestion.pdf_empty', 'PDF produced no extractable text') if text.strip.blank?

        Result.new(success: true, content: truncate(text))
      rescue LoadError
        failure('ingestion.pdf_reader_missing', "pdf-reader gem not installed; cannot ingest PDF #{document.id}")
      rescue ::PDF::Reader::MalformedPDFError => e
        failure('ingestion.pdf_malformed', e.message)
      end

      def strip_html(html)
        text = html.gsub(%r{<script[^>]*>.*?</script>}m, ' ')
                   .gsub(%r{<style[^>]*>.*?</style>}m, ' ')
                   .gsub(/<[^>]+>/, ' ')
                   .gsub(/\s+/, ' ')
                   .strip
        CGI.unescapeHTML(text)
      end

      def truncate(content)
        return content if content.bytesize <= MAX_CONTENT_BYTES

        content.byteslice(0, MAX_CONTENT_BYTES)
      end

      def failure(code, message)
        Result.new(success: false, error_code: code, error_message: message)
      end
    end
  end
end
