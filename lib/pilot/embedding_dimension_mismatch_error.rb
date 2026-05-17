module Pilot
  # Raised when an embedding provider returns a vector whose length does not
  # match the dimension we configured for the pgvector column (1536).
  #
  # In development and test environments this is fatal so we catch
  # misconfiguration immediately. In production the embedding service logs
  # a warning, skips the insert, and returns nil instead of raising — see
  # `Custom::Pilot::EmbeddingService` for the policy.
  class EmbeddingDimensionMismatchError < StandardError
    attr_reader :expected_dimension, :actual_dimension

    def initialize(expected:, actual:)
      @expected_dimension = expected
      @actual_dimension = actual
      super("Pilot embedding dimension mismatch: expected #{expected}, got #{actual}")
    end
  end
end
