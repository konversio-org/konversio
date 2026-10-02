require 'rails_helper'

RSpec.describe Whatsapp::CallService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false, validate_provider_config: false,
                              provider_config: { 'api_key' => 'k', 'phone_number_id' => '1', 'business_account_id' => '2',
                                                 'source' => 'embedded_signup', 'calling_enabled' => true })
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15550001111') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:call) { create(:call, account: account, inbox: inbox, conversation: conversation, contact: contact, provider: :whatsapp) }
  let(:provider) do
    instance_double(Whatsapp::Providers::WhatsappCloudService, pre_accept_call: true, accept_call: true, reject_call: true, terminate_call: true)
  end

  before do
    account.enable_features('channel_voice')
    allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider) # rubocop:disable RSpec/AnyInstance
  end

  def service(sdp_answer: 'answer-sdp')
    described_class.new(call: call, agent: agent, sdp_answer: sdp_answer)
  end

  describe '#accept' do
    it 'requires an sdp answer' do
      expect { service(sdp_answer: nil).accept }.to raise_error(Voice::CallErrors::CallFailed)
    end

    it 'raises a distinct error when already accepted' do
      call.update!(status: 'in_progress')

      expect { service.accept }.to raise_error(Voice::CallErrors::AlreadyAccepted)
    end

    it 'raises a distinct error when already ended' do
      call.update!(status: 'completed')

      expect { service.accept }.to raise_error(Voice::CallErrors::CallAlreadyEnded)
    end

    it 'forwards the answer, transitions, claims the conversation and broadcasts' do
      allow(ActionCable.server).to receive(:broadcast)

      service.accept

      expect(provider).to have_received(:accept_call)
      expect(call.reload.status).to eq('in_progress')
      expect(call.accepted_by_agent).to eq(agent)
      expect(call.conversation.reload.assignee).to eq(agent)
      expect(call.conversation.additional_attributes['call_status']).to eq('in-progress')
      expect(ActionCable.server).to have_received(:broadcast).with("account_#{account.id}", hash_including(event: 'voice_call.accepted'))
    end
  end

  describe '#reject' do
    it 'finalizes the call as rejected' do
      allow(ActionCable.server).to receive(:broadcast)

      service.reject

      expect(call.reload.status).to eq('rejected')
      expect(call.end_reason).to eq('agent_rejected')
    end
  end

  describe '#terminate' do
    it 'completes an in-progress call with a locally computed duration' do
      call.update!(status: 'in_progress', started_at: 30.seconds.ago)
      allow(ActionCable.server).to receive(:broadcast)

      service.terminate

      expect(call.reload.status).to eq('completed')
      expect(call.end_reason).to eq('agent_hangup')
      expect(call.duration_seconds).to be_within(2).of(30)
    end

    it 'maps a ringing call to no_answer' do
      allow(ActionCable.server).to receive(:broadcast)

      service.terminate

      expect(call.reload.status).to eq('no_answer')
      expect(call.end_reason).to eq('agent_hangup')
    end

    it 'aborts the local transition when the provider fails' do
      allow(provider).to receive(:terminate_call).and_raise(StandardError, 'boom')

      expect { service.terminate }.to raise_error(Voice::CallErrors::CallFailed)
      expect(call.reload.status).to eq('ringing')
    end
  end
end
