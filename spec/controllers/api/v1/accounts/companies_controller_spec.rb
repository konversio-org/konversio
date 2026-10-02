# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Companies API', type: :request do
  let(:account) { create(:account) }

  describe 'GET /api/v1/accounts/{account.id}/companies' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/companies"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }
      let!(:company1) { create(:company, name: 'Company 1', account: account) }
      let!(:company2) { create(:company, account: account) }

      it 'returns all companies' do
        get "/api/v1/accounts/#{account.id}/companies", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        payload = response.parsed_body['payload']
        expect(payload.size).to eq(2)
        expect(payload.map { |c| c['name'] }).to contain_exactly(company1.name, company2.name)
      end

      it 'paginates companies 25 per page' do
        create_list(:company, 30, account: account)

        get "/api/v1/accounts/#{account.id}/companies", params: { page: 1 }, headers: admin.create_new_auth_token, as: :json

        body = response.parsed_body
        expect(response).to have_http_status(:success)
        expect(body['payload'].size).to eq(25)
        expect(body['meta']['total_count']).to eq(32)
        expect(body['meta']['page']).to eq(1)
      end

      it 'returns the second page' do
        create_list(:company, 30, account: account)

        get "/api/v1/accounts/#{account.id}/companies", params: { page: 2 }, headers: admin.create_new_auth_token, as: :json

        body = response.parsed_body
        expect(body['payload'].size).to eq(7)
        expect(body['meta']['page']).to eq(2)
      end

      it 'returns contacts_count' do
        company = create(:company, name: 'With Contacts', account: account)
        create_list(:contact, 5, company: company, account: account)

        get "/api/v1/accounts/#{account.id}/companies", headers: admin.create_new_auth_token, as: :json

        data = response.parsed_body['payload'].find { |c| c['id'] == company.id }
        expect(data['contacts_count']).to eq(5)
      end

      it 'does not leak companies from other accounts' do
        other_account = create(:account)
        create(:company, name: 'Other Account Company', account: other_account)
        create(:company, name: 'My Company', account: account)

        get "/api/v1/accounts/#{account.id}/companies", headers: admin.create_new_auth_token, as: :json

        names = response.parsed_body['payload'].map { |c| c['name'] }
        expect(names).not_to include('Other Account Company')
        expect(names).to contain_exactly(company1.name, company2.name, 'My Company')
      end

      it 'sorts by contacts_count ascending' do
        five = create(:company, name: 'Five', account: account)
        two = create(:company, name: 'Two', account: account)
        ten = create(:company, name: 'Ten', account: account)
        create_list(:contact, 5, company: five, account: account)
        create_list(:contact, 2, company: two, account: account)
        create_list(:contact, 10, company: ten, account: account)

        get "/api/v1/accounts/#{account.id}/companies", params: { sort: 'contacts_count' }, headers: admin.create_new_auth_token, as: :json

        ids = response.parsed_body['payload'].map { |c| c['id'] }
        expect(ids.index(two.id)).to be < ids.index(five.id)
        expect(ids.index(five.id)).to be < ids.index(ten.id)
      end

      it 'sorts by contacts_count descending' do
        five = create(:company, name: 'Five', account: account)
        two = create(:company, name: 'Two', account: account)
        ten = create(:company, name: 'Ten', account: account)
        create_list(:contact, 5, company: five, account: account)
        create_list(:contact, 2, company: two, account: account)
        create_list(:contact, 10, company: ten, account: account)

        get "/api/v1/accounts/#{account.id}/companies", params: { sort: '-contacts_count' }, headers: admin.create_new_auth_token, as: :json

        ids = response.parsed_body['payload'].map { |c| c['id'] }
        expect(ids.index(ten.id)).to be < ids.index(five.id)
        expect(ids.index(five.id)).to be < ids.index(two.id)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/companies/search' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'rejects a missing query' do
      get "/api/v1/accounts/#{account.id}/companies/search", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Specify search string with parameter q')
    end

    it 'searches by name and domain case-insensitively' do
      create(:company, name: 'Acme Corp', domain: 'acme.com', account: account)
      create(:company, name: 'Tech Solutions', domain: 'tech.com', account: account)
      create(:company, name: 'Global Inc', domain: 'global.com', account: account)

      get "/api/v1/accounts/#{account.id}/companies/search", params: { q: 'ACME' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].map { |c| c['name'] }).to eq(['Acme Corp'])

      get "/api/v1/accounts/#{account.id}/companies/search", params: { q: 'global.com' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].map { |c| c['name'] }).to eq(['Global Inc'])
    end

    it 'returns an empty payload with empty meta when nothing matches' do
      create(:company, name: 'Acme Corp', account: account)

      get "/api/v1/accounts/#{account.id}/companies/search", params: { q: 'nope' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to eq([])
      expect(response.parsed_body['meta']['total_count']).to eq(0)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/companies/{id}' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:company) { create(:company, account: account) }

    it 'returns the company and its custom attributes' do
      company.update!(custom_attributes: { 'plan' => 'enterprise' })

      get "/api/v1/accounts/#{account.id}/companies/#{company.id}", headers: admin.create_new_auth_token, as: :json

      body = response.parsed_body['payload']
      expect(body['id']).to eq(company.id)
      expect(body['custom_attributes']).to eq('plan' => 'enterprise')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/companies' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'creates a company' do
      expect do
        post "/api/v1/accounts/#{account.id}/companies",
             params: { company: { name: 'New Company', domain: 'newcompany.com', description: 'A new company' } },
             headers: admin.create_new_auth_token, as: :json
      end.to change(Company, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to include('name' => 'New Company', 'domain' => 'newcompany.com')
    end

    it 'rejects invalid params' do
      post "/api/v1/accounts/#{account.id}/companies",
           params: { company: { name: '' } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/companies/{id}' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:company) { create(:company, account: account) }

    it 'updates the company' do
      patch "/api/v1/accounts/#{account.id}/companies/#{company.id}",
            params: { company: { name: 'Updated', domain: 'updated.com' } },
            headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to include('name' => 'Updated', 'domain' => 'updated.com')
    end

    it 'merges custom attributes instead of replacing them' do
      company.update!(custom_attributes: { 'plan' => 'startup', 'region' => 'us' })

      patch "/api/v1/accounts/#{account.id}/companies/#{company.id}",
            params: { company: { custom_attributes: { 'plan' => 'enterprise' } } },
            headers: admin.create_new_auth_token, as: :json

      expect(company.reload.custom_attributes).to eq('plan' => 'enterprise', 'region' => 'us')
      expect(response.parsed_body['payload']['custom_attributes']).to eq('plan' => 'enterprise', 'region' => 'us')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/companies/{id}/destroy_custom_attributes' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:company) { create(:company, account: account, custom_attributes: { 'plan' => 'enterprise', 'region' => 'us' }) }

    it 'removes the requested custom attribute keys' do
      post "/api/v1/accounts/#{account.id}/companies/#{company.id}/destroy_custom_attributes",
           params: { custom_attributes: ['plan'] },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(company.reload.custom_attributes).to eq('region' => 'us')
      expect(response.parsed_body['payload']['custom_attributes']).to eq('region' => 'us')
    end

    it 'rejects a non-array value' do
      post "/api/v1/accounts/#{account.id}/companies/#{company.id}/destroy_custom_attributes",
           params: { custom_attributes: 'plan' },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/companies/{id}/avatar' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:company) { create(:company, account: account) }

    before do
      company.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
    end

    it 'detaches the avatar and keeps the company' do
      delete "/api/v1/accounts/#{account.id}/companies/#{company.id}/avatar",
             headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(company.reload.avatar.attached?).to be(false)
      expect(response.parsed_body['payload']['avatar_url']).to be_blank
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/companies/{id}' do
    let(:company) { create(:company, account: account) }

    it 'enqueues deletion for an administrator' do
      admin = create(:user, account: account, role: :administrator)

      expect do
        delete "/api/v1/accounts/#{account.id}/companies/#{company.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Companies::DeleteJob).with(company_id: company.id)

      expect(response).to have_http_status(:ok)
    end

    it 'rejects a regular agent' do
      agent = create(:user, account: account, role: :agent)

      delete "/api/v1/accounts/#{account.id}/companies/#{company.id}",
             headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
