module Custom
  module Pilot
    module Tools
      # Text search over an account's conversations. The LLM uses this when an
      # agent asks "what conversations are open about refunds?" or "show me
      # ticket 42". We deliberately keep the surface small (status + free-text
      # query) so the model can call it without spelunking schema fields.
      class SearchConversation < Base
        MAX_RESULTS = 25

        description 'Search this account\'s conversations by status and an optional free-text query. ' \
                    'Returns a compact list of matching conversations (display id, contact name, status, ' \
                    'and the last message snippet).'

        def name
          'search_conversation'
        end

        param :query,
              type: 'string',
              desc: 'Optional free-text fragment to match against conversation messages and contact names',
              required: false
        param :status,
              type: 'string',
              desc: 'Optional status filter: open, resolved, pending, snoozed. Omit to search all statuses.',
              required: false

        def perform(tool_context, query: nil, status: nil)
          account = account_for(tool_context)
          return 'Account context unavailable; cannot search conversations.' if account.blank?

          scope = account.conversations
          scope = scope.where(status: status) if status.present? && ::Conversation.statuses.key?(status.to_s)
          scope = filter_by_query(scope, account, query) if query.present?

          conversations = scope.order(created_at: :desc).limit(MAX_RESULTS)
          return 'No matching conversations found.' if conversations.empty?

          format_results(conversations)
        rescue StandardError => e
          Rails.logger.warn("[pilot.tools.search_conversation] #{e.class}: #{e.message}")
          "Tool error while searching conversations: #{e.message}"
        end

        private

        def filter_by_query(scope, account, query)
          like = "%#{query}%"
          contact_ids = account.contacts.where('name ILIKE :q OR email ILIKE :q', q: like).limit(50).pluck(:id)
          conv_ids_by_message = ::Message.where(account_id: account.id, conversation_id: scope.select(:id))
                                         .where('content ILIKE ?', like)
                                         .reorder(nil)
                                         .distinct
                                         .limit(MAX_RESULTS * 3)
                                         .pluck(:conversation_id)
          ids = (conv_ids_by_message + scope.where(contact_id: contact_ids).limit(MAX_RESULTS).pluck(:id)).uniq
          scope.where(id: ids)
        end

        def format_results(conversations)
          lines = conversations.map do |c|
            contact_name = c.contact&.name.presence || 'Unknown contact'
            last_message = c.messages.order(created_at: :desc).first&.content.to_s.truncate(120)
            "##{c.display_id} | #{c.status} | #{contact_name} | #{last_message}"
          end
          (["Found #{conversations.size} conversations:"] + lines).join("\n")
        end
      end
    end
  end
end
