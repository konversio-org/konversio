require 'rails_helper'

RSpec.describe Pilot::LogbookExtractionJob do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  describe '.insert_with_eviction (atomicity)' do
    it 'inserts a new entry when the contact has no prior entries' do
      expect do
        described_class.insert_with_eviction(contact: contact, content: 'Prefers email', account: account)
      end.to change { Pilot::LogbookEntry.where(contact: contact).count }.by(1)
    end

    it 'evicts the oldest entry and inserts the new one within a single transaction at the cap' do
      cap = described_class::MAX_ENTRIES_PER_CONTACT
      oldest = travel_to(cap.days.ago) do
        create(:pilot_logbook_entry, contact: contact, account: account, content: 'oldest fact')
      end

      (cap - 1).times do |i|
        travel_to((cap - 1 - i).days.ago) do
          create(:pilot_logbook_entry, contact: contact, account: account, content: "fact #{i}")
        end
      end

      expect(Pilot::LogbookEntry.where(contact: contact).count).to eq(cap)

      described_class.insert_with_eviction(contact: contact, content: 'newest fact', account: account)

      expect(Pilot::LogbookEntry.where(contact: contact).count).to eq(cap)
      expect(Pilot::LogbookEntry.exists?(id: oldest.id)).to be(false)
      expect(Pilot::LogbookEntry.where(contact: contact).order(:created_at).last.content).to eq('newest fact')
    end

    it 'leaves the cap unchanged on rollback if insert fails (atomic eviction + insert)' do
      cap = described_class::MAX_ENTRIES_PER_CONTACT
      cap.times do |i|
        travel_to((cap - i).days.ago) do
          create(:pilot_logbook_entry, contact: contact, account: account, content: "fact #{i}")
        end
      end

      # Force the create! to blow up after eviction would have happened.
      allow(Pilot::LogbookEntry).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect do
        described_class.insert_with_eviction(contact: contact, content: 'should not stick', account: account)
      end.to raise_error(ActiveRecord::RecordInvalid)

      # Eviction inside the same transaction must have rolled back.
      expect(Pilot::LogbookEntry.where(contact: contact).count).to eq(cap)
    end

    it 'returns nil and is a no-op when contact is blank' do
      expect do
        expect(described_class.insert_with_eviction(contact: nil, content: 'x')).to be_nil
      end.not_to change(Pilot::LogbookEntry, :count)
    end

    it 'acquires the per-contact advisory lock at the start of the transaction' do
      lock_calls = []
      original_execute = Pilot::LogbookEntry.connection.method(:execute)
      allow(Pilot::LogbookEntry.connection).to receive(:execute) do |sql, *rest|
        lock_calls << sql if sql.is_a?(String) && sql.include?('pg_advisory_xact_lock')
        original_execute.call(sql, *rest)
      end

      described_class.insert_with_eviction(contact: contact, content: 'fact', account: account)

      expect(lock_calls.size).to eq(1)
      expect(lock_calls.first).to include(described_class::PILOT_LOGBOOK_LOCK_NAMESPACE.to_s)
      expect(lock_calls.first).to include(contact.id.to_s)
    end
  end

  describe '#perform — output-contract integration' do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    end

    before do
      create(:message, account: account, conversation: conversation, inbox: inbox,
                       message_type: :incoming, content: 'Just FYI I prefer email.')
    end

    def stub_service(returning:)
      svc = instance_double(Custom::Pilot::LogbookExtractionService, call: returning)
      allow(Custom::Pilot::LogbookExtractionService).to receive(:new).and_return(svc)
      svc
    end

    it 'inserts each LLM-returned fact verbatim (no post-filter)' do
      stub_service(returning: ['Prefers email', 'Has corporate account'])

      expect do
        described_class.perform_now(conversation.id)
      end.to change { Pilot::LogbookEntry.where(contact: contact).count }.by(2)
    end

    it 'inserts zero rows when the service returns an empty array (covers both empty and caught-LLM-error paths)' do
      stub_service(returning: [])

      expect do
        described_class.perform_now(conversation.id)
      end.not_to(change { Pilot::LogbookEntry.where(contact: contact).count })
    end

    it 'no-ops when the conversation has no contact' do
      conversation.update_columns(contact_id: nil)

      expect do
        described_class.perform_now(conversation.id)
      end.not_to(change { Pilot::LogbookEntry.count })
    end
  end

  describe 'concurrent extractions for the same contact', :slow do
    # The advisory lock is transaction-scoped, so two threads each opening a
    # transaction and calling `insert_with_eviction` for the same contact
    # MUST serialize. We assert the final count is <= cap even when both
    # threads start with the contact already at the cap.
    it 'serializes via the advisory lock and never exceeds the cap' do
      cap = described_class::MAX_ENTRIES_PER_CONTACT
      cap.times do |i|
        travel_to((cap - i).days.ago) do
          create(:pilot_logbook_entry, contact: contact, account: account, content: "fact #{i}")
        end
      end

      threads = Array.new(2) do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.insert_with_eviction(contact: contact, content: "concurrent fact #{i}", account: account)
          end
        end
      end
      threads.each(&:join)

      final_count = Pilot::LogbookEntry.where(contact: contact).count
      expect(final_count).to be <= cap
      # Both extractions ran — both new contents should be present.
      contents = Pilot::LogbookEntry.where(contact: contact).pluck(:content)
      expect(contents).to include('concurrent fact 0')
      expect(contents).to include('concurrent fact 1')
    end
  end
end
