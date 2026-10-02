require 'rails_helper'

RSpec.describe Whatsapp::IdentitySourceIdOrderer do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:phone_source_id) { '919745786257' }
  let(:bsuid) { 'IN.2081978709342942' }

  def create_history(source_id)
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: source_id)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  it 'starts a brand-new mixed caller on the phone number' do
    ordered = described_class.new(inbox: inbox, phone_source_id: phone_source_id, source_ids: [bsuid]).perform

    expect(ordered).to eq([phone_source_id, bsuid])
  end

  it 'lets phone history win for a mixed payload' do
    create_history(phone_source_id)

    ordered = described_class.new(inbox: inbox, phone_source_id: phone_source_id, source_ids: [bsuid]).perform

    expect(ordered).to eq([phone_source_id, bsuid])
  end

  it 'lets BSUID history win when the contact was first seen BSUID-only' do
    create_history(bsuid)

    ordered = described_class.new(inbox: inbox, phone_source_id: phone_source_id, source_ids: [bsuid]).perform

    expect(ordered).to eq([bsuid, phone_source_id])
  end

  it 'ignores history for non-addressable providers' do
    default_channel = create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false)
    create(:contact_inbox, inbox: default_channel.inbox, contact: contact, source_id: bsuid)
    create(:conversation, account: account, inbox: default_channel.inbox, contact: contact,
                          contact_inbox: default_channel.inbox.contact_inboxes.first)

    ordered = described_class.new(inbox: default_channel.inbox, phone_source_id: phone_source_id, source_ids: [bsuid]).perform

    expect(ordered).to eq([phone_source_id, bsuid])
  end
end
