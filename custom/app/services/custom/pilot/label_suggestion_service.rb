module Custom
  module Pilot
    # Suggests labels for a conversation by matching against the
    # account's existing label set.
    #
    # Wraps the MIT `::Pilot::LabelSuggestionService` (which returns a
    # comma/space-separated string of label titles) and maps them to
    # `account.labels` ids.
    #
    # Returns an Array of label ids (Integer). Empty array if no
    # suggestions could be produced. Raises
    # `Custom::Pilot::LabelSuggestionService::Error` on LLM/transport failure.
    class LabelSuggestionService < BaseService
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      attr_reader :conversation

      def initialize(conversation:, account: nil)
        @conversation = conversation
        super(account: account || conversation&.account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot Label Suggestion is not enabled for this account' unless feature_enabled?(:label_suggestion)

        dispatch_event(:label_suggestion_started, conversation_id: conversation_id)

        response = call_core_service
        return [] if response.blank?
        raise Error, response[:error] if response.is_a?(Hash) && response[:error].present?

        label_ids = extract_label_ids(response)
        dispatch_event(:label_suggestion_completed, conversation_id: conversation_id, label_count: label_ids.length)

        label_ids
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
        ::Pilot::LabelSuggestionService.new(
          account: account,
          conversation_display_id: conversation_id
        ).perform
      end

      def handle_error(error)
        Rails.logger.error("[pilot.label_suggestion] LLM error: #{error.class}: #{error.message}")
        dispatch_event(:label_suggestion_failed, conversation_id: conversation_id, error: error.message)
        raise Error, error.message
      end

      def extract_label_ids(response)
        raw = response.is_a?(Hash) ? response[:message].to_s : response.to_s
        return [] if raw.blank?

        suggested_titles = raw.split(/[,\n]/).map { |s| s.strip.downcase }.reject(&:blank?)
        return [] if suggested_titles.empty?

        account.labels.where('LOWER(title) IN (?)', suggested_titles).pluck(:id)
      end
    end
  end
end
