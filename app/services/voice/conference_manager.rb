class Voice::ConferenceManager
  AGENT_LABEL = /\Aagent-(\d+)-account-(\d+)\z/

  pattr_initialize [:call!, :event!, :participant_label]

  def process
    return if call.finished?

    case event.to_s
    when 'start' then mark_started!
    when 'join' then handle_join! if agent_participant?
    when 'leave' then handle_leave!
    when 'end' then finalize!
    end
  end

  private

  def status_manager
    @status_manager ||= Voice::StatusManager.new(call: call)
  end

  # A delayed conference-start retry must not roll a progressed call back.
  def mark_started!
    return unless call.ringing?

    status_manager.process_status_update('ringing')
  end

  def handle_join!
    user_id = agent_user_id
    return unless user_id

    return unless claim!(user_id)

    status_manager.process_status_update('in_progress', timestamp: now)
    return unless accepted_broadcast_gate!

    call.broadcast_voice_call_event(:accepted, accepted_by_agent_id: call.accepted_by_agent_id)
  end

  # First agent to join owns the call; later joins are ignored here (the API
  # layer surfaces the conflict to the losing agent).
  def claim!(user_id)
    claimed = false
    call.with_lock do
      claimed = call.accepted_by_agent_id.blank? || call.accepted_by_agent_id == user_id
      call.update!(accepted_by_agent_id: user_id) if claimed && call.accepted_by_agent_id != user_id
    end

    auto_assign!(user_id) if claimed
    claimed
  end

  # Separate exactly-once gate: the accept may already be recorded (outbound
  # creation, the join API), so it cannot double as the "already broadcast" flag.
  def accepted_broadcast_gate!
    first_time = false
    call.with_lock do
      next if call.accepted_broadcast_at.present?

      call.update!(accepted_broadcast_at: now)
      first_time = true
    end
    first_time
  end

  def auto_assign!(user_id)
    conversation = call.conversation
    return if conversation.assigned_entity.present?

    Conversations::AssignmentService.new(conversation: conversation, assignee_id: user_id).perform
  end

  # Only trust a label whose embedded account id matches the call's account.
  def agent_user_id
    match = participant_label.to_s.match(AGENT_LABEL)
    return unless match
    return unless match[2].to_i == call.account_id

    match[1].to_i
  end

  def handle_leave!
    case call.status
    when 'ringing'
      status_manager.process_status_update('no_answer', timestamp: now)
    when 'in_progress'
      status_manager.process_status_update('completed', timestamp: now)
    end
  end

  def finalize!
    return if call.finished?

    status_manager.process_status_update('completed', timestamp: now)
  end

  def agent_participant?
    participant_label.to_s.start_with?('agent-')
  end

  def now
    Time.zone.now.to_i
  end
end
