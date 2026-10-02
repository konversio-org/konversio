class Voice::StatusManager
  pattr_initialize [:call!]

  # Applies a single status transition to the call. Returns true when the call
  # changed state, false when the update was rejected, a duplicate, or blocked
  # because the call already reached a terminal status.
  def process_status_update(status, duration: nil, timestamp: nil)
    status = status.to_s
    return false unless Call::STATUSES.include?(status)
    return false if call.finished?
    # Repeats are ignored, except an in-progress update that carries an earlier
    # timestamp refines started_at so out-of-order retries keep the earliest.
    return false if call.status == status && !earlier_started_at?(status, timestamp)

    apply!(status, duration: duration, timestamp: timestamp)
    bump_conversation!
    rebroadcast_message!
    true
  end

  private

  def earlier_started_at?(status, timestamp)
    return false unless status == 'in_progress' && timestamp.present?

    call.started_at.nil? || Time.zone.at(timestamp) < call.started_at
  end

  def apply!(status, duration:, timestamp:)
    at = timestamp || Time.zone.now.to_i
    changes = { status: status }

    if status == 'in_progress'
      started = Time.zone.at(at)
      changes[:started_at] = started if call.started_at.nil? || started < call.started_at
    else
      call.ended_at = at
      changes[:meta] = call.meta
      changes[:duration_seconds] = resolve_duration(duration, at)
    end

    call.update!(changes)
  end

  def resolve_duration(reported, timestamp)
    return reported if reported

    return unless call.started_at

    [timestamp - call.started_at.to_i, 0].max
  end

  def bump_conversation!
    call.conversation.update!(last_activity_at: Time.zone.now)
  end

  # Touch so the message.updated dispatcher rebroadcasts the embedded call payload.
  def rebroadcast_message!
    call.message&.touch # rubocop:disable Rails/SkipsModelValidations
  end
end
