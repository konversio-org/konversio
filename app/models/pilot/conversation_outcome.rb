# frozen_string_literal: true

# == Schema Information
#
# Table name: pilot_conversation_outcomes
#
#  id                     :bigint           not null, primary key
#  ai_reply_count         :integer          default(0), not null
#  csat_rating            :integer
#  csat_received_at       :datetime
#  ended_at               :datetime
#  episode_trigger        :string           default("initial"), not null
#  first_ai_reply_at      :datetime
#  first_human_reply_at   :datetime
#  handoff_at             :datetime
#  handoff_reason_category :string
#  last_ai_reply_at       :datetime
#  resolved_at            :datetime
#  started_at             :datetime         not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  assistant_id           :bigint           not null
#  conversation_id        :bigint           not null
#  inbox_id               :bigint           not null
#
# A single continuous window of potential Pilot AI involvement on one
# conversation. Episodes form an ordered stream per conversation: exactly one
# may be open (`ended_at` empty) at a time, and each conversation has at most
# one initial episode. A reopen closes the open episode and succeeds it with a
# new one, so each row stays a complete terminal snapshot of one window.
class Pilot::ConversationOutcome < ApplicationRecord
  self.table_name = 'pilot_conversation_outcomes'

  # What opened the episode: the first time Pilot became eligible to respond,
  # or a conversation reopening after a previous episode had been recorded.
  EPISODE_TRIGGERS = %w[initial reopen].freeze

  # Konversio-owned handoff reason taxonomy. Extensible by appending here; every
  # handoff path must supply one of these categories. `quota_exhausted` keeps
  # usage-limit transfers distinguishable from genuine escalations, because a
  # quota block before the AI ever replied is blocked demand, not a failed
  # conversation.
  HANDOFF_REASON_CATEGORIES = %w[
    customer_escalation
    knowledge_gap
    policy_refusal
    system_failure
    quota_exhausted
    other
  ].freeze

  belongs_to :account, class_name: '::Account'
  belongs_to :assistant, class_name: 'Pilot::Assistant'
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :inbox, class_name: '::Inbox'

  enum :episode_trigger, EPISODE_TRIGGERS.index_with(&:itself), validate: true
  enum :handoff_reason_category, HANDOFF_REASON_CATEGORIES.index_with(&:itself), validate: { allow_nil: true }

  validates :started_at, presence: true
  validates :ai_reply_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :associations_share_account

  # Oldest first — the natural episode stream order for reporting.
  scope :chronological, -> { order(:started_at, :id) }

  # Episodes whose half-open window [started_at, ended_at) covers `at`. An open
  # episode (empty ended_at) covers every later instant.
  scope :covering, lambda { |at|
    where('started_at <= ?', at)
      .where('ended_at IS NULL OR ended_at > ?', at)
      .order(started_at: :desc)
  }

  def open?
    ended_at.nil?
  end

  private

  def associations_share_account
    return if account_id.blank?

    mismatched = [assistant, conversation, inbox].compact.find { |record| record.account_id != account_id }
    return if mismatched.blank?

    errors.add(:account_id, 'must match the assistant, conversation, and inbox account')
  end
end
