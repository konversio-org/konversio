require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Pilot::BulkActions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/pilot/bulk_actions" }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
    allow(Pilot::UpdateEmbeddingJob).to receive(:perform_later)
  end

  describe 'POST #create' do
    let!(:responses) { create_list(:pilot_assistant_response, 3, assistant: assistant, status: :pending) }
    let(:ids) { responses.map(&:id) }
    let(:valid_attrs) do
      {
        type: 'AssistantResponse',
        ids: ids,
        fields: { status: 'approve' }
      }
    end

    context 'when unauthenticated' do
      it 'returns 401' do
        post base_url, params: valid_attrs, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the autopilot feature is disabled' do
      it 'returns 403' do
        account.disable_features!(:pilot_autopilot)

        post base_url,
             params: valid_attrs,
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when an agent (non-admin) requests the bulk action' do
      it 'returns 403' do
        post base_url,
             params: valid_attrs,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when the type is unsupported' do
      it 'returns 422' do
        post base_url,
             params: valid_attrs.merge(type: 'UnsupportedType'),
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when the fields are invalid' do
      it 'returns 422' do
        post base_url,
             params: valid_attrs.merge(fields: { status: 'reject' }),
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with valid request' do
      it 'bulk approves the responses and schedules embedding updates' do
        expect(Pilot::UpdateEmbeddingJob).to receive(:perform_later).thrice

        post base_url,
             params: valid_attrs,
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:ok)

        responses.each do |res|
          expect(res.reload.status).to eq('approved')
          expect(res.edited).to be(true)
        end

        body = response.parsed_body
        expect(body).to be_an(Array)
        expect(body.size).to eq(3)
        expect(body.map { |r| r['id'] }).to match_array(ids)
      end
    end
  end
end
