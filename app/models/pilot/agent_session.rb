# One row per completed Pilot AI run. Links an assistant run to the subject it
# ran on (a conversation for autopilot, a copilot thread for copilot) and to the
# message it produced, and attributes the knowledge the run was offered, used,
# and actually cited to the customer.
#
# Sessions are written only for successful runs that produced a customer-facing
# reply (or handoff note); capture is failure-isolated so a recording bug can
# never affect delivery.
class Pilot::AgentSession < ApplicationRecord
  self.table_name = 'pilot_agent_sessions'

  # Constrains which subject/result polymorphic types are valid for each kind.
  SUBJECT_TYPES = {
    'autopilot' => 'Conversation',
    'copilot' => 'Pilot::CopilotThread'
  }.freeze
  RESULT_TYPES = {
    'autopilot' => 'Message',
    'copilot' => 'Pilot::CopilotMessage'
  }.freeze

  enum :session_kind, { autopilot: 0, copilot: 1 }, prefix: true

  belongs_to :account
  belongs_to :assistant, class_name: 'Pilot::Assistant'
  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true
  belongs_to :result, polymorphic: true, optional: true

  before_validation :derive_account

  validates :subject_type, :subject_id, presence: true
  validate :subject_type_matches_kind
  validate :result_type_matches_kind
  validate :subject_belongs_to_account
  validate :result_belongs_to_account

  scope :for_result, ->(record) { where(result_type: record.class.polymorphic_name, result_id: record.id) }

  # The turn-scoped transcript stored on the session, as an array of entries.
  def run_context_entries
    entries = run_context.is_a?(Hash) ? (run_context['entries'] || run_context[:entries]) : run_context
    Array(entries)
  end

  private

  def derive_account
    self.account = assistant.account if account.blank? && assistant.present?
  end

  def expected_subject_type
    SUBJECT_TYPES[session_kind]
  end

  def expected_result_type
    RESULT_TYPES[session_kind]
  end

  def subject_type_matches_kind
    return if subject_type.blank? || expected_subject_type.blank?
    return if subject_type == expected_subject_type

    errors.add(:subject_type, "must be #{expected_subject_type} for a #{session_kind} session")
  end

  def result_type_matches_kind
    return if result_type.blank? || expected_result_type.blank?
    return if result_type == expected_result_type

    errors.add(:result_type, "must be #{expected_result_type} for a #{session_kind} session")
  end

  def subject_belongs_to_account
    return if subject.blank? || account.blank?
    return if belongs_to_account?(subject)

    errors.add(:subject, 'must belong to the session account')
  end

  def result_belongs_to_account
    return if result.blank? || account.blank?
    return if belongs_to_account?(result)

    errors.add(:result, 'must belong to the session account')
  end

  def belongs_to_account?(record)
    !record.respond_to?(:account_id) || record.account_id == account_id
  end
end
