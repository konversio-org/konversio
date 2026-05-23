# frozen_string_literal: true

# Persists Pilot Logbook entries for a contact, enforcing the soft cap
# (100 entries per contact) atomically.
#
# The full extraction pipeline (LLM call, dedup, etc.) is implemented by
# later sub-tasks. This class today owns the durable insert step and the
# concurrency-safety contract spelled out in the pilot-logbook
# "Eviction atomicity at extraction time" requirement:
#
#   * eviction + insert run inside a single database transaction so no
#     reader observes an intermediate state with fewer than the cap minus
#     one entries
#   * concurrent extractions for the same contact serialize via a
#     transaction-scoped advisory lock keyed on `contact_id`, so two
#     extractions cannot each delete the oldest entry and then both
#     insert, producing an over-cap state
class Pilot::LogbookExtractionJob < ApplicationJob
  queue_as :low

  MAX_ENTRIES_PER_CONTACT = 100

  # Arbitrary stable namespace id for the two-arg `pg_advisory_xact_lock`
  # call. Postgres treats the pair `(namespace, contact_id)` as the lock
  # key. The namespace value itself has no Postgres-side semantics — it
  # just needs to be stable across processes and unique enough that
  # other Pilot subsystems won't collide on the same `contact_id`.
  PILOT_LOGBOOK_LOCK_NAMESPACE = 738_291_104

  # Atomically inserts a new Logbook entry for the contact, evicting the
  # oldest entry first if the contact is at or above the soft cap.
  #
  # Returns the persisted entry, or nil when the contact is blank.
  def self.insert_with_eviction(contact:, content:, account: nil, source_message: nil)
    return nil if contact.blank?

    effective_account = account || contact.account

    ApplicationRecord.transaction do
      acquire_contact_lock(contact.id)

      evict_oldest_until_under_cap(contact)

      attrs = { contact: contact, account: effective_account, content: content }
      attrs[:source_message] = source_message if source_message && Pilot::LogbookEntry.column_names.include?('source_message_id')
      Pilot::LogbookEntry.create!(attrs)
    end
  end

  def self.acquire_contact_lock(contact_id)
    Pilot::LogbookEntry.connection.execute(
      Pilot::LogbookEntry.send(:sanitize_sql_array,
                               ['SELECT pg_advisory_xact_lock(?, ?)', PILOT_LOGBOOK_LOCK_NAMESPACE, contact_id])
    )
  end

  def self.evict_oldest_until_under_cap(contact)
    surplus = Pilot::LogbookEntry.where(contact_id: contact.id).count - (MAX_ENTRIES_PER_CONTACT - 1)
    return if surplus <= 0

    victims = Pilot::LogbookEntry.where(contact_id: contact.id)
                                 .order(created_at: :asc, id: :asc)
                                 .limit(surplus)
                                 .pluck(:id)
    Pilot::LogbookEntry.where(id: victims).delete_all
  end

  # Full extraction entry-point. Per the deepdive's section 3:
  #
  #   * call `LogbookExtractionService` to obtain the candidate fact array
  #   * iterate verbatim — no programmatic post-filter (no min-length,
  #     no question-mark drop)
  #   * cross-call dedup is handled by the prompt's "skip already-present"
  #     instruction AND by the embedding-similarity dedup pass at insert
  #     time (which respects the soft cap + advisory lock via
  #     `insert_with_eviction`)
  #   * LLM exceptions and malformed output are caught inside the
  #     service; the job sees an empty array and inserts nothing
  def perform(conversation_id)
    conversation = ::Conversation.find_by(id: conversation_id)
    return if conversation.blank?
    return if conversation.contact.blank? || conversation.account.blank?

    facts = extract_facts(conversation)
    return if facts.blank?

    insert_each(facts, conversation)
  end

  private

  def extract_facts(conversation)
    ::Custom::Pilot::LogbookExtractionService.new(
      conversation: conversation, contact: conversation.contact, account: conversation.account
    ).call
  end

  def insert_each(facts, conversation)
    facts.each do |fact|
      next if fact.blank?

      self.class.insert_with_eviction(
        contact: conversation.contact, content: fact, account: conversation.account
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[pilot.logbook_extraction_job] invalid fact: #{e.message}")
    end
  end
end
