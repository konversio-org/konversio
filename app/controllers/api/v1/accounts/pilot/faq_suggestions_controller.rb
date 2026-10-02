class Api::V1::Accounts::Pilot::FaqSuggestionsController < Api::V1::Accounts::BaseController
  PER_PAGE = 25
  SOURCE_PREVIEW_LIMIT = 50

  before_action :ensure_feature_enabled
  before_action :load_suggestion, only: [:show, :update, :approve, :dismiss]
  before_action :authorize_request

  def index
    scope = finder.perform
    @suggestions = scope.page(current_page).per(PER_PAGE)
  end

  def show
    @observations = visible_observations
  end

  def update
    @suggestion.with_lock do
      raise ActiveRecord::RecordNotFound, 'FAQ suggestion is not open' unless @suggestion.open?

      @suggestion.update!(update_params)
    end
    @observations = visible_observations
    render :show
  end

  def approve
    @response = ::Pilot::FaqSuggestionApprovalService.new(
      suggestion: @suggestion,
      question: params[:question],
      answer: params[:answer]
    ).perform

    render 'api/v1/accounts/pilot/assistant_responses/show'
  end

  def dismiss
    @suggestion.with_lock do
      raise ActiveRecord::RecordNotFound, 'FAQ suggestion is not open' unless @suggestion.open?

      @suggestion.update!(status: :dismissed)
    end
    @observations = visible_observations
    render :show
  end

  private

  def ensure_feature_enabled
    return if Current.account.feature_enabled?('pilot') && Current.account.feature_enabled?('pilot_autopilot')

    render json: { error: 'Pilot Autopilot is not enabled for this account' }, status: :forbidden
  end

  def finder
    ::Pilot::FaqSuggestionFinder.new(account: Current.account, user: Current.user, params: finder_params)
  end

  def finder_params
    {
      assistant_id: params[:assistant_id],
      status: params[:status],
      search: params[:search]
    }
  end

  # Loaded through the permission-aware finder so a suggestion an agent may
  # not see behaves as not-found.
  def load_suggestion
    @suggestion = finder.perform.find_by(id: params[:id])
    render json: { error: 'Resource could not be found' }, status: :not_found if @suggestion.blank?
  end

  def authorize_request
    return if performed?

    record = @suggestion || ::Pilot::FaqSuggestion
    authorize(record, policy_class: Pilot::FaqSuggestionPolicy)
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to perform this action' }, status: :forbidden
  end

  # Most recent source sightings, conversation-filtered so an agent only
  # ever sees observations on conversations they can access.
  def visible_observations
    scope = @suggestion.observations.includes(:conversation).order(created_at: :desc)
    scope = scope.where(conversation_id: accessible_conversation_ids) unless Current.account_user&.administrator?
    scope.limit(SOURCE_PREVIEW_LIMIT)
  end

  def accessible_conversation_ids
    ::Conversations::PermissionFilterService
      .new(Current.account.conversations, Current.user, Current.account)
      .perform
      .select(:id)
  end

  def current_page
    [params[:page].to_i, 1].max
  end

  def update_params
    params.permit(:question, :answer)
  end
end
