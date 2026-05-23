require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::LogbookEntries', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:url) { "/api/v2/accounts/#{account.id}/pilot/logbook_entries" }

  before do
    account.enable_features!(:pilot, :pilot_logbook)
  end

  describe 'GET /api/v2/accounts/:account_id/pilot/logbook_entries' do
    context 'when authenticated' do
      it 'returns logbook entries for a contact' do
        create_list(:pilot_logbook_entry, 3, account: account, contact: contact)

        get url,
            params: { contact_id: contact.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.size).to eq(3)
      end

      it 'returns 403 if logbook feature is disabled' do
        account.disable_features!(:pilot_logbook)

        get url,
            params: { contact_id: contact.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when unauthenticated' do
      it 'returns 401' do
        get url, params: { contact_id: contact.id }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v2/accounts/:account_id/pilot/logbook_entries' do
    context 'when authenticated' do
      it 'creates a new logbook entry' do
        expect do
          post url,
               params: { contact_id: contact.id, content: 'Test entry' },
               headers: agent.create_new_auth_token,
               as: :json
        end.to change { contact.pilot_logbook_entries.count }.by(1)

        expect(response).to have_http_status(:created)
        expect(response.parsed_body['content']).to eq('Test entry')
      end

      it 'returns 422 if content is missing' do
        post url,
             params: { contact_id: contact.id, content: '' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
