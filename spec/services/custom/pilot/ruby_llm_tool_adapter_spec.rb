require 'rails_helper'

# Inline definition of a real subclass of Agents::Tool to avoid fragile double mocking
class TestAgentsTool < Agents::Tool
  description 'Test description'
  param :query, type: 'string', desc: 'Test query', required: true

  def name
    'test_agents_tool'
  end

  def perform(tool_context, query:)
    "Result: #{query} (Account: #{tool_context.context[:account_id]}, User: #{tool_context.context[:user_id]})"
  end

  def self.provider_params
    { custom: 'param' }
  end
end

RSpec.describe Pilot::RubyLlmToolAdapter do
  subject { described_class.new(agents_tool, account: account, context: { user_id: 42 }) }

  let(:account) { create(:account) }
  let(:agents_tool) { TestAgentsTool.new }

  describe '#name' do
    it 'delegates to the underlying agents tool' do
      expect(subject.name).to eq('test_agents_tool')
    end
  end

  describe '#description' do
    it 'delegates to the underlying agents tool' do
      expect(subject.description).to eq('Test description')
    end
  end

  describe '#parameters' do
    it 'delegates to the underlying agents tool and returns real parameter definitions' do
      expect(subject.parameters).to have_key(:query)
      expect(subject.parameters[:query]).to be_a(RubyLLM::Parameter)
    end
  end

  describe '#provider_params' do
    it 'delegates to the underlying agents tool class or instance' do
      expect(subject.provider_params).to eq({ custom: 'param' })
    end
  end

  describe '#params_schema' do
    it 'successfully generates a valid JSON schema using real parameters' do
      schema = subject.params_schema
      expect(schema).to be_a(Hash)
      expect(schema['type']).to eq('object')
      expect(schema['properties']).to have_key('query')
      expect(schema['properties']['query']['type']).to eq('string')
      expect(schema['properties']['query']['description']).to eq('Test query')
      expect(schema['required']).to eq(['query'])
    end
  end

  describe '#execute' do
    it 'constructs standard context merging custom context keys and runs perform' do
      res = subject.execute(query: 'hello')
      expect(res).to eq("Result: hello (Account: #{account.id}, User: 42)")
    end
  end

  describe '#call' do
    it 'performs the full round-trip execution starting from string-keyed arguments' do
      res = subject.call({ 'query' => 'world' })
      expect(res).to eq("Result: world (Account: #{account.id}, User: 42)")
    end
  end
end
