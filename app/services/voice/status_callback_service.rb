class Voice::StatusCallbackService
  pattr_initialize [:account!, :call_sid!, { call_status: nil }, { payload: {} }]

  STATUS_MAP = {
    'queued' => 'ringing',
    'initiated' => 'ringing',
    'ringing' => 'ringing',
    'in-progress' => 'in_progress',
    'inprogress' => 'in_progress',
    'answered' => 'in_progress',
    'completed' => 'completed',
    'busy' => 'no_answer',
    'no-answer' => 'no_answer',
    'failed' => 'failed',
    'canceled' => 'failed'
  }.freeze

  def perform
    status = STATUS_MAP[call_status.to_s.strip.downcase]
    return if status.blank?

    call = Call.where(account_id: account.id).find_by(provider: :twilio, provider_call_id: call_sid)
    return unless call

    Voice::StatusManager.new(call: call).process_status_update(
      status,
      duration: payload_duration,
      timestamp: payload_timestamp
    )
  end

  private

  def payload_duration
    return unless payload.is_a?(Hash)

    (payload['CallDuration'] || payload['call_duration'])&.to_i
  end

  def payload_timestamp
    return unless payload.is_a?(Hash)

    raw = payload['Timestamp'] || payload['timestamp']
    return if raw.blank?

    Time.zone.parse(raw).to_i
  rescue ArgumentError
    nil
  end
end
