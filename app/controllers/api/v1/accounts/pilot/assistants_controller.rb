class Api::V1::Accounts::Pilot::AssistantsController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :fetch_assistant, only: [:show, :update, :destroy, :playground]
  before_action :authorize_request

  def index
    @assistants = Current.account.pilot_assistants.ordered
  end

  def show; end

  def create
    @assistant = Current.account.pilot_assistants.create!(assistant_params)
  end

  def update
    @assistant.update!(assistant_params)
  end

  def destroy
    @assistant.destroy!
    head :no_content
  end

  def playground
    result = Custom::Pilot::AutopilotService.new(
      assistant: @assistant,
      message: params[:message_content],
      message_history: parsed_message_history,
      account: Current.account,
      source: 'playground'
    ).perform

    render json: { reply: result.reply }, status: :ok
  rescue Custom::Pilot::AutopilotService::FeatureDisabledError
    render json: { error: 'Pilot Autopilot is not enabled for this account' }, status: :forbidden
  rescue Custom::Pilot::AutopilotService::Error => e
    Rails.logger.error("[pilot.assistants.playground] LLM failure: #{e.message}")
    render json: { error: e.message }, status: :internal_server_error
  end

  def tools
    render json: tools_registry, status: :ok
  end

  private

  def ensure_feature_enabled
    return if Current.account.feature_enabled?('pilot') && Current.account.feature_enabled?('pilot_autopilot')

    render json: { error: 'Pilot Autopilot is not enabled for this account' }, status: :forbidden
  end

  def fetch_assistant
    @assistant = Current.account.pilot_assistants.find(params[:id])
  end

  def authorize_request
    if @assistant.present?
      authorize @assistant, policy_class: Pilot::AssistantPolicy
    else
      authorize Pilot::Assistant, policy_class: Pilot::AssistantPolicy
    end
  end

  def assistant_params
    params.permit(:name, :description, :response_guidelines, :guardrails, enabled_tool_slugs: [], config: {})
  end

  def parsed_message_history
    history = params[:message_history]
    return [] if history.blank?

    Array(history).map do |entry|
      entry = entry.to_unsafe_h if entry.respond_to?(:to_unsafe_h)
      { role: entry['role'] || entry[:role], content: entry['content'] || entry[:content] }
    end
  end

  def tools_registry
    path = Rails.root.join('config/agents/tools.yml')
    return [] unless File.exist?(path)

    YAML.safe_load_file(path) || []
  rescue StandardError => e
    Rails.logger.error("[pilot.assistants.tools] Failed to load tools registry: #{e.message}")
    []
  end
end
