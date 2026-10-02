class Api::V1::Accounts::Contacts::AttachmentsController < Api::V1::Accounts::Contacts::BaseController
  RESULTS_PER_PAGE = 100

  def index
    @attachments = visible_attachments.order(created_at: :desc).page(params[:page]).per(RESULTS_PER_PAGE)
    @attachments_count = @attachments.total_count
  end

  private

  def visible_attachments
    Attachment.where(message_id: visible_messages.select(:id))
              .includes({ file_attachment: :blob }, message: [:conversation, :inbox, { sender: { avatar_attachment: :blob } }])
  end

  def visible_messages
    Message.where(conversation_id: visible_conversations.select(:id))
  end

  def visible_conversations
    Conversations::PermissionFilterService.new(
      Current.account.conversations.where(contact_id: @contact.id),
      Current.user,
      Current.account
    ).perform
  end
end
