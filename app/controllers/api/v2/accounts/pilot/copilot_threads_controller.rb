class Api::V2::Accounts::Pilot::CopilotThreadsController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :load_thread, only: [:show]

  TITLE_PREVIEW_LENGTH = 80

  def index
    @threads = scoped_threads.order(created_at: :desc)
    render json: { data: @threads.map { |thread| serialize_thread(thread) } }
  end

  def create
    raise ActionController::ParameterMissing, :message if params[:message].blank?

    thread = nil
    ActiveRecord::Base.transaction do
      thread = Captain::CopilotThread.create!(
        account: Current.account,
        user: Current.user,
        title: derive_title(params[:message]),
        assistant_id: params[:assistant_id]
      )
      Captain::CopilotMessage.create!(
        copilot_thread: thread,
        account: Current.account,
        message_type: :user,
        message: { content: params[:message].to_s }
      )
    end

    Pilot::CopilotInferenceJob.perform_later(
      thread_id: thread.id,
      conversation_id: params[:conversation_id]
    )

    render json: serialize_thread(thread), status: :created
  rescue ActionController::ParameterMissing
    render json: { error: 'message is required' }, status: :bad_request
  end

  def show
    render json: serialize_thread(@thread)
  end

  private

  def ensure_feature_enabled
    return if Current.account.pilot_enabled && Current.account.pilot_copilot_enabled

    render json: { error: 'Pilot Copilot is not enabled for this account' }, status: :forbidden
  end

  def scoped_threads
    base = Captain::CopilotThread.where(account_id: Current.account.id)
    return base if Current.account_user&.administrator?

    base.where(user_id: Current.user.id)
  end

  def load_thread
    @thread = scoped_threads.find_by(id: params[:id])

    # Intentionally return 404 (not 403) when an agent accesses another
    # agent's thread so we don't leak existence — see pilot-copilot spec.
    return render json: { error: 'Thread not found' }, status: :not_found if @thread.blank?
  end

  def serialize_thread(thread)
    {
      id: thread.id,
      account_id: thread.account_id,
      user_id: thread.user_id,
      assistant_id: thread.assistant_id,
      title: thread.title,
      created_at: thread.created_at,
      updated_at: thread.updated_at
    }
  end

  def derive_title(text)
    cleaned = text.to_s.strip.gsub(/\s+/, ' ')
    cleaned = cleaned[0, TITLE_PREVIEW_LENGTH]
    cleaned.presence || 'New thread'
  end
end
