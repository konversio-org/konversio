class Api::V1::Accounts::Pilot::InboxesController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :fetch_assistant
  before_action :authorize_request

  def index
    @attached_inboxes = @assistant.pilot_inboxes.includes(:inbox)
    render json: @attached_inboxes.map { |pi|
      {
        id: pi.id,
        inbox_id: pi.inbox_id,
        name: pi.inbox.name,
        channel_type: pi.inbox.channel_type
      }
    }, status: :ok
  end

  def create
    inbox = Current.account.inboxes.find(params[:inbox_id])
    attached = @assistant.pilot_inboxes.create!(inbox: inbox)
    render json: {
      id: attached.id,
      inbox_id: attached.inbox_id,
      name: inbox.name,
      channel_type: inbox.channel_type
    }, status: :created
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
end
