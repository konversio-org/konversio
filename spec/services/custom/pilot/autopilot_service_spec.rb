# rubocop:disable RSpec/VerifiedDoubles
require 'rails_helper'

RSpec.describe Custom::Pilot::AutopilotService do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
  end

  describe '#perform' do
    it 'raises FeatureDisabledError when autopilot flag is off' do
      account.disable_features!(:pilot_autopilot)

      expect { described_class.new(assistant: assistant, message: 'hi').perform }
        .to raise_error(described_class::FeatureDisabledError)
    end

    it 'raises FeatureDisabledError when master pilot flag is off' do
      account.disable_features!(:pilot)

      expect { described_class.new(assistant: assistant, message: 'hi').perform }
        .to raise_error(described_class::FeatureDisabledError)
    end

    it 'raises Error when no customer message is present' do
      service = described_class.new(assistant: assistant, message_history: [])
      expect { service.perform }.to raise_error(described_class::Error, /No customer message/)
    end

    it 'runs the agents runner and returns a non-handover result for a normal answer' do
      service = described_class.new(assistant: assistant, message: 'How big is the box?')

      fake_result = double('RunResult', output: 'The box is 30cm wide.', failed?: false, error: nil)
      fake_runner = double('AgentRunner')
      allow(fake_runner).to receive(:run).and_return(fake_result)
      allow(fake_runner).to receive(:on_tool_start).and_yield('search_documentation')

      allow(Agents::Runner).to receive(:with_agents).and_return(fake_runner)

      result = service.perform
      expect(result.reply).to eq('The box is 30cm wide.')
      expect(result.handover.handover?).to be false
      expect(result.invoked_tool_names).to include('search_documentation')
    end

    it 'adds runner token usage to the trace span when present' do
      service = described_class.new(assistant: assistant, message: 'How big is the box?')
      span = instance_double(Custom::Pilot::TraceSpan::NullSpan, set_attribute: nil)
      fake_result = Agents::RunResult.new(
        output: 'The box is 30cm wide.',
        messages: [],
        usage: { input_tokens: 12, output_tokens: 5 },
        context: {}
      )
      fake_runner = double('AgentRunner', on_tool_start: nil)
      allow(fake_runner).to receive(:run).and_return(fake_result)
      allow(Agents::Runner).to receive(:with_agents).and_return(fake_runner)
      allow(Custom::Pilot::TraceSpan).to receive(:wrap) do |**_args, &block|
        block.call(span)
      end

      service.perform

      expect(span).to have_received(:set_attribute).with('prompt_tokens', 12)
      expect(span).to have_received(:set_attribute).with('completion_tokens', 5)
    end

    it 'flags handover when the reply contains the sentinel' do
      service = described_class.new(assistant: assistant, message: 'Where is my refund?')

      sentinel = Custom::Pilot::HandoverEvaluator::HANDOVER_SENTINEL
      fake_result = double('RunResult', output: "I cannot help here. #{sentinel}", failed?: false, error: nil)
      fake_runner = double('AgentRunner', on_tool_start: nil)
      allow(fake_runner).to receive(:run).and_return(fake_result)
      allow(Agents::Runner).to receive(:with_agents).and_return(fake_runner)

      result = service.perform
      expect(result.handover.handover?).to be true
      expect(result.handover.reason).to eq('sentinel')
    end

    describe 'no-assistant fallback' do
      let(:dispatcher) { instance_double(Dispatcher, dispatch: true) }

      before do
        allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
      end

      it 'returns a no-op result without invoking the LLM when no assistant is bound' do
        service = described_class.new(assistant: nil, message: 'hi', account: account)

        expect(Agents::Runner).not_to receive(:with_agents)

        result = service.perform

        expect(result.reply).to be_nil
        expect(result.invoked_tool_names).to eq([])
        expect(result.handover.handover?).to be false
      end

      it 'does not create any outgoing message when no assistant is bound' do
        service = described_class.new(assistant: nil, message: 'hi', account: account)

        expect { service.perform }.not_to(change(Message, :count))
      end

      it 'dispatches a pilot.autopilot.skipped telemetry event exactly once with the expected payload' do
        conversation = create(:conversation, account: account)
        service = described_class.new(assistant: nil, conversation: conversation, account: account)

        expect(dispatcher).to receive(:dispatch).with(
          'pilot.autopilot.skipped',
          kind_of(Time),
          hash_including(
            account_id: account.id,
            inbox_id: conversation.inbox_id,
            conversation_id: conversation.display_id,
            reason: 'no_assistant_attached'
          )
        ).once

        service.perform
      end

      it 'logs a structured warning so operators without telemetry consumers still see the skip' do
        service = described_class.new(assistant: nil, message: 'hi', account: account)

        expect(Rails.logger).to receive(:warn).with(/pilot.autopilot.*no assistant attached/)

        service.perform
      end
    end

    it 'flags handover when the customer asks for a human' do
      service = described_class.new(assistant: assistant, message: 'I want to speak to a human, please.')

      fake_result = double('RunResult', output: 'Sure.', failed?: false, error: nil)
      fake_runner = double('AgentRunner', on_tool_start: nil)
      allow(fake_runner).to receive(:run).and_return(fake_result)
      allow(Agents::Runner).to receive(:with_agents).and_return(fake_runner)

      result = service.perform
      expect(result.handover.handover?).to be true
      expect(result.handover.reason).to eq('customer_request')
    end

    it 'includes Logbook context in assistant instructions when enabled' do
      account.enable_features!(:pilot_logbook)
      contact = create(:contact, account: account)
      inbox = create(:inbox, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      create(:pilot_logbook_entry, account: account, contact: contact, content: 'Prefers email')

      service = described_class.new(assistant: assistant, conversation: conversation)

      expect(service.send(:assistant_instructions)).to include('Known facts about this contact:', 'Prefers email')
    end

    it 'omits Logbook context in assistant instructions when disabled' do
      account.disable_features!(:pilot_logbook)
      contact = create(:contact, account: account)
      inbox = create(:inbox, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      create(:pilot_logbook_entry, account: account, contact: contact, content: 'Prefers email')

      service = described_class.new(assistant: assistant, conversation: conversation)

      expect(service.send(:assistant_instructions)).not_to include('Prefers email')
    end

    it 'runs a real Agents::Runner turn through search_documentation', :aggregate_failures do
      service = described_class.new(assistant: assistant, message: 'How do refunds work?')
      response = create(:pilot_assistant_response,
                        assistant: assistant,
                        account: account,
                        question: 'How do refunds work?',
                        answer: 'Refunds take 30 days.',
                        status: :approved)
      stub_documentation_results(response)
      fake_chat = build_fake_runner_chat

      expect(Agents::Runner).to receive(:with_agents).and_call_original
      allow(RubyLLM::Chat).to receive(:new).and_return(fake_chat)

      result = service.perform

      expect(result.reply).to include('Refunds take 30 days.')
      expect(result.invoked_tool_names).to include('search_documentation')
      expect(fake_chat.tools.map(&:name)).to include('search_documentation')
    end
  end

  describe '#assistant_tools' do
    let(:service) { described_class.new(assistant: assistant, message: 'hello') }

    it 'always includes the built-in search_documentation tool' do
      tools = service.send(:assistant_tools)
      expect(tools.first).to be_a(Custom::Pilot::Tools::SearchDocumentation)
    end

    it 'appends an adapter for every enabled custom tool on the account' do
      enabled = create(:pilot_custom_tool, account: account, title: 'Lookup order')
      create(:pilot_custom_tool, account: account, title: 'Disabled tool', enabled: false)
      other_account_tool = create(:pilot_custom_tool, account: create(:account), title: 'Foreign tool')
      assistant.update!(enabled_tool_slugs: [enabled.slug])

      tools = service.send(:assistant_tools)
      slugs = tools.select { |t| t.is_a?(Pilot::Tools::AgentToolAdapter) }.map(&:name)

      expect(slugs).to include(enabled.slug)
      expect(slugs).not_to include(other_account_tool.slug)
      expect(tools.map(&:name)).not_to include('disabled', 'custom_disabled_tool')
    end

    it 'omits account tools that are not enabled for the assistant' do
      tool = create(:pilot_custom_tool, account: account, title: 'Lookup order')

      tools = service.send(:assistant_tools)
      slugs = tools.select { |t| t.is_a?(Pilot::Tools::AgentToolAdapter) }.map(&:name)

      expect(slugs).not_to include(tool.slug)
    end

    it 'omits custom tools when the account has none configured' do
      tools = service.send(:assistant_tools)
      expect(tools.count { |t| t.is_a?(Pilot::Tools::AgentToolAdapter) }).to eq(0)
    end
  end

  describe 'scenario agent tool wiring' do
    let(:lookup_tool) { create(:pilot_custom_tool, account: account, title: 'Lookup order') }
    let(:scenario) do
      create(:pilot_scenario,
             assistant: assistant,
             account: account,
             title: 'Refund flow',
             description: 'Refund handling',
             instruction: "Use [Lookup](tool://#{lookup_tool.slug}) when needed.")
    end

    it 'passes adapter-wrapped tools into the scenario agent constructor' do
      service = described_class.new(assistant: assistant, message: 'hello')
      service.assistant.scenarios.reload
      scenario # touch
      assistant.update!(enabled_tool_slugs: [lookup_tool.slug])
      resolved = Pilot::Tools::ScenarioResolver.call(scenario, account: account, assistant: assistant)
      expect(resolved.size).to eq(1)
      expect(resolved.first).to be_a(Pilot::Tools::AgentToolAdapter)
      expect(resolved.first.tool).to eq(lookup_tool)
    end
  end

  describe 'vector search wiring' do
    # Embedding column is vector(3584) since the BGE switchover migration; the
    # canonical dimension lives in EmbeddingService::MODEL_DIMENSIONS so the
    # test stays correct if the default model changes.
    let(:vector_dim) do
      Custom::Pilot::EmbeddingService::MODEL_DIMENSIONS.fetch(
        Custom::Pilot::EmbeddingService::DEFAULT_EMBEDDING_MODEL
      )
    end

    it 'returns matching approved responses via search_for_assistant' do
      approved = create(:pilot_assistant_response, assistant: assistant, account: account,
                                                   question: 'Q', answer: 'A',
                                                   status: :approved,
                                                   embedding: Array.new(vector_dim, 0.01))
      create(:pilot_assistant_response, assistant: assistant, account: account,
                                        question: 'Pending Q', answer: 'Pending A',
                                        status: :pending,
                                        embedding: Array.new(vector_dim, 0.01))

      result = Pilot::AssistantResponse.search_for_assistant(assistant.id, Array.new(vector_dim, 0.01), limit: 5)

      expect(result).to include(approved)
      expect(result.map(&:status)).to all(eq('approved'))
    end
  end

  def stub_documentation_results(*rows)
    allow(Custom::Pilot::EmbeddingService).to receive(:new)
      .and_return(instance_double(Custom::Pilot::EmbeddingService, embed: [0.1] * 1536))
    relation = Pilot::AssistantResponse.where(id: rows.map(&:id))
    scope = instance_double(ActiveRecord::Relation)
    allow(scope).to receive_messages(where: scope, order: scope, limit: relation)
    allow(Pilot::AssistantResponse).to receive(:where).and_call_original
    allow(Pilot::AssistantResponse).to receive(:where).with(account_id: account.id).and_return(scope)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def build_fake_runner_chat
    messages = []
    tools = []
    message_factory = method(:fake_llm_message)
    Object.new.tap do |chat|
      chat.define_singleton_method(:messages) { messages }
      chat.define_singleton_method(:tools) { tools }
      chat.define_singleton_method(:add_message) do |message|
        messages << message
        self
      end
      chat.define_singleton_method(:with_headers) { |**_headers| self }
      chat.define_singleton_method(:with_model) { |_model| self }
      chat.define_singleton_method(:with_instructions) { |_instructions, **_options| self }
      chat.define_singleton_method(:with_temperature) { |_temperature| self }
      chat.define_singleton_method(:with_schema) { |_schema| self }
      chat.define_singleton_method(:with_tools) do |*new_tools, replace: false|
        tools.replace(replace ? new_tools : tools + new_tools)
        self
      end
      chat.define_singleton_method(:ask) do |input|
        messages << message_factory.call(role: :user, content: input)
        documentation_tool = tools.find { |tool| tool.name == 'search_documentation' }
        tool_result = documentation_tool.call('query' => input)
        message_factory.call(role: :assistant, content: "Found this: #{tool_result}", input_tokens: 10, output_tokens: 5).tap do |message|
          messages << message
        end
      end
      chat.define_singleton_method(:complete) { ask('(continue)') }
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def fake_llm_message(role:, content:, input_tokens: 0, output_tokens: 0)
    Object.new.tap do |message|
      message.define_singleton_method(:role) { role }
      message.define_singleton_method(:content) { content }
      message.define_singleton_method(:input_tokens) { input_tokens }
      message.define_singleton_method(:output_tokens) { output_tokens }
      message.define_singleton_method(:tool_call?) { false }
      message.define_singleton_method(:tool_result?) { false }
      message.define_singleton_method(:tool_calls) { {} }
    end
  end
end

# rubocop:enable RSpec/VerifiedDoubles
