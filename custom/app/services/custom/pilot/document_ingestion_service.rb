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
      # Transient fetch failures are raised so the caller (a job) can retry
      # them on a bounded backoff. They carry a machine-readable category in
      # addition to the legacy `error_code`.
      class TransientFetchError < StandardError
        attr_reader :error_code, :failure_category

        def initialize(message, error_code:, failure_category: nil)
          super(message)
          @error_code = error_code
          @failure_category = failure_category
        end

        def transient?
          true
        end
      end

      Result = Struct.new(:success, :content, :error_code, :error_message, :failure_category, :transient, keyword_init: true) do
        def success?
          success == true
        end

        def transient?
          transient == true
        end

        def permanent?
          !success? && !transient?
        end
      end

      DEFAULT_TIMEOUT_SECONDS = 30
      MAX_CONTENT_BYTES = 500_000

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
        Result.new(success: false, error_code: 'ingestion.unexpected', error_message: e.message, failure_category: :unexpected)
      end

      private

      def ingest_url
        url = document.external_link.to_s
        return failure('ingestion.missing_url', 'No external_link to ingest', category: :missing_url) if url.blank?

        ingest_via_simple_http(url)
      end

      def ingest_via_simple_http(url)
        uri = parse_uri(url)
        return failure('ingestion.invalid_url', "Cannot parse URL: #{url}", category: :invalid_url) if uri.nil?

        response = http_get(uri)
        return classify_http_failure(response) unless response.is_a?(Net::HTTPSuccess)

        content = truncate(strip_html(response.body.to_s))
        return failure('ingestion.empty_body', 'Fetched page produced no text', category: :empty_body) if content.blank?

        Result.new(success: true, content: content)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT => e
        raise TransientFetchError.new("Timeout fetching URL: #{e.message}", error_code: 'ingestion.timeout',
                                                                            failure_category: :timeout)
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError, OpenSSL::SSL::SSLError => e
        raise TransientFetchError.new("Connection error: #{e.message}", error_code: 'ingestion.connection_error',
                                                                        failure_category: :connection)
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
        raise TransientFetchError.new("HTTP #{code}", error_code: "ingestion.http_#{code}", failure_category: :server_error) if code >= 500
        raise TransientFetchError.new('HTTP 408', error_code: "ingestion.http_#{code}", failure_category: :timeout) if code == 408
        raise TransientFetchError.new('HTTP 429', error_code: "ingestion.http_#{code}", failure_category: :rate_limited) if code == 429

        category = case code
                   when 404, 410 then :not_found
                   when 401, 403 then :access_denied
                   else :http_error
                   end
        failure("ingestion.http_#{code}", "HTTP #{code}", category: category)
      end

      def ingest_pdf
        require 'pdf-reader'
        text = ::PDF::Reader.new(StringIO.new(document.pdf_file.download)).pages.map(&:text).join("\n\n")
        return failure('ingestion.pdf_empty', 'PDF produced no extractable text', category: :empty_body) if text.strip.blank?

        Result.new(success: true, content: truncate(text))
      rescue LoadError
        failure('ingestion.pdf_reader_missing', "pdf-reader gem not installed; cannot ingest PDF #{document.id}",
                category: :pdf_failure)
      rescue ::PDF::Reader::MalformedPDFError => e
        failure('ingestion.pdf_malformed', e.message, category: :pdf_failure)
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

      def failure(code, message, category: :unexpected)
        Result.new(success: false, error_code: code, error_message: message, failure_category: category)
      end
    end
  end
end
