class Api::V1::Accounts::Pilot::BulkActionsController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :authorize_request

  def create
    case normalized_type
    when 'AssistantResponse', 'Pilot::AssistantResponse'
      if params[:fields] && params[:fields][:status] == 'approve'
        # Fetch the matching responses for this account
        @responses = Current.account.pilot_assistant_responses.where(id: params[:ids])

        # rubocop:disable Rails/SkipsModelValidations
        # Bulk update status to approved and set edited flag
        @responses.update_all(status: :approved, edited: true)
        # rubocop:enable Rails/SkipsModelValidations

        # Enqueue embedding jobs for responses that need pgvector updates
        @responses.each do |response|
          ::Pilot::UpdateEmbeddingJob.perform_later(response.id) if response.embedding.nil? && defined?(::Pilot::UpdateEmbeddingJob)
        end

        # We will render the updated records so frontend store can sync
        # Uses app/views/api/v1/accounts/pilot/bulk_actions/create.json.jbuilder
        render :create
      else
        render json: { error: 'Invalid fields' }, status: :unprocessable_content
      end
    else
      render json: { error: 'Unsupported type' }, status: :unprocessable_content
    end
  end

  private

  def ensure_feature_enabled
    return if Current.account.feature_enabled?('pilot') && Current.account.feature_enabled?('pilot_autopilot')

    render json: { error: 'Pilot Autopilot is not enabled for this account' }, status: :forbidden
  end

  def authorize_request
    authorize(Pilot::AssistantResponse, :update?, policy_class: Pilot::AssistantResponsePolicy)
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to perform this action' }, status: :forbidden
  end

  def normalized_type
    params[:type]
  end
end
