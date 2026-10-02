require 'rails_helper'

RSpec.describe 'Campaign Analytics API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, audience: []) }

  before do
    account.enable_features!(:whatsapp_campaign)
    campaign
  end

  def create_recipient(status:, source_id: nil)
    create(:pilot_campaign_recipient, account: account, campaign: campaign, inbox: inbox,
                                      contact: create(:contact, account: account, name: 'Recipient'),
                                      status: status, source_id: source_id)
  end

  describe 'GET metrics' do
    it 'returns aggregate counts' do
      create_recipient(status: :sent, source_id: 'wamid.1')
      create_recipient(status: :delivered, source_id: 'wamid.2')
      create_recipient(status: :read, source_id: 'wamid.3')
      create_recipient(status: :failed, source_id: 'wamid.4')
      create_recipient(status: :skipped)

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/metrics",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(
        'audience' => 5, 'sent' => 4, 'delivered' => 2, 'read' => 1, 'failed' => 1, 'skipped' => 1
      )
      expect(response.parsed_body['status_counts']).to include('queued' => 0, 'read' => 1)
    end

    it 'denies agents' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/metrics",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects non-WhatsApp campaigns' do
      widget_campaign = create(:campaign, account: account)

      get "/api/v1/accounts/#{account.id}/campaigns/#{widget_campaign.display_id}/analytics/metrics",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects cross-account access' do
      create(:campaign, account: create(:account))

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id + 100_000}/analytics/metrics",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET contacts' do
    it 'paginates and filters by status with per-contact outcomes' do
      create_recipient(status: :failed, source_id: 'wamid.f').then do |recipient|
        recipient.update!(error_message: 'window closed', error_code: '131047')
      end
      create_recipient(status: :delivered, source_id: 'wamid.d')

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/contacts",
          headers: administrator.create_new_auth_token,
          params: { status: 'failed' },
          as: :json

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['payload'].length).to eq(1)
      row = json['payload'].first
      expect(row['status']).to eq('failed')
      expect(row['error_message']).to eq('window closed')
      expect(row['error_code']).to eq('131047')
      expect(row['contact']).to include('name' => 'Recipient')
      expect(json['meta']['total_count']).to eq(1)
    end
  end
end
