require 'rails_helper'

RSpec.describe Custom::Pilot::Tools::SearchConversation do
  let(:account) { create(:account) }
  let(:tool) { described_class.new }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ account_id: account.id }))
  end

  it 'has the canonical tool name and a description' do
    expect(tool.name).to eq('search_conversation')
    expect(tool.description).to include('Search')
  end

  it 'returns "No matching conversations found." when the account has none' do
    expect(tool.perform(tool_context)).to eq('No matching conversations found.')
  end

  it 'lists conversations with display_id, status, contact name, and last message snippet' do
    contact = create(:contact, account: account, name: 'Alice')
    inbox = create(:inbox, account: account)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    create(:message, account: account, conversation: conversation, content: 'refund please')

    result = tool.perform(tool_context, query: 'refund')
    expect(result).to include("##{conversation.display_id}")
    expect(result).to include('Alice')
    expect(result).to include('refund please')
  end

  it 'returns a friendly message when account_id is missing from context' do
    empty_ctx = Agents::ToolContext.new(run_context: Agents::RunContext.new({}))
    expect(tool.perform(empty_ctx)).to match(/Account context unavailable/)
  end
end
