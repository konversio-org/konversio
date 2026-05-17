require 'net/http'
require 'uri'

module Custom
  module Pilot
    # Fetches the body of a `Pilot::Document` from its source — either an
    # external URL (via Firecrawl when `PILOT_FIRECRAWL_API_KEY` is
    # configured, otherwise an in-process HTTP fetch with HTML stripping)
    # or an attached PDF (via `pdf-reader` if available).
    #
    # Returns a Result struct describing success/failure and the fetched
    # content so the caller can persist it.
    class DocumentIngestionService < BaseService
      Result = Struct.new(:success, :content, :error_code, :error_message, keyword_init: true) do
        def success?
          success == true
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
      rescue StandardError => e
        Rails.logger.error("[pilot.document_ingestion] #{e.class}: #{e.message}")
        Result.new(success: false, error_code: 'ingestion.unexpected', error_message: e.message)
      end

      private

      def ingest_url
        url = document.external_link.to_s
        return failure('ingestion.missing_url', 'No external_link to ingest') if url.blank?

        if firecrawl_api_key.present?
          ingest_via_firecrawl(url)
        else
          ingest_via_simple_http(url)
        end
      end

      def ingest_via_firecrawl(url)
        uri = URI.parse('https://api.firecrawl.dev/v1/scrape')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = DEFAULT_TIMEOUT_SECONDS

        req = Net::HTTP::Post.new(uri.request_uri,
                                  'Authorization' => "Bearer #{firecrawl_api_key}",
                                  'Content-Type' => 'application/json')
        req.body = { url: url, formats: ['markdown'] }.to_json

        response = http.request(req)
        return failure('ingestion.firecrawl_http_error', "Firecrawl HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(response.body)
        # Firecrawl historically returns { data: { markdown: ... } } or top-level keys.
        # Per D23 tolerate unexpected key shapes — try a few.
        content = parsed.dig('data', 'markdown').presence ||
                  parsed.dig('data', 'content').presence ||
                  parsed['markdown'].presence ||
                  parsed['content'].presence

        return failure('ingestion.firecrawl_empty', 'Firecrawl returned empty content') if content.blank?

        Result.new(success: true, content: truncate(content))
      rescue JSON::ParserError => e
        failure('ingestion.firecrawl_parse_error', e.message)
      end

      def ingest_via_simple_http(url)
        uri = URI.parse(url)
        return failure('ingestion.invalid_url', "Cannot parse URL: #{url}") unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = DEFAULT_TIMEOUT_SECONDS

        response = http.get(uri.request_uri)
        return failure('ingestion.http_error', "HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)

        Result.new(success: true, content: truncate(strip_html(response.body.to_s)))
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

      def firecrawl_api_key
        GlobalConfigService.load('PILOT_FIRECRAWL_API_KEY', nil)
      end
    end
  end
end
