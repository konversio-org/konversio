require 'openai'

module Custom
  module Pilot
    # Generates a single 1536-dim embedding vector for a piece of text.
    #
    # Routes via the embedding slot configured in Super Admin > LLM Settings
    # (`Llm::Config.for_slot(:embedding)`), so any OpenAI-compatible provider
    # (Scaleway, Nebius, OpenAI, etc.) works without further branching.
    #
    # The configured `PILOT_LLM_EMBEDDING_DIMENSIONS` value is passed as
    # `dimensions:` on the request. Servers that support server-side
    # truncation (OpenAI text-embedding-3-*) will honour it. Servers that
    # don't will still produce their native-size vector; this service then
    # raises in dev/test (so misconfiguration is caught immediately) and
    # logs a warning + returns nil in production (per pilot-foundation spec).
    class EmbeddingService < BaseService
      EXPECTED_DIMENSION = 1536
      DEFAULT_EMBEDDING_MODEL = 'text-embedding-3-small'.freeze

      def initialize(account: nil)
        super(account: account)
      end

      def embed(text)
        return nil if text.blank?

        response = client.embeddings(
          parameters: {
            model: embedding_model,
            input: text.to_s,
            dimensions: embedding_dimensions
          }
        )

        vector = extract_vector(response)
        return nil if vector.nil?

        guard_dimension(vector)
      end

      private

      # Returns the vector when the dimension matches the pgvector column.
      # On mismatch: raise in dev/test (catch misconfiguration early), log a
      # warning and return nil in production (skip the insert, per spec).
      def guard_dimension(vector)
        return vector if vector.length == EXPECTED_DIMENSION

        if Rails.env.production?
          Rails.logger.warn(
            "[pilot.embedding] dimension mismatch expected=#{EXPECTED_DIMENSION} " \
            "actual=#{vector.length} configured=#{embedding_dimensions} model=#{embedding_model}"
          )
          nil
        else
          raise ::Pilot::EmbeddingDimensionMismatchError.new(
            expected: EXPECTED_DIMENSION,
            actual: vector.length
          )
        end
      end

      def extract_vector(response)
        response.dig('data', 0, 'embedding')
      end

      def client
        @client ||= OpenAI::Client.new(
          access_token: slot_config[:api_key],
          uri_base: "#{slot_config[:endpoint]}/v1"
        )
      end

      def slot_config
        @slot_config ||= ::Llm::Config.for_slot(:embedding)
      end

      def embedding_model
        slot_config[:model].presence || DEFAULT_EMBEDDING_MODEL
      end

      def embedding_dimensions
        GlobalConfigService.load('PILOT_LLM_EMBEDDING_DIMENSIONS', nil).to_i.then do |dim|
          dim.positive? ? dim : EXPECTED_DIMENSION
        end
      end
    end
  end
end
