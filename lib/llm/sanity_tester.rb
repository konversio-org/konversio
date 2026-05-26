require 'net/http'
require 'json'
require 'uri'

# Runs reachability and credential checks against LLM providers.
#
# Two entry points:
#
#   - `test_slot(slot)` confirms the operator's currently-saved routing
#     (provider + model + embedding dimensions) works end-to-end. Used by
#     the LLM Models post-save banner; mirrors the previous inline logic in
#     SuperAdmin::LlmSettingsController byte-for-byte.
#
#   - `test_provider(slug)` verifies an API key + endpoint pair without
#     needing to know which model identifier is valid for this provider.
#     It hits `GET /v1/models` and treats any 2xx as success. Used by the
#     API Keys per-provider "Run test" button.
#
# Both return `{ state: :connected | :failed | :not_configured, message: }`.
module Llm::SanityTester
  AUDIO_RESULT = {
    state: :not_configured,
    message: 'Audio transcription is not enabled for this build.'
  }.freeze

  HTTP_TIMEOUT_SECONDS = 15

  class << self
    def test_slot(slot)
      slot = slot.to_sym
      config = Llm::Config.for_slot(slot)
      return { state: :not_configured, message: 'No provider is configured for this capability.' } if config[:api_key].blank?

      case slot
      when :chat then chat_slot_test(config)
      when :embedding then embedding_slot_test(config)
      when :audio then AUDIO_RESULT
      end
    rescue StandardError => e
      { state: :failed, message: e.message }
    end

    def test_provider(slug)
      provider = Llm::ProviderRegistry.provider(slug)
      return not_configured(provider) unless provider[:available]

      response = http_get(URI("#{strip_trailing_slash(provider[:endpoint])}/v1/models"), provider[:api_key])
      interpret_credentials_response(response)
    rescue StandardError => e
      { state: :failed, message: e.message }
    end

    private

    def chat_slot_test(config)
      Llm::Config.reset!
      Llm::Config.initialize!

      agent = ::Agents::Agent.new(
        name: 'llm_settings_test',
        instructions: 'Respond with the single word: pong.',
        model: config[:model],
        temperature: 0.0,
        tools: []
      )
      result = ::Agents::Runner.with_agents(agent).run('ping', max_turns: 1)
      return { state: :failed, message: result.error&.message.presence || 'Provider returned a failure with no error message.' } if result.failed?

      { state: :connected, message: 'Provider responded successfully.' }
    end

    def embedding_slot_test(config)
      client = OpenAI::Client.new(access_token: config[:api_key], uri_base: "#{config[:endpoint]}/v1")
      expected = Custom::Pilot::EmbeddingService.expected_dimension(config)
      response = client.embeddings(parameters: { model: config[:model], input: 'ping', dimensions: expected })
      vector = response.dig('data', 0, 'embedding')
      return { state: :failed, message: 'Provider returned no embedding vector.' } if vector.blank?

      return dimension_mismatch_result(vector.length, expected) if vector.length != expected

      { state: :connected, message: "Provider responded successfully — #{vector.length} dimensions." }
    rescue Custom::Pilot::EmbeddingService::UnknownModelDimensionError => e
      { state: :failed, message: e.message }
    end

    def dimension_mismatch_result(actual, expected)
      {
        state: :failed,
        message: "Model returned #{actual}-dim vectors but you declared #{expected}-dim. " \
                 'Update the Dimensions field or pick a model whose native dimension is ' \
                 "#{expected}."
      }
    end

    def not_configured(provider)
      reason = provider[:misconfigured_reason] || 'Provider is not configured.'
      { state: :not_configured, message: reason }
    end

    def interpret_credentials_response(response)
      case response.code.to_i
      when 200..299
        parsed = safe_parse(response.body)
        count = parsed.is_a?(Hash) ? Array(parsed['data']).size : nil
        { state: :connected, message: count ? "Provider responded — #{count} models advertised." : 'Provider responded successfully.' }
      when 401, 403
        { state: :failed, message: "Authentication rejected (HTTP #{response.code}). Verify the API key." }
      when 404
        { state: :failed, message: 'Provider returned 404 on /v1/models. Endpoint may be wrong or this provider is not OpenAI-compatible.' }
      else
        { state: :failed, message: "Provider returned HTTP #{response.code}: #{truncate(response.body.to_s, 200)}" }
      end
    end

    def http_get(uri, bearer_token)
      request = Net::HTTP::Get.new(uri.request_uri, 'Authorization' => "Bearer #{bearer_token}")
      Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == 'https',
        open_timeout: HTTP_TIMEOUT_SECONDS,
        read_timeout: HTTP_TIMEOUT_SECONDS
      ) { |http| http.request(request) }
    end

    def safe_parse(body)
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def strip_trailing_slash(endpoint)
      endpoint.to_s.chomp('/')
    end

    def truncate(string, max)
      string.length > max ? "#{string[0, max]}…" : string
    end
  end
end
