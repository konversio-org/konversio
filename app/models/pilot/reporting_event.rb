# frozen_string_literal: true

# == Schema Information
#
# Table name: pilot_reporting_events
#
#  id                      :bigint           not null, primary key
#  event_end_at            :datetime
#  event_start_at          :datetime
#  name                    :string           not null
#  value                   :float
#  value_in_business_hours :float
#  created_at              :datetime         not null
#  account_id              :bigint           not null
#  conversation_id         :bigint
#  inbox_id                :bigint
#  user_id                 :bigint
#
# Indexes
#
#  index_pilot_reporting_events_on_account_id          (account_id)
#  index_pilot_reporting_events_on_account_name_start  (account_id,name,event_start_at)
#  index_pilot_reporting_events_on_conversation_id     (conversation_id)
#  index_pilot_reporting_events_on_inbox_id            (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
# Long-lived BI store for conversation-outcome events driven by Pilot.
# Sister to the host's `reporting_events` table; written by the Pilot
# event dispatcher reporting listener so existing host reports stay
# unchanged.
class Pilot::ReportingEvent < ApplicationRecord
  self.table_name = 'pilot_reporting_events'

  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :user, optional: true
  belongs_to :conversation, optional: true

  validates :name, presence: true
  validates :account_id, presence: true
end
