# == Schema Information
#
# Table name: pilot_inboxes
#
#  id                 :bigint           not null, primary key
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  inbox_id           :bigint           not null
#  pilot_assistant_id :bigint           not null
#
# Indexes
#
#  index_pilot_inboxes_on_inbox_id            (inbox_id) UNIQUE
#  index_pilot_inboxes_on_pilot_assistant_id  (pilot_assistant_id)
#

# Join model linking a Pilot::Assistant to a Chatwoot Inbox.
class Pilot::Inbox < ApplicationRecord
  self.table_name = 'pilot_inboxes'

  belongs_to :assistant,
             class_name: 'Pilot::Assistant',
             foreign_key: :pilot_assistant_id,
             inverse_of: :pilot_inboxes
  belongs_to :inbox, class_name: '::Inbox'

  validates :inbox_id, uniqueness: { message: :already_connected_to_assistant }
end
