class Api::V1::Accounts::ConferenceController < Api::V1::Accounts::BaseController
  before_action :voice_inbox
  rescue_from CustomExceptions::CallAlreadyAccepted, with: :render_already_accepted

  def token
    render json: Voice::Twilio::TokenService.new(
      inbox: voice_inbox,
      user: Current.user,
      account: Current.account
    ).generate
  end

  def create
    call = find_call!
    service = Voice::Twilio::ConferenceService.new(call: call)
    conference_sid = service.ensure_conference_sid
    service.mark_agent_joined(user: Current.user)

    render json: {
      status: 'success',
      id: call.conversation.display_id,
      conference_sid: conference_sid,
      using_webrtc: true
    }
  end

  def destroy
    call = find_call!
    # Provider teardown first: a failure leaves local state untouched.
    Voice::Twilio::ConferenceService.new(call: call).end_conference
    finalize!(call)
    call.broadcast_voice_call_event(:ended, status: call.display_status)
    render json: { status: 'success', id: call.conversation.display_id }
  end

  private

  def voice_inbox
    @voice_inbox ||= begin
      inbox = Current.account.inboxes.where(channel_type: 'Channel::TwilioSms').find(params[:inbox_id])
      authorize inbox, :show?
      inbox
    end
  end

  def find_call!
    sid = params[:call_sid].presence
    raise ActionController::ParameterMissing, :call_sid if sid.blank?

    conversation = find_conversation!
    Call.where(inbox_id: voice_inbox.id, provider: :twilio, conversation_id: conversation.id)
        .find_by!(provider_call_id: sid)
  end

  def find_conversation!
    display_id = params[:conversation_id]
    raise ActiveRecord::RecordNotFound, 'conversation_id required' if display_id.blank?

    conversation = voice_inbox.conversations.find_by!(display_id: display_id)
    authorize conversation, :show?
    conversation
  end

  # Persist a terminal status under the row lock before the ended broadcast so a
  # late join webhook cannot flip a finished call back to accepted.
  def finalize!(call)
    status = nil
    call.with_lock do
      next if call.finished?

      if call.ringing? && call.accepted_by_agent_id.nil?
        status = 'rejected'
        call.update!(end_reason: 'agent_rejected', accepted_by_agent_id: Current.user.id)
      elsif call.in_progress?
        status = 'completed'
        call.update!(end_reason: 'agent_hangup')
      else
        status = 'no_answer'
        call.update!(end_reason: 'agent_hangup')
      end
      Voice::StatusManager.new(call: call).process_status_update(status)
    end
    Voice::CallMessageFactory.new(call).update_status!(status: status, agent: Current.user) if status
  end

  def render_already_accepted(error)
    render json: { error: error.message }, status: :conflict
  end
end
