require 'rails_helper'

RSpec.describe Custom::Pilot::EventDispatcher do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  # Capture-by-callback pattern from §3 / §5 of the testing-patterns doc:
  # rather than asserting `.with(...)` on a specific argument shape (brittle
  # when new dispatch sites land), let the stub capture the call and assert
  # on the captured value. Fewer broken tests when payload schema evolves.
  def stub_host_dispatcher(captured: nil)
    dispatcher = instance_double(Dispatcher)
    allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
    if captured
      allow(dispatcher).to receive(:dispatch) do |name, time, payload|
        captured[:name] = name
        captured[:time] = time
        captured[:payload] = payload
      end
    else
      allow(dispatcher).to receive(:dispatch)
    end
    dispatcher
  end

  describe '.dispatch' do
    it 'persists a row to pilot_events scoped to the account' do
      expect do
        described_class.dispatch('pilot.briefing.completed',
                                 { account_id: account.id, conversation_id: 42 },
                                 account: account)
      end.to change(Pilot::Event, :count).by(1)

      event = Pilot::Event.last
      expect(event.account_id).to eq(account.id)
      expect(event.event_name).to eq('pilot.briefing.completed')
      expect(event.payload['conversation_id']).to eq(42)
    end

    it 'forwards the event to Rails.configuration.dispatcher with the given time' do
      account # ensure account is created before stubbing the dispatcher
      time = Time.zone.parse('2026-05-22 12:00:00')
      captured = {}
      stub_host_dispatcher(captured: captured)

      described_class.dispatch('pilot.briefing.completed',
                               { account_id: account.id },
                               time: time, account: account)

      expect(captured[:name]).to eq('pilot.briefing.completed')
      expect(captured[:time]).to eq(time)
      expect(captured[:payload]).to be_a(Hash)
    end

    it 'uses Time.zone.now when no time is provided' do
      account
      captured = {}
      stub_host_dispatcher(captured: captured)

      frozen = Time.zone.parse('2026-05-22 09:30:00')
      travel_to(frozen) do
        described_class.dispatch('pilot.briefing.completed', { account_id: account.id }, account: account)
      end

      expect(captured[:time]).to eq(frozen)
      expect(Pilot::Event.last.created_at).to be_within(1.second).of(frozen)
    end

    it 'redacts sensitive payload fields before persisting and dispatching' do
      account # ensure account is created before stubbing
      captured = {}
      stub_host_dispatcher(captured: captured)

      described_class.dispatch('pilot.briefing.completed',
                               { account_id: account.id, prompt: 'Top secret prompt' },
                               account: account)

      expect(captured[:payload]).not_to have_key(:prompt)
      expect(captured[:payload][:prompt_length]).to eq('Top secret prompt'.length)
      expect(captured[:payload][:prompt_sha256]).to eq(Digest::SHA256.hexdigest('Top secret prompt'))

      expect(Pilot::Event.last.payload.keys).to include('prompt_length', 'prompt_sha256')
      expect(Pilot::Event.last.payload).not_to have_key('prompt')
    end

    it 'does not persist a pilot_events row when account is not resolvable' do
      expect do
        described_class.dispatch('pilot.briefing.completed', { conversation_id: 1 })
      end.not_to change(Pilot::Event, :count)
    end

    # §12 of the testing-patterns doc: negative-path / missing-row coverage.
    it 'tolerates a nil payload without raising and still forwards a hash' do
      account
      captured = {}
      stub_host_dispatcher(captured: captured)

      expect do
        described_class.dispatch('pilot.briefing.completed', nil, account: account)
      end.not_to raise_error

      expect(captured[:payload]).to eq({})
    end

    it 'tolerates an empty-hash payload and still scopes the row to the explicit account' do
      expect do
        described_class.dispatch('pilot.briefing.completed', {}, account: account)
      end.to change(Pilot::Event, :count).by(1)
      expect(Pilot::Event.last.account_id).to eq(account.id)
    end

    it 'resolves account from payload[:account_id] when no explicit account is passed' do
      expect do
        described_class.dispatch('pilot.briefing.completed', { account_id: account.id })
      end.to change(Pilot::Event, :count).by(1)
      expect(Pilot::Event.last.account_id).to eq(account.id)
    end

    it 'continues to other listeners when one raises' do
      account # ensure account is created before stubbing
      allow(Pilot::Event).to receive(:create!).and_raise(StandardError, 'persist boom')
      dispatcher = instance_double(Dispatcher)
      allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
      expect(dispatcher).to receive(:dispatch).once

      expect do
        described_class.dispatch('pilot.briefing.completed', { account_id: account.id }, account: account)
      end.not_to raise_error
    end

    # §13 listed account-scoping multi-tenant assertions as worth filling in.
    # Account A's dispatch should never bleed into account B's row count.
    context 'with multiple accounts in scope' do
      let(:other_account) { create(:account) }

      it 'never writes a pilot_events row against the wrong account' do
        described_class.dispatch('pilot.briefing.completed', { account_id: account.id }, account: account)

        expect(Pilot::Event.where(account_id: other_account.id).count).to eq(0)
        expect(Pilot::Event.where(account_id: account.id).count).to eq(1)
      end
    end

    # §8 race-condition pattern: hook the stub itself to perform a racing
    # mutation. Here: simulate an event landing while the dispatcher is
    # mid-flight. If the implementation ever starts reading mutable state
    # *after* sanitization (e.g. looking up the conversation again), we want
    # the test to flag it. We assert that mutation during the host-dispatcher
    # call does not change what gets persisted to pilot_events.
    it 'is not affected by payload-source mutation that races the host dispatch' do
      account
      raw_payload = { account_id: account.id, conversation_id: 99 }

      dispatcher = instance_double(Dispatcher)
      allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
      allow(dispatcher).to receive(:dispatch) do
        # Mutate the source hash during dispatch — emulates a concurrent
        # callsite handing off and modifying the same hash.
        raw_payload[:conversation_id] = 100_000
      end

      described_class.dispatch('pilot.briefing.completed', raw_payload, account: account)

      expect(Pilot::Event.last.payload['conversation_id']).to eq(99)
    end

    # The dispatcher is invoked concurrently from background jobs.
    # Two sequential dispatches in the same example mimic that pattern at
    # the persistence layer: both rows must land, both must scope to the
    # right account.
    it 'persists each row on repeated dispatches without conflating them' do
      stub_host_dispatcher

      expect do
        described_class.dispatch('pilot.briefing.completed', { account_id: account.id, n: 1 }, account: account)
        described_class.dispatch('pilot.briefing.completed', { account_id: account.id, n: 2 }, account: account)
      end.to change(Pilot::Event, :count).by(2)

      ns = Pilot::Event.where(account_id: account.id).order(:id).pluck(:payload).map { |p| p['n'] }
      expect(ns).to eq([1, 2])
    end

    context 'with conversation-outcome events' do
      let(:assistant) { create(:pilot_assistant, account: account) }
      let(:envelope) do
        Custom::Pilot::ConversationPayloadBuilder.call(conversation: conversation, assistant: assistant)
      end

      it 'persists two rows for handover.triggered' do
        expect do
          described_class.dispatch(
            'pilot.autopilot.handover.triggered',
            { account_id: account.id, conversation_envelope: envelope, conversation_db_id: conversation.id },
            account: account
          )
        end.to change(Pilot::ReportingEvent, :count).by(2)

        names = Pilot::ReportingEvent.where(conversation_id: conversation.id).pluck(:name)
        expect(names).to contain_exactly('pilot.autopilot.handover.triggered', 'conversation.bot_handoff')
      end

      it 'does not persist a reporting row for non-outcome events' do
        expect do
          described_class.dispatch('pilot.briefing.completed', { account_id: account.id }, account: account)
        end.not_to change(Pilot::ReportingEvent, :count)
      end

      # §13 gap-tied: when the conversation referenced by the envelope no
      # longer exists, persistence must skip the reporting row rather than
      # blowing up the dispatcher.
      it 'silently skips the reporting row when the referenced conversation has been deleted' do
        envelope_with_dead_id = envelope.merge(id: 0)
        expect do
          described_class.dispatch(
            'pilot.autopilot.handover.triggered',
            { account_id: account.id, conversation_envelope: envelope_with_dead_id, conversation_db_id: 0 },
            account: account
          )
        end.not_to change(Pilot::ReportingEvent, :count)
      end
    end
  end
end
