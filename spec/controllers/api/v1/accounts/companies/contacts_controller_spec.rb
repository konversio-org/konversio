# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Company contacts API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:company) do
    create(:company, name: 'Acme', domain: 'acme.com', description: 'Primary account', account: account,
                     custom_attributes: { 'industry' => 'Manufacturing' })
  end

  describe 'GET /api/v1/accounts/{account.id}/companies/{company.id}/contacts' do
    it 'returns paginated member contacts with linkage context' do
      linked = create(:contact, name: 'Linked Contact', company: company, account: account)
      create(:contact, name: 'Other Contact', account: account)

      get "/api/v1/accounts/#{account.id}/companies/#{company.id}/contacts",
          headers: admin.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(response).to have_http_status(:success)
      expect(body['payload'].pluck('id')).to eq([linked.id])
      expect(body['meta']['total_count']).to eq(1)
      expect(body['payload'].first['company_id']).to eq(company.id)
      expect(body['payload'].first['linked_to_current_company']).to be(true)
      expect(body['payload'].first['company']).to include(
        'id' => company.id,
        'name' => 'Acme',
        'domain' => 'acme.com',
        'custom_attributes' => { 'industry' => 'Manufacturing' }
      )
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/companies/{company.id}/contacts/search' do
    it 'returns matching non-member contacts' do
      other_company = create(:company, name: 'Other Company', account: account)
      linked = create(:contact, name: 'Jane Current', company: company, account: account)
      available = create(:contact, name: 'Jane Available', account: account)
      assigned = create(:contact, name: 'Jane Assigned', company: other_company, account: account)

      get "/api/v1/accounts/#{account.id}/companies/#{company.id}/contacts/search",
          params: { q: 'Jane' }, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(response).to have_http_status(:success)
      expect(payload.pluck('id')).to contain_exactly(available.id, assigned.id)
      expect(payload.pluck('id')).not_to include(linked.id)
      expect(payload.find { |c| c['id'] == assigned.id }['company']).to include(
        'id' => other_company.id, 'name' => 'Other Company'
      )
    end

    it 'rejects a missing query' do
      get "/api/v1/accounts/#{account.id}/companies/#{company.id}/contacts/search",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/companies/{company.id}/contacts' do
    it 'attaches a contact and seeds company activity' do
      contact = create(:contact, name: 'Jane Contact', account: account, last_activity_at: 1.hour.ago,
                                 additional_attributes: { 'city' => 'Berlin' })

      post "/api/v1/accounts/#{account.id}/companies/#{company.id}/contacts",
           params: { contact_id: contact.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(contact.reload.company_id).to eq(company.id)
      expect(contact.additional_attributes).to eq('city' => 'Berlin', 'company_name' => 'Acme')
      expect(company.reload.last_activity_at).to be_within(1.second).of(contact.last_activity_at)
      expect(response.parsed_body['payload']['linked_to_current_company']).to be(true)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/companies/{company.id}/contacts/{id}' do
    it 'detaches the contact and keeps it' do
      contact = create(:contact, name: 'Jane Contact', company: company, account: account,
                                 additional_attributes: { 'company_name' => 'Acme', 'city' => 'Berlin' })

      delete "/api/v1/accounts/#{account.id}/companies/#{company.id}/contacts/#{contact.id}",
             headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(contact.reload.company_id).to be_nil
      expect(contact.additional_attributes).to eq('city' => 'Berlin')
    end
  end
end
