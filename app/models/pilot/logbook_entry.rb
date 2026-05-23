# frozen_string_literal: true

# == Schema Information
#
# Table name: pilot_logbook_entries
#
#  id         :bigint           not null, primary key
#  content    :text             not null
#  metadata   :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  contact_id :bigint           not null
#
# Indexes
#
#  index_pilot_logbook_entries_on_account_id  (account_id)
#  index_pilot_logbook_entries_on_contact_id  (contact_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#

class Pilot::LogbookEntry < ApplicationRecord
  self.table_name = 'pilot_logbook_entries'
  belongs_to :account
  belongs_to :contact

  validates :content, presence: true
  validates :account_id, presence: true
  validates :contact_id, presence: true

  before_validation :ensure_account_id

  after_commit :dispatch_entry_created_event, on: :create
  after_commit :dispatch_entry_deleted_event, on: :destroy

  scope :latest, -> { order(created_at: :desc) }

  private

  def ensure_account_id
    self.account_id = contact&.account_id if account_id.blank?
  end

  def dispatch_entry_created_event
    ::Custom::Pilot::EventDispatcher.dispatch(
      'pilot.logbook.entry.created',
      {
        account_id: account_id,
        contact_id: contact_id,
        entry_id: id,
        content_length: content.to_s.length
      },
      account: account
    )
  rescue StandardError => e
    Rails.logger.warn("[pilot.logbook_entry] dispatch entry.created failed: #{e.class}: #{e.message}")
  end

  def dispatch_entry_deleted_event
    ::Custom::Pilot::EventDispatcher.dispatch(
      'pilot.logbook.entry.deleted',
      {
        account_id: account_id,
        contact_id: contact_id,
        entry_id: id
      },
      account: account
    )
  rescue StandardError => e
    Rails.logger.warn("[pilot.logbook_entry] dispatch entry.deleted failed: #{e.class}: #{e.message}")
  end
end
