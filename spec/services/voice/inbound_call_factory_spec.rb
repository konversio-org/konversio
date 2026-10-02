require 'rails_helper'

RSpec.describe Voice::InboundCallFactory do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_twilio_sms, :with_phone_number, account: account, phone_number: '+15551239999') }
  let(:inbox) { channel.inbox }
  let(:from_number) { '+15550001111' }
  let(:call_sid) { 'CA1234567890abcdef' }

  before { channel.update_column(:voice_enabled, true) } # rubocop:disable Rails/SkipsModelValidations

  def perform_factory(sid: call_sid, caller: nil)
    described_class.perform!(
      inbox: inbox,
      call_sid: sid,
      caller: caller || { source_ids: [from_number], contact_attributes: { name: from_number, phone_number: from_number } }
    )
  end

  it 'creates a contact, open conversation, ringing call and voice_call message', :aggregate_failures do
    call = perform_factory

    expect(call).to be_twilio
    expect(call).to be_incoming
    expect(call.status).to eq('ringing')
    expect(call.conference_sid).to eq("conf_account_#{account.id}_call_#{call.id}")
    expect(call.contact.phone_number).to eq(from_number)
    expect(call.conversation).to be_open
    expect(call.message).to be_present
    expect(call.message.content_type).to eq('voice_call')
    expect(call.message.message_type).to eq('incoming')
    expect(call.conversation.additional_attributes['call_status']).to eq('ringing')
  end

  it 'is idempotent for the same provider call id' do
    first = perform_factory

    second = nil
    expect { second = perform_factory }.not_to change(Call, :count)
    expect(second.id).to eq(first.id)
    expect(Call.where(provider_call_id: call_sid).count).to eq(1)
  end

  it 'reuses the latest non-resolved conversation on the contact inbox' do
    first = perform_factory
    first.conversation.update!(status: :pending)

    second = perform_factory(sid: 'CA-second')

    expect(second.conversation_id).to eq(first.conversation_id)
  end

  it 'reuses the single locked conversation' do
    inbox.update!(lock_to_single_conversation: true)
    first = perform_factory
    first.conversation.update!(status: :resolved)

    second = perform_factory(sid: 'CA-second')

    expect(second.conversation_id).to eq(first.conversation_id)
  end
end
