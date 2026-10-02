class Whatsapp::CallService
  pattr_initialize [:call!, :agent!, :sdp_answer]

  def accept
    raise Voice::CallErrors::CallFailed, 'sdp_answer is required' if sdp_answer.blank?

    # All side effects under the lock so a concurrent terminate cannot finalize
    # the call between the status update and the message/conversation writes.
    call.with_lock do
      transition_to_in_progress!
      update_message('in_progress')
      claim_conversation!
      broadcast(:accepted, accepted_by_agent_id: agent.id)
    end
    call
  end

  def reject
    call.with_lock do
      next if call.finished? || call.in_progress?

      invoke_provider!(:reject_call)
      call.update!(accepted_by_agent_id: agent.id) if call.accepted_by_agent_id.nil?
      finalize!('rejected', end_reason: 'agent_rejected')
    end
    call
  end

  def terminate
    call.with_lock do
      next if call.finished?

      invoke_provider!(:terminate_call)
      # The webhook arrives after the call is already terminal and bails on its
      # idempotency guard, so duration must be computed locally here.
      if call.in_progress?
        duration = call.started_at ? (Time.current - call.started_at).to_i : nil
        finalize!('completed', duration_seconds: duration, end_reason: 'agent_hangup')
      else
        finalize!('no_answer', end_reason: 'agent_hangup')
      end
    end
    call
  end

  private

  def transition_to_in_progress!
    raise Voice::CallErrors::AlreadyAccepted if call.in_progress?
    raise Voice::CallErrors::CallAlreadyEnded if call.finished?
    raise Voice::CallErrors::NotRinging unless call.ringing?

    forward_answer!
    call.update!(status: 'in_progress', accepted_by_agent_id: agent.id, started_at: Time.current,
                 meta: (call.meta || {}).merge('sdp_answer' => sdp_answer))
  end

  def forward_answer!
    invoke_provider!(:pre_accept_call, sdp_answer)
    invoke_provider!(:accept_call, sdp_answer)
  end

  # Claim an unheld conversation and set call_status in one save so the activity
  # message and the conversation.updated webhook both carry the change.
  def claim_conversation!
    conversation = call.conversation
    attrs = { additional_attributes: (conversation.additional_attributes || {}).merge('call_status' => call.display_status) }
    attrs[:assignee] = agent if conversation.assigned_entity.nil?
    conversation.update!(attrs)
  end

  # Raise on provider failure so callers abort before finalizing local state.
  def invoke_provider!(method, *)
    success = call.inbox.channel.provider_service.public_send(method, call.provider_call_id, *)
    raise Voice::CallErrors::CallFailed, "Meta #{method} failed" unless success
  rescue Voice::CallErrors::CallFailed
    raise
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP CALL] #{method} failed: #{e.class} #{e.message}"
    raise Voice::CallErrors::CallFailed, "Meta #{method} failed"
  end

  def finalize!(status, **attrs)
    call.update!(status: status, meta: (call.meta || {}).merge('ended_at' => Time.zone.now.to_i), **attrs)
    update_message(status, duration_seconds: attrs[:duration_seconds])
    update_conversation_call_status(call.display_status)
    broadcast(:ended, status: call.display_status)
  end

  def update_message(status, duration_seconds: nil)
    Voice::CallMessageFactory.new(call).update_status!(status: status, agent: agent, duration_seconds: duration_seconds)
  end

  def update_conversation_call_status(status)
    call.conversation.update!(
      additional_attributes: (call.conversation.additional_attributes || {}).merge('call_status' => status)
    )
  end

  def broadcast(event, **extra)
    payload = {
      event: "voice_call.#{event}",
      data: { id: call.id, call_id: call.provider_call_id, provider: call.provider,
              conversation_id: call.conversation_id, account_id: call.account_id }.merge(extra)
    }
    ActionCable.server.broadcast("account_#{call.account_id}", payload)
  end
end
