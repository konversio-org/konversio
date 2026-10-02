# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Company notes API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:company) { create(:company, account: account) }
  let(:member) { create(:contact, company: company, account: account) }
  let(:non_member) { create(:contact, account: account) }

  describe 'GET /api/v1/accounts/{account.id}/companies/{company.id}/notes' do
    it 'returns newest notes across member contacts with contact and author' do
      author = create(:user, account: account)
      create(:note, account: account, contact: member, user: author, content: 'Member note')
      create(:note, account: account, contact: non_member, user: author, content: 'Other note')

      get "/api/v1/accounts/#{account.id}/companies/#{company.id}/notes",
          headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(response).to have_http_status(:success)
      expect(payload.size).to eq(1)
      expect(payload.first['content']).to eq('Member note')
      expect(payload.first['contact']['id']).to eq(member.id)
      expect(payload.first['user']['id']).to eq(author.id)
    end

    it 'caps the notes at 20' do
      create_list(:note, 25, account: account, contact: member)

      get "/api/v1/accounts/#{account.id}/companies/#{company.id}/notes",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].size).to eq(20)
    end
  end
end
