# All sibling services under `custom/app/services/custom/pilot/` use the
# nested module style (autopilot_no_assistant_skip, briefing_service,
# copilot_service, etc.). Keeping this file consistent with the directory
# convention is more valuable than the compact form the global cop prefers;
# flipping just this file would make it the lone outlier in the dir.
# rubocop:disable Style/ClassAndModuleChildren
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

      DEFAULT_MAX_TURNS = 6

      Result = Struct.new(:reply, :invoked_tool_names, :handover, keyword_init: true)

      attr_reader :assistant, :conversation, :customer_message, :message_history, :source

      # Six keyword arguments is one over the cop's cap, but each one is a
      # distinct construction concern called by a distinct caller path:
      #   - production job:        assistant + conversation + account
      #   - super-admin playground: assistant + message + message_history + source
      # Collapsing them into a single `context:` bag would obscure the public
      # API and force every caller (job, controller, specs) to rewrap.
      # rubocop:disable Metrics/ParameterLists
      def initialize(assistant:, conversation: nil, message: nil, message_history: nil, account: nil, source: 'production')
        # rubocop:enable Metrics/ParameterLists
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

        emit_inference_started
        result = run_runner
        emit_inference_completed(result)
        result
      rescue FeatureDisabledError, Error
        raise
      rescue StandardError => e
        handle_inference_failure(e)
      end

      private

      def emit_inference_started
        dispatch_event(:autopilot_inference_started, assistant_id: assistant.id, conversation_id: conversation&.display_id)
      end

      def emit_inference_completed(result)
        dispatch_event(:autopilot_inference_completed,
                       assistant_id: assistant.id,
                       length: result.reply.to_s.length,
                       handover: result.handover.handover?)
      end

      def handle_inference_failure(error)
        Rails.logger.error("[pilot.autopilot] LLM error: #{error.class}: #{error.message}")
        dispatch_event(:autopilot_inference_failed, assistant_id: assistant&.id, error: error.message)
        raise Error, error.message
      end

      def run_runner
        history = build_history
        last_user = extract_last_user_text(history)
        raise Error, 'No customer message to respond to' if last_user.blank?

        invoked_tool_names = []
        runner = build_runner(invoked_tool_names)
        context = build_context(history_without_last_user(history))

        run_result = execute_runner(runner, last_user, context, invoked_tool_names)
        raise Error, run_result.error&.message.presence || 'Agents::Runner reported failure with no error attached' if run_result.failed?

        reply = extract_reply(run_result)

        handover = ::Custom::Pilot::HandoverEvaluator.new.evaluate(
          assistant_reply: reply,
          customer_message: last_user,
          invoked_tool_names: invoked_tool_names
        )

        Result.new(reply: reply, invoked_tool_names: invoked_tool_names, handover: handover)
      end

      def execute_runner(runner, last_user, context, invoked_tool_names)
        ::Custom::Pilot::TraceSpan.wrap(name: 'pilot.autopilot.inference', attributes: span_attributes) do |span|
          result = runner.run(last_user, context: context, max_turns: max_turns)
          attach_token_usage(span, result.usage) if result.respond_to?(:usage)
          span.set_attribute('invoked_tools', invoked_tool_names.join(',')) if invoked_tool_names.any?
          result
        end
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
        [
          persona_section,
          product_section,
          logbook_section,
          response_guidelines_section,
          guardrails_section,
          'Use the `search_documentation` tool whenever the user asks a factual or product question.',
          handover_policy
        ].compact.join("\n\n")
      end

      def persona_section
        assistant.description.presence || "You are #{assistant.name}, a helpful assistant."
      end

      def product_section
        return nil if assistant.product_name.blank?

        "Product: #{assistant.product_name}"
      end

      def logbook_section
        return nil if conversation.blank?

        logbook_context_for(conversation.contact)
      end

      def response_guidelines_section
        bullet_section('Response guidelines', assistant.response_guidelines)
      end

      def guardrails_section
        bullet_section('Guardrails', assistant.guardrails)
      end

      # `items` may be an Array or a newline-separated String (the assistant
      # editor saves these fields as trimmed strings). Normalise to a list of
      # non-blank lines so configured guardrails/guidelines reach the prompt.
      def bullet_section(heading, items)
        list = items.is_a?(String) ? items.split("\n") : Array(items)
        list = list.map { |item| item.to_s.strip }.reject(&:blank?)
        return nil if list.empty?

        "#{heading}:\n#{list.map { |item| "- #{item}" }.join("\n")}"
      end

      def handover_policy
        return handover_pending_policy if handoff_already_requested?

        sentinel = ::Custom::Pilot::HandoverEvaluator::HANDOVER_SENTINEL
        <<~HANDOVER.strip
          Scope and escalation policy — follow exactly:

          Stay inside your configured role and guardrails. Only state product facts that come from `search_documentation` results. If a message is off-topic, personal, or outside your scope, briefly and politely decline and steer the user back to what you can help with — follow your guardrails. Declining an out-of-scope message is NOT an escalation and must NOT end with the token below.

          When you cannot answer a genuine in-scope question from `search_documentation`, ask one focused clarifying question before doing anything else. A single missed lookup is not a reason to escalate.

          Escalate to a human ONLY when one of these is true:
            1. The user explicitly asks for a human, agent, operator, or live person — directly or indirectly (e.g. "speak to a human", "real person", "I need someone", "talk to a person").
            2. The user has a genuine in-scope need you still cannot resolve after consulting documentation and asking your clarifying question.
            3. The request needs an action, permission, or expertise you do not have.
            4. Repeated attempts to help have already failed.

          To escalate you MUST end your reply with the literal token `#{sentinel}`. The system parses this token to transfer the conversation to a human; without it your reply is sent as a normal message and the user stays with you. Format an escalation as ONE short sentence followed by the token, e.g.:
            Let me get a human to help with that. #{sentinel}

          Never invent fallbacks: do not mention a "reception", "front desk", "support page", "contact form", "FAQ section", "knowledge base", URL, email, phone number, or category that did not come from a tool result. Do not apologise at length or list topics.
        HANDOVER
      end

      # When a handoff has already been requested, the conversation is
      # waiting for a human and re-offering to connect is just noise. Tell
      # the model to keep answering from documentation instead, and never
      # re-emit the handover token (the system ignores it in this state).
      def handoff_already_requested?
        state = conversation&.additional_attributes&.dig('pilot_handoff', 'state')
        %w[handoff_requested offline_acknowledged].include?(state)
      end

      def handover_pending_policy
        <<~PENDING.strip
          A human handoff has ALREADY been requested for this conversation and a teammate will follow up.

          Do NOT offer to connect them to a human again, and do NOT emit any handover token. Simply keep helping: answer the user's questions using `search_documentation`. If you cannot answer from the documentation, briefly say a teammate will follow up — do not repeat that you are connecting them to a human.
        PENDING
      end

      def assistant_tools
        builtins = [::Custom::Pilot::Tools::SearchDocumentation.new]
        return builtins if assistant.blank?

        builtins + assistant.enabled_custom_tools.map { |tool| ::Pilot::Tools::AgentToolAdapter.new(tool) }
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
                    .last(assistant&.max_history || ::Pilot::Assistant::DEFAULT_MAX_HISTORY)
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
# rubocop:enable Style/ClassAndModuleChildren
