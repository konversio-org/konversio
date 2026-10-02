require 'rails_helper'

RSpec.describe Pilot::CampaignRecipient do
  let(:account) { create(:account) }
  let(:campaign) { create(:campaign, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:recipient) { create(:pilot_campaign_recipient, account: account, campaign: campaign, contact: contact, inbox: campaign.inbox) }

  describe 'validations' do
    it 'allows one recipient per campaign and contact' do
      recipient
      duplicate = build(:pilot_campaign_recipient, account: account, campaign: campaign, contact: contact)

      expect(duplicate).not_to be_valid
    end

    it 'requires a unique source id when present' do
      recipient.update!(source_id: 'wamid.abc')
      duplicate = build(:pilot_campaign_recipient, account: account, campaign: campaign, contact: create(:contact, account: account),
                                                   source_id: 'wamid.abc')

      expect(duplicate).not_to be_valid
    end
  end

  describe '#mark_sent!' do
    it 'records the provider identifier, timestamp and content' do
      recipient.mark_sent!('wamid.abc', content: 'rendered body')

      expect(recipient.reload).to be_sent
      expect(recipient.source_id).to eq('wamid.abc')
      expect(recipient.sent_at).to be_present
      expect(recipient.message_content).to eq('rendered body')
    end
  end

  describe '#mark_skipped!' do
    it 'records the reason' do
      recipient.mark_skipped!('No destination available')

      expect(recipient.reload).to be_skipped
      expect(recipient.error_message).to eq('No destination available')
    end
  end

  describe '#mark_failed!' do
    it 'records structured error details' do
      recipient.mark_failed!(message: 'provider rejected', code: 131_026, title: 'Re-engagement')

      expect(recipient.reload).to be_failed
      expect(recipient.failed_at).to be_present
      expect(recipient.error_code).to eq('131026')
      expect(recipient.error_title).to eq('Re-engagement')
      expect(recipient.error_message).to eq('provider rejected')
    end
  end

  describe '#apply_whatsapp_status!' do
    it 'moves sent -> delivered -> read recording both timestamps' do
      recipient.mark_sent!('wamid.abc')

      recipient.apply_whatsapp_status!({ status: 'delivered', timestamp: 10.minutes.ago.to_i })
      recipient.apply_whatsapp_status!({ status: 'read', timestamp: 5.minutes.ago.to_i })

      expect(recipient.reload).to be_read
      expect(recipient.delivered_at).to be_present
      expect(recipient.read_at).to be_present
    end

    it 'does not downgrade read to delivered but backfills delivered_at' do
      recipient.update!(status: :read, read_at: Time.current)

      recipient.apply_whatsapp_status!({ status: 'delivered', timestamp: 3.minutes.ago.to_i })

      expect(recipient.reload).to be_read
      expect(recipient.delivered_at).to be_present
    end

    it 'does not downgrade delivered to sent' do
      recipient.update!(status: :delivered, delivered_at: Time.current)

      recipient.apply_whatsapp_status!({ status: 'sent', timestamp: Time.current.to_i })

      expect(recipient.reload).to be_delivered
    end

    it 'ignores a failure that arrives after delivery' do
      recipient.update!(status: :delivered, delivered_at: Time.current)

      recipient.apply_whatsapp_status!({ status: 'failed', errors: [{ code: 1, title: 'x' }] })

      expect(recipient.reload).to be_delivered
    end

    it 'records a failure before delivery with provider details' do
      recipient.mark_sent!('wamid.abc')

      recipient.apply_whatsapp_status!(
        { status: 'failed', timestamp: Time.current.to_i, errors: [{ code: 131_047, title: 'Re-engagement', message: 'window closed' }] }
      )

      expect(recipient.reload).to be_failed
      expect(recipient.failed_at).to be_present
      expect(recipient.error_code).to eq('131047')
      expect(recipient.error_message).to eq('window closed')
    end

    it 'ignores unknown delivery states' do
      recipient.mark_sent!('wamid.abc')

      recipient.apply_whatsapp_status!({ status: 'deleted' })

      expect(recipient.reload).to be_sent
    end
  end

  describe '.summary_for' do
    it 'reports audience, per-status counts, delivered including read, and sent with a source id' do
      create(:pilot_campaign_recipient, account: account, campaign: campaign, contact: create(:contact, account: account), status: :queued)
      create(:pilot_campaign_recipient, account: account, campaign: campaign, contact: create(:contact, account: account),
                                        status: :sent, source_id: 'wamid.1')
      create(:pilot_campaign_recipient, account: account, campaign: campaign, contact: create(:contact, account: account),
                                        status: :delivered, source_id: 'wamid.2')
      create(:pilot_campaign_recipient, account: account, campaign: campaign, contact: create(:contact, account: account),
                                        status: :read, source_id: 'wamid.3')
      create(:pilot_campaign_recipient, account: account, campaign: campaign, contact: create(:contact, account: account),
                                        status: :failed, source_id: 'wamid.4')
      create(:pilot_campaign_recipient, account: account, campaign: campaign, contact: create(:contact, account: account), status: :skipped)

      summary = described_class.summary_for(campaign)

      expect(summary[:audience]).to eq(6)
      expect(summary[:sent]).to eq(4)
      expect(summary[:delivered]).to eq(2)
      expect(summary[:read]).to eq(1)
      expect(summary[:failed]).to eq(1)
      expect(summary[:skipped]).to eq(1)
      expect(summary[:status_counts]['queued']).to eq(1)
    end
  end
end
