# frozen_string_literal: true

# Two-stage matcher that decides how a mined FAQ candidate is routed:
#
#   1. Embedding shortlist — nearest neighbors of the candidate's
#      `"<question>: <answer>"` vector under a cosine-distance threshold,
#      a small fixed number of records per pool. Nearest-neighbor queries
#      run inside a transaction with index scans disabled locally so
#      relation filters (status, language) cannot make the approximate
#      vector index miss true matches.
#   2. LLM equivalence judgment — for each shortlisted record a lightweight
#      boolean verdict decides whether the pair is truly the same FAQ.
#
# Pools are consulted in order: approved knowledge entries, dismissed
# suggestions in the candidate's language, open suggestions in the
# candidate's language. The first pool with a confirmed match decides the
# route: :knowledge (discard), :dismissed (discard), :attach (attach an
# observation to the matched open suggestion). No match routes :create.
#
# A judgment call that fails (LLM error, unparseable or non-boolean
# verdict) raises JudgmentError so the caller retries instead of silently
# misrouting the candidate.
class Custom::Pilot::FaqSuggestionMatcher < Custom::Pilot::BaseService
  DISTANCE_THRESHOLD = ::Pilot::Conversations::FaqMiningJob::FAQ_DEDUP_DISTANCE_THRESHOLD
  SHORTLIST_LIMIT = 5

  class JudgmentError < StandardError; end

  Match = Struct.new(:route, :record, keyword_init: true)

  attr_reader :assistant

  def initialize(assistant:, account: nil)
    @assistant = assistant
    @candidate_vectors = []
    super(account: account || assistant&.account)
  end

  def match(question:, answer:, language:)
    vector = safely_embed("#{question}: #{answer}")
    return Match.new(route: :create) if vector.nil?
    return Match.new(route: :duplicate) if duplicate_in_batch?(vector)

    result = route_by_pools(vector, question, answer, language)
    @candidate_vectors << vector
    result
  end

  private

  def route_by_pools(vector, question, answer, language)
    pools = [
      [:knowledge, ::Pilot::AssistantResponse.by_assistant(assistant.id).approved],
      [:dismissed, suggestion_pool(:dismissed, language)],
      [:attach, suggestion_pool(:open, language)]
    ]

    pools.each do |route, pool|
      record = first_confirmed(pool, vector, question, answer)
      return Match.new(route: route, record: record) if record
    end

    Match.new(route: :create)
  end

  # Returns the first shortlisted record the equivalence judgment confirms
  # as the same FAQ, else nil.
  def first_confirmed(pool, vector, question, answer)
    shortlist(pool, vector).each do |record|
      return record if same_faq?(question, answer, record.question, record.answer)
    end
    nil
  end

  def suggestion_pool(status, language)
    ::Pilot::FaqSuggestion.where(assistant_id: assistant.id).public_send(status).by_language(language)
  end

  # Nearest neighbors under the distance threshold. Runs inside a
  # transaction with index scans disabled locally: pgvector's approximate
  # ivfflat index can miss true matches when a WHERE filter (status,
  # language) shrinks the candidate set below what the index probes return.
  def shortlist(pool, vector)
    records = nil
    pool.klass.transaction do
      pool.klass.connection.execute("SET LOCAL enable_indexscan = 'off'")
      records = pool.nearest_neighbors(:embedding, vector, distance: 'cosine').limit(SHORTLIST_LIMIT).to_a
    end
    records.select { |record| record.neighbor_distance.present? && record.neighbor_distance < DISTANCE_THRESHOLD }
  end

  # Boolean LLM verdict: is the shortlisted record the same FAQ as the
  # candidate? Anything but a clean true/false raises JudgmentError.
  def same_faq?(candidate_question, candidate_answer, question, answer)
    verdict = invoke_judgment(candidate_question, candidate_answer, question, answer)
    parse_verdict(verdict)
  rescue JudgmentError
    raise
  rescue StandardError => e
    raise JudgmentError, "equivalence judgment failed: #{e.class}: #{e.message}"
  end

  def invoke_judgment(candidate_question, candidate_answer, question, answer)
    text = nil
    chat_context do |context|
      chat_options = { model: model_for(:autopilot) }
      if ::Llm::Config.openai_compatible?
        chat_options[:provider] = :openai
        chat_options[:assume_model_exists] = true
      end
      chat = context.chat(**chat_options)
      chat.with_instructions(judgment_instructions)
      response = chat.ask(judgment_prompt(candidate_question, candidate_answer, question, answer))
      text = response.respond_to?(:content) ? response.content : response.to_s
    end
    text.to_s
  end

  def parse_verdict(text)
    case text.to_s.strip.downcase
    when 'true' then true
    when 'false' then false
    else
      raise JudgmentError, "non-boolean equivalence verdict: #{text.to_s.first(100).inspect}"
    end
  end

  def judgment_instructions
    <<~PROMPT.strip
      You compare two FAQ entries and decide whether they are the same question-and-answer pair.
      They are the same only when a customer asking one question would consider the other entry's answer a complete answer to their own question.
      Different wording of the same question and answer counts as the same; a shared topic with a different question or a different answer does not.
      Reply with exactly one word: true or false.
    PROMPT
  end

  def judgment_prompt(candidate_question, candidate_answer, question, answer)
    <<~PROMPT.strip
      Entry A
      Question: #{candidate_question}
      Answer: #{candidate_answer}

      Entry B
      Question: #{question}
      Answer: #{answer}
    PROMPT
  end

  # Two candidates mined in the same job run that are near-duplicates of
  # each other should only be persisted once (the fresh suggestion has no
  # embedding yet, so the pool shortlist cannot see it).
  def duplicate_in_batch?(vector)
    @candidate_vectors.any? { |existing| cosine_distance(vector, existing) < DISTANCE_THRESHOLD }
  end

  def safely_embed(text)
    ::Custom::Pilot::EmbeddingService.new(account: account).embed(text)
  rescue StandardError => e
    Rails.logger.error("[pilot.faq_suggestion_matcher] embed error: #{e.class}: #{e.message}")
    nil
  end

  def cosine_distance(vec_a, vec_b)
    dot = 0.0
    norm_a = 0.0
    norm_b = 0.0
    vec_a.each_with_index do |val, i|
      bval = vec_b[i] || 0.0
      dot += val * bval
      norm_a += val * val
      norm_b += bval * bval
    end
    return 1.0 if norm_a.zero? || norm_b.zero?

    1.0 - (dot / (Math.sqrt(norm_a) * Math.sqrt(norm_b)))
  end
end
