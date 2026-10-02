require 'agents'

module Custom
  module Pilot
    # Generates a suggested reply for a conversation using the same ai-agents
    # SDK runner pipeline as Copilot chat, then persists it as the single
    # assistant message of a reply-suggestion copilot thread.
    #
    # Behaviour (openspec change pilot-reply-suggestion):
    #   1. Short-circuit when the thread already has an assistant response, so
    #      a duplicate dispatch never creates a second one.
    #   2. Capture the conversation's latest public message when the run starts
    #      and skip early when it is not an incoming customer message.
    #   3. Run the agent with draft-oriented instructions and a restricted tool
    #      set (knowledge lookup + opt-in account HTTP tools).
    #   4. Persist under a thread lock, rechecking access and that the captured
    #      target is still the latest public message. Stale runs persist a
    #      localized "no longer applicable" response instead of the draft.
    #   5. Record response usage only for a draft that is actually persisted.
    #
    # Generation errors are re-raised as `Error` so the job can retry them; the
    # job persists the localized failure response once retries are exhausted.
    # rubocop:disable Metrics/ClassLength
    class CopilotReplySuggestionService < BaseService
      include SwitchLocale

      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      MAX_AGENT_STEPS = 8
      DISCARDED_KEY = 'pilot.copilot.reply_suggestion.discarded'.freeze
      FAILURE_KEY = 'pilot.copilot.reply_suggestion.failed'.freeze
      DEFAULT_INPUT = 'Write the suggested reply for the customer.'.freeze

      attr_reader :thread, :conversation_id, :persisted_assistant_message

      def initialize(thread:, conversation_id:, account: nil)
        @thread = thread
        @conversation_id = conversation_id
        @persisted_assistant_message = nil
        @credit_used = false
        @user = thread&.user
        @current_account = account || thread&.account
        super(account: @current_account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot Copilot is not enabled for this account' unless feature_enabled?(:copilot)
        raise Error, 'Thread is required' if thread.blank?

        existing = existing_assistant_message
        return @persisted_assistant_message = existing if existing.present?

        target = latest_public_message
        return persist_discarded_response unless incoming_target?(target)

        run_and_persist(target)
      end

      # True only when a draft was persisted and therefore consumed a response
      # credit. Discarded/failure terminal states leave this false.
      def credit_used?
        @credit_used
      end

      # Persists the generic localized failure response. Called by the job once
      # its retries are exhausted so the drawer always settles. Idempotent.
      def persist_failure_response
        return if thread.blank?

        thread.with_lock do
          return if thread.copilot_messages.assistant.exists?

          persist_message(localized(FAILURE_KEY), reply_suggestion: false)
        end
      end

      private

      def run_and_persist(target)
        ::Custom::Pilot::TraceSpan.wrap(name: 'pilot.copilot.reply_suggestion', attributes: span_attributes) do |span|
          result = run_agent
          finalize(result, target, span)
        end
      end

      def run_agent
        agent = build_agent
        runner = ::Agents::Runner.with_agents(agent)
        register_callbacks(runner)
        runner.run(agent_input, context: runner_context, max_turns: MAX_AGENT_STEPS)
      rescue StandardError => e
        Rails.logger.error("[pilot.reply_suggestion] runner error: #{e.class}: #{e.message}")
        raise Error, e.message
      end

      def finalize(result, target, span)
        return persist_message(localized(FAILURE_KEY), reply_suggestion: false) if result.error.is_a?(::Agents::Runner::MaxTurnsExceeded)

        persist_under_lock(target, extract_final_content(result), span)
      end

      def persist_under_lock(target, content, span)
        thread.with_lock do
          existing = thread.copilot_messages.assistant.order(:created_at).last
          return @persisted_assistant_message = existing if existing.present?

          return persist_message(localized(FAILURE_KEY), reply_suggestion: false) unless access_allowed?
          return persist_message(localized(DISCARDED_KEY), reply_suggestion: false, discarded: true) unless same_target?(target)

          persist_message(content.presence || localized(FAILURE_KEY), reply_suggestion: true, credit_used: true, span: span)
        end
      end

      def persist_discarded_response
        thread.with_lock do
          return @persisted_assistant_message if existing_assistant_message.present?

          persist_message(localized(DISCARDED_KEY), reply_suggestion: false, discarded: true)
        end
      end

      def persist_message(content, reply_suggestion:, discarded: false, credit_used: false, span: nil)
        payload = { content: content }
        payload[:reply_suggestion] = true if reply_suggestion
        record = ::Pilot::CopilotMessage.create!(
          copilot_thread: thread,
          account: account,
          message_type: :assistant,
          message: payload
        )
        @persisted_assistant_message = record
        @credit_used = credit_used
        mark_span(span, discarded: discarded, credit_used: credit_used)
        record
      end

      def mark_span(span, discarded:, credit_used:)
        return if span.blank?

        span.set_attribute('discarded', discarded)
        span.set_attribute('credit_used', credit_used)
      end

      def existing_assistant_message
        return nil if thread.blank?

        thread.copilot_messages.assistant.order(:created_at).last
      end

      def access_allowed?
        ::Custom::Pilot::ConversationAccess.accessible?(account: account, user: thread&.user, conversation: conversation)
      end

      def same_target?(target)
        latest_public_message&.id == target&.id
      end

      def incoming_target?(target)
        target.present? && target.incoming?
      end

      def latest_public_message
        return nil if conversation.blank?

        conversation.messages
                    .where(private: false, message_type: %i[incoming outgoing])
                    .order(:created_at, :id)
                    .last
      end

      def conversation
        return @conversation if defined?(@conversation)
        return @conversation = nil if conversation_id.blank? || account.blank?

        @conversation = account.conversations.find_by(display_id: conversation_id) ||
                        account.conversations.find_by(id: conversation_id)
      end

      def bound_assistant
        return @bound_assistant if defined?(@bound_assistant)
        return @bound_assistant = nil if thread&.assistant_id.blank? || account.blank?

        @bound_assistant = ::Pilot::Assistant.find_by(id: thread.assistant_id, account_id: account.id)
      end

      def build_agent
        ::Agents::Agent.new(
          name: 'Pilot Copilot Reply Suggestion',
          instructions: system_prompt,
          model: model_for(:copilot),
          tools: draft_tools
        )
      end

      def draft_tools
        tools = []
        tools << ::Custom::Pilot::Tools::SearchDocumentation.new if ::Custom::Pilot::Tools::SearchDocumentation.available?
        account.pilot_custom_tools.enabled.available_for_reply_drafting.each do |custom_tool|
          tools << ::Pilot::Tools::AgentToolAdapter.new(custom_tool)
        end

        ::Custom::Pilot::CopilotToolPermissionFilter
          .new(account: account, user: thread&.user, assistant: bound_assistant)
          .call(tools)
      end

      def register_callbacks(runner)
        runner.on_tool_start do |tool_name, _args|
          persist_thinking_message(tool_name)
        end
      end

      def persist_thinking_message(tool_name)
        ::Pilot::CopilotMessage.create!(
          copilot_thread: thread,
          account: account,
          message_type: :assistant_thinking,
          message: { content: "Using #{tool_name}", function_name: tool_name }
        )
      rescue StandardError => e
        Rails.logger.warn("[pilot.reply_suggestion] failed to persist thinking message: #{e.class}: #{e.message}")
      end

      def agent_input
        thread.copilot_messages.user.order(:created_at).last&.message&.dig('content').presence || DEFAULT_INPUT
      end

      def runner_context
        {
          account_id: account&.id,
          thread_id: thread&.id,
          assistant_id: bound_assistant&.id,
          conversation_id: conversation_id,
          conversation_history: [],
          state: { account_id: account&.id }
        }
      end

      def system_prompt
        template = Rails.root.join('lib/integrations/openai/openai_prompts/copilot_reply_draft.liquid').read
        Liquid::Template.parse(template).render(prompt_variables)
      end

      def prompt_variables
        {
          'account_language' => account&.locale_english_name,
          'product_name' => bound_assistant&.product_name,
          'assistant_instructions' => bound_assistant&.instructions,
          'conversation' => conversation_transcript,
          'has_search_tool' => ::Custom::Pilot::Tools::SearchDocumentation.available?
        }
      end

      def conversation_transcript
        conversation&.to_llm_text(include_contact_details: true)
      end

      def extract_final_content(result)
        output = result.output
        case output
        when String then output
        when Hash   then (output[:response] || output['response'] || output.to_s)
        else output.to_s
        end
      end

      def span_attributes
        {
          account_id: account&.id,
          assistant_id: bound_assistant&.id,
          conversation_id: conversation&.id,
          conversation_display_id: conversation_id,
          channel_type: conversation&.inbox&.channel_type,
          source: 'production',
          model: model_for(:copilot)
        }
      end

      def localized(key)
        switch_locale_using_account_locale { I18n.t(key) }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
# rubocop:enable Style/ClassAndModuleChildren
