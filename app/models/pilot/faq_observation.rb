# One mined FAQ candidate sighting, tied to its source conversation. Stores
# the question/answer exactly as generated for that conversation. Either
# attached to a `Pilot::FaqSuggestion` (the sighting fed an open review
# candidate) or discarded (the candidate matched existing approved knowledge
# or a dismissed suggestion). Discarded rows are kept as an audit trail.
class Pilot::FaqObservation < ApplicationRecord
  self.table_name = 'pilot_faq_observations'

  belongs_to :account
  belongs_to :conversation
  belongs_to :faq_suggestion, class_name: 'Pilot::FaqSuggestion', optional: true, inverse_of: :observations

  enum :status, { attached: 0, discarded: 1 }

  validates :generated_question, presence: true
  validates :generated_answer, presence: true
  validates :language, presence: true
  validate :attached_observation_requires_suggestion_in_same_account

  before_validation :ensure_account

  private

  def ensure_account
    self.account = conversation&.account if account.blank?
  end

  def attached_observation_requires_suggestion_in_same_account
    return unless attached?
    return if faq_suggestion.present? && faq_suggestion.account_id == account_id

    errors.add(:faq_suggestion, 'must reference a suggestion in the same account when attached')
  end
end
