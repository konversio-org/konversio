require 'rails_helper'

RSpec.describe Voice::OutboundCallFactory do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:channel) { create(:channel_twilio_sms, :with_phone_number, account: account, phone_number: '+15551239999') }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15550001111') }
  let(:call_sid) { 'CA-outbound-1' }

  before do
    channel.update_column(:voice_enabled, true) # rubocop:disable Rails/SkipsModelValidations
    allow(channel).to receive(:initiate_call).and_return({ call_sid: call_sid })
  end

  def perform_factory(conversation: nil)
    described_class.perform!(
      account: account, inbox: inbox, user: agent, contact: contact, conversation: conversation
    )
  end

  it 'creates an open conversation assigned to the agent plus a ringing outgoing call' do
    call = perform_factory

    expect(call).to be_outgoing
    expect(call.status).to eq('ringing')
    expect(call.accepted_by_agent).to eq(agent)
    expect(call.provider_call_id).to eq(call_sid)
    expect(call.conversation).to be_open
    expect(call.conversation.assignee).to eq(agent)
    expect(call.message).to be_present
  end

  it 'reuses an open conversation and claims it for the caller' do
    inbox.update!(lock_to_single_conversation: false)
    existing = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open)

    call = perform_factory(conversation: existing)

    expect(call.conversation_id).to eq(existing.id)
    expect(existing.reload.assignee).to eq(agent)
  end

  it 'rejects a contact without a phone number' do
    contact.update!(phone_number: nil)

    expect { perform_factory }.to raise_error(ArgumentError, /phone number/i)
  end
end
