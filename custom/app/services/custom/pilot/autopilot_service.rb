module Custom
  module Pilot
    # Drives a single Autopilot inference turn for an assistant: builds the
    # message history, registers built-in/scenario tools, runs the
    # ai-agents SDK runner loop, and returns the assistant's reply along
    # with any handover signal.
    #
    # Per design D20 this is V2-only — no single-turn fallback. The runner
    # MAY invoke `search_documentation`, custom HTTP tools, and scenario
    # handoff tools in-process before producing the final assistant reply.
    class AutopilotService < BaseService # rubocop:disable Metrics/ClassLength
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      MAX_HISTORY = 40
      DEFAULT_MAX_TURNS = 6

      Result = Struct.new(:reply, :invoked_tool_names, :handover, keyword_init: true)

      attr_reader :assistant, :conversation, :customer_message, :message_history, :source

      def initialize(assistant:, conversation: nil, message: nil, message_history: nil, account: nil, source: 'production')
        @assistant = assistant
        @conversation = conversation
        @customer_message = message
        @message_history = message_history
        @source = source.to_s
        super(account: account || assistant&.account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot Autopilot is not enabled for this account' unless feature_enabled?(:autopilot)
        return ::Custom::Pilot::AutopilotNoAssistantSkip.new(account: account, conversation: conversation).call if assistant.blank?

        dispatch_event(:autopilot_inference_started, assistant_id: assistant.id, conversation_id: conversation&.display_id)
        result = run_runner
        dispatch_event(:autopilot_inference_completed,
                       assistant_id: assistant.id,
                       length: result.reply.to_s.length,
                       handover: result.handover.handover?)
        result
      rescue FeatureDisabledError, Error
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.autopilot] LLM error: #{e.class}: #{e.message}")
        dispatch_event(:autopilot_inference_failed, assistant_id: assistant&.id, error: e.message)
        raise Error, e.message
      end

      private

      def run_runner
        history = build_history
        last_user = extract_last_user_text(history)
        raise Error, 'No customer message to respond to' if last_user.blank?

        invoked_tool_names = []
        runner = build_runner(invoked_tool_names)
        context = build_context(history_without_last_user(history))

        run_result = ::Custom::Pilot::TraceSpan.wrap(name: 'pilot.autopilot.inference', attributes: span_attributes) do |span|
          result = runner.run(last_user, context: context, max_turns: max_turns)
          span.set_attribute('invoked_tools', invoked_tool_names.join(',')) if invoked_tool_names.any?
          result
        end
        raise Error, run_result.error&.message.presence || 'Agents::Runner reported failure with no error attached' if run_result.failed?

        reply = extract_reply(run_result)

        handover = ::Custom::Pilot::HandoverEvaluator.new.evaluate(
          assistant_reply: reply,
          customer_message: last_user,
          invoked_tool_names: invoked_tool_names
        )

        Result.new(reply: reply, invoked_tool_names: invoked_tool_names, handover: handover)
      end

      def span_attributes
        {
          account_id: account&.id,
          assistant_id: assistant&.id,
          conversation_id: conversation&.id,
          conversation_display_id: conversation&.display_id,
          channel_type: conversation&.inbox&.channel_type,
          source: source,
          model: model_for(:autopilot),
          credit_used: source != 'playground'
        }
      end

      def build_runner(invoked_tool_names)
        agents = build_and_wire_agents
        runner = ::Agents::Runner.with_agents(*agents)
        runner.on_tool_start do |tool_name, *_rest|
          invoked_tool_names << tool_name.to_s
        end
        runner
      end

      # Mirrors the upstream Captain `AgentRunnerService#build_and_wire_agents`:
      # the assistant is the primary agent; each enabled scenario becomes a
      # handoff target. Scenarios can also hand back to the assistant.
      def build_and_wire_agents
        assistant_agent = build_assistant_agent
        scenario_agents = scenario_agents_for(assistant_agent)

        if scenario_agents.any?
          assistant_agent.register_handoffs(*scenario_agents)
          scenario_agents.each { |scenario_agent| scenario_agent.register_handoffs(assistant_agent) }
        end

        [assistant_agent] + scenario_agents
      end

      def build_assistant_agent
        ::Agents::Agent.new(
          name: assistant.name.parameterize(separator: '_').presence || "assistant_#{assistant.id}",
          instructions: assistant_instructions,
          model: model_for(:autopilot),
          temperature: (assistant.try(:temperature) || 0.7).to_f,
          tools: assistant_tools
        )
      end

      def assistant_instructions
        sections = []
        sections << (assistant.description.presence || "You are #{assistant.name}, a helpful assistant.")
        sections << "Product: #{assistant.product_name}" if assistant.product_name.present?

        if assistant.response_guidelines.is_a?(Array) && assistant.response_guidelines.any?
          sections << "Response guidelines:\n#{assistant.response_guidelines.map { |g| "- #{g}" }.join("\n")}"
        end

        if assistant.guardrails.is_a?(Array) && assistant.guardrails.any?
          sections << "Guardrails:\n#{assistant.guardrails.map { |g| "- #{g}" }.join("\n")}"
        end

        sections << 'Use the `search_documentation` tool whenever the user asks a factual or product question.'
        sections << handover_policy
        sections.join("\n\n")
      end

      def handover_policy
        sentinel = ::Custom::Pilot::HandoverEvaluator::HANDOVER_SENTINEL
        <<~HANDOVER.strip
          Handover policy — follow exactly:

          Trigger a handover whenever EITHER of these is true:
            1. The user asks for a human, agent, operator, or live person — directly or indirectly (e.g. "speak to a human", "speak with a human", "real person", "I need a human", "talk to someone").
            2. You cannot answer confidently from `search_documentation` results and the user needs a real answer.

          To trigger a handover you MUST end your reply with the literal token `#{sentinel}`. The system parses this token and transitions the conversation to a human. Without it, your reply is sent as a normal bot message and the user stays stuck with the bot — this is a critical failure.

          Format the handover reply as ONE short sentence followed by the token. Examples:
            Let me get a human to help with that. #{sentinel}
            Connecting you with a teammate now. #{sentinel}

          Never invent fallbacks: do not mention a "reception", "front desk", "support page", "contact form", "FAQ section", "knowledge base", URL, email, phone number, or category that did not come from a tool result. Do not apologise at length or list topics. Just hand over with the token.
        HANDOVER
      end

      # Adapter-wrapped custom tools share the assistant's tool list with the
      # built-in `SearchDocumentation`. The pilot-tools spec's per-assistant
      # enablement filter is not yet backed by data — only the account-level
      # `enabled` flag gates each tool today.
      def assistant_tools
        builtins = [::Custom::Pilot::Tools::SearchDocumentation.new]
        return builtins if account.blank?

        builtins + account.pilot_custom_tools.enabled.map { |t| ::Pilot::Tools::AgentToolAdapter.new(t) }
      end

      def scenario_agents_for(_assistant_agent)
        assistant.scenarios.enabled.filter_map do |scenario|
          build_scenario_agent(scenario)
        end
      end

      def build_scenario_agent(scenario)
        ::Agents::Agent.new(
          name: scenario.handoff_key,
          instructions: scenario.instruction.to_s,
          model: model_for(:autopilot),
          temperature: (assistant.try(:temperature) || 0.7).to_f,
          tools: ::Pilot::Tools::ScenarioResolver.call(scenario, account: account, assistant: assistant)
        )
      end

      def build_history
        return Array(@message_history) if @message_history.present?
        return conversation_history if conversation.present?

        [{ role: 'user', content: customer_message.to_s }]
      end

      def conversation_history
        conversation.messages
                    .where(message_type: %i[incoming outgoing])
                    .where(private: false)
                    .order(:created_at)
                    .last(MAX_HISTORY)
                    .filter_map do |msg|
          content = msg.content.to_s
          next if content.blank?

          { role: msg.message_type == 'incoming' ? 'user' : 'assistant', content: content }
        end
      end

      def extract_last_user_text(history)
        last = history.reverse.find { |m| m[:role].to_s == 'user' }
        last&.dig(:content).to_s
      end

      def history_without_last_user(history)
        idx = history.rindex { |m| m[:role].to_s == 'user' }
        return history if idx.nil?

        history.reject.with_index { |_msg, i| i == idx }
      end

      def build_context(prior_history)
        {
          session_id: "#{assistant.account_id}_#{conversation&.display_id || SecureRandom.hex(4)}",
          account_id: assistant.account_id,
          assistant_id: assistant.id,
          conversation_id: conversation&.display_id,
          conversation_history: prior_history.map { |h| { role: h[:role].to_sym, content: h[:content] } },
          state: build_state
        }
      end

      def build_state
        state = { account_id: assistant.account_id, assistant_id: assistant.id, assistant_config: assistant.config }
        if conversation
          state[:conversation] = {
            id: conversation.id,
            display_id: conversation.display_id,
            inbox_id: conversation.inbox_id,
            status: conversation.status
          }
          state[:contact] = { id: conversation.contact_id, name: conversation.contact&.name } if conversation.contact
        end
        state
      end

      def extract_reply(run_result)
        output = run_result.output
        return output if output.is_a?(String)
        return output[:response] || output['response'] || output.to_s if output.is_a?(Hash)

        output.to_s
      end

      def max_turns
        GlobalConfigService.load('PILOT_AUTOPILOT_MAX_TURNS', DEFAULT_MAX_TURNS).to_i.then do |v|
          v.positive? ? v : DEFAULT_MAX_TURNS
        end
      end
    end
  end
end
