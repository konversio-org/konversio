module Pilot
  # Triggered when an inbound customer message lands in an inbox that has
  # a Pilot::Assistant attached AND the account has
  # `pilot_autopilot_enabled = true`. Runs `AutopilotService` and either
  # posts the reply as an outgoing message or transitions the conversation
  # to `pending` for human follow-up.
  class AutopilotInferenceJob < ApplicationJob
    queue_as :default

    def perform(message_id:)
      message = ::Message.find_by(id: message_id)
      return if message.blank?
      return unless eligible?(message)

      conversation = message.conversation
      assistant = assistant_for(conversation.inbox)
      return if assistant.blank?

      result = ::Custom::Pilot::AutopilotService.new(
        assistant: assistant,
        conversation: conversation,
        account: assistant.account
      ).perform

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

    def process_handover(conversation, _assistant, result)
      conversation.update(status: :pending) unless conversation.pending?
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        content: "Autopilot handover: #{result.handover.reason}",
        private: true
      )
    end
  end
end
