# Deterministic detector behind the opt-in false-promise guard. Given the
# conversation context and a draft reply, a temperature-0 model call returns
# exactly one of two verdicts — safe to deliver, or an unsupported promise of
# future work — plus a categorized reason from the fixed taxonomy below and
# the model used.
#
# The detector NEVER raises into the delivery path: any call failure or
# unusable output yields an inconclusive verdict, which callers must treat as
# "not a block". Every detection is logged (verdict, reason, model, account,
# conversation) so guarded decisions stay auditable.
class Pilot::PromiseGuard
  Verdict = Struct.new(:status, :reason_category, :model, keyword_init: true) do
    def safe?
      status == :safe
    end

    def promise?
      status == :promise
    end

    def inconclusive?
      status == :inconclusive
    end
  end

  # Fixed implementation-side taxonomy for the categorized reason.
  REASON_CATEGORIES = %w[
    no_future_commitment
    deferred_check_or_follow_up
    ongoing_monitoring
    later_contact_or_notification
    background_or_offline_action
    other_future_commitment
  ].freeze

  SAFE_VERDICT = 'safe'.freeze
  PROMISE_VERDICT = 'future_promise'.freeze

  INSTRUCTIONS = <<~PROMPT.freeze
    You audit draft replies from a customer-support assistant before they are sent.

    Decide whether the draft commits the assistant to work that would happen AFTER the reply is sent: checking back or investigating later, monitoring or tracking something, following up, notifying, emailing, or calling the customer, or any background escalation or other offline action the assistant did not already complete within this turn.

    Statements about actions already completed, answers grounded in the conversation, and plain goodwill ("happy to help") are safe.

    Reply ONLY with a JSON object in this exact shape:
      {"verdict":"safe"|"future_promise","reason":"<one category>"}

    Categories: #{REASON_CATEGORIES.join(', ')}. Use "no_future_commitment" only with a safe verdict.
  PROMPT

  def self.call(conversation:, draft_reply:)
    new(conversation: conversation, draft_reply: draft_reply).call
  end

  def initialize(conversation:, draft_reply:)
    @conversation = conversation
    @draft_reply = draft_reply
  end

  def call
    verdict = detect
    log_detection(verdict)
    verdict
  rescue StandardError => e
    Rails.logger.warn("[pilot.promise_guard] detector failed: #{e.class}: #{e.message}")
    Verdict.new(status: :inconclusive, reason_category: nil, model: model)
  end

  private

  attr_reader :conversation, :draft_reply

  def detect
    content = ask_detector
    parse_verdict(content)
  end

  def ask_detector
    ::Llm::Config.with_api_key(::Llm::Config.api_key, api_base: ::Llm::Config.api_base) do |context|
      chat = build_chat(context)
      response = chat.ask(detector_input)
      response.content
    end
  end

  def build_chat(context)
    chat_options = { model: model }
    if ::Llm::Config.openai_compatible?
      chat_options[:provider] = :openai
      chat_options[:assume_model_exists] = true
    end
    chat = context.chat(**chat_options)
    chat.with_temperature(0)
    chat.with_instructions(INSTRUCTIONS)
    chat
  end

  # The detector resolves its model through the standard per-feature
  # resolution (PILOT_LLM_PROMISE_GUARD_MODEL escape hatch, then the chat
  # slot) rather than pinning a provider model.
  def model
    @model ||= ::Llm::Config.model_for(:promise_guard)
  end

  def detector_input
    transcript = conversation_transcript
    <<~INPUT
      Conversation so far (most recent last):
      #{transcript.presence || '(no prior messages)'}

      Draft reply to audit:
      #{draft_reply}
    INPUT
  end

  def conversation_transcript
    return '' if conversation.blank?

    conversation.messages
                .where(message_type: %i[incoming outgoing])
                .where(private: false)
                .order(:created_at)
                .last(10)
                .filter_map do |message|
                  content = message.content_for_llm.to_s
                  next if content.blank?

                  "#{message.message_type == 'incoming' ? 'Customer' : 'Assistant'}: #{content}"
                end
                .join("\n")
  end

  def parse_verdict(content)
    decoded = decode_json(content)
    return inconclusive unless decoded.is_a?(Hash)

    case decoded['verdict'].to_s
    when SAFE_VERDICT
      Verdict.new(status: :safe, reason_category: 'no_future_commitment', model: model)
    when PROMISE_VERDICT
      Verdict.new(status: :promise, reason_category: normalize_category(decoded['reason']), model: model)
    else
      inconclusive
    end
  end

  def decode_json(content)
    text = content.to_s.strip.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '')
    JSON.parse(text)
  rescue JSON::ParserError
    nil
  end

  def normalize_category(reason)
    category = reason.to_s.strip
    return 'other_future_commitment' if category.blank? || category == 'no_future_commitment'

    REASON_CATEGORIES.include?(category) ? category : 'other_future_commitment'
  end

  def inconclusive
    Verdict.new(status: :inconclusive, reason_category: nil, model: model)
  end

  def log_detection(verdict)
    Rails.logger.info(
      "[pilot.promise_guard] detection verdict=#{verdict.status} reason=#{verdict.reason_category} " \
      "model=#{verdict.model} account=#{conversation&.account_id} conversation=#{conversation&.display_id}"
    )
  end
end
