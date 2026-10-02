class Voice::Twilio::ConferenceService
  pattr_initialize [:call!]

  def ensure_conference_sid
    return call.conference_sid if call.conference_sid.present?

    call.update!(conference_sid: call.default_conference_sid)
    call.conference_sid
  end

  # Reserves the call for the joining agent. Raises before touching anything when
  # another agent already holds it, so the API can answer 409.
  def mark_agent_joined(user:)
    claim!(user)
    assign_conversation!(user)
  end

  # Tears the provider conference down. Raises on failure so the caller can leave
  # local state untouched and keep the call repairable.
  def end_conference
    return if call.conference_sid.blank?

    client = call.inbox.channel.client
    client
      .conferences
      .list(friendly_name: call.conference_sid, status: 'in-progress')
      .each { |conference| client.conferences(conference.sid).update(status: 'completed') }
  end

  private

  def claim!(user)
    call.with_lock do
      raise_already_accepted!(call.accepted_by_agent) if held_by_other?(user)

      call.update!(accepted_by_agent: user) if call.accepted_by_agent_id != user.id
    end
  end

  def held_by_other?(user)
    call.accepted_by_agent_id.present? && call.accepted_by_agent_id != user.id
  end

  def raise_already_accepted!(agent)
    raise CustomExceptions::CallAlreadyAccepted.new(agent_name: agent&.available_name || agent&.name)
  end

  # Manual and pre-call assignments win; only a completely unheld thread is claimed.
  def assign_conversation!(user)
    conversation = call.conversation
    return if conversation.assigned_entity.present?

    Conversations::AssignmentService.new(conversation: conversation, assignee_id: user.id).perform
  end
end
