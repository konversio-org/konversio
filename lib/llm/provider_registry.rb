module Llm
  # Registry for LLM providers used by Pilot.
  #
  # `DEFAULTS` ships metadata for well-known providers — operators only set
  # `PILOT_LLM_<SLUG>_API_KEY` to enable them. Any additional provider works
  # without a code change: declare `PILOT_LLM_<SLUG>_API_KEY` plus
  # `PILOT_LLM_<SLUG>_ENDPOINT` (and optionally `_LABEL`, `_OPENAI_COMPATIBLE`,
  # `_CAPABILITIES`).
  module ProviderRegistry
    SLOTS = %i[chat embedding audio].freeze

    DEFAULTS = {
      openai: { label: 'OpenAI', endpoint: 'https://api.openai.com', openai_compatible: false,
                capabilities: %i[chat embedding audio] },
      nebius: { label: 'Nebius', endpoint: 'https://api.tokenfactory.nebius.com', openai_compatible: true,
                capabilities: %i[chat embedding] },
      scaleway: { label: 'Scaleway', endpoint: 'https://api.scaleway.ai', openai_compatible: true,
                  capabilities: %i[chat embedding audio] },
      openrouter: { label: 'OpenRouter', endpoint: 'https://openrouter.ai/api', openai_compatible: true,
                    capabilities: %i[chat] }
    }.freeze

    SLOT_DEFAULT_MODELS = {
      chat: -> { Llm::Config::DEFAULT_MODEL },
      embedding: -> { 'text-embedding-3-small' },
      audio: -> { 'whisper-1' }
    }.freeze

    ENV_KEY_PATTERN = /\APILOT_LLM_([A-Z0-9_]+)_API_KEY\z/

    class UnknownProvider < StandardError; end
    class CapabilityMismatch < StandardError; end

    class << self
      # All discovered slugs (defaults ∪ ENV-declared), sorted alphabetically.
      def known_slugs
        env_slugs = ENV.keys.filter_map do |key|
          match = ENV_KEY_PATTERN.match(key)
          match && match[1].downcase.to_sym
        end
        (DEFAULTS.keys + env_slugs).uniq.sort
      end

      # Slugs that have both an API key and a resolved endpoint.
      def available_providers
        known_slugs.select { |slug| provider(slug)[:available] }
      end

      # Available providers whose capabilities include the given slot.
      def providers_for(slot)
        slot = slot.to_sym
        available_providers.select { |slug| provider(slug)[:capabilities].include?(slot) }
      end

      # Resolve a provider's metadata. Returns a hash with :slug, :label,
      # :endpoint, :openai_compatible, :api_key, :capabilities, :available,
      # :misconfigured_reason.
      def provider(slug)
        slug = slug.to_sym
        raise UnknownProvider, "Unknown LLM provider slug: #{slug}" unless known_slugs.include?(slug)

        defaults = DEFAULTS[slug] || {}
        endpoint = resolve_endpoint(slug, defaults)
        api_key = api_key_for(slug)
        label = ENV["PILOT_LLM_#{slug.upcase}_LABEL"].presence || defaults[:label] || slug.to_s
        compat = resolve_openai_compatible(slug, defaults)
        capabilities = resolve_capabilities(slug, defaults)

        misconfigured_reason = nil
        misconfigured_reason = 'Missing endpoint' if endpoint.blank?
        misconfigured_reason ||= 'Missing API key' if api_key.blank?

        {
          slug: slug,
          label: label,
          endpoint: endpoint,
          openai_compatible: compat,
          api_key: api_key,
          capabilities: capabilities,
          available: api_key.present? && endpoint.present?,
          misconfigured_reason: misconfigured_reason
        }
      end

      def api_key_for(slug)
        ENV["PILOT_LLM_#{slug.to_sym.upcase}_API_KEY"].presence
      end

      def endpoint_for(slug)
        provider(slug)[:endpoint]
      end

      def openai_compatible?(slug)
        provider(slug)[:openai_compatible]
      end

      # Resolved provider for a slot. Reads `PILOT_LLM_<SLOT>_PROVIDER`, falls
      # back to the first capable+available provider (openai preferred). The
      # 'none' sentinel means the slot is explicitly disabled (preset omitted it).
      def slot_provider(slot)
        slot = slot.to_sym
        raw = GlobalConfigService.load("PILOT_LLM_#{slot.upcase}_PROVIDER", nil)
        return nil if raw == Llm::Presets::DISABLED_SENTINEL

        configured = raw.presence
        return configured.to_sym if configured && providers_for(slot).include?(configured.to_sym)

        capable = providers_for(slot)
        return :openai if capable.include?(:openai)

        capable.first
      end

      # Resolved model for a slot. Reads `PILOT_LLM_<SLOT>_MODEL`, falls back
      # to the slot's hardcoded default. The 'none' sentinel returns nil.
      def slot_model(slot)
        slot = slot.to_sym
        raw = GlobalConfigService.load("PILOT_LLM_#{slot.upcase}_MODEL", nil)
        return nil if raw == Llm::Presets::DISABLED_SENTINEL

        configured = raw.presence
        return configured if configured

        SLOT_DEFAULT_MODELS[slot].call
      end

      private

      def resolve_endpoint(slug, defaults)
        ENV["PILOT_LLM_#{slug.upcase}_ENDPOINT"].presence || defaults[:endpoint]
      end

      def resolve_openai_compatible(slug, defaults)
        raw = ENV["PILOT_LLM_#{slug.upcase}_OPENAI_COMPATIBLE"].presence
        return parse_bool(raw) if raw

        defaults.fetch(:openai_compatible, true)
      end

      def resolve_capabilities(slug, defaults)
        raw = ENV["PILOT_LLM_#{slug.upcase}_CAPABILITIES"].presence
        if raw
          parsed = raw.split(',').map { |s| s.strip.downcase.to_sym }.select { |s| SLOTS.include?(s) }
          return parsed if parsed.any?
        end

        defaults[:capabilities] || %i[chat]
      end

      def parse_bool(value)
        value.to_s.strip.downcase == 'true'
      end
    end
  end
end
