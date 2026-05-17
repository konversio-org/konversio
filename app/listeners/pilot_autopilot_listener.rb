# Hooks the Pilot Autopilot inference into Chatwoot's MessageCreatedEvent
# pipeline. Enqueues `Pilot::AutopilotInferenceJob` for every inbound
# customer message in an inbox that has a `Pilot::Assistant` attached AND
# the account has `pilot_autopilot_enabled = true`. The job itself
# re-validates eligibility before talking to the LLM, so this listener is
# best-effort and safe to over-trigger.
class PilotAutopilotListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return if message.blank? || account.blank?
    return unless message.message_type == 'incoming'
    return if message.private?
    return unless autopilot_active?(account, message.inbox)

    ::Pilot::AutopilotInferenceJob.perform_later(message_id: message.id)
  end

  private

  def autopilot_active?(account, inbox)
    return false unless account.respond_to?(:pilot_enabled) && account.pilot_enabled
    return false unless account.respond_to?(:pilot_autopilot_enabled) && account.pilot_autopilot_enabled
    return false if inbox.blank?

    ::Pilot::Inbox.exists?(inbox_id: inbox.id)
  end
end
