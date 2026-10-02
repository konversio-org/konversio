# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Pilot::FaqMiningService do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:service) { described_class.new(assistant: assistant, account: account, transcript: transcript) }
  let(:transcript) { "[CUSTOMER] How do I cancel?\n[AGENT] From Settings > Billing." }

  describe 'generation-quality gates' do
    let(:prompt) { service.send(:system_prompt) }

    it 'requires answers to come only from human support agent statements' do
      expect(prompt).to include('Build answers ONLY from statements made by the human support agent')
    end

    it 'restricts output to durable, publicly reusable knowledge' do
      expect(prompt).to include('durable, publicly reusable knowledge')
    end

    it 'bans private and customer-specific identifiers from generated text' do
      expect(prompt).to include('Never include names, email addresses, phone numbers, order numbers')
    end

    it 'requires an explicit empty result when nothing qualifies' do
      expect(prompt).to include('return an empty pairs array')
    end
  end

  describe '#call' do
    it 'returns an empty result for a blank transcript without calling the LLM' do
      blank_service = described_class.new(assistant: assistant, account: account, transcript: '')
      expect(blank_service).not_to receive(:invoke_llm)

      expect(blank_service.call).to eq([])
    end

    it 'returns an empty result on malformed LLM output' do
      allow(service).to receive(:invoke_llm).and_return('not json at all')

      expect(service.call).to eq([])
    end

    it 'returns an empty result when the LLM call fails' do
      allow(service).to receive(:invoke_llm).and_raise(StandardError, 'boom')

      expect(service.call).to eq([])
    end

    it 'parses well-formed pairs' do
      allow(service).to receive(:invoke_llm).and_return(
        { pairs: [{ question: 'How do I cancel?', answer: 'From Settings > Billing.' }] }.to_json
      )

      pairs = service.call
      expect(pairs.size).to eq(1)
      expect(pairs.first.question).to eq('How do I cancel?')
      expect(pairs.first.answer).to eq('From Settings > Billing.')
    end
  end
end
