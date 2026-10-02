require 'rails_helper'

RSpec.describe Voice::StatusManager do
  let(:call) { create(:call, status: 'ringing') }
  let(:manager) { described_class.new(call: call) }

  it 'ignores unknown statuses and repeats' do
    expect(manager.process_status_update('nonsense')).to be(false)
    expect(manager.process_status_update('ringing')).to be(false)
  end

  it 'never overwrites a terminal status' do
    call.update!(status: 'rejected', end_reason: 'agent_rejected')

    manager.process_status_update('completed')

    expect(call.reload.status).to eq('rejected')
    expect(call.end_reason).to eq('agent_rejected')
  end

  it 'keeps the earliest in-progress timestamp' do
    t1 = 100.seconds.ago.to_i
    t2 = 10.seconds.ago.to_i

    manager.process_status_update('in_progress', timestamp: t2)
    manager.process_status_update('in_progress', timestamp: t1)

    expect(call.reload.started_at.to_i).to eq(t1)
  end

  it 'derives duration from started_at when none is provided' do
    call.update!(status: 'in_progress', started_at: 95.seconds.ago)

    manager.process_status_update('completed', timestamp: Time.zone.now.to_i)

    expect(call.reload.duration_seconds).to be_within(2).of(95)
  end

  it 'stamps ended_at and uses a provided duration' do
    call.update!(status: 'in_progress', started_at: 40.seconds.ago)

    manager.process_status_update('completed', duration: 12)

    expect(call.reload.ended_at).to be_present
    expect(call.duration_seconds).to eq(12)
  end

  it 'bumps the conversation activity and touches the call message' do
    message = create(:message, account: call.account, inbox: call.inbox, conversation: call.conversation)
    call.update!(message: message)
    call.conversation.update!(last_activity_at: 2.days.ago)

    manager.process_status_update('in_progress')

    expect(call.conversation.reload.last_activity_at).to be_within(5.seconds).of(Time.zone.now)
  end
end
