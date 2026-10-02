class Whatsapp::IncomingCallService
  # A terminate can overtake its paired connect by ~1s; tombstone it briefly.
  TERMINATE_TOMBSTONE_TTL = 60

  TERMINATE_FAILURES = %w[failed error rejected busy invalid_offer cancelled].freeze

  pattr_initialize [:inbox!, :params!]

  def perform
    return unless inbox.channel.voice_enabled?

    Array(params[:calls]).each { |call| handle_event(call.with_indifferent_access) }
    Array(params[:statuses]).each { |status| handle_status(status.with_indifferent_access) }
  end

  private

  def handle_event(payload)
    case payload[:event]
    when 'connect' then handle_connect(payload)
    when 'terminate' then handle_terminate(payload)
    else Rails.logger.warn "[WHATSAPP CALL] Unknown call event: #{payload[:event]}"
    end
  end

  # Meta's `connect` fires when the WebRTC tunnel is ready, ~20s before the
  # contact answers; the real pickup is the separate status=ACCEPTED webhook.
  def handle_status(payload)
    return unless payload[:type] == 'call'

    call = Call.whatsapp.find_by(provider_call_id: payload[:id])
    return unless call

    case payload[:status]
    when 'ACCEPTED' then mark_outbound_accepted(call, payload)
    when 'RINGING' then nil
    else Rails.logger.info "[WHATSAPP CALL] Unhandled call status: #{payload[:status]} for #{payload[:id]}"
    end
  end

  def mark_outbound_accepted(call, payload)
    call.with_lock do
      next unless call.outgoing?
      next if call.in_progress? || call.finished?

      started_at = payload[:timestamp].present? ? Time.zone.at(payload[:timestamp].to_i) : Time.current
      transition!(call, 'in_progress', started_at: started_at)
      broadcast(call, 'voice_call.outbound_accepted')
    end
  end

  def handle_connect(payload)
    call = Call.whatsapp.find_by(provider_call_id: payload[:id])
    return create_inbound_call(payload) if call.nil? && inbound_offer?(payload)
    return if call.nil?

    return apply_outbound_answer(call, payload) if call.outgoing?

    Rails.logger.info "[WHATSAPP CALL] Duplicate inbound connect for #{payload[:id]}; ignoring"
  end

  def inbound_offer?(payload)
    payload.dig(:session, :sdp_type).to_s.downcase == 'offer'
  end

  def create_inbound_call(payload)
    unless inbox.channel.inbound_calls_enabled?
      inbox.channel.provider_service.reject_call(payload[:id])
      return
    end

    sdp_offer = payload.dig(:session, :sdp)
    call = build_inbound_call(payload, sdp_offer)
    return if call.finished? # terminated before pickup; no ringing widget to surface

    update_conversation(call)
    broadcast_incoming(call, sdp_offer)
  end

  # Build and finalize in one transaction so a pre-arrived terminate leaves the
  # message already terminal and agents are never rung for a dead call.
  def build_inbound_call(payload, sdp_offer)
    ActiveRecord::Base.transaction do
      call = Voice::InboundCallFactory.perform!(
        inbox: inbox,
        call_sid: payload[:id],
        provider: :whatsapp,
        extra_meta: { 'sdp_offer' => sdp_offer, 'ice_servers' => Call.default_ice_servers },
        caller: caller_attributes(payload)
      )
      tombstone = consume_tombstone(payload[:id])
      finalize_terminate(call, tombstone['duration'], tombstone['terminate_reason']) if tombstone
      call
    end
  end

  # `connect` only signals the tunnel is up; store Meta's answer so the browser
  # can complete the handshake while the call stays ringing until ACCEPTED.
  def apply_outbound_answer(call, payload)
    call.with_lock do
      next if call.finished? || call.meta&.dig('sdp_answer').present?

      sdp_answer = payload.dig(:session, :sdp)&.gsub('a=setup:actpass', 'a=setup:active')
      call.update!(meta: (call.meta || {}).merge('sdp_answer' => sdp_answer))
      broadcast(call, 'voice_call.outbound_connected', sdp_answer: sdp_answer)
    end
  end

  def handle_terminate(payload)
    call = Call.whatsapp.find_by(provider_call_id: payload[:id])
    return record_tombstone(payload) if call.nil?

    finalize_terminate(call, payload[:duration], payload[:terminate_reason])
  end

  def finalize_terminate(call, duration, reason)
    call.with_lock do
      next if call.finished?

      status = terminate_status(call, duration.to_i, reason.to_s)
      transition!(call, status, duration_seconds: duration&.to_i, end_reason: reason,
                                meta: (call.meta || {}).merge('ended_at' => Time.zone.now.to_i))
      broadcast(call, 'voice_call.ended', status: call.display_status, duration_seconds: call.duration_seconds)
    end
  end

  def terminate_status(call, duration, reason)
    return 'failed' if TERMINATE_FAILURES.any? { |failure| reason.include?(failure) }

    answered?(call, duration) ? 'completed' : 'no_answer'
  end

  # accepted_by_agent_id is the initiating agent on outbound, so it only means
  # "answered" for inbound calls.
  def answered?(call, duration)
    call.in_progress? || duration.positive? || (call.incoming? && call.accepted_by_agent_id.present?)
  end

  def transition!(call, status, **attrs)
    call.update!(status: status, **attrs)
    Voice::CallMessageFactory.new(call).update_status!(status: status, agent: call.accepted_by_agent,
                                                       duration_seconds: attrs[:duration_seconds])
    update_conversation(call)
  end

  def update_conversation(call)
    call.conversation.update!(
      additional_attributes: (call.conversation.additional_attributes || {}).merge(
        'call_status' => call.display_status, 'call_direction' => call.direction_label
      )
    )
  end

  def caller_attributes(payload)
    phone = payload[:from].presence || caller_contact(payload)&.dig(:wa_id)
    name = caller_contact(payload)&.dig(:profile, :name).presence || phone
    attributes = { name: name }
    attributes[:phone_number] = "+#{phone}" if phone.present?
    { source_ids: [phone].compact, contact_attributes: attributes }
  end

  def caller_contact(payload)
    Array(params[:contacts]).map(&:with_indifferent_access).find { |contact| contact[:wa_id].to_s == payload[:from].to_s }
  end

  # Ring the assignee, else online inbox agents, else the inbox's own agents and
  # account admins — never the whole account stream.
  def broadcast_incoming(call, sdp_offer)
    contact = call.contact
    assignee = call.conversation.assignee
    streams = assignee ? [assignee.pubsub_token] : (online_agent_streams.presence || fallback_agent_streams)
    broadcast(call, 'voice_call.incoming',
              streams: streams,
              direction: call.direction_label, inbox_id: call.inbox_id,
              sdp_offer: sdp_offer, ice_servers: Call.default_ice_servers,
              recording_enabled: call.recording_enabled?,
              caller: { name: contact.name, phone: contact.phone_number, avatar: contact.avatar_url })
  end

  def online_agent_streams
    inbox.available_agents.pluck('users.pubsub_token').compact
  end

  def fallback_agent_streams
    user_ids = inbox.member_ids | inbox.account.administrators.ids
    User.where(id: user_ids).pluck(:pubsub_token).compact
  end

  def broadcast(call, event, streams: account_streams, **extra)
    payload = { event: event, data: base_payload(call).merge(extra) }
    streams.each { |stream| ActionCable.server.broadcast(stream, payload) }
  end

  def account_streams
    ["account_#{inbox.account_id}"]
  end

  def base_payload(call)
    { account_id: inbox.account_id, id: call.id, call_id: call.provider_call_id,
      provider: 'whatsapp', conversation_id: call.conversation_id }
  end

  def record_tombstone(payload)
    Redis::Alfred.setex(
      tombstone_key(payload[:id]),
      { 'duration' => payload[:duration], 'terminate_reason' => payload[:terminate_reason] }.to_json,
      TERMINATE_TOMBSTONE_TTL
    )
  end

  def consume_tombstone(provider_call_id)
    key = tombstone_key(provider_call_id)
    raw = Redis::Alfred.get(key)
    return if raw.blank?

    Redis::Alfred.delete(key)
    JSON.parse(raw)
  end

  def tombstone_key(provider_call_id)
    "WHATSAPP_CALL_TERMINATE_TOMBSTONE:#{provider_call_id}"
  end
end
