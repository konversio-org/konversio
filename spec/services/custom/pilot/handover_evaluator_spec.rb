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
                                  invoked_tool_names: ['search_documentation', 'handoff_to_scenario_42_billing_agent'])

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
  end
end
