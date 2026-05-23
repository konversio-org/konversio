class Api::V2::Accounts::Pilot::CustomToolsController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :fetch_custom_tool, only: [:show, :update, :destroy]
  before_action :authorize_request

  def index
    @custom_tools = Current.account.pilot_custom_tools.order(created_at: :desc)
  end

  def show; end

  def create
    @custom_tool = Current.account.pilot_custom_tools.create!(custom_tool_params)
    render :show, status: :created
  end

  def update
    @custom_tool.update!(custom_tool_params)
    render :show
  end

  def destroy
    @custom_tool.destroy!
    head :no_content
  end

  def test
    # Build a temporary custom tool object on Current.account
    tool = Current.account.pilot_custom_tools.new(custom_tool_params)
    tool.enabled = true # Force it enabled to test even if it's currently disabled

    # Execute the test with provided arguments
    test_args = params[:test_arguments]&.to_unsafe_h || {}

    result = Pilot::Tools::Executor.new(tool).call(test_args)

    if result.is_a?(Hash) && result[:error]
      render json: { success: false, error: result[:error], message: result[:message] }, status: :ok
    else
      render json: { success: true, result: result }, status: :ok
    end
  end

  private

  def ensure_feature_enabled
    return if Current.account.feature_enabled?('pilot') && Current.account.feature_enabled?('pilot_tools')

    render json: { error: 'Pilot Custom Tools are not enabled for this account' }, status: :forbidden
  end

  def fetch_custom_tool
    @custom_tool = Current.account.pilot_custom_tools.find(params[:id])
  end

  def authorize_request
    return if performed?

    record = @custom_tool || Pilot::CustomTool
    authorize(record, policy_class: Pilot::CustomToolPolicy)
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to perform this action' }, status: :forbidden
  end

  def custom_tool_params
    params.permit(
      :title, :description, :endpoint_url, :http_method, :auth_type, :enabled,
      :request_template, :response_template,
      auth_config: {},
      param_schema: [:name, :type, :description, :required]
    )
  end
end
