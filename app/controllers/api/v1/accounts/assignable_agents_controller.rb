class Api::V1::Accounts::AssignableAgentsController < Api::V1::Accounts::BaseController
  before_action :fetch_inboxes

  def index
    agent_ids = @inboxes.map do |inbox|
      authorize inbox, :show?
      member_ids = inbox.members.pluck(:user_id)
      member_ids
    end
    agent_ids = agent_ids.inject(:&)
    agents = Current.account.users.where(id: agent_ids)
    @assignable_agents = (agents + Current.account.administrators).uniq
    fetch_ai_assignees if include_ai_assignees?
  end

  private

  # Opt-in only: older clients assume every payload entry is a human user, so
  # AI assignees (Pilot assistants and agent bots) are appended only when the
  # client asks for them.
  def fetch_ai_assignees
    @ai_assignees = Current.account.pilot_assistants.order(:name).to_a +
                    AgentBot.accessible_to(Current.account).order(:name).to_a
  end

  def include_ai_assignees?
    ActiveModel::Type::Boolean.new.cast(permitted_params[:include_ai_assignees])
  end

  def fetch_inboxes
    @inboxes = Current.account.inboxes.find(permitted_params[:inbox_ids])
  end

  def permitted_params
    params.permit(:include_ai_assignees, inbox_ids: [])
  end
end
