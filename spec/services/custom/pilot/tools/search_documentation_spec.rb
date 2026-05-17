require 'rails_helper'

RSpec.describe Custom::Pilot::Tools::SearchDocumentation do
  let(:account) { create(:account) }
  let(:tool) { described_class.new }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ account_id: account.id }))
  end

  it 'has the canonical name and description' do
    expect(tool.name).to eq('search_documentation')
    expect(tool.description).to include('knowledge base')
  end

  it 'reports unavailable when Pilot::AssistantResponse is not defined yet' do
    # Pilot::AssistantResponse ships with Autopilot (section 4); until then
    # `.available?` returns false and the tool is omitted from the runner.
    # We assert the runtime gracefully reports it rather than crashing.
    skip('Pilot::AssistantResponse is defined; section 4 has shipped — update this spec.') if defined?(::Pilot::AssistantResponse)

    expect(described_class.available?).to be(false)
    expect(tool.perform(tool_context, query: 'refund')).to match(/not enabled/)
  end

  it 'returns a friendly message when account is missing' do
    empty_ctx = Agents::ToolContext.new(run_context: Agents::RunContext.new({}))
    expect(tool.perform(empty_ctx, query: 'x')).to match(/Account context unavailable/)
  end
end
