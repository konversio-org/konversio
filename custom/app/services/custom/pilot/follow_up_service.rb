module Custom
  module Pilot
    # Generates 1-3 clarifying follow-up question suggestions for an agent.
    #
    # Wraps the MIT `::Pilot::FollowUpService` for use from the composer
    # follow-up affordance. The MIT service is built for an iterative
    # follow-up loop (event_name + previous response context); for the
    # Pilot Utilities use-case we ask the LLM to produce a small set of
    # candidate clarifying questions in one shot, using the conversation
    # transcript as context.
    #
    # Returns an Array of suggestion Strings; raises
    # `Custom::Pilot::FollowUpService::Error` on LLM/transport failure.
    class FollowUpService < BaseService
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      attr_reader :conversation

      def initialize(conversation:, account: nil)
        @conversation = conversation
        super(account: account || conversation&.account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot Follow-up is not enabled for this account' unless feature_enabled?(:follow_up)

        dispatch_event(:follow_up_started, conversation_id: conversation&.display_id)

        response = ::Pilot::FollowUpService.new(
          account: account,
          follow_up_context: build_follow_up_context,
          user_message: clarifying_request,
          conversation_display_id: conversation&.display_id
        ).perform

        raise Error, response[:error] if response.is_a?(Hash) && response[:error].present?

        suggestions = extract_suggestions(response)
        dispatch_event(:follow_up_completed, conversation_id: conversation&.display_id, suggestion_count: suggestions.length)

        suggestions
      rescue FeatureDisabledError, Error
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.follow_up] LLM error: #{e.class}: #{e.message}")
        dispatch_event(:follow_up_failed, conversation_id: conversation&.display_id, error: e.message)
        raise Error, e.message
      end

      private

      # The MIT FollowUpService needs `event_name`, `original_context`, and
      # `last_response`. For the Utilities use-case, we synthesize a
      # context that frames the transcript as the "original" and asks
      # for clarifying questions.
      def build_follow_up_context
        transcript = conversation.to_llm_text(include_contact_details: false)
        {
          'event_name' => 'reply_suggestion',
          'original_context' => transcript.presence || 'No prior messages.',
          'last_response' => 'No prior agent reply.',
          'conversation_history' => [],
          'channel_type' => conversation&.inbox&.channel_type
        }
      end

      def clarifying_request
        'Suggest 1-3 short clarifying questions an agent could ask the customer ' \
          'to better understand their request. Return one question per line, no numbering.'
      end

      def extract_suggestions(response)
        raw = response.is_a?(Hash) ? response[:message].to_s : response.to_s
        raw.split(/\r?\n/)
           .map { |line| line.strip.sub(/\A(?:[\-\*•]|\d+[.)])\s*/, '') }
           .reject(&:blank?)
           .first(3)
      end
    end
  end
end
