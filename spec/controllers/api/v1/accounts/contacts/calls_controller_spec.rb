require 'rails_helper'

RSpec.describe 'Contacts Calls API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:channel) { create(:channel_twilio_sms, :with_phone_number, account: account, phone_number: '+15551239999') }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15550001111') }
  let(:headers) { agent.create_new_auth_token }

  before do
    channel.update_column(:voice_enabled, true) # rubocop:disable Rails/SkipsModelValidations
    create(:inbox_member, user: agent, inbox: inbox)
    allow_any_instance_of(Channel::TwilioSms).to receive(:initiate_call).and_return({ call_sid: 'CA-outbound' }) # rubocop:disable RSpec/AnyInstance
  end

  def create_call(conversation_id: nil)
    post "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/call",
         params: { inbox_id: inbox.id, conversation_id: conversation_id }.compact,
         headers: headers, as: :json
  end

  it 'creates an open conversation assigned to the agent and a ringing call' do
    create_call

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    call = Call.last
    expect(call.provider_call_id).to eq('CA-outbound')
    expect(call.conversation.assignee).to eq(agent)
    expect(body['call_sid']).to eq('CA-outbound')
    expect(body['conversation_id']).to eq(call.conversation.display_id)
  end

  it 'reuses an open conversation for the same inbox and contact' do
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open)

    create_call(conversation_id: conversation.display_id)

    expect(Call.last.conversation_id).to eq(conversation.id)
  end

  it 'does not reuse a resolved conversation' do
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, status: :resolved)

    create_call(conversation_id: conversation.display_id)

    expect(Call.last.conversation_id).not_to eq(conversation.id)
  end

  it 'rejects a contact without a phone number' do
    contact.update!(phone_number: nil)

    create_call

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Call.count).to eq(0)
  end
end
