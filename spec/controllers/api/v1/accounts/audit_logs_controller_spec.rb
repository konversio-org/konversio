require 'rails_helper'

RSpec.describe 'Audit Logs API', type: :request do
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }

  before { AuditLog.delete_all }

  def auth_headers(user)
    user.create_new_auth_token
  end

  def request_logs(params = {})
    get "/api/v1/accounts/#{account.id}/audit_logs",
        params: params,
        headers: auth_headers(admin),
        as: :json
    response.parsed_body
  end

  def create_entry(**attrs)
    AuditLog.create!({ auditable: inbox, associated: account, action: 'update' }.merge(attrs))
  end

  describe 'authorization' do
    it 'rejects an unauthenticated request' do
      get "/api/v1/accounts/#{account.id}/audit_logs", as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects an agent' do
      agent = create(:user, account: account, role: :agent)

      get "/api/v1/accounts/#{account.id}/audit_logs", headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'feature gating' do
    it 'returns an empty page and logs a warning when the feature is disabled' do
      create_entry
      allow(Rails.logger).to receive(:warn)

      body = request_logs

      expect(response).to have_http_status(:success)
      expect(body['audit_logs']).to eq([])
      expect(body.slice('current_page', 'per_page', 'total_entries')).to eq(
        'current_page' => 1, 'per_page' => 25, 'total_entries' => 0
      )
      expect(Rails.logger).to have_received(:warn).with(/Audit logs are disabled/)
    end

    it 'returns only entries associated with the account' do
      account.enable_features!(:audit_logs)
      AuditLog.delete_all
      ours = create_entry
      foreign_account = create(:account)
      create_entry(auditable: create(:inbox, account: foreign_account), associated: foreign_account)

      expect(request_logs['audit_logs'].pluck('id')).to eq([ours.id])
    end
  end

  describe 'pagination' do
    before do
      account.enable_features!(:audit_logs)
      AuditLog.delete_all
    end

    it 'paginates at 25 per page' do
      create_list(:inbox, 30, account: account)

      body = request_logs
      expect(body['audit_logs'].length).to eq(25)
      expect(body.slice('current_page', 'per_page', 'total_entries')).to eq(
        'current_page' => 1, 'per_page' => 25, 'total_entries' => 30
      )

      second_page = request_logs(page: 2)
      expect(second_page['audit_logs'].length).to eq(5)
      expect(second_page['current_page']).to eq(2)
    end
  end

  describe 'entry payload' do
    before { account.enable_features!(:audit_logs) }

    it 'redacts message deletion entries but keeps the display number' do
      message = create(:message, account: account, content: 'original body')
      AuditLog.create!(
        auditable: message,
        associated: account,
        action: 'destroy',
        audited_changes: { 'content' => 'original body', 'display_id' => 4321 }
      )

      entry = request_logs['audit_logs'].find { |log| log['auditable_type'] == 'Message' }
      expect(entry['auditable']).to be_nil
      expect(entry['audited_changes']).not_to have_key('content')
      expect(entry['audited_changes']['display_id']).to eq(4321)
    end
  end

  describe 'filtering' do
    let!(:jane) { create(:user, name: 'Jane Agent', email: 'jane@example.com', account: account) }
    let!(:john) { create(:user, name: 'John Smith', email: 'john@acme.com', account: account) }

    before do
      account.enable_features!(:audit_logs)
      AuditLog.delete_all
    end

    def inbox_entry
      create_entry(user: jane, created_at: 10.days.ago)
    end

    def sign_in_entry
      create_entry(auditable: john, user: john, action: 'sign_in', created_at: 2.days.ago)
    end

    it 'filters by auditable type' do
      inbox_entry
      sign_in_entry

      types = request_logs(types: ['User'])['audit_logs'].pluck('auditable_type').uniq
      expect(types).to eq(['User'])
    end

    it 'ignores non-string type values' do
      inbox_entry
      sign_in_entry

      expect(request_logs(types: { foo: 'bar' })['audit_logs'].length).to eq(2)
    end

    it 'searches by email fragment' do
      entry = inbox_entry
      sign_in_entry

      expect(request_logs(q: 'jane@exam')['audit_logs'].pluck('id')).to eq([entry.id])
    end

    it 'searches by the linked user name' do
      inbox_entry
      sign_in = sign_in_entry

      expect(request_logs(q: 'smith')['audit_logs'].pluck('id')).to eq([sign_in.id])
    end

    it 'treats LIKE metacharacters in the search term literally' do
      literal = create_entry(user: create(:user, account: account, email: '100%_sure@example.com'))
      create_entry(user: create(:user, account: account, email: '10023sure@example.com'))

      expect(request_logs(q: '100%_')['audit_logs'].pluck('id')).to eq([literal.id])
    end

    it 'applies the inclusive date window' do
      create_entry(created_at: 3.days.ago.beginning_of_day)
      day_two = create_entry(created_at: 2.days.ago.beginning_of_day)
      create_entry(created_at: 1.day.ago.beginning_of_day)

      params = { since: 2.days.ago.beginning_of_day.to_i, until: 2.days.ago.end_of_day.to_i }
      expect(request_logs(params)['audit_logs'].pluck('id')).to eq([day_two.id])
    end

    it 'ignores unparseable and out-of-range epoch values' do
      inbox_entry
      sign_in_entry

      body = request_logs(since: 'not-a-number', until: 9_999_999_999_999)
      expect(response).to have_http_status(:success)
      expect(body['audit_logs'].length).to eq(2)
    end

    it 'ignores non-string search values' do
      inbox_entry
      sign_in_entry

      expect(request_logs(q: ['not-a-string'])['audit_logs'].length).to eq(2)
    end
  end

  describe 'sorting' do
    before do
      account.enable_features!(:audit_logs)
      AuditLog.delete_all
    end

    it 'defaults to newest first' do
      older = create_entry(created_at: 2.days.ago)
      newer = create_entry(created_at: 1.day.ago)

      expect(request_logs['audit_logs'].pluck('id')).to eq([newer.id, older.id])
    end

    it 'sorts oldest first when requested' do
      older = create_entry(created_at: 2.days.ago)
      newer = create_entry(created_at: 1.day.ago)

      expect(request_logs(sort: 'asc')['audit_logs'].pluck('id')).to eq([older.id, newer.id])
    end
  end

  describe 'IP privacy' do
    before do
      account.enable_features!(:audit_logs)
      AuditLog.delete_all
      create_entry(remote_address: '203.0.113.42', city: 'Berlin', country: 'Germany')
    end

    it 'masks the address and serves the resolved location by default' do
      entry = request_logs['audit_logs'].last

      expect(entry['remote_address']).to eq('203.0.113.x')
      expect(entry['location']).to eq('Berlin, Germany')
    end

    it 'serves the full address and omits the location when the flag is on' do
      account.enable_features!(:audit_log_ip_address)

      entry = request_logs['audit_logs'].last
      expect(entry['remote_address']).to eq('203.0.113.42')
      expect(entry).not_to have_key('location')
    end
  end
end
