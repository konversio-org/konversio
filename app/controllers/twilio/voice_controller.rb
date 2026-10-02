class Twilio::VoiceController < ApplicationController
  CONFERENCE_EVENT_PATTERNS = {
    /conference-start/i => 'start',
    /participant-join/i => 'join',
    /participant-leave/i => 'leave',
    /conference-end/i => 'end'
  }.freeze

  before_action :set_inbox!

  def status
    Voice::StatusCallbackService.new(
      account: inbox_account,
      call_sid: twilio_call_sid,
      call_status: params[:CallStatus],
      payload: params.to_unsafe_h
    ).perform

    head :no_content
  end

  def call_twiml
    return render xml: reject_twiml if reject_inbound?

    render xml: conference_twiml(resolve_call)
  end

  def conference_status
    event = mapped_conference_event
    return head :no_content if event.nil?

    call = find_conference_call!
    persist_twilio_conference_sid!(call)

    Voice::ConferenceManager.new(call: call, event: event, participant_label: params[:ParticipantLabel]).process

    head :no_content
  end

  def recording_status
    Voice::RecordingCallbackService.new(account: inbox_account, payload: params.to_unsafe_h).perform

    head :no_content
  end

  private

  attr_reader :inbox

  def twilio_call_sid
    params[:CallSid]
  end

  def twilio_from
    params[:From].to_s
  end

  def twilio_direction
    @twilio_direction ||= (params['Direction'] || params['CallDirection']).to_s
  end

  def mapped_conference_event
    event = params[:StatusCallbackEvent].to_s
    CONFERENCE_EVENT_PATTERNS.each { |pattern, mapped| return mapped if event.match?(pattern) }
    nil
  end

  def agent_leg?(from)
    from.start_with?('client:')
  end

  # A fresh contact-initiated leg on an inbox with inbound calls off.
  def reject_inbound?
    twilio_direction == 'inbound' && !agent_leg?(twilio_from) && !inbox_channel.inbound_calls_enabled?
  end

  def reject_twiml
    Twilio::TwiML::VoiceResponse.new(&:reject).to_s
  end

  def resolve_call
    return find_agent_call if agent_leg?(twilio_from)

    case twilio_direction
    when 'inbound'
      Voice::InboundCallFactory.perform!(
        inbox: inbox,
        call_sid: twilio_call_sid,
        caller: { source_ids: [twilio_from], contact_attributes: { name: twilio_from, phone_number: twilio_from } }
      )
    when 'outbound-api', 'outbound-dial'
      sync_outbound_leg
    else
      raise ArgumentError, "Unsupported Twilio direction: #{twilio_direction}"
    end
  end

  def find_agent_call
    sid = params[:call_sid].presence
    raise ArgumentError, 'call_sid is required for agent leg' if sid.blank?

    inbox_calls.find_by!(provider_call_id: sid)
  end

  def sync_outbound_leg
    parent_sid = params['ParentCallSid'].presence
    lookup_sid = twilio_direction == 'outbound-dial' ? parent_sid || twilio_call_sid : twilio_call_sid
    call = inbox_calls.find_by!(provider_call_id: lookup_sid)

    call.update!(parent_call_sid: parent_sid) if parent_sid.present? && call.parent_call_sid != parent_sid
    call
  end

  def inbox_calls
    Call.where(inbox_id: inbox.id, provider: :twilio)
  end

  def conference_twiml(call)
    conference_sid = call.conference_sid.presence || call.default_conference_sid
    call.update!(conference_sid: conference_sid) if call.conference_sid.blank?

    Twilio::TwiML::VoiceResponse.new.tap do |response|
      response.dial do |dial|
        dial.conference(
          conference_sid,
          start_conference_on_enter: agent_leg?(twilio_from),
          end_conference_on_exit: false,
          record: call.recording_enabled? ? 'record-from-start' : 'do-not-record',
          recording_status_callback: phone_callback_url(:twilio_voice_recording_status_url),
          recording_status_callback_event: 'completed',
          recording_status_callback_method: 'POST',
          status_callback: phone_callback_url(:twilio_voice_conference_status_url),
          status_callback_event: 'start end join leave',
          status_callback_method: 'POST',
          participant_label: participant_label_for(twilio_from)
        )
      end
    end.to_s
  end

  def participant_label_for(from)
    return from.delete_prefix('client:') if agent_leg?(from)

    'contact'
  end

  def phone_callback_url(route)
    Rails.application.routes.url_helpers.public_send(route, phone: inbox_channel.phone_number.to_s.delete_prefix('+'))
  end

  def find_conference_call!
    name = params[:FriendlyName].to_s
    call = inbox_calls.by_conference_sid(name).first if name.present?
    call || inbox_calls.find_by!(provider_call_id: twilio_call_sid)
  end

  # Twilio's recording webhook carries only its own ConferenceSid, so persist it
  # the first time we see it for the recording lookup to match later.
  def persist_twilio_conference_sid!(call)
    sid = params[:ConferenceSid].to_s
    return if sid.blank? || call.twilio_conference_sid == sid

    call.update!(twilio_conference_sid: sid)
  end

  def set_inbox!
    digits = params[:phone].to_s.gsub(/\D/, '')
    phone_number = "+#{digits}"
    channel = Channel::TwilioSms.find_by!(phone_number: phone_number)
    raise ActiveRecord::RecordNotFound, "Voice not enabled for #{phone_number}" unless channel.voice_enabled?

    @inbox = channel.inbox
  end

  def inbox_account
    inbox.account
  end

  def inbox_channel
    inbox.channel
  end
end
