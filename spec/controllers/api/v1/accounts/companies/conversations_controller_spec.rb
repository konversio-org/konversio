# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Company conversations API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:company) { create(:company, account: account) }
  let(:member) { create(:contact, company: company, account: account) }
  let(:non_member) { create(:contact, account: account) }

  describe 'GET /api/v1/accounts/{account.id}/companies/{company.id}/conversations' do
    it 'returns only conversations of member contacts, newest first' do
      create(:conversation, account: account, inbox: inbox, contact: member, last_activity_at: 2.hours.ago)
      newer = create(:conversation, account: account, inbox: inbox, contact: member, last_activity_at: 1.minute.ago)
      create(:conversation, account: account, inbox: inbox, contact: non_member)

      get "/api/v1/accounts/#{account.id}/companies/#{company.id}/conversations",
          headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(response).to have_http_status(:success)
      expect(payload.size).to eq(2)
      expect(payload.first['id']).to eq(newer.display_id)
    end

    it 'caps the history at 20 conversations' do
      create_list(:conversation, 25, account: account, inbox: inbox, contact: member)

      get "/api/v1/accounts/#{account.id}/companies/#{company.id}/conversations",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].size).to eq(20)
    end
  end
end
