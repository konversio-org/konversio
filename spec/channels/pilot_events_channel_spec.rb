require 'rails_helper'

RSpec.describe PilotEventsChannel do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:other_account) { create(:account) }

  before do
    stub_connection
  end

  it 'subscribes a user with a valid pubsub_token to their account stream' do
    subscribe(user_id: user.id, pubsub_token: user.pubsub_token, account_id: account.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("pilot_events_#{account.id}")
  end

  it 'rejects subscription when the pubsub_token does not match a user' do
    subscribe(user_id: user.id, pubsub_token: 'nope', account_id: account.id)

    expect(subscription).to be_rejected
  end

  it 'rejects subscription when the user does not belong to the requested account' do
    subscribe(user_id: user.id, pubsub_token: user.pubsub_token, account_id: other_account.id)

    expect(subscription).to be_rejected
  end

  it 'isolates account streams so a subscriber to account 1 does not receive account 2 events' do
    subscribe(user_id: user.id, pubsub_token: user.pubsub_token, account_id: account.id)

    expect(subscription).not_to have_stream_from("pilot_events_#{other_account.id}")
  end

  it 'delivers a broadcast on the account stream after subscription' do
    subscribe(user_id: user.id, pubsub_token: user.pubsub_token, account_id: account.id)

    expect do
      ActionCable.server.broadcast("pilot_events_#{account.id}", { event: 'pilot.briefing.completed', payload: { foo: 'bar' } })
    end.to have_broadcasted_to("pilot_events_#{account.id}").with(event: 'pilot.briefing.completed', payload: { foo: 'bar' })
  end
end
