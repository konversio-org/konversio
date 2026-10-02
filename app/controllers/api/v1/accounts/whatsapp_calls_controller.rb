class Api::V1::Accounts::WhatsappCallsController < Api::V1::Accounts::BaseController
  before_action :set_call, only: %i[show accept reject terminate upload_recording]
  before_action :set_call_context, only: :initiate
  before_action :ensure_calling_enabled, only: :initiate
  before_action :ensure_sdp_offer, only: :initiate
  before_action :ensure_call_recipient, only: :initiate
  before_action :ensure_recording_present, only: :upload_recording
  before_action :ensure_recording_enabled, only: :upload_recording
  before_action :ensure_call_message, only: :upload_recording

  rescue_from Voice::CallErrors::NotRinging, Voice::CallErrors::CallFailed, with: :render_call_error
  rescue_from Voice::CallErrors::AlreadyAccepted, with: :render_already_accepted
  rescue_from Voice::CallErrors::CallAlreadyEnded, with: :render_call_ended

  def show; end

  def accept
    call_service.accept
  end

  def reject
    call_service.reject
  end

  def terminate
    call_service.terminate
  end

  def upload_recording
    @upload_status = @call.message.with_lock { attach_recording_idempotently }
  end

  def initiate
    @call = create_outbound_call
    # Link call and message in one transaction so the message.created broadcast
    # fires only after call.message_id is set (clients never see a ringing bubble
    # without its call payload).
    ActiveRecord::Base.transaction do
      @message = Voice::CallMessageFactory.new(@call).perform!
      @call.update!(message_id: @message.id)
    end
  rescue Voice::CallErrors::NoCallPermission
    render_permission_request
  end

  private

  def call_service
    @call_service ||= Whatsapp::CallService.new(call: @call, agent: Current.user, sdp_answer: params[:sdp_answer])
  end

  def provider_service
    @inbox.channel.provider_service
  end

  def set_call
    @call = Current.account.calls.whatsapp.find(params[:id])
    authorize @call.conversation, :show?
  end

  def set_call_context
    params[:conversation_id].present? ? set_context_from_conversation : set_context_from_contact
  end

  def set_context_from_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
    @inbox = @conversation.inbox
    @contact = @conversation.contact
  end

  def set_context_from_contact
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
    @contact = Current.account.contacts.find(params[:contact_id])
    @conversation = conversation_resolver.existing_conversation
    # Authorize the thread the call will land in — after the dial is too late.
    authorize(@conversation || conversation_resolver.new_conversation, :show?)
  end

  def conversation_resolver
    @conversation_resolver ||= Whatsapp::CallConversationResolver.new(inbox: @inbox, contact: @contact, user: Current.user)
  end

  # Created only after the dial succeeds, so a failed call leaves no empty thread.
  def open_conversation!
    (@conversation || conversation_resolver.perform!).tap { |conversation| authorize conversation, :show? }
  end

  def ensure_calling_enabled
    channel = @inbox.channel
    return if channel.is_a?(Channel::Whatsapp) && channel.voice_enabled?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.not_enabled'))
  end

  def ensure_sdp_offer
    return if params[:sdp_offer].present?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.sdp_offer_required'))
  end

  def ensure_call_recipient
    return if call_recipient.present?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.contact_phone_required'))
  end

  def ensure_recording_present
    return if params[:recording].present?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.no_recording'))
  end

  # Re-checked server-side because a stale tab may hold an outdated toggle.
  def ensure_recording_enabled
    return if @call.recording_enabled?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.recording_disabled'))
  end

  def ensure_call_message
    return if @call.message.present?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.no_message'))
  end

  def attach_recording_idempotently
    return 'already_uploaded' if @call.message.attachments.exists?(file_type: :audio)

    @call.message.attachments.create!(account_id: @call.account_id, file_type: :audio, file: params[:recording])
    'uploaded'
  end

  def create_outbound_call
    # A reused thread unassigned at click time is claimed for the caller; a fresh
    # thread is created already assigned to the caller.
    claim_for_caller = @conversation.present? && @conversation.assigned_entity.nil?

    result = provider_service.initiate_call(call_recipient, params[:sdp_offer])
    provider_call_id = result.dig('calls', 0, 'id') || result['call_id']

    @conversation = open_conversation!
    @conversation.with_lock { @conversation.update!(assignee: Current.user) } if claim_for_caller

    create_call_record(provider_call_id)
  end

  def call_recipient
    # A conversation is anchored to the exact WhatsApp identity selected by
    # routing; contact-level calling uses the phone number.
    @call_recipient ||= if params[:conversation_id].present?
                          @conversation.contact_inbox&.source_id
                        else
                          @contact.phone_number&.delete('+')
                        end
  end

  def create_call_record(provider_call_id)
    existing = Current.account.calls.whatsapp.find_by(provider_call_id: provider_call_id)
    return existing if existing

    Current.account.calls.create!(
      provider: :whatsapp, inbox: @conversation.inbox, conversation: @conversation, contact: @conversation.contact,
      provider_call_id: provider_call_id, direction: :outgoing, status: 'ringing',
      accepted_by_agent_id: Current.user.id,
      meta: { 'sdp_offer' => params[:sdp_offer], 'ice_servers' => Call.default_ice_servers }
    )
  rescue ActiveRecord::RecordNotUnique
    Current.account.calls.whatsapp.find_by!(provider_call_id: provider_call_id)
  end

  def render_permission_request
    # Raised mid-dial, so a fresh contact has no thread yet — open one for the
    # opt-in template to land in.
    @conversation = open_conversation!
    status = Whatsapp::CallPermissionRequestService.new(conversation: @conversation, recipient: call_recipient).perform

    return render_could_not_create_error(I18n.t('errors.whatsapp.calls.permission_request_failed')) if status == 'failed'

    # 422 (not 200) so a client treating 2xx as "call placed" can't mistake the
    # permission path for a successful dial.
    render json: { status: status, conversation_id: @conversation.display_id }, status: :unprocessable_entity
  end

  def render_call_error(error)
    render_could_not_create_error(error.message)
  end

  def render_call_ended
    render json: { error: I18n.t('errors.whatsapp.calls.already_ended') }, status: :conflict
  end

  def render_already_accepted
    render json: { error: I18n.t('errors.whatsapp.calls.already_accepted') }, status: :conflict
  end
end
