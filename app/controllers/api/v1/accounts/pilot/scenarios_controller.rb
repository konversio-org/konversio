class Api::V1::Accounts::Pilot::ScenariosController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :fetch_assistant
  before_action :fetch_scenario, only: [:show, :update, :destroy]
  before_action :authorize_request

  def index
    @scenarios = @assistant.scenarios.order(id: :desc)
    render json: @scenarios, status: :ok
  end

  def show
    render json: @scenario, status: :ok
  end

  def create
    @scenario = @assistant.scenarios.create!(scenario_params)
    render json: @scenario, status: :created
  end

  def update
    @scenario.update!(scenario_params)
    render json: @scenario, status: :ok
  end

  def destroy
    @scenario.destroy!
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

  def fetch_scenario
    @scenario = @assistant.scenarios.find(params[:id])
  end

  def authorize_request
    authorize @assistant, :update?, policy_class: Pilot::AssistantPolicy
  end

  def scenario_params
    params.require(:scenario).permit(:title, :description, :instruction, :enabled)
  end
end
