# Permission-aware filter applied BEFORE the runner is built in
# `Custom::Pilot::CopilotService` so the LLM never sees tool names it
# cannot actually call (pilot-copilot spec — "Permission-aware tool
# filtering before LLM").
#
# Drops a tool when ANY of these is true:
#
#   1. The tool is a custom HTTP tool (i.e. responds to `custom?` with
#      `true`) AND the account's `pilot_tools` feature flag is off.
#   2. The tool's class declares `required_role :administrator` (etc.)
#      and the requesting agent's `AccountUser#role` is below the
#      declared one.
#   3. The bound assistant's `config['disabled_tools']` array lists the
#      tool's name.
class Custom::Pilot::CopilotToolPermissionFilter
  def initialize(account:, user:, assistant: nil)
    @account = account
    @user = user
    @assistant = assistant
  end

  def call(tools)
    tools.reject { |tool| blocked?(tool) }
  end

  private

  attr_reader :account, :user, :assistant

  def blocked?(tool)
    custom_tool_blocked_by_account?(tool) ||
      role_blocked?(tool) ||
      disabled_by_assistant?(tool)
  end

  def custom_tool_blocked_by_account?(tool)
    return false unless tool.respond_to?(:custom?) && tool.custom?

    !account&.feature_enabled?('pilot_tools')
  end

  def role_blocked?(tool)
    required = tool.class.try(:required_role)
    return false if required.blank?

    agent_role = user&.account_users&.find_by(account_id: account&.id)&.role
    agent_role.to_s != required.to_s
  end

  def disabled_by_assistant?(tool)
    disabled = assistant&.config&.dig('disabled_tools')
    return false if disabled.blank?

    Array(disabled).map(&:to_s).include?(tool.name.to_s)
  end
end
