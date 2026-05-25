require 'openai'

module Custom
  module Pilot
    # Generates an embedding vector for a piece of text.
    #
    # Routes via the embedding slot configured in Super Admin > LLM Settings
    # (`Llm::Config.for_slot(:embedding)`), so any OpenAI-compatible provider
    # (Scaleway, Nebius, etc.) works without further branching.
    #
    # The request is sent without a `dimensions:` parameter — that's an
    # OpenAI-only feature (text-embedding-3-*) and BGE / other Scaleway models
    # 400 on it. The expected dimension is derived from the slot config:
    # explicit `:dimensions` override first, then `MODEL_DIMENSIONS[model]`,
    # else raise `UnknownModelDimensionError`. The "fail hard on unknown
    # model" rule prevents silent wrong-dim inserts that pgvector would
    # reject (leaving no embeddings + no obvious cause).
    class EmbeddingService < BaseService
      # Canonical model-name -> native output dimension map. The only
      # authoritative embedding-dimensions lookup in the codebase; the
      # Super Admin controller and view read from here.
      #
      # Konversio standardizes on LOCKED_EMBEDDING_DIMENSIONS (1536) installation-
      # wide so OpenAI and Scaleway can share one pgvector column without a
      # schema-altering rebuild on every provider swap. Each model listed here
      # must be able to *produce* 1536-dim vectors — either natively or via the
      # provider's `dimensions` parameter with MRL-aware truncation.
      #
      # `bge-multilingual-gemma2` (Scaleway, native 3584) is INTENTIONALLY ABSENT.
      # Its serving endpoint locks output at 3584 and the model was not
      # MRL-trained, so neither the API nor the model itself supports
      # truncation to 1536. Supporting it would require giving up the single-
      # column interop story (one model per installation, schema rebuild on
      # swap). If a future installation needs it, the auto-reindex flow
      # tracked in konversio-org/konversio#12 must ship first.
      MODEL_DIMENSIONS = {
        'text-embedding-3-small' => 1536,
        'text-embedding-3-large' => 3072,
        'qwen3-embedding-8b' => 4096,
        'BAAI/bge-en-icl' => 4096
      }.freeze

      # Single installation-wide embedding size. Every supported model emits
      # vectors at this dimension — either natively (text-embedding-3-small)
      # or via MRL-aware truncation through the provider's `dimensions` param
      # (text-embedding-3-large, qwen3-embedding-8b). Changing this constant
      # requires a column-type migration and a corpus rebuild.
      LOCKED_EMBEDDING_DIMENSIONS = 1536

      DEFAULT_EMBEDDING_MODEL = 'qwen3-embedding-8b'.freeze

      class UnknownModelDimensionError < StandardError
        def initialize(model)
          super(
            "Unknown embedding model '#{model}' — add it to " \
            'Custom::Pilot::EmbeddingService::MODEL_DIMENSIONS or set the ' \
            'Dimensions field in Super Admin > LLM Settings > Custom mode.'
          )
        end
      end

      def initialize(account: nil)
        super(account: account)
      end

      def embed(text)
        return nil if text.blank?

        response = client.embeddings(
          parameters: {
            model: embedding_model,
            input: text.to_s,
            dimensions: expected_dimension
          }
        )

        vector = extract_vector(response)
        return nil if vector.nil?

        guard_dimension(vector)
      end

      # Resolves the dimension we'll request from the provider AND validate
      # the response against. Precedence:
      #   1. slot_config[:dimensions] — Custom-mode explicit override (escape
      #      hatch for an operator pinning a non-default dim).
      #   2. LOCKED_EMBEDDING_DIMENSIONS — the installation-wide lock (1536).
      #
      # The model's native dim from MODEL_DIMENSIONS is NOT used here; that
      # catalog exists for UI display + sanity-checking that a chosen model
      # is capable of producing the locked dim (either natively or via the
      # provider's `dimensions` truncation). The service always emits at the
      # locked dim so cross-provider swaps don't trigger a column rebuild.
      def expected_dimension
        self.class.expected_dimension(slot_config)
      end

      class << self
        # Class-level resolver so the Super Admin controller can compute the
        # expected dimension for any slot config without instantiating the
        # service.
        def expected_dimension(slot_config)
          override = slot_config[:dimensions]
          return override.to_i if override.present? && override.to_i.positive?

          LOCKED_EMBEDDING_DIMENSIONS
        end
      end

      private

      # Returns the vector when the dimension matches the expected dimension.
      # On mismatch: raise in dev/test (catch misconfiguration early), log a
      # warning and return nil in production (skip the insert, per spec).
      def guard_dimension(vector)
        expected = expected_dimension
        return vector if vector.length == expected

        if Rails.env.production?
          Rails.logger.warn(
            "[pilot.embedding] dimension mismatch expected=#{expected} " \
            "actual=#{vector.length} model=#{embedding_model}"
          )
          nil
        else
          raise ::Pilot::EmbeddingDimensionMismatchError.new(
            expected: expected,
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
    end
  end
end
