# No-assistant fallback per the pilot-autopilot spec ("No-assistant fallback
# on inbox" requirement). Used by `Custom::Pilot::AutopilotService` when an
# inbox has Autopilot enabled at the account level but has no `Pilot::Inbox`
# linkage (i.e. no bound assistant).
#
# The runtime must NOT raise and must NOT call the LLM. Instead, this object
# emits a structured log line + `pilot.autopilot.skipped` event so operators
# can detect mis-configured inboxes, and returns a neutral
# `AutopilotService::Result` (no reply, no handover).
class Custom::Pilot::AutopilotNoAssistantSkip
  def initialize(account:, conversation:)
    @account = account
    @conversation = conversation
  end

  def call
    Rails.logger.warn("[pilot.autopilot] skipped — no assistant attached #{payload.inspect}")
    Custom::Pilot::EventDispatcher.dispatch('pilot.autopilot.skipped', payload, time: Time.zone.now, account: account)
    Custom::Pilot::AutopilotService::Result.new(
      reply: nil,
      invoked_tool_names: [],
      handover: Custom::Pilot::HandoverEvaluator::Result.new(handover?: false, reason: nil)
    )
  end

  private

  attr_reader :account, :conversation

  def payload
    {
      account_id: account&.id,
      inbox_id: conversation&.inbox_id,
      conversation_id: conversation&.display_id,
      reason: 'no_assistant_attached'
    }
  end
end
