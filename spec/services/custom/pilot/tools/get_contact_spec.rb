require 'rails_helper'

RSpec.describe Custom::Pilot::Tools::GetContact do
  let(:account) { create(:account) }
  let(:tool) { described_class.new }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ account_id: account.id }))
  end

  it 'has the canonical name and description' do
    expect(tool.name).to eq('get_contact')
    expect(tool.description).to include('Fetch a single contact')
  end

  it 'returns contact attributes when found' do
    contact = create(:contact, account: account, name: 'Bob', email: 'bob@example.com', phone_number: '+1234')
    result = tool.perform(tool_context, id: contact.id)
    expect(result).to include("id: #{contact.id}")
    expect(result).to include('name: Bob')
    expect(result).to include('email: bob@example.com')
    expect(result).to include('phone: +1234')
  end

  it 'returns "not found" when the contact is missing' do
    expect(tool.perform(tool_context, id: 9999)).to match(/not found/)
  end

  it 'returns a friendly message when account is missing' do
    empty_ctx = Agents::ToolContext.new(run_context: Agents::RunContext.new({}))
    expect(tool.perform(empty_ctx, id: 1)).to match(/Account context unavailable/)
  end
end
