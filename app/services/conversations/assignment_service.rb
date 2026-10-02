class Conversations::AssignmentService
  def initialize(conversation:, assignee_id:, assignee_type: nil)
    @conversation = conversation
    @assignee_id = assignee_id
    @assignee_type = assignee_type
  end

  def perform
    conversation.with_lock do
      if agent_bot_assignment?
        assign_ai_assignee(agent_bot)
      elsif pilot_assistant_assignment?
        assign_ai_assignee(pilot_assistant)
      else
        assign_agent
      end
    end
  end

  private

  attr_reader :conversation, :assignee_id, :assignee_type

  def assign_agent
    had_ai_assignee = conversation.assignee_agent_bot_id.present?
    conversation.assignee = assignee
    conversation.assignee_agent_bot_id = nil
    conversation.ai_assignee_type = nil
    if had_ai_assignee
      conversation.status = :open if conversation.pending?
      conversation.waiting_since = Time.current if conversation.waiting_since.blank?
    end
    conversation.save!
    assignee
  end

  # An AI assignee (webhook agent bot or Pilot assistant) takes over the
  # conversation: the human assignee is cleared and the thread goes back to
  # `pending` for bot handling.
  def assign_ai_assignee(entity)
    return unless entity

    conversation.assignee = nil
    conversation.ai_assignee = entity
    conversation.status = :pending
    conversation.save!
    entity
  end

  def assignee
    @assignee ||= conversation.account.users.find_by(id: assignee_id)
  end

  def agent_bot
    @agent_bot ||= AgentBot.accessible_to(conversation.account).find_by(id: assignee_id)
  end

  def pilot_assistant
    @pilot_assistant ||= conversation.account.pilot_assistants.find_by(id: assignee_id)
  end

  def agent_bot_assignment?
    assignee_type.to_s == 'AgentBot'
  end

  def pilot_assistant_assignment?
    assignee_type.to_s == 'Pilot::Assistant'
  end
end
