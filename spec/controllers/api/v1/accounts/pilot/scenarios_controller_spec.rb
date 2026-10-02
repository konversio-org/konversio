# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Pilot::Scenarios', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/pilot/assistants/#{assistant.id}/scenarios" }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
  end

  describe 'GET index' do
    it 'returns enabled and disabled scenarios with their enabled flags' do
      create(:pilot_scenario, assistant: assistant, account: account, enabled: true)
      create(:pilot_scenario, assistant: assistant, account: account, enabled: false)

      get base_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.length).to eq(2)
      expect(response.parsed_body.pluck('enabled')).to contain_exactly(true, false)
    end
  end

  describe 'PATCH update' do
    let!(:scenario) { create(:pilot_scenario, assistant: assistant, account: account, enabled: true) }

    it 'toggles enabled without touching the content' do
      patch "#{base_url}/#{scenario.id}",
            params: { scenario: { enabled: false } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      scenario.reload
      expect(scenario.enabled).to be(false)
      expect(scenario.title).to be_present
      expect(scenario.description).to be_present
      expect(scenario.instruction).to be_present
    end

    it 're-enables a disabled scenario' do
      scenario.update!(enabled: false)

      patch "#{base_url}/#{scenario.id}",
            params: { scenario: { enabled: true } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(scenario.reload.enabled).to be(true)
    end
  end
end
