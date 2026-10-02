# Reviewable FAQ candidate mined from resolved conversations. One record per
# distinct FAQ per assistant and language; repeat sightings attach
# `Pilot::FaqObservation` rows and raise `source_count` instead of
# duplicating. Approval converts the suggestion into an approved
# `Pilot::AssistantResponse`; dismissal suppresses future re-mining of the
# same FAQ in the same language.
#
# The pgvector(1536) `embedding` column holds the vector of
# `"<question>: <answer>"` and is refreshed asynchronously while the
# suggestion is open whenever the text changes.
class Pilot::FaqSuggestion < ApplicationRecord
  self.table_name = 'pilot_faq_suggestions'

  belongs_to :assistant, class_name: 'Pilot::Assistant'
  belongs_to :account
  has_many :observations,
           class_name: 'Pilot::FaqObservation',
           foreign_key: :faq_suggestion_id,
           inverse_of: :faq_suggestion,
           dependent: :delete_all

  has_neighbors :embedding, normalize: true

  enum :status, { open: 0, approved: 1, dismissed: 2 }

  validates :question, presence: true
  validates :answer, presence: true
  validates :language, presence: true

  before_validation :ensure_account

  after_commit :enqueue_embedding_refresh, on: %i[create update], if: :embedding_refresh_needed?

  scope :ordered, -> { order(source_count: :desc, updated_at: :desc) }
  scope :by_language, ->(language) { where(language: language) }

  # Collapses a locale string to its normalized primary subtag:
  # "pt-BR" / "pt_BR" / "PT" all become "pt".
  def self.normalize_language(locale)
    locale.to_s.downcase.tr('_', '-').split('-').first.presence || I18n.default_locale.to_s
  end

  # Normalized language for a conversation, derived from the account locale
  # with the installation default locale as fallback.
  def self.language_for(conversation)
    normalize_language(conversation&.account&.locale.presence || I18n.default_locale)
  end

  # The text that gets embedded for similarity matching. Kept in one place so
  # the refresh job and the candidate matcher embed the exact same string.
  def embeddable_text
    "#{question}: #{answer}"
  end

  private

  def ensure_account
    self.account = assistant&.account if account.blank?
  end

  def embedding_refresh_needed?
    open? && (saved_change_to_question? || saved_change_to_answer? || embedding.nil?)
  end

  def enqueue_embedding_refresh
    ::Pilot::UpdateFaqSuggestionEmbeddingJob.perform_later(id)
  end
end
