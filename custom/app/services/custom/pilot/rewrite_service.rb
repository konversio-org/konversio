module Custom
  module Pilot
    # Rewrites a draft message via one of the supported Pilot operations.
    #
    # Wraps the MIT `::Pilot::RewriteService` and exposes a unified
    # `operation` parameter covering Improve, Fix Grammar, and the five
    # spec-defined Pilot tones (`friendly`, `formal`, `concise`,
    # `empathetic`, `assertive`).
    #
    # The MIT service supports a different tone enum
    # (`casual/professional/friendly/confident/straightforward`). We map
    # the spec-defined Pilot tones onto the closest supported MIT tones.
    # `improve` and `fix_spelling_grammar` are forwarded as-is.
    #
    # Returns the rewritten text as a String. Raises:
    #   * `ArgumentError` if `operation` is not in `ALLOWED_OPERATIONS`
    #   * `FeatureDisabledError` if the feature flag is off
    #   * `Error` on LLM/transport failure
    class RewriteService < BaseService
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      TONES = %w[friendly formal concise empathetic assertive].freeze
      NON_TONE_OPERATIONS = %w[improve fix_spelling_grammar].freeze
      ALLOWED_OPERATIONS = (NON_TONE_OPERATIONS + TONES).freeze

      # Map spec-defined Pilot tones to the MIT RewriteService tone enum
      # (casual/professional/friendly/confident/straightforward).
      TONE_TO_OPERATION = {
        'friendly' => 'friendly',
        'formal' => 'professional',
        'concise' => 'straightforward',
        'empathetic' => 'friendly',
        'assertive' => 'confident'
      }.freeze

      attr_reader :text, :operation

      def initialize(text:, operation:, account:)
        @text = text
        @operation = operation.to_s
        super(account: account)
      end

      def perform
        validate_operation_and_feature_enabled!

        dispatch_event(:rewrite_started, operation: operation, text_length: text.to_s.length)

        response = call_core_service
        raise Error, response[:error] if response.is_a?(Hash) && response[:error].present?

        rewritten = extract_rewritten(response)
        dispatch_event(:rewrite_completed, operation: operation, rewritten_length: rewritten.to_s.length)

        rewritten
      rescue FeatureDisabledError, ArgumentError, Error
        raise
      rescue StandardError => e
        handle_error(e)
      end

      private

      def validate_operation_and_feature_enabled!
        raise FeatureDisabledError, 'Pilot Rewrite is not enabled for this account' unless feature_enabled?(:rewrite)

        return if ALLOWED_OPERATIONS.include?(operation)

        raise ArgumentError, "Invalid operation: #{operation}. Allowed: #{ALLOWED_OPERATIONS.join(', ')}"
      end

      def call_core_service
        ::Pilot::RewriteService.new(
          account: account,
          content: text,
          operation: mit_operation
        ).perform
      end

      def handle_error(error)
        Rails.logger.error("[pilot.rewrite] LLM error: #{error.class}: #{error.message}")
        dispatch_event(:rewrite_failed, operation: operation, error: error.message)
        raise Error, error.message
      end

      def mit_operation
        TONE_TO_OPERATION[operation] || operation
      end

      def extract_rewritten(response)
        return response if response.is_a?(String)
        return response[:message] if response.is_a?(Hash) && response.key?(:message)

        response.to_s
      end
    end
  end
end
