module Custom
  module Pilot
    # Rewrites a draft message with a selected tone.
    #
    # Wraps the MIT `::Pilot::RewriteService` and enforces the Pilot-side
    # tone whitelist from the pilot-utilities spec
    # (`friendly`, `formal`, `concise`, `empathetic`, `assertive`).
    #
    # The MIT service supports a different operation enum
    # (`casual/professional/friendly/confident/straightforward` for tone +
    # `fix_spelling_grammar/improve`). We map the spec-defined Pilot tones
    # onto the closest supported MIT operations.
    #
    # Returns the rewritten text as a String. Raises:
    #   * `ArgumentError` if `tone` is not in `ALLOWED_TONES`
    #   * `FeatureDisabledError` if the feature flag is off
    #   * `Error` on LLM/transport failure
    class RewriteService < BaseService
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      ALLOWED_TONES = %w[friendly formal concise empathetic assertive].freeze

      # Map spec-defined Pilot tones to the MIT RewriteService operations
      # (which only knows casual/professional/friendly/confident/straightforward).
      TONE_TO_OPERATION = {
        'friendly' => 'friendly',
        'formal' => 'professional',
        'concise' => 'straightforward',
        'empathetic' => 'friendly',
        'assertive' => 'confident'
      }.freeze

      attr_reader :text, :tone

      def initialize(text:, tone:, account:)
        @text = text
        @tone = tone.to_s
        super(account: account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot Rewrite is not enabled for this account' unless feature_enabled?(:rewrite)
        raise ArgumentError, "Invalid tone: #{tone}. Allowed: #{ALLOWED_TONES.join(', ')}" unless ALLOWED_TONES.include?(tone)

        dispatch_event(:rewrite_started, tone: tone, text_length: text.to_s.length)

        response = ::Pilot::RewriteService.new(
          account: account,
          content: text,
          operation: TONE_TO_OPERATION[tone]
        ).perform

        raise Error, response[:error] if response.is_a?(Hash) && response[:error].present?

        rewritten = extract_rewritten(response)
        dispatch_event(:rewrite_completed, tone: tone, rewritten_length: rewritten.to_s.length)

        rewritten
      rescue FeatureDisabledError, ArgumentError, Error
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.rewrite] LLM error: #{e.class}: #{e.message}")
        dispatch_event(:rewrite_failed, tone: tone, error: e.message)
        raise Error, e.message
      end

      private

      def extract_rewritten(response)
        return response if response.is_a?(String)
        return response[:message] if response.is_a?(Hash) && response.key?(:message)

        response.to_s
      end
    end
  end
end
