# rubocop:disable Style/ClassAndModuleChildren
module Custom
  module Pilot
    # Generates a one-click reply draft for an agent on a given conversation.
    #
    # This wraps `Pilot::ReplySuggestionService` per Pilot design D3/D4
    # and adds:
    #   * per-account feature-flag gating (`pilot_briefing` + master
    #     `pilot`)
    #   * Pilot-namespaced telemetry events
    #   * optional Logbook context injection as an extra system message
    #
    # Returns the generated draft text as a String, or raises
    # `Custom::Pilot::BriefingService::Error` on LLM/transport failure.
    class BriefingService < BaseService
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      attr_reader :conversation, :user, :previous_output, :refinement_instruction

      def initialize(conversation:, user: nil, account: nil, previous_output: nil, refinement_instruction: nil)
        @conversation = conversation
        @user = user
        @previous_output = previous_output
        @refinement_instruction = refinement_instruction
        super(account: account || conversation&.account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot Briefing is not enabled for this account' unless feature_enabled?(:briefing)

        dispatch_event(:briefing_started, conversation_id: conversation&.display_id)

        draft = generate_draft

        dispatch_event(:briefing_completed, conversation_id: conversation&.display_id, draft_length: draft.to_s.length)

        draft
      rescue FeatureDisabledError, Error
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.briefing] LLM error: #{e.class}: #{e.message}")
        raise Error, e.message
      end

      private

      def generate_draft
        ::Custom::Pilot::TraceSpan.wrap(name: 'pilot.briefing.generate', attributes: span_attributes) do |span|
          response = run_reply_suggestion
          raise Error, response[:error] if response.is_a?(Hash) && response[:error].present?

          attach_token_usage(span, response[:usage] || response['usage']) if response.is_a?(Hash)
          extracted = extract_draft(response)
          span.set_attribute('draft_length', extracted.to_s.length)
          extracted
        end
      end

      def span_attributes
        {
          account_id: account&.id,
          conversation_id: conversation&.id,
          conversation_display_id: conversation&.display_id,
          channel_type: conversation&.inbox&.channel_type,
          source: 'production',
          model: model_for(:briefing),
          credit_used: true
        }
      end

      def run_reply_suggestion
        suggestion_service = ::Pilot::ReplySuggestionService.new(
          account: account,
          conversation_display_id: conversation.display_id,
          user: user,
          previous_output: previous_output,
          refinement_instruction: refinement_instruction,
          extra_system_context: logbook_context_for(conversation.contact)
        )

        suggestion_service.perform
      end

      # The MIT ReplySuggestionService returns a Hash with a `:message` key on
      # success (see lib/pilot/base_task_service.rb#build_ruby_llm_response).
      # If for any reason a String slips through (e.g. a test stub) we return
      # it as-is.
      def extract_draft(response)
        return response if response.is_a?(String)
        return response[:message] if response.is_a?(Hash) && response.key?(:message)

        response.to_s
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
