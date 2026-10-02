require 'rails_helper'

RSpec.describe Whatsapp::CallPermissionReplyService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false, validate_provider_config: false,
                              provider_config: { 'api_key' => 'k', 'phone_number_id' => '1', 'source' => 'embedded_signup',
                                                 'calling_enabled' => true })
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, name: 'Ada', phone_number: '+15550001111') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    account.enable_features('channel_voice')
    conversation.update!(
      additional_attributes: {
        'call_permission_request_message_id' => 'wamid.REQUEST',
        'call_permission_requests' => { '15550001111' => { 'call_permission_request_message_id' => 'wamid.REQUEST' } }
      }
    )
  end

  def params_for(response:, context_id: 'wamid.REQUEST')
    {
      entry: [{
        changes: [{
          value: {
            messages: [{
              from: '15550001111',
              interactive: { call_permission_reply: { response: response } },
              context: { id: context_id }
            }]
          }
        }]
      }]
    }
  end

  it 'treats an affirmative reply as granted, clears the request and broadcasts' do
    allow(ActionCable.server).to receive(:broadcast)
    expect { described_class.new(inbox: inbox, params: params_for(response: 'accept')).perform }
      .to have_enqueued_job(Conversations::ActivityMessageJob)

    expect(conversation.reload.additional_attributes['call_permission_request_message_id']).to be_nil
    expect(ActionCable.server).to have_received(:broadcast)
      .with("account_#{account.id}", hash_including(event: 'voice_call.permission_granted'))
  end

  it 'ignores a negative reply' do
    described_class.new(inbox: inbox, params: params_for(response: 'reject')).perform

    expect(conversation.reload.additional_attributes['call_permission_request_message_id']).to eq('wamid.REQUEST')
  end

  it 'ignores a reply to an unknown request' do
    described_class.new(inbox: inbox, params: params_for(response: 'accept', context_id: 'wamid.OTHER')).perform

    expect(conversation.reload.additional_attributes['call_permission_request_message_id']).to eq('wamid.REQUEST')
  end
end
