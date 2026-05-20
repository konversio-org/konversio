module Custom
  module Pilot
    module Tools
      # Vector-similarity search over the Pilot knowledge base
      # (`pilot_assistant_responses`). The class is always defined so it
      # can be unit-tested; CopilotService registers it only when the
      # underlying model class AND embedding service are present, which
      # ships with the Autopilot sub-feature (section 4). Until then the
      # tool is omitted from the agent's tool list and never invoked.
      class SearchDocumentation < Base
        DEFAULT_LIMIT = 5

        description 'Semantic search over the account knowledge base. Returns matching question/answer pairs ' \
                    'ranked by cosine similarity to the query.'
        param :query, type: 'string', desc: 'Free-text question to look up in the knowledge base', required: true

        def name
          'search_documentation'
        end

        def perform(tool_context, query:)
          account = account_for(tool_context)
          return 'Account context unavailable; cannot search documentation.' if account.blank?
          return 'Documentation search is not enabled on this install.' unless model_class

          embedding = ::Custom::Pilot::EmbeddingService.new(account: account).embed(query)
          return 'No knowledge base entries indexed yet.' if embedding.blank?

          results = model_class.where(account_id: account.id)
                               .where(status: 'approved')
                               .order(Arel.sql("embedding <=> '#{vector_literal(embedding)}'"))
                               .limit(DEFAULT_LIMIT)
          return 'No matching documentation found.' if results.empty?

          format_results(results)
        rescue StandardError => e
          Rails.logger.error("[pilot.tools.search_documentation] #{e.class}: #{e.message}")
          "[BACKEND_ERROR] Documentation search failed: #{e.class.name}: #{e.message}. " \
            'Relay this error verbatim to the agent. Do not apologize, do not invent an ' \
            'answer, do not claim you lack tools — the knowledge base exists but is ' \
            'currently unreachable due to a Pilot configuration problem.'
        end

        # CopilotService calls this when deciding whether to register the tool.
        # When `Pilot::AssistantResponse` lands (section 4) this returns true.
        def self.available?
          !!(defined?(::Pilot::AssistantResponse) && defined?(::Custom::Pilot::EmbeddingService))
        end

        private

        def model_class
          ::Pilot::AssistantResponse if defined?(::Pilot::AssistantResponse)
        end

        def vector_literal(vector)
          "[#{vector.join(',')}]"
        end

        def format_results(results)
          results.map do |r|
            "Q: #{r.try(:question)}\nA: #{r.try(:answer)}"
          end.join("\n---\n")
        end
      end
    end
  end
end
