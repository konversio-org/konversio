require 'rails_helper'

RSpec.describe Campaigns::ReconcileRecipientStatusJob do
  let(:account) { create(:account) }
  let(:campaign) { create(:campaign, account: account) }
  let(:inbox) { campaign.inbox }
  let(:recipient) do
    create(:pilot_campaign_recipient, account: account, campaign: campaign, contact: create(:contact, account: account),
                                      inbox: inbox, status: :sent, source_id: 'wamid.match')
  end

  it 'applies the delivery status to the matching recipient' do
    recipient

    described_class.perform_now(inbox.id, { 'id' => 'wamid.match', 'status' => 'delivered', 'timestamp' => Time.current.to_i })

    expect(recipient.reload).to be_delivered
  end

  it 'retries with backoff when the recipient is not yet visible' do
    expect do
      described_class.perform_now(inbox.id, { 'id' => 'wamid.missing', 'status' => 'read' })
    end.to have_enqueued_job(described_class).at_least(:once)
  end

  it 'reconciles the recipient synchronously from the webhook status path' do
    account.enable_features!(:whatsapp_campaign)
    recipient
    params = {
      entry: [{
        changes: [{ value: { statuses: [{ id: 'wamid.match', status: 'delivered', timestamp: Time.current.to_i }] } }]
      }]
    }

    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params.with_indifferent_access).perform

    expect(recipient.reload).to be_delivered
  end
end
