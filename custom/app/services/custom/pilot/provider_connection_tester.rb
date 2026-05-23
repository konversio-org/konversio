# frozen_string_literal: true

require 'openai'

# Runs a low-cost smoke test against the configured Pilot LLM slots.
#
# Per pilot-onboarding spec "Provider configuration step with connection
# test", the wizard must verify chat-slot credentials work before
# marking the provider step complete.
#
# Per the pilot-foundation gap noted in the onboarding work, the tester
# also exercises the embedding slot — many EU providers (Scaleway,
# Nebius) split chat and embedding credentials/endpoints, and an
# embedding mismatch only surfaces at first document ingestion, hours
# later. Testing both at wizard time catches the misconfig immediately.
#
# Returns a structured Result:
#   Result#success? -> true when both slots respond
#   Result#chat / #embedding -> per-slot { ok:, error_class:, message: }
class Custom::Pilot::ProviderConnectionTester
  Result = Struct.new(:chat, :embedding, keyword_init: true) do
    def success?
      chat[:ok] && embedding[:ok]
    end

    def to_h
      { success: success?, chat: chat, embedding: embedding }
    end
  end

  def self.call(...)
    new(...).call
  end

  def initialize(account: nil)
    @account = account
  end

  def call
    Result.new(chat: test_chat, embedding: test_embedding)
  end

  private

  attr_reader :account

  def test_chat
    config = ::Llm::Config.for_slot(:chat)
    return failure_blank(:chat, config) if config[:api_key].blank?

    ::Llm::Config.with_api_key(config[:api_key], api_base: config[:endpoint]) do |context|
      options = { provider: 'openai', model: config[:model] }
      options[:assume_model_exists] = true if config[:openai_compatible]
      chat = context.chat(**options)
      chat.ask('ping')
    end

    { ok: true }
  rescue StandardError => e
    { ok: false, error_class: e.class.name, message: e.message }
  end

  def test_embedding
    config = ::Llm::Config.for_slot(:embedding)
    return failure_blank(:embedding, config) if config[:api_key].blank?

    client = OpenAI::Client.new(access_token: config[:api_key], uri_base: "#{config[:endpoint]}/v1")
    client.embeddings(parameters: { model: config[:model], input: 'ping' })

    { ok: true }
  rescue StandardError => e
    { ok: false, error_class: e.class.name, message: e.message }
  end

  def failure_blank(slot, config)
    {
      ok: false,
      error_class: 'MissingCredentialError',
      message: "No API key configured for the #{slot} slot (provider=#{config[:provider] || 'unset'})"
    }
  end
end
