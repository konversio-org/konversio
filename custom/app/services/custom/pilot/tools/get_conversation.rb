module Custom
  module Pilot
    module Tools
      # Fetch a single conversation by its display id. Returns a transcript-style
      # block containing assignee, status, and message history — the same
      # shape Chatwoot uses elsewhere via `Conversation#to_llm_text`.
      class GetConversation < Base
        description 'Fetch a single conversation in the current account by its display id. ' \
                    'Returns assignee, status, and the full message transcript.'
        param :display_id, type: 'integer', desc: 'Conversation display id (the human-visible number)', required: true

        def name
          'get_conversation'
        end


        def perform(tool_context, display_id:)
          account = account_for(tool_context)
          return 'Account context unavailable; cannot fetch conversation.' if account.blank?

          conversation = account.conversations.find_by(display_id: display_id)
          return "Conversation ##{display_id} not found in this account." if conversation.blank?

          format_conversation(conversation)
        rescue StandardError => e
          Rails.logger.warn("[pilot.tools.get_conversation] #{e.class}: #{e.message}")
          "Tool error while fetching conversation: #{e.message}"
        end

        private

        def format_conversation(conversation)
          assignee = conversation.assignee&.name || 'unassigned'
          header = "Conversation ##{conversation.display_id} | status=#{conversation.status} | assignee=#{assignee}"
          transcript = if conversation.respond_to?(:to_llm_text)
                         conversation.to_llm_text(include_contact_details: true)
                       else
                         fallback_transcript(conversation)
                       end
          [header, '---', transcript.to_s].join("\n")
        end

        def fallback_transcript(conversation)
          conversation.messages.order(:created_at).limit(50).map do |m|
            sender = m.sender&.name || (m.outgoing? ? 'agent' : 'contact')
            "#{sender}: #{m.content.to_s.truncate(500)}"
          end.join("\n")
        end
      end
    end
  end
end
