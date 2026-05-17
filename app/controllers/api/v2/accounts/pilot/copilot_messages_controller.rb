class Api::V2::Accounts::Pilot::CopilotMessagesController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :load_thread

  def index
    messages = @thread.copilot_messages.order(:created_at)
    render json: { data: messages.map { |m| serialize_message(m) } }
  end

  def create
    raise ActionController::ParameterMissing, :message if params[:message].blank?

    user_message = Captain::CopilotMessage.create!(
      copilot_thread: @thread,
      account: Current.account,
      message_type: :user,
      message: { content: params[:message].to_s }
    )

    Pilot::CopilotInferenceJob.perform_later(
      thread_id: @thread.id,
      conversation_id: params[:conversation_id]
    )

    render json: serialize_message(user_message), status: :created
  rescue ActionController::ParameterMissing
    render json: { error: 'message is required' }, status: :bad_request
  end

  private

  def ensure_feature_enabled
    return if Current.account.pilot_enabled && Current.account.pilot_copilot_enabled

    render json: { error: 'Pilot Copilot is not enabled for this account' }, status: :forbidden
  end

  def load_thread
    base = Captain::CopilotThread.where(account_id: Current.account.id)
    base = base.where(user_id: Current.user.id) unless Current.account_user&.administrator?

    @thread = base.find_by(id: params[:copilot_thread_id])

    # Intentionally return 404 (not 403) when an agent accesses another
    # agent's thread so we don't leak existence — see pilot-copilot spec.
    return render json: { error: 'Thread not found' }, status: :not_found if @thread.blank?
  end

  def serialize_message(message)
    {
      id: message.id,
      copilot_thread_id: message.copilot_thread_id,
      message_type: message.message_type,
      message: message.message,
      created_at: message.created_at,
      updated_at: message.updated_at
    }
  end
end
