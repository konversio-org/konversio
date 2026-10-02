require 'rails_helper'

RSpec.describe Voice::ConferenceManager do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:call) { create(:call, account: account, status: 'ringing') }
  let(:label) { "agent-#{agent.id}-account-#{account.id}" }

  def process(event, participant_label: label)
    described_class.new(call: call, event: event, participant_label: participant_label).process
  end

  describe 'join' do
    it 'claims the call for the first agent to join and starts it' do
      allow(call).to receive(:broadcast_voice_call_event)

      process('join')

      expect(call.reload.accepted_by_agent).to eq(agent)
      expect(call.status).to eq('in_progress')
    end

    it 'broadcasts accepted exactly once across duplicate joins' do
      expect(call).to receive(:broadcast_voice_call_event).with(:accepted, accepted_by_agent_id: agent.id).once

      process('join')
      process('join')
    end

    it 'ignores a join label embedding another account id' do
      process('join', participant_label: "agent-#{agent.id}-account-#{account.id + 999}")

      expect(call.reload.accepted_by_agent).to be_nil
      expect(call.status).to eq('ringing')
    end

    it 'ignores a join after another agent claimed the call' do
      process('join')
      process('join', participant_label: "agent-#{other_agent.id}-account-#{account.id}")

      expect(call.reload.accepted_by_agent).to eq(agent)
    end
  end

  describe 'leave' do
    it 'maps ringing to no_answer' do
      process('leave')

      expect(call.reload.status).to eq('no_answer')
    end

    it 'maps in_progress to completed' do
      call.update!(status: 'in_progress', started_at: 10.seconds.ago)

      process('leave')

      expect(call.reload.status).to eq('completed')
    end
  end

  describe 'end' do
    it 'finalizes a non-terminal call' do
      process('end')

      expect(call.reload).to be_finished
    end
  end

  it 'ignores all events for terminal calls' do
    call.update!(status: 'completed')

    process('join')

    expect(call.reload.status).to eq('completed')
  end
end
