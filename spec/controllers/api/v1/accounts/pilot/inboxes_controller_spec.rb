require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Pilot::Inboxes', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/pilot/assistants/#{assistant.id}/inboxes" }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
  end

  describe 'GET /api/v1/accounts/:account_id/pilot/assistants/:assistant_id/inboxes' do
    it 'lists only inboxes attached to the selected assistant' do
      attached = Pilot::Inbox.create!(assistant: assistant, inbox: inbox)
      other_assistant = create(:pilot_assistant, account: account)
      Pilot::Inbox.create!(assistant: other_assistant, inbox: create(:inbox, account: account))

      get base_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.pluck('id')).to contain_exactly(attached.id)
      expect(response.parsed_body.first).to include(
        'inbox_id' => inbox.id,
        'name' => inbox.name,
        'channel_type' => inbox.channel_type
      )
    end
  end

  describe 'POST /api/v1/accounts/:account_id/pilot/assistants/:assistant_id/inboxes' do
    it 'attaches an inbox to an assistant' do
      expect do
        post base_url,
             params: { inbox_id: inbox.id },
             headers: admin.create_new_auth_token,
             as: :json
      end.to change(Pilot::Inbox, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        'inbox_id' => inbox.id,
        'name' => inbox.name,
        'channel_type' => inbox.channel_type
      )
    end

    it 'returns the existing connection when the inbox is already attached to the same assistant' do
      attached = Pilot::Inbox.create!(assistant: assistant, inbox: inbox)

      expect do
        post base_url,
             params: { inbox_id: inbox.id },
             headers: admin.create_new_auth_token,
             as: :json
      end.not_to change(Pilot::Inbox, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['id']).to eq(attached.id)
      expect(response.parsed_body['inbox_id']).to eq(inbox.id)
    end

    it 'rejects attaching an inbox already attached to another assistant' do
      Pilot::Inbox.create!(
        assistant: create(:pilot_assistant, account: account),
        inbox: inbox
      )

      expect do
        post base_url,
             params: { inbox_id: inbox.id },
             headers: admin.create_new_auth_token,
             as: :json
      end.not_to change(Pilot::Inbox, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('already connected to another assistant')
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/pilot/assistants/:assistant_id/inboxes/:inbox_id' do
    it 'detaches an inbox from the selected assistant' do
      Pilot::Inbox.create!(assistant: assistant, inbox: inbox)

      expect do
        delete "#{base_url}/#{inbox.id}",
               headers: admin.create_new_auth_token,
               as: :json
      end.to change(Pilot::Inbox, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
