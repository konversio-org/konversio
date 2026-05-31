# Triggered when an inbound customer message lands in an inbox that has
# a Pilot::Assistant attached AND the account has the `pilot_autopilot`
# feature flag enabled. Runs `AutopilotService` and either posts the
# reply as an outgoing message or hands the conversation off to a human.
# The conversation stays `open` through the whole handoff wait so it sits
# in agent queues and is eligible for Chatwoot's native auto-resolve;
# there is no bot-resume timer.
class Pilot::AutopilotInferenceJob < ApplicationJob
  include Events::Types

  queue_as :default

  def perform(message_id:)
    message = ::Message.find_by(id: message_id)
    return if message.blank?
    return unless eligible?(message)

    conversation = message.conversation
    assistant = assistant_for(conversation.inbox)
    return if assistant.blank?

    result = run_inference_with_typing(conversation, assistant, message)
    dispatch_inference_outcome(result, conversation, assistant)
  rescue ::Custom::Pilot::AutopilotService::FeatureDisabledError => e
    Rails.logger.warn("[pilot.autopilot_inference_job] feature disabled msg=#{message_id}: #{e.message}")
  rescue ::Custom::Pilot::AutopilotService::Error => e
    Rails.logger.error("[pilot.autopilot_inference_job] LLM failure msg=#{message_id}: #{e.message}")
    # Dead air on error is the worst outcome — hand off to a human instead
    # of swallowing it. conversation/assistant are set before inference runs.
    handoff_on_error(conversation, assistant) if conversation && assistant
  end

  private

  def run_inference_with_typing(conversation, assistant, incoming_message)
    dispatch_typing(CONVERSATION_TYPING_ON, conversation, assistant)
    notify_whatsapp_typing(incoming_message)
    ::Custom::Pilot::AutopilotService.new(
      assistant: assistant,
      conversation: conversation,
      account: assistant.account
    ).perform
  ensure
    dispatch_typing(CONVERSATION_TYPING_OFF, conversation, assistant)
  end

  def dispatch_typing(event, conversation, assistant)
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, conversation: conversation, user: assistant)
  rescue StandardError => e
    Rails.logger.warn("[pilot.autopilot_inference_job] typing dispatch failed event=#{event}: #{e.message}")
  end

  # Best-effort: a Meta blip on the typing call must never break the
  # actual reply, so we swallow errors and just log them.
  def notify_whatsapp_typing(message)
    channel = message.inbox.channel
    return unless channel.is_a?(::Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
    return if message.source_id.blank?

    channel.provider_service.mark_seen_with_typing(message.source_id)
  rescue StandardError => e
    Rails.logger.warn("[pilot.autopilot_inference_job] whatsapp typing failed: #{e.message}")
  end

  def eligible?(message)
    return false unless message.message_type == 'incoming'
    return false if message.private?

    account = message.account
    return false if account.blank?
    return false unless account.feature_enabled?('pilot')
    return false unless account.feature_enabled?('pilot_autopilot')

    true
  end

  def assistant_for(inbox)
    return nil if inbox.blank?

    join = ::Pilot::Inbox.find_by(inbox_id: inbox.id)
    join&.assistant
  end

  # Routes the LLM result to the correct side-effect: hand off to a
  # human, acknowledge the team is offline, or just post the reply.
  # Extracted from `perform` to keep that method's complexity under
  # the project's rubocop thresholds.
  def dispatch_inference_outcome(result, conversation, assistant)
    if fresh_handover?(result, conversation)
      return process_handover(conversation, assistant, result) if agents_available?(conversation.inbox)

      return acknowledge_offline_team(conversation, assistant)
    end

    return resolve_after_reply(conversation, assistant, result) if fresh_resolution?(result, conversation)

    post_reply(conversation, assistant, result.reply)
  end

  # Action C: the assistant signalled the conversation is finished. Post its
  # (token-stripped) sign-off, then close. Gated by the account's auto-resolve
  # mode — a `disabled` account never honours the token.
  def fresh_resolution?(result, conversation)
    result.resolution? && !conversation.account.pilot_auto_resolve_disabled?
  end

  def resolve_after_reply(conversation, assistant, result)
    post_reply(conversation, assistant, result.reply)
    ::Custom::Pilot::ConversationResolver.resolve!(
      conversation: conversation,
      assistant: assistant,
      reason: 'agentic_close'
    )
  end

  def fresh_handover?(result, conversation)
    result.handover.handover? &&
      !already_in_warm_handoff?(conversation) &&
      !offline_already_acknowledged?(conversation)
  end

  # Once `process_handover` has fired and the conversation carries the
  # warm-bot envelope, subsequent LLM-signalled handover intents must
  # NOT re-handoff — that creates a loop where every customer message
  # gets met with the handoff message again. Fall through to
  # `post_reply` instead so the bot can keep helping while the
  # conversation routes to a human.
  def already_in_warm_handoff?(conversation)
    conversation.additional_attributes&.dig('pilot_handoff', 'state') == 'handoff_requested'
  end

  def offline_already_acknowledged?(conversation)
    conversation.additional_attributes&.dig('pilot_handoff', 'state') == 'offline_acknowledged'
  end

  def agents_available?(inbox)
    return false if inbox.blank?
    return false unless inbox.respond_to?(:available_agents)

    inbox.available_agents.exists?
  end

  # No human is online in this inbox right now. Posting the standard
  # "I'll connect you to a teammate" message would be a lie. Instead,
  # post a one-time acknowledgement, mark the conversation so we don't
  # repeat it on every follow-up, and let the bot keep answering
  # normally via the `post_reply` path on subsequent turns.
  def acknowledge_offline_team(conversation, assistant)
    conversation.additional_attributes ||= {}
    conversation.additional_attributes['pilot_handoff'] = {
      'state' => 'offline_acknowledged',
      'acknowledged_at' => Time.zone.now.iso8601
    }
    conversation.save!

    content = assistant.config['handoff_message_offline'].presence ||
              I18n.t('conversations.pilot.handoff_offline')
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: assistant,
      content: content
    )
  end

  def post_reply(conversation, assistant, reply)
    content = reply.to_s
                   .sub(::Custom::Pilot::HandoverEvaluator::HANDOVER_SENTINEL, '')
                   .sub(::Custom::Pilot::HandoverEvaluator::RESOLUTION_SENTINEL, '')
                   .strip
    return if content.blank?

    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: assistant,
      content: content
    )
  end

  # Normal LLM-signalled handover: post the assistant's configured
  # handoff message and route to a human.
  def process_handover(conversation, assistant, result)
    ::Custom::Pilot::HandoffService.call(
      conversation: conversation,
      assistant: assistant,
      reason: handover_reason(result),
      message: assistant.config['handoff_message'].presence || I18n.t('conversations.pilot.handoff')
    )
  end

  # Inference failed (LLM error). Hand off so the customer isn't stranded
  # in dead air; post a generic "a human will help" message regardless of
  # the co-active toggle, since an error is not a normal wait.
  def handoff_on_error(conversation, assistant)
    ::Custom::Pilot::HandoffService.call(
      conversation: conversation,
      assistant: assistant,
      reason: 'inference_error',
      message: I18n.t('conversations.pilot.handoff_error')
    )
  rescue StandardError => e
    Rails.logger.error("[pilot.autopilot_inference_job] error handoff failed: #{e.class}: #{e.message}")
  end

  def handover_reason(result)
    handover = result&.handover
    return 'llm_requested' if handover.blank?

    handover.respond_to?(:reason) ? (handover.reason.presence || 'llm_requested') : 'llm_requested'
  end
end
