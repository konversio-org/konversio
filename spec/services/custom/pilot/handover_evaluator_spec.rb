require 'rails_helper'

RSpec.describe Custom::Pilot::HandoverEvaluator do
  describe '#evaluate' do
    subject(:evaluator) { described_class.new }

    it 'flags handover when the assistant reply contains the sentinel' do
      result = evaluator.evaluate(assistant_reply: "Sure, let me get you a human. #{described_class::HANDOVER_SENTINEL}",
                                  customer_message: 'Hello')

      expect(result.handover?).to be true
      expect(result.reason).to eq('sentinel')
    end

    it 'flags handover when the customer message asks for a human' do
      result = evaluator.evaluate(assistant_reply: 'Sure thing.',
                                  customer_message: 'Can I please speak to a human?')

      expect(result.handover?).to be true
      expect(result.reason).to eq('customer_request')
    end

    it 'flags handover when an invoked tool starts with handoff_' do
      result = evaluator.evaluate(assistant_reply: 'Routing now.',
                                  customer_message: 'Where is my order?',
                                  invoked_tool_names: %w[search_documentation handoff_to_scenario_42_billing_agent])

      expect(result.handover?).to be true
      expect(result.reason).to eq('handoff_tool')
    end

    it 'returns no handover when none of the triggers fire' do
      result = evaluator.evaluate(assistant_reply: 'Here is your answer.',
                                  customer_message: 'How big is the box?',
                                  invoked_tool_names: ['search_documentation'])

      expect(result.handover?).to be false
      expect(result.reason).to be_nil
    end

    it 'matches human-request phrases regardless of capitalization' do
      result = evaluator.evaluate(customer_message: 'I want to TALK TO A HUMAN now.')

      expect(result.handover?).to be true
    end

    it 'matches preposition-agnostic variants like "speak with a human"' do
      result = evaluator.evaluate(customer_message: 'I need to speak with a human please')
      expect(result.handover?).to be true
    end

    it 'matches other preposition-agnostic and colloquial variations' do
      expect(evaluator.evaluate(customer_message: 'chat with someone').handover?).to be true
      expect(evaluator.evaluate(customer_message: 'talk with a human').handover?).to be true
      expect(evaluator.evaluate(customer_message: 'I need a human').handover?).to be true
      expect(evaluator.evaluate(customer_message: 'real person').handover?).to be true
      expect(evaluator.evaluate(customer_message: 'live agent').handover?).to be true
    end

    describe 'precedence (scenario tool > sentinel > customer phrase)' do
      it 'prefers handoff_tool when a scenario tool also fires with the sentinel' do
        result = evaluator.evaluate(
          assistant_reply: "Connecting you now. #{described_class::HANDOVER_SENTINEL}",
          customer_message: 'How big is the box?',
          invoked_tool_names: %w[handoff_to_billing]
        )
        expect(result.handover?).to be true
        expect(result.reason).to eq('handoff_tool')
      end

      it 'prefers the sentinel over a customer-phrase match when no scenario tool fired' do
        result = evaluator.evaluate(
          assistant_reply: "Let me grab a teammate. #{described_class::HANDOVER_SENTINEL}",
          customer_message: 'Please let me speak to a human',
          invoked_tool_names: []
        )
        expect(result.handover?).to be true
        expect(result.reason).to eq('sentinel')
      end

      it 'falls back to customer-phrase when neither the scenario tool nor the sentinel fired' do
        result = evaluator.evaluate(
          assistant_reply: 'Here is the answer.',
          customer_message: 'I want to speak to a human',
          invoked_tool_names: %w[search_documentation]
        )
        expect(result.handover?).to be true
        expect(result.reason).to eq('customer_request')
      end

      it 'returns a single Result even when all three signals fire (no double-firing)' do
        result = evaluator.evaluate(
          assistant_reply: "Sure. #{described_class::HANDOVER_SENTINEL}",
          customer_message: 'speak to a human',
          invoked_tool_names: %w[handoff_to_billing]
        )
        expect(result.handover?).to be true
        expect(result.reason).to eq('handoff_tool')
      end
    end
  end
end
