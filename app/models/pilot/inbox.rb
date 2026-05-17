# == Schema Information
#
# Table name: pilot_inboxes
#
#  id                  :bigint           not null, primary key
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  pilot_assistant_id  :bigint           not null
#  inbox_id            :bigint           not null
#

# Join model linking a Pilot::Assistant to a Chatwoot Inbox.
class Pilot::Inbox < ApplicationRecord
  self.table_name = 'pilot_inboxes'

  belongs_to :assistant,
             class_name: 'Pilot::Assistant',
             foreign_key: :pilot_assistant_id,
             inverse_of: :pilot_inboxes
  belongs_to :inbox, class_name: '::Inbox'

  validates :inbox_id, uniqueness: { scope: :pilot_assistant_id }
end
