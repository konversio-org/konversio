module Custom
  module Pilot
    # Generates a short summary of a conversation suitable for handover notes.
    #
    # Wraps the MIT `::Pilot::SummaryService` and adds:
    #   * per-account feature-flag gating (`pilot_summary_enabled` + master `pilot_enabled`)
    #   * Pilot-namespaced telemetry events
    #
    # Returns the summary text as a String, or raises
    # `Custom::Pilot::SummaryService::Error` on LLM/transport failure.
    class SummaryService < BaseService
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      attr_reader :conversation

      def initialize(conversation:, account: nil)
        @conversation = conversation
        super(account: account || conversation&.account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot Summary is not enabled for this account' unless feature_enabled?(:summary)

        dispatch_event(:summary_started, conversation_id: conversation&.display_id)

        response = ::Pilot::SummaryService.new(
          account: account,
          conversation_display_id: conversation.display_id
        ).perform

        raise Error, response[:error] if response.is_a?(Hash) && response[:error].present?

        summary = extract_summary(response)
        dispatch_event(:summary_completed, conversation_id: conversation&.display_id, summary_length: summary.to_s.length)

        summary
      rescue FeatureDisabledError, Error
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.summary] LLM error: #{e.class}: #{e.message}")
        dispatch_event(:summary_failed, conversation_id: conversation&.display_id, error: e.message)
        raise Error, e.message
      end

      private

      def extract_summary(response)
        return response if response.is_a?(String)
        return response[:message] if response.is_a?(Hash) && response.key?(:message)

        response.to_s
      end
    end
  end
end
