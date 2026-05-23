module Custom
  module Pilot
    # Generates a one-click reply draft for an agent on a given conversation.
    #
    # This wraps `Pilot::ReplySuggestionService` per Pilot design D3/D4
    # and adds:
    #   * per-account feature-flag gating (`pilot_briefing` + master
    #     `pilot`)
    #   * Pilot-namespaced telemetry events
    #   * optional Logbook context injection once the Logbook sub-feature
    #     lands (section 5 of the Pilot tasks)
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

        draft = ::Custom::Pilot::TraceSpan.wrap(name: 'pilot.briefing.generate', attributes: span_attributes) do |span|
          response = run_reply_suggestion
          raise Error, response[:error] if response.is_a?(Hash) && response[:error].present?

          extracted = extract_draft(response)
          span.set_attribute('draft_length', extracted.to_s.length)
          extracted
        end

        dispatch_event(:briefing_completed, conversation_id: conversation&.display_id, draft_length: draft.to_s.length)

        draft
      rescue FeatureDisabledError
        raise
      rescue Error
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.briefing] LLM error: #{e.class}: #{e.message}")
        raise Error, e.message
      end

      private

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
          refinement_instruction: refinement_instruction
        )

        result = suggestion_service.perform

        inject_logbook_context!(result) if logbook_active?
        result
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

      # Logbook context is injected at the prompt layer once the Logbook
      # sub-feature lands. Until then this is a no-op: the helper is
      # stubbed on BaseService and the model is not yet defined.
      def inject_logbook_context!(_response)
        context_text = logbook_context_for(conversation.contact)
        return if context_text.blank?

        # Placeholder hook — concrete prompt-injection happens in section 5
        # once we own the request construction inside Pilot via a wrapper.
        Rails.logger.info("[pilot.briefing] logbook context length=#{context_text.length}")
      end

      def logbook_active?
        return false unless feature_enabled?(:logbook)
        return false unless defined?(::Pilot::LogbookEntry)

        true
      end

      # Until section 5 ships, BaseService has no `logbook_context_for`
      # helper. We use `try` so this code is forward-compatible.
      def logbook_context_for(contact)
        return nil if contact.blank?

        try(:base_logbook_context_for, contact)
      end
    end
  end
end
