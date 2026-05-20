class Api::V2::Accounts::Pilot::ResponsesController < Api::V1::Accounts::BaseController
  PER_PAGE = 25

  before_action :ensure_feature_enabled
  before_action :load_assistant
  before_action :load_response, only: [:update, :destroy]
  before_action :authorize_request

  def index
    scope = @assistant.responses.ordered
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = apply_search(scope)

    @responses = scope.page(current_page).per(PER_PAGE)
  end

  def create
    @response = @assistant.responses.new(create_params)
    @response.account = Current.account
    @response.edited = true if @response.approved?
    @response.save!

    render :show, status: :created
  end

  def update
    @response.assign_attributes(update_params)
    @response.edited = true
    @response.save!

    render :show
  end

  def destroy
    @response.destroy!
    head :no_content
  end

  private

  def ensure_feature_enabled
    return if Current.account.pilot_enabled && Current.account.pilot_autopilot_enabled

    render json: { error: 'Pilot Autopilot is not enabled for this account' }, status: :forbidden
  end

  def load_assistant
    @assistant = Current.account.pilot_assistants.find_by(id: params[:assistant_id])
    render json: { error: 'Assistant not found' }, status: :not_found if @assistant.blank?
  end

  def load_response
    return if performed?

    @response = @assistant.responses.find_by(id: params[:id])
    render json: { error: 'Resource could not be found' }, status: :not_found if @response.blank?
  end

  def authorize_request
    return if performed?

    authorize(@assistant, policy_class: Pilot::AssistantResponsePolicy)
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to perform this action' }, status: :forbidden
  end

  def apply_search(scope)
    query = params[:search].to_s.strip
    return scope if query.blank?

    like = "%#{query}%"
    scope.where('question ILIKE :q OR answer ILIKE :q', q: like)
  end

  def current_page
    [params[:page].to_i, 1].max
  end

  def create_params
    permitted = params.permit(:question, :answer, :status)
    permitted[:status] = 'approved' if permitted[:status].blank?
    permitted
  end

  def update_params
    params.permit(:question, :answer, :status)
  end
end
