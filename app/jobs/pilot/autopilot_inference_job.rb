module Pilot
  # Triggered when an inbound customer message lands in an inbox that has
  # a Pilot::Assistant attached AND the account has
  # `pilot_autopilot_enabled = true`. Runs `AutopilotService` and either
  # posts the reply as an outgoing message or transitions the conversation
  # to `pending` for human follow-up.
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

      if result.handover.handover?
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
      return false unless account.respond_to?(:pilot_enabled) && account.pilot_enabled
      return false unless account.respond_to?(:pilot_autopilot_enabled) && account.pilot_autopilot_enabled

      true
    end

    def assistant_for(inbox)
      return nil if inbox.blank?

      join = ::Pilot::Inbox.find_by(inbox_id: inbox.id)
      join&.assistant
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
    def process_handover(conversation, assistant, _result)
      conversation.bot_handoff! unless conversation.open?

      content = assistant.config['handoff_message'].presence ||
                I18n.t('conversations.pilot.handoff')

      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        sender: assistant,
        content: content
      )
    end
  end
end
