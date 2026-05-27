# Scheduled by `Pilot::AutopilotInferenceJob#process_handover` to fire
# `handoff_timeout_minutes` after a customer-initiated handoff. When the
# timer elapses and no human agent has taken over, this job flips the
# conversation back to `pending`, posts the configured fallback message,
# and writes a timeline activity row — re-engaging the bot so the
# customer isn't stranded.
#
# The job is guarded against staleness on every front: the conversation
# may have already resolved, the agent may have replied or assigned, or
# a later handoff may have superseded this `requested_at` token. Any of
# those means we exit silently.
class Pilot::HandoffTimeoutJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, requested_at)
    conversation = ::Conversation.find_by(id: conversation_id)
    return unless resumable?(conversation, requested_at)

    assistant = assistant_for(conversation)
    return if assistant.blank?

    resume_bot!(conversation, assistant)
  end

  private

  def resumable?(conversation, requested_at)
    return false if conversation.blank? || conversation.resolved? || conversation.assignee_id.present?
    return false unless current_handoff?(conversation, requested_at)

    requested_time = parse_timestamp(requested_at)
    return false if requested_time.blank?

    !conversation.human_replied_since?(requested_time)
  end

  def current_handoff?(conversation, requested_at)
    handoff = conversation.additional_attributes&.dig('pilot_handoff') || {}
    handoff['state'] == 'handoff_requested' && handoff['requested_at'] == requested_at
  end

  def parse_timestamp(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def assistant_for(conversation)
    join = ::Pilot::Inbox.find_by(inbox_id: conversation.inbox_id)
    join&.assistant
  end

  def resume_bot!(conversation, assistant)
    conversation.pending!

    handoff = conversation.additional_attributes['pilot_handoff']
    handoff['state'] = 'pilot_resumed'
    handoff['resume_count'] = handoff['resume_count'].to_i + 1
    conversation.additional_attributes['pilot_handoff'] = handoff
    conversation.save!

    post_fallback_message(conversation, assistant)
    append_activity_message(conversation)
  end

  def post_fallback_message(conversation, assistant)
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: assistant,
      content: assistant.handoff_timeout_message
    )
  end

  def append_activity_message(conversation)
    conversation.messages.create!(
      message_type: :activity,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      content: I18n.t('pilot.activity.handoff_timeout_triggered')
    )
  rescue StandardError => e
    Rails.logger.warn("[pilot.handoff_timeout_job] activity persist failed: #{e.class}: #{e.message}")
  end
end
