module Llm
  # Hybrid registry for LLM providers used by Pilot.
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
      nebius: { label: 'Nebius', endpoint: 'https://api.studio.nebius.ai', openai_compatible: true,
                capabilities: %i[chat embedding] },
      scaleway: { label: 'Scaleway', endpoint: 'https://api.scaleway.ai', openai_compatible: true,
                  capabilities: %i[chat embedding] },
      openrouter: { label: 'OpenRouter', endpoint: 'https://openrouter.ai/api', openai_compatible: true,
                    capabilities: %i[chat] }
    }.freeze

    SLOT_DEFAULT_MODELS = {
      chat: -> { Llm::Config::DEFAULT_MODEL },
      embedding: -> { GlobalConfigService.load('PILOT_EMBEDDING_MODEL', nil).presence || 'text-embedding-3-small' },
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
        slug = slug.to_sym
        key = ENV["PILOT_LLM_#{slug.upcase}_API_KEY"].presence
        return key if key

        # Legacy fallback for the openai slug.
        return GlobalConfigService.load('PILOT_OPEN_AI_API_KEY', nil).presence if slug == :openai

        nil
      end

      def endpoint_for(slug)
        provider(slug)[:endpoint]
      end

      def openai_compatible?(slug)
        provider(slug)[:openai_compatible]
      end

      # Resolved provider for a slot. Reads `PILOT_LLM_<SLOT>_PROVIDER`, falls
      # back to the first capable+available provider (openai preferred).
      def slot_provider(slot)
        slot = slot.to_sym
        configured = GlobalConfigService.load("PILOT_LLM_#{slot.upcase}_PROVIDER", nil).presence
        if configured && providers_for(slot).include?(configured.to_sym)
          return configured.to_sym
        end

        capable = providers_for(slot)
        return :openai if capable.include?(:openai)

        capable.first
      end

      # Resolved model for a slot. Reads `PILOT_LLM_<SLOT>_MODEL`, then falls
      # back to the slot's default (chat → DEFAULT_MODEL, embedding →
      # legacy PILOT_EMBEDDING_MODEL or text-embedding-3-small, audio →
      # whisper-1).
      def slot_model(slot)
        slot = slot.to_sym
        configured = GlobalConfigService.load("PILOT_LLM_#{slot.upcase}_MODEL", nil).presence
        return configured if configured

        # Chat slot keeps its legacy PILOT_OPEN_AI_MODEL fallback.
        if slot == :chat
          legacy = GlobalConfigService.load('PILOT_OPEN_AI_MODEL', nil).presence
          return legacy if legacy
        end

        SLOT_DEFAULT_MODELS[slot].call
      end

      # Emits a one-line deprecation log when legacy ENV vars are in use.
      # Called once from `Llm::Config.initialize!`.
      def log_legacy_deprecation_once
        return if @legacy_logged

        legacy_set = ENV['PILOT_OPEN_AI_API_KEY'].present? || ENV['PILOT_OPEN_AI_ENDPOINT'].present? ||
                     ENV['PILOT_OPEN_AI_API_PROVIDER'].present?
        new_openai_set = ENV['PILOT_LLM_OPENAI_API_KEY'].present?
        legacy_active = GlobalConfigService.load('PILOT_LLM_ACTIVE_PROVIDER', nil).present? ||
                        GlobalConfigService.load('PILOT_LLM_ACTIVE_MODEL', nil).present?

        if legacy_set
          msg = if new_openai_set
                  'PILOT_OPEN_AI_* env vars are deprecated; PILOT_LLM_OPENAI_* takes precedence. ' \
                    'Remove the legacy vars to silence this notice.'
                else
                  'PILOT_OPEN_AI_* env vars are deprecated; please migrate to PILOT_LLM_OPENAI_*.'
                end
          Rails.logger.info("[Llm::ProviderRegistry] #{msg}")
        end

        if legacy_active
          Rails.logger.info(
            '[Llm::ProviderRegistry] PILOT_LLM_ACTIVE_PROVIDER/MODEL are legacy single-slot rows; ' \
              'values are migrated to PILOT_LLM_CHAT_* on boot. Edit slots via Super Admin > LLM Settings.'
          )
        end

        @legacy_logged = true
      end

      def reset_legacy_log!
        @legacy_logged = false
      end

      private

      def resolve_endpoint(slug, defaults)
        override = ENV["PILOT_LLM_#{slug.upcase}_ENDPOINT"].presence
        return override if override

        if slug == :openai
          return GlobalConfigService.load('PILOT_OPEN_AI_ENDPOINT',
                                          nil).presence || defaults[:endpoint]
        end

        defaults[:endpoint]
      end

      def resolve_openai_compatible(slug, defaults)
        raw = ENV["PILOT_LLM_#{slug.upcase}_OPENAI_COMPATIBLE"].presence
        return parse_bool(raw) if raw

        if slug == :openai && GlobalConfigService.load('PILOT_OPEN_AI_API_PROVIDER', nil).to_s == 'openai_compatible'
          return true
        end

        return defaults[:openai_compatible] if defaults.key?(:openai_compatible)

        true
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
