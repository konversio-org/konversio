class Api::V1::Accounts::Pilot::AssistantsController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :fetch_assistant, only: [:show, :update, :destroy, :playground, :avatar]
  before_action :authorize_request

  def index
    @assistants = Current.account.pilot_assistants.ordered
  end

  def show; end

  def create
    @assistant = Current.account.pilot_assistants.create!(assistant_params.except(:avatar_url))
    process_avatar_from_url
  end

  def update
    @assistant.with_lock do
      attrs = assistant_params.except(:avatar_url)
      # Merge partial config updates over the persisted config (inside the
      # lock) so concurrent edits to different keys don't clobber each other.
      attrs[:config] = @assistant.config.deep_merge(attrs[:config].to_unsafe_h) if attrs[:config].present?
      @assistant.update!(attrs)
    end
    process_avatar_from_url
  end

  def destroy
    @assistant.destroy!
    head :no_content
  end

  def avatar
    @assistant.avatar.purge if @assistant.avatar.attached?
    render :show
  end

  def playground
    if params[:playground_config].nil?
      render_legacy_playground
    else
      render_configured_playground
    end
  rescue Pilot::Playground::SessionConfig::Invalid => e
    render json: { error: 'Invalid playground configuration', errors: e.errors }, status: :unprocessable_entity
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

  # Backward-compatible path: no configuration payload means run with the
  # assistant's persisted scenarios, rules, and knowledge, and return the
  # original response shape.
  def render_legacy_playground
    result = Custom::Pilot::AutopilotService.new(
      assistant: @assistant,
      message: params[:message_content],
      message_history: parsed_message_history,
      account: Current.account,
      source: 'playground'
    ).perform

    render json: { reply: result.reply, invoked_tool_names: result.invoked_tool_names }, status: :ok
  end

  def render_configured_playground
    result = Pilot::Playground::SessionRunner.call(
      assistant: @assistant,
      payload: params[:playground_config],
      message: params[:message_content],
      message_history: parsed_message_history,
      account: Current.account
    )

    render json: result, status: :ok
  end

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
    params.permit(:name, :description, :response_guidelines, :guardrails, :avatar, :avatar_url, enabled_tool_slugs: [], config: {})
  end

  def process_avatar_from_url
    ::Avatar::AvatarFromUrlJob.perform_later(@assistant, params[:avatar_url]) if params[:avatar_url].present?
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
