require 'ruby_llm'

module Llm::Config
  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze
  DEFAULT_API_ENDPOINT = 'https://api.openai.com'.freeze

  class << self
    def initialized?
      @initialized ||= false
    end

    def initialize!
      return if @initialized

      configure_ruby_llm
      @initialized = true
    end

    def reset!
      @initialized = false
    end

    # Resolves the model name to use for a given Pilot feature.
    #
    # Precedence:
    #   1. PILOT_OPEN_AI_<FEATURE>_MODEL (e.g. PILOT_OPEN_AI_TRANSLATION_MODEL)
    #   2. PILOT_OPEN_AI_MODEL
    #   3. DEFAULT_MODEL
    def model_for(feature)
      feature_key = feature.to_s.upcase
      per_feature = GlobalConfigService.load("PILOT_OPEN_AI_#{feature_key}_MODEL", nil)
      return per_feature if per_feature.present?

      GlobalConfigService.load('PILOT_OPEN_AI_MODEL', nil).presence || DEFAULT_MODEL
    end

    # Returns the hash of options to pass to a RubyLLM chat invocation for the
    # given feature. When the operator has opted into the OpenAI-compatible
    # routing path (`PILOT_OPEN_AI_API_PROVIDER=openai_compatible`) we ask
    # RubyLLM to skip its model registry by setting `assume_model_exists: true`.
    def model_options(feature)
      options = { provider: 'openai', model: model_for(feature) }
      options[:assume_model_exists] = true if openai_compatible?
      options
    end

    # Base endpoint with any trailing `/v1` stripped. Code paths that need the
    # versioned URL (RubyLLM) re-append `/v1` themselves.
    def api_base
      endpoint = GlobalConfigService.load('PILOT_OPEN_AI_ENDPOINT', nil).presence || DEFAULT_API_ENDPOINT
      strip_v1_suffix(endpoint)
    end

    def api_key
      GlobalConfigService.load('PILOT_OPEN_AI_API_KEY', nil)
    end

    def openai_compatible?
      GlobalConfigService.load('PILOT_OPEN_AI_API_PROVIDER', nil).to_s == 'openai_compatible'
    end

    def configure_ruby_llm
      RubyLLM.configure do |config|
        config.openai_api_key = api_key if api_key.present?
        config.openai_api_base = "#{api_base}/v1"
        config.openai_use_system_role = true
        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
      end
    end

    def with_api_key(api_key, api_base: nil)
      initialize!
      effective_base = api_base.present? ? "#{strip_v1_suffix(api_base)}/v1" : nil
      context = RubyLLM.context do |config|
        config.openai_api_key = api_key
        config.openai_api_base = effective_base
        config.openai_use_system_role = true
      end

      yield context
    end

    private

    def strip_v1_suffix(endpoint)
      endpoint.chomp('/').chomp('/v1')
    end
  end
end
