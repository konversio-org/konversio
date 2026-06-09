module Custom
  module Pilot
    # Generates a short summary of a conversation suitable for handover notes.
    #
    # Wraps the MIT `::Pilot::SummaryService` and adds:
    #   * per-account feature-flag gating (`pilot_summary` + master `pilot`)
    #   * Pilot-namespaced telemetry events
    #
    # Returns the summary text as a String, or raises
    # `Custom::Pilot::SummaryService::Error` on LLM/transport failure.
    class SummaryService < BaseService
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      attr_reader :conversation, :previous_output, :refinement_instruction

      def initialize(conversation:, account: nil, previous_output: nil, refinement_instruction: nil)
        @conversation = conversation
        @previous_output = previous_output
        @refinement_instruction = refinement_instruction
        super(account: account || conversation&.account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot Summary is not enabled for this account' unless feature_enabled?(:summary)

        dispatch_event(:summary_started, conversation_id: conversation_id)

        response = call_core_service
        raise Error, response[:error] if response.is_a?(Hash) && response[:error].present?

        summary = extract_summary(response)
        dispatch_event(:summary_completed, conversation_id: conversation_id, summary_length: summary.to_s.length)

        summary
      rescue FeatureDisabledError, Error
        raise
      rescue StandardError => e
        handle_error(e)
      end

      private

      def conversation_id
        conversation&.display_id
      end

      def call_core_service
        ::Pilot::SummaryService.new(
          account: account,
          conversation_display_id: conversation_id,
          previous_output: previous_output,
          refinement_instruction: refinement_instruction
        ).perform
      end

      def handle_error(error)
        Rails.logger.error("[pilot.summary] LLM error: #{error.class}: #{error.message}")
        dispatch_event(:summary_failed, conversation_id: conversation_id, error: error.message)
        raise Error, error.message
      end

      def extract_summary(response)
        return response if response.is_a?(String)
        return response[:message] if response.is_a?(Hash) && response.key?(:message)

        response.to_s
      end
    end
  end
end
