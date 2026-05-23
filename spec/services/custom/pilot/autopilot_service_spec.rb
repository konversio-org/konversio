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
  end

  # §13 follow-up: end-to-end agentic-loop integration spec. Today every
  # autopilot spec stubs `Agents::Runner.with_agents`, which means a wiring
  # regression (tool list never reaches the runner, scenario tools never
  # register, system prompt drops on the floor) wouldn't be caught here.
  # The integration spec should stub only the LLM-client HTTP boundary and
  # let `Agents::Runner` orchestrate one real tool call (e.g.
  # `search_documentation`) so we know the wiring is intact.
  pending 'TODO: integration spec exercising a real Agents::Runner against a stubbed LLM HTTP boundary'

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
end

# rubocop:enable RSpec/VerifiedDoubles
