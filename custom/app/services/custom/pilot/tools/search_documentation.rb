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

          format_results(results, assistant_for(tool_context))
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

        def assistant_for(tool_context)
          assistant_id = tool_context.context[:assistant_id]
          return nil if assistant_id.blank?
          return nil unless defined?(::Pilot::Assistant)

          ::Pilot::Assistant.find_by(id: assistant_id)
        end

        def format_results(results, assistant)
          citation_off = assistant&.citation_behavior.to_s == 'off'
          results.map { |r| format_single(r, citation_off: citation_off) }.join("\n---\n")
        end

        def format_single(result, citation_off:)
          lines = ["Q: #{result.try(:question)}", "A: #{result.try(:answer)}"]
          source_line = source_line_for(result, citation_off: citation_off)
          lines << source_line if source_line
          lines.join("\n")
        end

        # Returns the "Source: ..." line to append, or nil to suppress it.
        # PDF-origin matches honor the citation_behavior toggle; URL-origin
        # matches always surface the URL regardless of the toggle (per
        # pilot-autopilot "URL citation always visible" scenario).
        def source_line_for(result, citation_off:)
          doc = result.try(:documentable)
          return nil if doc.blank?
          return nil unless doc.respond_to?(:external_link)

          if pdf_origin?(doc)
            return nil if citation_off

            "Source: #{doc.try(:name).presence || doc.external_link}"
          else
            "Source: #{doc.external_link}"
          end
        end

        def pdf_origin?(document)
          link = document.external_link.to_s
          return true if link.start_with?('PDF:') || link.downcase.end_with?('.pdf')
          return document.pdf_document? if document.respond_to?(:pdf_document?)

          false
        end
      end
    end
  end
end
