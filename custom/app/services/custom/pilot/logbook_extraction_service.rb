# frozen_string_literal: true

module Custom
  module Pilot
    # Calls the LLM to extract durable contact-level facts from a resolved
    # conversation transcript. Mirrors the deepdive's section 3 (Logbook /
    # Contact-Fact Extraction):
    #
    #   * positions the model as a CRM note-taker for the contact
    #   * grounds output strictly in the dialogue (no external knowledge)
    #   * feeds the contact's existing notes into the user content for
    #     cross-call dedup (the prompt instructs the model to skip facts
    #     already represented)
    #   * output schema: `{ "facts": [<string>, ...] }` — per-fact is just
    #     a plain string, no category / confidence / provenance
    #
    # Failure semantics (per deepdive 3.3): malformed JSON, LLM exception,
    # missing key, or empty array MUST each yield an empty fact array. No
    # exception bubbled. Failures get reported to the application
    # exception tracker because corrupting the CRM is higher-signal than
    # missing FAQ-store entries.
    #
    # There is intentionally NO programmatic post-extraction sanity filter
    # (no min-length, no question-mark drop). Per the deepdive: "the
    # product trusts the model and the prompt fully."
    class LogbookExtractionService < BaseService
      MAX_HISTORY = 40

      attr_reader :conversation, :contact

      def initialize(conversation:, contact: nil, account: nil)
        @conversation = conversation
        @contact = contact || conversation&.contact
        super(account: account || conversation&.account)
      end

      def call
        return [] if conversation.blank? || contact.blank?

        transcript = build_transcript
        return [] if transcript.blank?

        raw = invoke_llm(transcript)
        parse_facts(raw)
      rescue StandardError => e
        report_failure(e)
        []
      end

      private

      def invoke_llm(transcript)
        text = nil
        ::Custom::Pilot::TraceSpan.wrap(name: 'pilot.logbook.extract', attributes: span_attributes) do |_span|
          chat_context do |context|
            chat_options = { model: model_for(:logbook) }
            if ::Llm::Config.openai_compatible?
              chat_options[:provider] = :openai
              chat_options[:assume_model_exists] = true
            end
            chat = context.chat(**chat_options)
            chat.with_instructions(system_prompt)
            response = chat.ask(user_prompt(transcript))
            text = response.respond_to?(:content) ? response.content : response.to_s
          end
        end
        text.to_s
      end

      def span_attributes
        {
          account_id: account&.id,
          conversation_id: conversation&.id,
          conversation_display_id: conversation&.display_id,
          contact_id: contact&.id,
          channel_type: conversation&.inbox&.channel_type,
          source: 'production',
          model: model_for(:logbook),
          credit_used: true
        }
      end

      def system_prompt
        <<~PROMPT.strip
          You are a CRM note-taker. From the conversation, extract durable, contact-level facts about the contact (preferences, account details, ongoing constraints, jurisdiction).

          Rules:
          - Use ONLY information present in the dialogue. Do not invent facts or pull from outside knowledge.
          - Skip facts already represented in the existing notes provided below.
          - Each fact is a single plain English sentence. No categories, no tags, no metadata.
          - Respond with strict JSON in EXACTLY this shape:
            { "facts": [ "<fact>", "<fact>" ] }
          - If no new durable facts can be extracted, return { "facts": [] }.
          - Do not include any text, markdown, or commentary outside the JSON.
        PROMPT
      end

      def user_prompt(transcript)
        existing_block = existing_notes_block
        <<~PROMPT
          Existing notes about this contact:
          #{existing_block}

          Conversation transcript (oldest first):

          #{transcript}

          Extract new durable facts as JSON.
        PROMPT
      end

      def existing_notes_block
        entries = ::Pilot::LogbookEntry.where(contact_id: contact.id).order(created_at: :desc).limit(50).pluck(:content)
        return '(none)' if entries.empty?

        entries.map { |c| "- #{c}" }.join("\n")
      end

      def build_transcript
        conversation.messages
                    .where(message_type: %i[incoming outgoing])
                    .where(private: false)
                    .order(:created_at)
                    .last(MAX_HISTORY)
                    .filter_map do |msg|
                      content = msg.content.to_s.strip
                      next if content.blank?

                      role = msg.message_type == 'incoming' ? 'CUSTOMER' : 'AGENT'
                      "[#{role}] #{content}"
                    end.join("\n")
      end

      def parse_facts(raw)
        text = raw.to_s.strip
        return [] if text.blank?

        text = text.gsub(/\A```(?:json)?\s*/, '').gsub(/\s*```\z/, '')
        json = JSON.parse(text)
        Array(json['facts'] || json[:facts]).map { |f| f.to_s.strip }.reject(&:blank?)
      rescue JSON::ParserError => e
        report_failure(e, raw: raw.to_s.first(200))
        []
      end

      def report_failure(error, raw: nil)
        ctx = failure_context(raw)
        Rails.logger.error("[pilot.logbook_extraction_service] #{error.class}: #{error.message} ctx=#{ctx.inspect}")
        capture_exception(error, ctx)
      end

      def failure_context(raw)
        ctx = { account_id: account&.id, conversation_id: conversation&.display_id, contact_id: contact&.id }
        ctx[:raw_excerpt] = raw if raw
        ctx
      end

      def capture_exception(error, ctx)
        if defined?(::KonversioExceptionTracker)
          ::KonversioExceptionTracker.new(error).capture_exception
        elsif Rails.respond_to?(:error) && Rails.error.respond_to?(:report)
          Rails.error.report(error, context: ctx)
        end
      end
    end
  end
end
