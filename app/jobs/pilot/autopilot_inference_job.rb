module Pilot
  # Triggered when an inbound customer message lands in an inbox that has
  # a Pilot::Assistant attached AND the account has the `pilot_autopilot`
  # feature flag enabled. Runs `AutopilotService` and either posts the
  # reply as an outgoing message or transitions the conversation to
  # `pending` for human follow-up.
  class AutopilotInferenceJob < ApplicationJob
    include Events::Types

    queue_as :default

    def perform(message_id:)
      message = ::Message.find_by(id: message_id)
      return if message.blank?
      return unless eligible?(message)

      conversation = message.conversation
      assistant = assistant_for(conversation.inbox)
      return if assistant.blank?

      result = run_inference_with_typing(conversation, assistant)

      if result.handover.handover? && !already_in_warm_handoff?(conversation)
        process_handover(conversation, assistant, result)
      else
        post_reply(conversation, assistant, result.reply)
      end
    rescue ::Custom::Pilot::AutopilotService::FeatureDisabledError => e
      Rails.logger.warn("[pilot.autopilot_inference_job] feature disabled msg=#{message_id}: #{e.message}")
    rescue ::Custom::Pilot::AutopilotService::Error => e
      Rails.logger.error("[pilot.autopilot_inference_job] LLM failure msg=#{message_id}: #{e.message}")
    end

    private

    def run_inference_with_typing(conversation, assistant)
      dispatch_typing(CONVERSATION_TYPING_ON, conversation, assistant)
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

    # Once `process_handover` has fired and the conversation carries the
    # warm-bot envelope, subsequent LLM-signalled handover intents must
    # NOT re-handoff — that creates a loop where every customer message
    # gets met with the handoff message again. Fall through to
    # `post_reply` instead so the bot can keep helping while the
    # conversation routes to a human.
    def already_in_warm_handoff?(conversation)
      conversation.additional_attributes&.dig('pilot_handoff', 'state') == 'handoff_requested'
    end

    def post_reply(conversation, assistant, reply)
      content = reply.to_s.sub(::Custom::Pilot::HandoverEvaluator::HANDOVER_SENTINEL, '').strip
      return if content.blank?

      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        sender: assistant,
        content: content
      )
    end

    # Customer-facing handover per pilot-autopilot spec ("Handover to human agent"
    # requirement) and mirroring Chatwoot Enterprise Captain's
    # `Captain::Conversation::ResponseBuilderJob#create_handoff_message`.
    # Uses Chatwoot core's `bot_handoff!` (transitions status, resets
    # waiting_since, dispatches CONVERSATION_BOT_HANDOFF) instead of a raw
    # status update. Posts a customer-visible message from the assistant's
    # configured handoff_message, falling back to the i18n default.
    #
    # Per pilot-telemetry "Dispatcher exception handling" (17.25): the
    # `pilot.autopilot.handover.triggered` dispatch happens AFTER the
    # transition is committed and is wrapped in an outer rescue so a
    # raise inside the dispatch path never propagates to this job. The
    # event timestamp is captured at the moment of state transition and
    # passed explicitly.
    def process_handover(conversation, assistant, result)
      conversation.bot_handoff! unless conversation.open?
      transitioned_at = Time.zone.now
      requested_at_iso = transitioned_at.iso8601

      mark_handoff_requested!(conversation, requested_at_iso)
      schedule_handoff_timeout(conversation, assistant, requested_at_iso)

      content = assistant.config['handoff_message'].presence ||
                I18n.t('conversations.pilot.handoff')

      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        sender: assistant,
        content: content
      )

      append_activity_message(conversation, handover_reason(result))
      dispatch_handover_event(conversation, assistant, result, transitioned_at)
    end

    # Tags the conversation with the warm-bot handoff envelope. The
    # listener and `Pilot::HandoffTimeoutJob` both key off this metadata
    # to decide whether the bot may still respond and whether to resume
    # it on timeout.
    def mark_handoff_requested!(conversation, requested_at_iso)
      conversation.additional_attributes ||= {}
      conversation.additional_attributes['pilot_handoff'] = {
        'state' => 'handoff_requested',
        'requested_at' => requested_at_iso,
        'mode' => 'keep_pilot_warm',
        'resume_count' => 0
      }
      conversation.save!
    end

    def schedule_handoff_timeout(conversation, assistant, requested_at_iso)
      ::Pilot::HandoffTimeoutJob
        .set(wait: assistant.handoff_timeout_minutes.to_i.minutes)
        .perform_later(conversation.id, requested_at_iso)
    end

    # Per pilot-telemetry "Activity messages on conversation timeline": every
    # inference-driven outcome appends a `messages` row with
    # `message_type = activity` so agents see the model-supplied reason on
    # the conversation timeline.
    def append_activity_message(conversation, reason)
      body = I18n.t('pilot.activity.handed_off_by_inference', reason: reason.to_s)
      conversation.messages.create!(
        message_type: :activity,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        content: body
      )
    rescue StandardError => e
      Rails.logger.warn("[pilot.autopilot_inference_job] activity message persist failed: #{e.class}: #{e.message}")
    end

    def dispatch_handover_event(conversation, assistant, result, transitioned_at)
      envelope = ::Custom::Pilot::ConversationPayloadBuilder.call(conversation: conversation, assistant: assistant)
      payload = {
        account_id: conversation.account_id,
        assistant_id: assistant.id,
        conversation_envelope: envelope,
        reason: handover_reason(result)
      }
      ::Custom::Pilot::EventDispatcher.dispatch(
        'pilot.autopilot.handover.triggered',
        payload,
        time: transitioned_at,
        account: conversation.account
      )
    rescue StandardError => e
      Rails.logger.error("[pilot.autopilot_inference_job] handover dispatch failed: #{e.class}: #{e.message}")
    end

    def handover_reason(result)
      handover = result&.handover
      return 'llm_requested' if handover.blank?

      handover.respond_to?(:reason) ? (handover.reason.presence || 'llm_requested') : 'llm_requested'
    end
  end
end
