# == Schema Information
#
# Table name: pilot_assistant_responses
#
#  id                :bigint           not null, primary key
#  answer            :text             not null
#  documentable_type :string
#  edited            :boolean          default(FALSE), not null
#  embedding         :vector(1536)
#  question          :string           not null
#  status            :integer          default("approved"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  assistant_id      :bigint           not null
#  documentable_id   :bigint
#

# Searchable knowledge entry for a Pilot assistant. Embedding lives in the
# `embedding` pgvector(1536) column; on create/update the question+answer
# text is re-embedded via `Pilot::UpdateEmbeddingJob`.
#
# Status enum (`pending` = 0, `approved` = 1, `rejected` = 2) controls whether
# the entry participates in customer-facing search.
class Pilot::AssistantResponse < ApplicationRecord
  self.table_name = 'pilot_assistant_responses'

  belongs_to :assistant, class_name: 'Pilot::Assistant'
  belongs_to :account
  belongs_to :documentable, polymorphic: true, optional: true
  has_neighbors :embedding, normalize: true

  enum :status, { pending: 0, approved: 1, rejected: 2 }

  validates :question, presence: true
  validates :answer, presence: true

  before_validation :ensure_account
  before_validation :mark_as_edited, on: :update

  after_commit :enqueue_embedding_refresh, on: %i[create update]

  scope :ordered, -> { order(created_at: :desc) }
  scope :by_account, ->(account_id) { where(account_id: account_id) }
  scope :by_assistant, ->(assistant_id) { where(assistant_id: assistant_id) }

  # Vector similarity search against the approved knowledge base of a single
  # assistant. `query_embedding` is a 1536-dim Array (Float). Returns up to
  # `limit` rows ordered by cosine distance.
  def self.search_for_assistant(assistant_id, query_embedding, limit: 5)
    return none if query_embedding.blank?

    by_assistant(assistant_id)
      .approved
      .nearest_neighbors(:embedding, query_embedding, distance: 'cosine')
      .limit(limit)
  end

  private

  def ensure_account
    self.account = assistant&.account if account.blank?
  end

  def mark_as_edited
    self.edited = true if question_changed? || answer_changed?
  end

  def enqueue_embedding_refresh
    return unless defined?(::Pilot::UpdateEmbeddingJob)
    return unless saved_change_to_question? || saved_change_to_answer? || embedding.nil?

    ::Pilot::UpdateEmbeddingJob.perform_later(id)
  end
end
