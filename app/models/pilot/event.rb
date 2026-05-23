# frozen_string_literal: true

# == Schema Information
#
# Table name: pilot_events
#
#  id                  :bigint           not null, primary key
#  event_name          :string           not null
#  payload             :jsonb            not null
#  related_entity_type :string
#  created_at          :datetime         not null
#  account_id          :bigint           not null
#  related_entity_id   :bigint
#
# Indexes
#
#  index_pilot_events_on_account_id                      (account_id)
#  index_pilot_events_on_account_id_and_created_at_desc  (account_id,created_at DESC)
#  index_pilot_events_on_event_name                      (event_name)
#  index_pilot_events_on_related_entity                  (related_entity_type,related_entity_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
# Account-scoped activity log of Pilot dispatcher events. Populated by
# `Custom::Pilot::EventDispatcher` so the admin Activity view can render
# a recent history of every Pilot action.
class Pilot::Event < ApplicationRecord
  self.table_name = 'pilot_events'

  belongs_to :account

  validates :event_name, presence: true
  validates :account_id, presence: true

  scope :latest, -> { order(created_at: :desc) }
  scope :with_prefix, ->(prefix) { where('event_name LIKE ?', "#{sanitize_sql_like(prefix)}%") }
end
