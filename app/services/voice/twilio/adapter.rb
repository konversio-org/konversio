class Voice::Twilio::Adapter
  TERMINAL_STATUS_EVENTS = %w[initiated ringing answered completed failed busy no-answer canceled].freeze

  pattr_initialize [:channel!]

  # Dials the contact through Twilio; Twilio then fetches the channel's TwiML
  # webhook to learn how to bridge the call into a conference.
  def initiate_call(to:)
    call = client.calls.create(
      from: channel.phone_number,
      to: to,
      url: call_webhook_url,
      status_callback: status_webhook_url,
      status_callback_event: TERMINAL_STATUS_EVENTS,
      status_callback_method: 'POST'
    )

    {
      provider: 'twilio',
      call_sid: call.sid,
      status: call.status,
      call_direction: 'outbound',
      requires_agent_join: true
    }
  end

  private

  def call_webhook_url
    channel.voice_call_webhook_url
  end

  def status_webhook_url
    channel.voice_status_webhook_url
  end

  def client
    channel.client
  end
end
