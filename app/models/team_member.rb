# == Schema Information
#
# Table name: team_members
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  team_id    :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_team_members_on_team_id              (team_id)
#  index_team_members_on_team_id_and_user_id  (team_id,user_id) UNIQUE
#  index_team_members_on_user_id              (user_id)
#
class TeamMember < ApplicationRecord
  belongs_to :user
  belongs_to :team
  validates :user_id, uniqueness: { scope: :team_id }

  after_create_commit -> { record_membership_audit('create') }
  after_destroy_commit -> { record_membership_audit('destroy') }

  private

  def record_membership_audit(action)
    return if team.blank?

    AuditLog.create!(
      auditable_type: 'TeamMember',
      auditable_id: id,
      action: action,
      associated_type: 'Account',
      associated_id: team.account_id,
      audited_changes: attributes.except('created_at', 'updated_at')
    )
  end
end
