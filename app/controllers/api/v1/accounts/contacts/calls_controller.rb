class Api::V1::Accounts::Contacts::CallsController < Api::V1::Accounts::BaseController
  before_action :contact
  before_action :voice_inbox

  def create
    authorize contact, :show?
    authorize voice_inbox, :show?

    call = Voice::OutboundCallFactory.perform!(
      account: Current.account,
      inbox: voice_inbox,
      user: Current.user,
      contact: contact,
      conversation: reusable_conversation
    )

    render json: {
      conversation_id: call.conversation.display_id,
      inbox_id: voice_inbox.id,
      call_sid: call.provider_call_id,
      conference_sid: call.conference_sid
    }
  rescue ArgumentError => e
    render_could_not_create_error(e.message)
  end

  private

  def contact
    @contact ||= Current.account.contacts.find(params[:id])
  end

  def voice_inbox
    @voice_inbox ||= begin
      inbox = Current.user.assigned_inboxes.where(
        account_id: Current.account.id,
        channel_type: 'Channel::TwilioSms'
      ).find(params.require(:inbox_id))
      raise ActiveRecord::RecordNotFound, 'Voice not enabled' unless inbox.channel.voice_enabled?

      inbox
    end
  end

  # Reuse only an open conversation that belongs to the same voice inbox and
  # contact; a resolved/snoozed thread can't be reopened by an outgoing bubble.
  def reusable_conversation
    return if params[:conversation_id].blank?

    conversation = Current.account.conversations.find_by(display_id: params[:conversation_id])
    return unless conversation
    return unless conversation.inbox_id == voice_inbox.id && conversation.contact_id == contact.id
    return unless conversation.open?

    conversation
  end
end
