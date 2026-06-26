module Custom
  module Pilot
    # Fix #2 helper — one cheap classification over the enabled-tool catalog.
    # Answers "which tool, if any, should the latest customer message trigger?"
    # and returns that tool's slug, or nil for off-topic / out-of-scope ('none').
    #
    # General by construction: the only inputs are the latest user message and
    # the assistant's own `{slug, description}` catalog — "is this within a
    # tool's purpose?" is delegated to the model reading the descriptions, so
    # there is zero per-tool / per-domain code.
    #
    # Runs on the chat slot (the SAME provider / endpoint / key as the
    # assistant) via `BaseService#chat_context`, so no customer text is sent to
    # a different provider. We deliberately bind the model to
    # `for_slot(:chat)[:model]` rather than the per-feature `model_for` escape
    # hatch: `model_for` swaps only the model NAME and could send customer text
    # to the chat-slot provider under a foreign model id (404 / residency leak).
    class ToolRouter < BaseService
      NONE = 'none'.freeze

      def initialize(assistant:)
        @assistant = assistant
        super(account: assistant&.account)
      end

      # @param customer_message [String, nil] the latest customer turn
      # @param catalog [Array<CustomToolCatalog::Entry>] enabled tools
      # @return [String, nil] an enabled slug, or nil for off-topic / failure
      def route(customer_message:, catalog:)
        return nil if catalog.blank? || customer_message.blank?

        answer = classify(customer_message.to_s, catalog).to_s.strip.downcase
        catalog.map(&:slug).find { |slug| slug.downcase == answer }
      rescue StandardError => e
        Rails.logger.warn("[pilot.tool_router] classification failed: #{e.class}: #{e.message}")
        nil
      end

      private

      def classify(customer_message, catalog)
        text = nil
        ::Custom::Pilot::TraceSpan.wrap(name: 'pilot.tool_router.classify', attributes: span_attributes) do |_span|
          chat_context do |context|
            chat = context.chat(**chat_options)
            chat.with_instructions(system_prompt(catalog))
            response = chat.ask(customer_message)
            text = response.respond_to?(:content) ? response.content : response.to_s
          end
        end
        text
      end

      def chat_options
        options = { model: ::Llm::Config.for_slot(:chat)[:model] }
        if ::Llm::Config.openai_compatible?
          options[:provider] = :openai
          options[:assume_model_exists] = true
        end
        options
      end

      def span_attributes
        {
          account_id: account&.id,
          assistant_id: @assistant&.id,
          model: ::Llm::Config.for_slot(:chat)[:model],
          credit_used: true
        }
      end

      def system_prompt(catalog)
        list = catalog.map { |entry| "- #{entry.slug}: #{entry.description}" }.join("\n")
        <<~PROMPT.strip
          You are a routing classifier for a customer-support assistant. Decide whether the user's latest message should be answered by calling one of these tools:

          #{list}

          Reply with EXACTLY one tool name from the list above when the message falls within that tool's stated purpose. If the message is off-topic, personal, a greeting, or outside every tool's purpose, reply with the single word: #{NONE}.

          Output ONLY the tool name or "#{NONE}" — no punctuation, no quotes, no explanation.
        PROMPT
      end
    end
  end
end
