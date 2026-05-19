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
      register_slot_models!
      @initialized = true
    end

    # Tells RubyLLM's in-memory registry about the slot models the admin
    # has configured. The agents SDK (used by Autopilot) refuses to call
    # `RubyLLM::Chat.new(model: X)` if X isn't in the registry, even when
    # the upstream provider (e.g. Scaleway) would happily serve it. We map
    # the admin's chosen ID onto the `openai` provider class because every
    # configured slot here routes through the OpenAI-compatible HTTP API.
    def register_slot_models!
      registry = RubyLLM::Models.instance.all
      Llm::Presets::SLOTS.each do |slot|
        model_id = for_slot(slot)[:model]
        next if model_id.blank? || model_id == Llm::Presets::DISABLED_SENTINEL
        next if registry.any? { |m| m.id == model_id && m.provider == 'openai' }

        registry << RubyLLM::Model::Info.default(model_id, 'openai')
      end
    end

    def reset!
      @initialized = false
    end

    # Resolves the model name to use for a given Pilot feature.
    #
    # Precedence:
    #   1. PILOT_LLM_<FEATURE>_MODEL (e.g. PILOT_LLM_TRANSLATION_MODEL) — escape hatch
    #   2. Chat slot's model (PILOT_LLM_CHAT_MODEL → DEFAULT_MODEL)
    def model_for(feature)
      feature_key = feature.to_s.upcase
      per_feature = GlobalConfigService.load("PILOT_LLM_#{feature_key}_MODEL", nil)
      return per_feature if per_feature.present?

      for_slot(:chat)[:model]
    end

    # Returns the hash of options to pass to a RubyLLM chat invocation for the
    # given feature. When the chat provider is OpenAI-compatible we ask
    # RubyLLM to skip its model registry by setting `assume_model_exists: true`.
    def model_options(feature)
      options = { provider: 'openai', model: model_for(feature) }
      options[:assume_model_exists] = true if openai_compatible?
      options
    end

    # Resolved config for a single slot. Returns a hash with :provider, :endpoint,
    # :api_key, :model, :openai_compatible.
    def for_slot(slot)
      slot = slot.to_sym
      slug = Llm::ProviderRegistry.slot_provider(slot)
      model = Llm::ProviderRegistry.slot_model(slot)
      return blank_slot(slot, model) if slug.nil?

      data = Llm::ProviderRegistry.provider(slug)
      {
        provider: slug,
        endpoint: strip_v1_suffix(data[:endpoint].presence || DEFAULT_API_ENDPOINT),
        api_key: data[:api_key],
        model: model,
        openai_compatible: data[:openai_compatible] ? true : false
      }
    end

    # Base endpoint with any trailing `/v1` stripped. Code paths that need the
    # versioned URL (RubyLLM) re-append `/v1` themselves.
    def api_base
      for_slot(:chat)[:endpoint]
    end

    def api_key
      for_slot(:chat)[:api_key]
    end

    def openai_compatible?
      for_slot(:chat)[:openai_compatible]
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

    def blank_slot(slot, model)
      { provider: nil, endpoint: DEFAULT_API_ENDPOINT, api_key: nil, model: model, openai_compatible: false }
    end

    def strip_v1_suffix(endpoint)
      endpoint.to_s.chomp('/').chomp('/v1')
    end
  end
end
