class Api::V1::Accounts::Pilot::InboxesController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :fetch_assistant
  before_action :authorize_request

  def index
    @attached_inboxes = @assistant.pilot_inboxes.joins(:inbox).includes(:inbox)
    render json: @attached_inboxes.map { |pi|
      {
        id: pi.id,
        inbox_id: pi.inbox_id,
        name: pi.inbox.name,
        channel_type: pi.inbox.channel_type,
        medium: pi.inbox.channel.try(:medium)
      }
    }, status: :ok
  end

  def create
    inbox = Current.account.inboxes.find(params[:inbox_id])
    existing = ::Pilot::Inbox.find_by(inbox_id: inbox.id)
    return render_connection(existing, inbox, :ok) if existing&.pilot_assistant_id == @assistant.id
    return render_inbox_conflict(inbox) if existing.present?

    attached = @assistant.pilot_inboxes.create!(inbox: inbox)
    render_connection(attached, inbox, :created)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    existing = ::Pilot::Inbox.find_by(inbox_id: inbox.id)
    return render_connection(existing, inbox, :ok) if existing&.pilot_assistant_id == @assistant.id

    render_inbox_conflict(inbox)
  end

  def destroy
    attached = @assistant.pilot_inboxes.find_by!(inbox_id: params[:inbox_id])
    attached.destroy!
    head :no_content
  end

  private

  def ensure_feature_enabled
    return if Current.account.feature_enabled?('pilot') && Current.account.feature_enabled?('pilot_autopilot')

    render json: { error: 'Pilot Autopilot is not enabled for this account' }, status: :forbidden
  end

  def fetch_assistant
    @assistant = Current.account.pilot_assistants.find(params[:assistant_id])
  end

  def authorize_request
    authorize @assistant, :update?, policy_class: Pilot::AssistantPolicy
  end

  def render_connection(pilot_inbox, inbox, status)
    render json: {
      id: pilot_inbox.id,
      inbox_id: pilot_inbox.inbox_id,
      name: inbox.name,
      channel_type: inbox.channel_type,
      medium: inbox.channel.try(:medium)
    }, status: status
  end

  def render_inbox_conflict(inbox)
    message = "Inbox '#{inbox.name}' is already connected to another assistant."
    render json: { error: message, message: message }, status: :unprocessable_entity
  end
end
