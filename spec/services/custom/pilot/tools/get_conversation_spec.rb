require 'rails_helper'

RSpec.describe Custom::Pilot::Tools::GetConversation do
  let(:account) { create(:account) }
  let(:tool) { described_class.new }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ account_id: account.id }))
  end

  it 'has the canonical name and description' do
    expect(tool.name).to eq('get_conversation')
    expect(tool.description).to include('Fetch a single conversation')
  end

  it 'returns a transcript-style block when the conversation exists' do
    contact = create(:contact, account: account, name: 'Carol')
    inbox = create(:inbox, account: account)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    create(:message, account: account, conversation: conversation, content: 'hello pilot')

    result = tool.perform(tool_context, display_id: conversation.display_id)
    expect(result).to include("##{conversation.display_id}")
    expect(result).to include('status=')
    expect(result).to include('assignee=')
  end

  it 'returns "not found" when the display_id is missing' do
    expect(tool.perform(tool_context, display_id: 999_999)).to match(/not found/)
  end
end
