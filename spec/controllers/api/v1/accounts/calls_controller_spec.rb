require 'rails_helper'

RSpec.describe 'Calls API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:hidden_conversation) { create(:conversation, account: account, inbox: other_inbox, contact: contact) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    create(:call, account: account, inbox: inbox, conversation: conversation, accepted_by_agent: admin)
    create(:call, account: account, inbox: inbox, conversation: conversation, accepted_by_agent: agent)
    create(:call, account: account, inbox: other_inbox, conversation: hidden_conversation, accepted_by_agent: agent)
  end

  it 'returns every call to an administrator' do
    get "/api/v1/accounts/#{account.id}/calls", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['meta']['count']).to eq(3)
  end

  it 'returns only the agent accessible accepted calls to an agent' do
    get "/api/v1/accounts/#{account.id}/calls", headers: agent.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['meta']['count']).to eq(1)
    expect(body['payload'].first['status']).to be_present
    expect(body['payload'].first['direction']).to be_present
  end
end
