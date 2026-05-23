# frozen_string_literal: true

module Custom
  module Pilot
    # Returns the standardised "conversation envelope" hash that every
    # Pilot conversation-lifecycle dispatcher event carries.
    #
    # Per pilot-telemetry spec "Conversation event payload envelope": every
    # downstream consumer (webhooks, ActionCable, activity log) should be
    # able to assume a fixed schema across event names.
    #
    # When the actor is an assistant, callers pass the `assistant` and the
    # envelope grows an `assistant: { id, name, avatar_url }` block. Otherwise
    # the key is omitted (not `nil`) so consumers can `payload.key?(:assistant)`
    # to branch.
    class ConversationPayloadBuilder
      def self.call(conversation:, assistant: nil)
        new(conversation: conversation, assistant: assistant).call
      end

      def initialize(conversation:, assistant: nil)
        @conversation = conversation
        @assistant = assistant
      end

      def call
        return {} if @conversation.blank?

        envelope = base_envelope
        envelope[:assistant] = assistant_block if @assistant.present?
        envelope
      end

      private

      def base_envelope
        {
          id: @conversation.id,
          display_id: @conversation.display_id,
          inbox_id: @conversation.inbox_id,
          contact_id: @conversation.contact_id,
          status: @conversation.status.to_s,
          priority: @conversation.priority.to_s.presence,
          labels: safe_labels,
          custom_attributes: @conversation.custom_attributes || {}
        }
      end

      def safe_labels
        @conversation.respond_to?(:label_list) ? Array(@conversation.label_list) : []
      end

      def assistant_block
        {
          id: @assistant.id,
          name: @assistant.try(:name).to_s,
          avatar_url: assistant_avatar_url
        }
      end

      def assistant_avatar_url
        return @assistant.avatar_url if @assistant.respond_to?(:avatar_url)

        nil
      end
    end
  end
end
