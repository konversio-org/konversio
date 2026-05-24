require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::Events', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v2/accounts/#{account.id}/pilot/events" }

  before do
    account.enable_features!(:pilot)
  end

  describe 'GET /api/v2/accounts/:account_id/pilot/events' do
    it 'returns recent events for the current account only' do
      older = account.pilot_events.create!(
        event_name: 'pilot.summary.completed',
        payload: { summary_length: 42 },
        created_at: 2.minutes.ago
      )
      newer = account.pilot_events.create!(
        event_name: 'pilot.autopilot.completed',
        payload: { prompt_sha256: 'abc123' },
        related_entity_type: 'Conversation',
        related_entity_id: 7,
        created_at: 1.minute.ago
      )
      create(:account).pilot_events.create!(
        event_name: 'pilot.other_account.completed',
        payload: {},
        created_at: Time.current
      )

      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data'].pluck('id')).to eq([newer.id, older.id])
      expect(response.parsed_body['data'].first).to include(
        'event_name' => 'pilot.autopilot.completed',
        'payload' => { 'prompt_sha256' => 'abc123' },
        'related_entity_type' => 'Conversation',
        'related_entity_id' => 7
      )
      expect(response.parsed_body['meta']).to include('total_count' => 2)
    end

    it 'returns 403 when Pilot is disabled' do
      account.disable_features!(:pilot)

      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 401 when unauthenticated' do
      get url, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
