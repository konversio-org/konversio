require 'agents'

module Custom
  module Pilot
    # Generates the assistant reply for a Copilot thread using the ai-agents
    # SDK runner pattern.
    #
    # This service is the deliberate divergence from upstream Chatwoot
    # Copilot V1 (`Captain::Copilot::ChatService`) — see openspec
    # changes/pilot-full design D20 + D21 + the pilot-copilot requirement
    # "Copilot uses the ai-agents SDK runner with full tool execution".
    #
    # Behaviour:
    #   1. Build an `Agents::Agent` with the configured Pilot model + the
    #      account-scoped tool list.
    #   2. Run the agent via `Agents::Runner.with_agents(...)` capped at
    #      `MAX_AGENT_STEPS` turns.
    #   3. During the run, persist a `Pilot::CopilotMessage` with
    #      `message_type: assistant_thinking` for every tool call (so the
    #      drawer UI can render "Using <tool>...").
    #   4. Persist the final reply as `message_type: assistant`.
    #   5. On step exhaustion, persist a fallback assistant message and fire
    #      `:copilot_inference_failed` with `reason: 'max_steps_exhausted'`.
    class CopilotService < BaseService
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      MAX_HISTORY = 40
      MAX_AGENT_STEPS = 8
      DEFAULT_REPLY_ON_EMPTY = 'I could not generate a response. Try rephrasing the question.'.freeze
      MAX_STEPS_FALLBACK = "I couldn't complete the request after several steps. Try a more specific question.".freeze

      attr_reader :thread, :conversation_id

      def initialize(thread:, conversation_id: nil, account: nil)
        @thread = thread
        @conversation_id = conversation_id
        @persisted_assistant_message = nil
        super(account: account || thread&.account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot Copilot is not enabled for this account' unless feature_enabled?(:copilot)

        validate_thread!

        dispatch_event(:copilot_inference_started, thread_id: thread&.id, conversation_id: conversation_id)
        result = run_agent
        finalize_result(result)
      rescue FeatureDisabledError, Error
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.copilot] runner error: #{e.class}: #{e.message}")
        dispatch_event(:copilot_inference_failed, thread_id: thread&.id, reason: e.class.name, error: e.message)
        raise Error, e.message
      end

      # Exposed for tests and for the inference job — returns the last
      # persisted assistant message record (or nil if nothing persisted).
      attr_reader :persisted_assistant_message

      private

      def validate_thread!
        raise Error, 'Thread is required' if thread.blank?
        return if thread.copilot_messages.where(message_type: :user).exists?

        raise Error, 'No user message in thread to respond to'
      end

      def run_agent
        ::Custom::Pilot::TraceSpan.wrap(name: 'pilot.copilot.inference', attributes: span_attributes) do |span|
          agent = build_agent
          runner = ::Agents::Runner.with_agents(agent)
          register_callbacks(runner)

          user_input, history = split_history
          context = build_runner_context(history)

          result = runner.run(user_input, context: context, max_turns: MAX_AGENT_STEPS)
          span.set_attribute('output_length', result&.output.to_s.length)
          result
        end
      end

      def span_attributes
        {
          account_id: account&.id,
          assistant_id: bound_assistant&.id,
          conversation_id: bound_conversation&.id,
          conversation_display_id: conversation_id,
          channel_type: bound_conversation&.inbox&.channel_type,
          source: 'production',
          model: model_for(:copilot),
          credit_used: true
        }
      end

      def bound_conversation
        return @bound_conversation if defined?(@bound_conversation)
        return @bound_conversation = nil if conversation_id.blank? || account.blank?

        @bound_conversation = account.conversations.find_by(display_id: conversation_id) ||
                              account.conversations.find_by(id: conversation_id)
      end

      def finalize_result(result)
        if result.error.is_a?(::Agents::Runner::MaxTurnsExceeded)
          persist_max_steps_fallback
          dispatch_event(:copilot_inference_failed, thread_id: thread&.id, reason: 'max_steps_exhausted')
          return MAX_STEPS_FALLBACK
        end

        content = extract_final_content(result)
        record = persist_assistant_reply(content)
        @persisted_assistant_message = record
        dispatch_event(:copilot_inference_completed, thread_id: thread&.id, length: content.to_s.length)
        content
      end

      def build_agent
        ::Agents::Agent.new(
          name: 'Pilot Copilot',
          instructions: system_prompt,
          model: model_for(:copilot),
          tools: registered_tools
        )
      end

      def registered_tools
        tools = [
          ::Custom::Pilot::Tools::SearchConversation.new,
          ::Custom::Pilot::Tools::GetConversation.new,
          ::Custom::Pilot::Tools::GetContact.new
        ]
        if ::Custom::Pilot::Tools::SearchDocumentation.available?
          tools << ::Custom::Pilot::Tools::SearchDocumentation.new
        else
          Rails.logger.debug('[pilot.copilot] search_documentation tool skipped — Pilot::AssistantResponse not loaded yet')
        end
        ::Custom::Pilot::CopilotToolPermissionFilter
          .new(account: account, user: thread&.user, assistant: bound_assistant)
          .call(tools)
      end

      def bound_assistant
        return @bound_assistant if defined?(@bound_assistant)
        return @bound_assistant = nil if thread&.assistant_id.blank?

        @bound_assistant = ::Pilot::Assistant.find_by(id: thread.assistant_id, account_id: account&.id)
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
        Rails.logger.warn("[pilot.copilot] failed to persist thinking message: #{e.class}: #{e.message}")
      end

      def persist_assistant_reply(content)
        body = content.presence || DEFAULT_REPLY_ON_EMPTY
        ::Pilot::CopilotMessage.create!(
          copilot_thread: thread,
          account: account,
          message_type: :assistant,
          message: { content: body }
        )
      end

      def persist_max_steps_fallback
        ::Pilot::CopilotMessage.create!(
          copilot_thread: thread,
          account: account,
          message_type: :assistant,
          message: { content: MAX_STEPS_FALLBACK }
        )
      end

      def extract_final_content(result)
        output = result.output
        case output
        when String then output
        when Hash   then (output[:response] || output['response'] || output.to_s)
        else output.to_s
        end
      end

      # Split persisted thread history into the latest user turn (sent as the
      # runner's `input`) plus the prior context (sent as
      # `context[:conversation_history]`). This mirrors how
      # `Captain::Assistant::AgentRunnerService` shapes its payload.
      def split_history
        messages = thread.copilot_messages
                         .where(message_type: %i[user assistant])
                         .order(:created_at)
                         .last(MAX_HISTORY)
                         .map { |m| { role: m.message_type.to_sym, content: m.message['content'].to_s } }
                         .reject { |m| m[:content].blank? }

        last_user_index = messages.rindex { |m| m[:role] == :user }
        raise Error, 'No user message in thread to respond to' if last_user_index.nil?

        user_input = messages[last_user_index][:content]
        history    = messages.each_with_index.reject { |(_msg, i)| i == last_user_index }.map(&:first)
        [user_input, history]
      end

      def build_runner_context(history)
        ctx = {
          account_id: account&.id,
          thread_id: thread&.id,
          conversation_id: conversation_id,
          conversation_history: history,
          state: { account_id: account&.id }
        }
        ctx[:bound_conversation_transcript] = bound_conversation_transcript if conversation_id.present?
        ctx
      end

      def system_prompt
        sections = ['You are Pilot, a helpful AI co-pilot for support agents.']
        sections << "Reply in #{account.locale_english_name}." if account.respond_to?(:locale_english_name)
        sections << <<~TOOLS_HINT
          You have tools that can fetch live data from this Chatwoot account
          (search_conversation, get_conversation, get_contact). Call them when
          the agent asks about specific conversations, contacts, or tickets
          rather than guessing.
        TOOLS_HINT

        bound = bound_conversation_transcript
        sections << "Context — the customer conversation the agent is looking at:\n\n#{bound}" if bound.present?

        logbook_context = logbook_context_for(thread_contact)
        sections << logbook_context if logbook_context.present?

        sections.join("\n\n")
      end

      def bound_conversation_transcript
        return @bound_conversation_transcript if defined?(@bound_conversation_transcript)
        return @bound_conversation_transcript = nil if conversation_id.blank?

        conversation = account.conversations.find_by(display_id: conversation_id) ||
                       account.conversations.find_by(id: conversation_id)
        @bound_conversation_transcript = conversation&.to_llm_text(include_contact_details: true)
      end

      def thread_contact
        return nil if conversation_id.blank?

        conversation = account.conversations.find_by(display_id: conversation_id) ||
                       account.conversations.find_by(id: conversation_id)
        conversation&.contact
      end

      # Stubbed until the Logbook sub-feature lands (section 5). Forward-
      # compatible: returns nil today so the system prompt simply doesn't
      # include logbook context.
    end
  end
end
