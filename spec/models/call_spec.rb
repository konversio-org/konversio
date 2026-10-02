require 'rails_helper'

RSpec.describe Call do
  describe 'provider call id uniqueness' do
    it 'rejects duplicate provider_call_id for the same provider' do
      create(:call, provider: :twilio, provider_call_id: 'CA123')

      duplicate = build(:call, provider: :twilio, provider_call_id: 'CA123')

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same provider_call_id across providers' do
      create(:call, provider: :twilio, provider_call_id: 'shared-id')

      expect { create(:call, provider: :whatsapp, provider_call_id: 'shared-id') }.not_to raise_error
    end
  end

  describe '.active' do
    it 'excludes terminal calls' do
      ringing = create(:call, status: 'ringing')
      in_progress = create(:call, status: 'in_progress')
      create(:call, status: 'completed')
      create(:call, status: 'failed')

      expect(described_class.active).to contain_exactly(ringing, in_progress)
    end
  end

  describe 'display normalization' do
    it 'renders direction and status in display form' do
      call = build(:call, direction: :outgoing, status: 'in_progress')

      expect(call.direction_label).to eq('outbound')
      expect(call.display_status).to eq('in-progress')
    end

    it 'maps display inputs back to stored forms' do
      expect(described_class.direction_from_label('inbound')).to eq('incoming')
      expect(described_class.status_from_display('no-answer')).to eq('no_answer')
    end
  end

  describe 'recording snapshot' do
    it 'snapshots the channel recording setting at creation' do
      channel = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                                          provider_config: { 'api_key' => 'k', 'phone_number_id' => '1', 'recording_enabled' => false,
                                                             'source' => 'embedded_signup' })
      inbox = channel.inbox
      call = create(:call, inbox: inbox, conversation: nil, contact: nil)

      expect(call.recording_enabled?).to be(false)
    end

    it 'treats a call without a snapshot as recording-enabled' do
      call = build(:call, meta: {})

      expect(call.recording_enabled?).to be(true)
    end
  end

  describe '#push_event_data' do
    it 'exposes the accepting agent name and a recording url' do
      agent = create(:user)
      call = create(:call, status: 'in_progress', accepted_by_agent: agent)

      expect(call.push_event_data[:accepted_by_agent_name]).to eq(agent.available_name)
    end
  end
end
