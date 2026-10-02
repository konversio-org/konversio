require 'rails_helper'

RSpec.describe 'Twilio Voice webhooks', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_twilio_sms, :with_phone_number, account: account, phone_number: '+15551239999') }
  let(:inbox) { channel.inbox }
  let(:phone) { channel.phone_number.delete_prefix('+') }

  before { channel.update_column(:voice_enabled, true) } # rubocop:disable Rails/SkipsModelValidations

  describe 'POST /twilio/voice/call/:phone' do
    it 'refuses a non-voice number with not found' do
      channel.update_column(:voice_enabled, false) # rubocop:disable Rails/SkipsModelValidations

      post "/twilio/voice/call/#{phone}", params: { CallSid: 'CA1', From: '+15550001111', Direction: 'inbound' }

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects an inbound caller when inbound calls are disabled' do
      channel.update!(provider_config: { 'inbound_calls_enabled' => false })

      expect do
        post "/twilio/voice/call/#{phone}",
             params: { CallSid: 'CA-reject', From: '+15550001111', To: channel.phone_number, Direction: 'inbound' }
      end.not_to change(Call, :count)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<Reject')
    end

    it 'bridges an inbound caller into a conference' do
      post "/twilio/voice/call/#{phone}",
           params: { CallSid: 'CA-inbound', From: '+15550001111', To: channel.phone_number, Direction: 'inbound' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<Conference')
      expect(response.body).to include('record="record-from-start"')
      expect(response.body).to include('participantLabel="contact"')
      expect(Call.find_by(provider_call_id: 'CA-inbound')).to be_present
    end
  end

  describe 'POST /twilio/voice/status/:phone' do
    it 'applies the reported status to the call' do
      call = create(:call, account: account, inbox: inbox, provider: :twilio, provider_call_id: 'CA-status', status: 'ringing')

      post "/twilio/voice/status/#{phone}", params: { CallSid: call.provider_call_id, CallStatus: 'in-progress' }

      expect(response).to have_http_status(:no_content)
      expect(call.reload.status).to eq('in_progress')
    end
  end

  describe 'POST /twilio/voice/conference_status/:phone' do
    it 'ignores unknown conference events' do
      call = create(:call, account: account, inbox: inbox, provider: :twilio, provider_call_id: 'CA-conf', status: 'ringing')

      post "/twilio/voice/conference_status/#{phone}",
           params: { CallSid: call.provider_call_id, FriendlyName: "conf_account_#{account.id}_call_#{call.id}",
                     StatusCallbackEvent: 'participant-mute' }

      expect(response).to have_http_status(:no_content)
      expect(call.reload.status).to eq('ringing')
    end

    it 'processes a participant-join event' do
      agent = create(:user, account: account)
      call = create(:call, account: account, inbox: inbox, provider: :twilio, provider_call_id: 'CA-conf2', status: 'ringing')
      allow(ActionCable.server).to receive(:broadcast)

      post "/twilio/voice/conference_status/#{phone}",
           params: { CallSid: call.provider_call_id, FriendlyName: "conf_account_#{account.id}_call_#{call.id}",
                     StatusCallbackEvent: 'participant-join', ParticipantLabel: "agent-#{agent.id}-account-#{account.id}" }

      expect(call.reload.status).to eq('in_progress')
      expect(call.accepted_by_agent_id).to eq(agent.id)
    end
  end
end
