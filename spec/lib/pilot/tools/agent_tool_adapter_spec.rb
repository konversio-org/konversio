# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Tools::AgentToolAdapter do
  let(:account) { create(:account) }
  let(:tool) do
    create(:pilot_custom_tool,
           account: account,
           title: 'Lookup order',
           description: 'Fetch an order by ID',
           param_schema: [
             { 'name' => 'order_id', 'type' => 'string', 'description' => 'Order identifier', 'required' => true }
           ])
  end

  describe 'SDK surface' do
    it 'exposes the tool slug as #name' do
      adapter = described_class.new(tool)
      expect(adapter.name).to eq(tool.slug)
    end

    it 'exposes the tool description' do
      adapter = described_class.new(tool)
      expect(adapter.description).to eq('Fetch an order by ID')
    end

    it 'translates param_schema entries into RubyLLM::Parameter objects' do
      adapter = described_class.new(tool)
      params = adapter.parameters

      expect(params.keys).to eq([:order_id])
      param = params[:order_id]
      expect(param.type).to eq('string')
      expect(param.description).to eq('Order identifier')
      expect(param.required).to be(true)
    end
  end

  describe '#execute' do
    let(:adapter) { described_class.new(tool) }
    let(:executor) { instance_double(Pilot::Tools::Executor) }

    before do
      allow(Pilot::Tools::Executor).to receive(:new).with(tool).and_return(executor)
    end

    it 'returns the executor success body verbatim when it is a string' do
      allow(executor).to receive(:call).and_return('order body')

      expect(adapter.execute(nil, order_id: 'ABC')).to eq('order body')
      expect(executor).to have_received(:call).with({ order_id: 'ABC' })
    end

    it 'serializes a structured executor error to JSON so the LLM consumes a string' do
      allow(executor).to receive(:call).and_return(error: 'tool.timeout', message: 'Tool exceeded 10s timeout')

      result = adapter.execute(nil, order_id: 'ABC')

      parsed = JSON.parse(result)
      expect(parsed['error']).to eq('tool.timeout')
      expect(parsed['message']).to eq('Tool exceeded 10s timeout')
    end
  end

  describe 'per-account scoping' do
    it 'wraps only the tool it was constructed with, regardless of other accounts' do
      other_account = create(:account)
      other_tool = create(:pilot_custom_tool, account: other_account, title: 'Other tool')

      adapter = described_class.new(tool)
      expect(adapter.tool.account_id).to eq(account.id)
      expect(adapter.name).not_to eq(other_tool.slug)
    end
  end
end
