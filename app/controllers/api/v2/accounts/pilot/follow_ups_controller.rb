class Api::V2::Accounts::Pilot::FollowUpsController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :ensure_conversation_id
  before_action :load_conversation
  before_action :authorize_conversation

  def create
    suggestions = Custom::Pilot::FollowUpService.new(
      conversation: @conversation,
      account: Current.account
    ).perform

    render json: { suggestions: suggestions }, status: :ok
  rescue Custom::Pilot::FollowUpService::FeatureDisabledError
    render json: { error: 'Pilot Follow-up is not enabled for this account' }, status: :forbidden
  rescue Custom::Pilot::FollowUpService::Error => e
    Rails.logger.error("[pilot.follow_ups] LLM failure: #{e.message}")
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def ensure_feature_enabled
    return if Current.account.pilot_enabled && Current.account.pilot_follow_up_enabled

    render json: { error: 'Pilot Follow-up is not enabled for this account' }, status: :forbidden
  end

  def ensure_conversation_id
    return if params[:conversation_id].present?

    render json: { error: 'conversation_id is required' }, status: :bad_request
  end

  def load_conversation
    @conversation = Current.account.conversations.find_by(display_id: params[:conversation_id])
    render json: { error: 'Conversation not found' }, status: :not_found if @conversation.blank?
  end

  def authorize_conversation
    return if @conversation.blank?

    authorize @conversation, :create?, policy_class: Pilot::FollowUpPolicy
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to access this conversation' }, status: :forbidden
  end
end
