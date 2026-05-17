module Custom
  module Pilot
    # Generates an asynchronous assistant reply for a Copilot thread.
    #
    # Per Pilot design D4 + D20 we wrap RubyLLM directly (V2 agentic loop only).
    # The agentic ai-agents SDK loop is reserved for Autopilot (section 4);
    # Copilot is a simple chat thread where the LLM responds to the agent's
    # questions with optional bound-conversation context and Logbook hints.
    #
    # Returns the assistant reply content as a String, or raises
    # `Custom::Pilot::CopilotService::Error` on LLM/transport failure.
    class CopilotService < BaseService
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      MAX_HISTORY = 40

      attr_reader :thread, :conversation_id

      def initialize(thread:, conversation_id: nil, account: nil)
        @thread = thread
        @conversation_id = conversation_id
        super(account: account || thread&.account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot Copilot is not enabled for this account' unless feature_enabled?(:copilot)

        dispatch_event(:copilot_inference_started, thread_id: thread&.id, conversation_id: conversation_id)
        content = run_chat
        dispatch_event(:copilot_inference_completed, thread_id: thread&.id, length: content.to_s.length)
        content
      rescue FeatureDisabledError
        raise
      rescue Error
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.copilot] LLM error: #{e.class}: #{e.message}")
        dispatch_event(:copilot_inference_failed, thread_id: thread&.id, error: e.message)
        raise Error, e.message
      end

      private

      def run_chat
        messages = build_messages
        raise Error, 'No user message in thread to respond to' if messages.none? { |m| m[:role] == 'user' }

        chat_context do |context|
          chat = context.chat(model: model_for(:copilot))
          system_prompt = messages.find { |m| m[:role] == 'system' }
          chat.with_instructions(system_prompt[:content]) if system_prompt

          conversation_messages = messages.reject { |m| m[:role] == 'system' }
          conversation_messages[0...-1].each do |msg|
            chat.add_message(role: msg[:role].to_sym, content: msg[:content])
          end

          response = chat.ask(conversation_messages.last[:content])
          response.content.to_s
        end
      end

      def build_messages
        [{ role: 'system', content: system_prompt }] +
          bound_conversation_messages +
          thread_history_messages
      end

      def system_prompt
        sections = ['You are Pilot, a helpful AI co-pilot for support agents.']
        sections << "Reply in #{account.locale_english_name}." if account.respond_to?(:locale_english_name)

        logbook_context = logbook_context_for(thread_contact)
        sections << logbook_context if logbook_context.present?

        sections.join("\n\n")
      end

      # When the agent opened Copilot from inside a customer conversation we
      # add the transcript as a "user" assist context. We intentionally
      # prepend it (not append) so the latest agent question stays the final
      # `user` turn.
      def bound_conversation_messages
        return [] if conversation_id.blank?

        conversation = account.conversations.find_by(display_id: conversation_id) || account.conversations.find_by(id: conversation_id)
        return [] if conversation.blank?

        transcript = conversation.to_llm_text(include_contact_details: true)
        return [] if transcript.blank?

        [{ role: 'user', content: "Context — the customer conversation the agent is currently looking at:\n\n#{transcript}" }]
      end

      def thread_history_messages
        thread.copilot_messages
              .where(message_type: %w[user assistant])
              .order(:created_at)
              .last(MAX_HISTORY)
              .map { |msg| { role: msg.message_type, content: msg.message['content'].to_s } }
              .reject { |msg| msg[:content].blank? }
      end

      def thread_contact
        return nil if conversation_id.blank?

        conversation = account.conversations.find_by(display_id: conversation_id) || account.conversations.find_by(id: conversation_id)
        conversation&.contact
      end

      # Stubbed until the Logbook sub-feature lands (section 5). Forward-
      # compatible: returns nil today so the system prompt simply doesn't
      # include logbook context.
      def logbook_context_for(contact)
        return nil if contact.blank?
        return nil unless feature_enabled?(:logbook)
        return nil unless defined?(::Pilot::LogbookEntry)

        nil
      end
    end
  end
end
