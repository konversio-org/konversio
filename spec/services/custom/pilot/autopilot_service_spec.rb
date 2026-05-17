require 'rails_helper'

RSpec.describe Custom::Pilot::AutopilotService do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }

  before do
    account.update!(pilot_enabled: true, pilot_autopilot_enabled: true)
  end

  describe '#perform' do
    it 'raises FeatureDisabledError when autopilot flag is off' do
      account.update!(pilot_autopilot_enabled: false)

      expect { described_class.new(assistant: assistant, message: 'hi').perform }
        .to raise_error(described_class::FeatureDisabledError)
    end

    it 'raises FeatureDisabledError when master pilot flag is off' do
      account.update!(pilot_enabled: false)

      expect { described_class.new(assistant: assistant, message: 'hi').perform }
        .to raise_error(described_class::FeatureDisabledError)
    end

    it 'raises Error when no customer message is present' do
      service = described_class.new(assistant: assistant, message_history: [])
      expect { service.perform }.to raise_error(described_class::Error, /No customer message/)
    end

    it 'runs the agents runner and returns a non-handover result for a normal answer' do
      service = described_class.new(assistant: assistant, message: 'How big is the box?')

      fake_result = double('RunResult', output: 'The box is 30cm wide.')
      fake_runner = double('AgentRunner')
      allow(fake_runner).to receive(:run).and_return(fake_result)
      allow(fake_runner).to receive(:on_tool_start).and_yield('search_documentation')

      allow(::Agents::Runner).to receive(:with_agents).and_return(fake_runner)

      result = service.perform
      expect(result.reply).to eq('The box is 30cm wide.')
      expect(result.handover.handover?).to be false
      expect(result.invoked_tool_names).to include('search_documentation')
    end

    it 'flags handover when the reply contains the sentinel' do
      service = described_class.new(assistant: assistant, message: 'Where is my refund?')

      fake_result = double('RunResult', output: "I cannot help here. #{Custom::Pilot::HandoverEvaluator::HANDOVER_SENTINEL}")
      fake_runner = double('AgentRunner', on_tool_start: nil)
      allow(fake_runner).to receive(:run).and_return(fake_result)
      allow(::Agents::Runner).to receive(:with_agents).and_return(fake_runner)

      result = service.perform
      expect(result.handover.handover?).to be true
      expect(result.handover.reason).to eq('sentinel')
    end

    it 'flags handover when the customer asks for a human' do
      service = described_class.new(assistant: assistant, message: 'I want to speak to a human, please.')

      fake_result = double('RunResult', output: 'Sure.')
      fake_runner = double('AgentRunner', on_tool_start: nil)
      allow(fake_runner).to receive(:run).and_return(fake_result)
      allow(::Agents::Runner).to receive(:with_agents).and_return(fake_runner)

      result = service.perform
      expect(result.handover.handover?).to be true
      expect(result.handover.reason).to eq('customer_request')
    end
  end

  describe 'vector search wiring' do
    it 'returns matching approved responses via search_for_assistant' do
      approved = create(:pilot_assistant_response, assistant: assistant, account: account,
                                                   question: 'Q', answer: 'A',
                                                   status: :approved,
                                                   embedding: Array.new(1536, 0.01))
      create(:pilot_assistant_response, assistant: assistant, account: account,
                                        question: 'Pending Q', answer: 'Pending A',
                                        status: :pending,
                                        embedding: Array.new(1536, 0.01))

      result = ::Pilot::AssistantResponse.search_for_assistant(assistant.id, Array.new(1536, 0.01), limit: 5)

      expect(result).to include(approved)
      expect(result.map(&:status)).to all(eq('approved'))
    end
  end
end
