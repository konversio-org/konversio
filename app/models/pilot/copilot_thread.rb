# == Schema Information
#
# Table name: copilot_threads
#
#  id           :bigint           not null, primary key
#  title        :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  assistant_id :integer
#  user_id      :bigint           not null
#
# Indexes
#
#  index_copilot_threads_on_account_id    (account_id)
#  index_copilot_threads_on_assistant_id  (assistant_id)
#  index_copilot_threads_on_user_id       (user_id)
#

# Persistent Copilot thread between an account agent and the Pilot
# assistant. Backed by the existing `copilot_threads` table.
class Pilot::CopilotThread < ApplicationRecord
  self.table_name = 'copilot_threads'

  belongs_to :account
  belongs_to :user
  # `assistant_id` is an optional integer column (no FK constraint at the DB
  # level — the Pilot::Assistant model lands in section 4 of the Pilot
  # rebuild). We model it as a loose attribute today and tighten it later
  # without changing this contract.
  attribute :assistant_id, :integer

  has_many :copilot_messages,
           class_name: 'Pilot::CopilotMessage',
           foreign_key: :copilot_thread_id,
           inverse_of: :copilot_thread,
           dependent: :destroy

  validates :title, presence: true
end
