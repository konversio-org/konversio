require 'rails_helper'

RSpec.describe 'WhatsApp Manual Setup API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  let(:preview_payload) do
    {
      verified_name: 'Acme',
      display_phone_number: '+15551234567',
      phone_number_id: 'phone-1',
      waba_id: 'waba-1',
      template_access: true,
      suggested_inbox_name: 'Acme WhatsApp'
    }
  end

  describe 'POST /api/v1/accounts/{account.id}/whatsapp/manual/preview' do
    it 'returns unauthorized for unauthenticated users' do
      post "/api/v1/accounts/#{account.id}/whatsapp/manual/preview"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the credential preview' do
      validation = instance_double(Whatsapp::ManualSetupValidationService, perform: preview_payload)
      allow(Whatsapp::ManualSetupValidationService).to receive(:new).and_return(validation)

      post "/api/v1/accounts/#{account.id}/whatsapp/manual/preview",
           params: { waba_id: 'waba-1', phone_number_id: 'phone-1', access_token: 'token' },
           headers: administrator.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(preview_payload.stringify_keys)
    end

    it 'returns unprocessable entity when validation fails' do
      validation = instance_double(Whatsapp::ManualSetupValidationService)
      allow(validation).to receive(:perform).and_raise(ArgumentError, 'invalid credentials')
      allow(Whatsapp::ManualSetupValidationService).to receive(:new).and_return(validation)

      post "/api/v1/accounts/#{account.id}/whatsapp/manual/preview",
           params: { waba_id: 'waba-1', phone_number_id: 'phone-1', access_token: 'token' },
           headers: administrator.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq('invalid credentials')
    end

    it 'returns unauthorized for agents' do
      post "/api/v1/accounts/#{account.id}/whatsapp/manual/preview",
           params: { waba_id: 'waba-1', phone_number_id: 'phone-1', access_token: 'token' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/whatsapp/manual/connect' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                                provider_config: { 'api_key' => 'token', 'phone_number_id' => 'phone-1',
                                                   'business_account_id' => 'waba-1', 'source' => 'manual_setup_v2' })
    end
    let(:inbox) { channel.inbox }

    it 'creates the channel and inbox and reports webhook success' do
      setup = instance_double(Whatsapp::ManualSetupService, channel: channel, webhook_setup?: true, webhook_error: nil)
      allow(setup).to receive(:perform).and_return(setup)
      allow(Whatsapp::ManualSetupService).to receive(:new).and_return(setup)

      post "/api/v1/accounts/#{account.id}/whatsapp/manual/connect",
           params: { waba_id: 'waba-1', phone_number_id: 'phone-1', access_token: 'token' },
           headers: administrator.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        'id' => inbox.id,
        'name' => inbox.name,
        'number_access' => true,
        'template_access' => true,
        'webhook_setup' => true
      )
    end

    it 'reports a webhook failure without failing the connect' do
      setup = instance_double(Whatsapp::ManualSetupService, channel: channel, webhook_setup?: false, webhook_error: 'webhook boom')
      allow(setup).to receive(:perform).and_return(setup)
      allow(Whatsapp::ManualSetupService).to receive(:new).and_return(setup)

      post "/api/v1/accounts/#{account.id}/whatsapp/manual/connect",
           params: { waba_id: 'waba-1', phone_number_id: 'phone-1', access_token: 'token' },
           headers: administrator.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['webhook_setup']).to be false
      expect(response.parsed_body['webhook_error']).to eq('webhook boom')
    end
  end

  describe 'webhook status and registration' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                                provider_config: { 'api_key' => 'token', 'phone_number_id' => 'phone-1',
                                                   'business_account_id' => 'waba-1', 'source' => 'manual_setup_v2' })
    end
    let(:inbox) { channel.inbox }
    let(:status_payload) { { callback_configured: true, callback_verified: true, subscription_verified: true } }

    it 'reports the webhook status for a manual inbox' do
      status = instance_double(Whatsapp::ManualWebhookStatusService, perform: status_payload)
      allow(Whatsapp::ManualWebhookStatusService).to receive(:new).and_return(status)

      get "/api/v1/accounts/#{account.id}/whatsapp/manual/#{inbox.id}/webhook_status",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(status_payload.stringify_keys)
    end

    it 'returns not found for an inbox not created by manual setup' do
      embedded = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                                           provider_config: { 'api_key' => 'token', 'source' => 'embedded_signup' })

      get "/api/v1/accounts/#{account.id}/whatsapp/manual/#{embedded.inbox.id}/webhook_status",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'retries webhook registration and returns the new status' do
      webhook_setup = instance_double(Whatsapp::WebhookSetupService, registration_error: nil)
      allow(webhook_setup).to receive(:perform)
      allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(webhook_setup)

      status = instance_double(Whatsapp::ManualWebhookStatusService, perform: status_payload)
      allow(Whatsapp::ManualWebhookStatusService).to receive(:new).and_return(status)
      allow(channel).to receive(:reload).and_return(channel)

      post "/api/v1/accounts/#{account.id}/whatsapp/manual/#{inbox.id}/setup_webhook",
           headers: administrator.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(status_payload.stringify_keys)
    end
  end
end
