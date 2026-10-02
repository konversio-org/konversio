class Twilio::VoiceProvisioningService
  HTTP_METHOD = 'POST'.freeze

  pattr_initialize [:channel!]

  # Creates the TwiML app Twilio dials through and points the number's voice
  # webhooks at the app's voice endpoints. Returns the new TwiML app SID.
  def provision!
    verify_credentials!
    app_sid = create_twiml_app!
    configure_number!
    app_sid
  end

  # Re-points an existing TwiML app at the current host, recreating it when it
  # was deleted on Twilio's side.
  def sync!
    return create_twiml_app! if channel.twiml_app_sid.blank?

    channel.client.applications(channel.twiml_app_sid).update(
      voice_url: channel.voice_call_webhook_url,
      voice_method: HTTP_METHOD
    )
    channel.twiml_app_sid
  rescue Twilio::REST::RestError => e
    raise unless e.status_code == 404

    create_twiml_app!
  end

  def configure_number!
    number = find_number
    return if number.blank?

    channel.client.incoming_phone_numbers(number.sid).update(
      voice_url: channel.voice_call_webhook_url,
      voice_method: HTTP_METHOD,
      status_callback: channel.voice_status_webhook_url,
      status_callback_method: HTTP_METHOD
    )
  end

  # Best-effort teardown: always clear the stored credential so the channel
  # stops advertising voice even when Twilio is unreachable.
  def teardown!
    delete_twiml_app if channel.twiml_app_sid.present?
    clear_number!
  ensure
    channel.update(twiml_app_sid: nil)
  end

  # Raises when the number is missing or cannot do voice, so a bad enable fails loudly.
  def verify_voice_capability!
    number = find_number
    raise 'Phone number not found in the connected Twilio account' if number.blank?
    raise 'This phone number does not support voice calls' unless number.capabilities&.dig('voice')

    number
  end

  private

  def verify_credentials!
    channel.client.incoming_phone_numbers.list(limit: 1)
  end

  def create_twiml_app!
    app = channel.client.applications.create(
      friendly_name: "Konversio Voice #{channel.phone_number}",
      voice_url: channel.voice_call_webhook_url,
      voice_method: HTTP_METHOD
    )
    app.sid
  end

  def delete_twiml_app
    channel.client.applications(channel.twiml_app_sid).delete
  rescue StandardError => e
    Rails.logger.error("TWILIO_VOICE_TEARDOWN app delete failed: #{e.class} #{e.message}")
  end

  def clear_number!
    number = find_number
    return if number.blank?

    channel.client.incoming_phone_numbers(number.sid).update(voice_url: '', status_callback: '')
  rescue StandardError => e
    Rails.logger.error("TWILIO_VOICE_TEARDOWN webhook clear failed: #{e.class} #{e.message}")
  end

  def find_number
    channel.client.incoming_phone_numbers.list(phone_number: channel.phone_number).first
  rescue StandardError => e
    Rails.logger.error("TWILIO_VOICE_SETUP number lookup failed: #{e.class} #{e.message}")
    nil
  end
end
