class Api::V1::Accounts::Companies::ConversationsController < Api::V1::Accounts::Companies::BaseController
  before_action :authorize_company_read!

  def index
    @conversations = Conversations::PermissionFilterService.new(
      member_conversations,
      Current.user,
      Current.account
    ).perform.order(last_activity_at: :desc).limit(20)
  end

  private

  def member_conversations
    Current.account.conversations
           .includes(:assignee, :contact, :inbox, :taggings)
           .where(contact_id: @company.contacts.select(:id))
  end
end
