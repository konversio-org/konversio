require 'yaml'

module Llm
  # Loads, validates, and applies preset bundles from `config/llm_presets.yml`.
  module Presets
    CONFIG_PATH = Rails.root.join('config/llm_presets.yml')
    SLOTS = %i[chat embedding audio].freeze
    PRESET_CONFIG_KEY = 'PILOT_LLM_PRESET'.freeze
    CUSTOM_SLUG = 'custom'.freeze
    DISABLED_SENTINEL = 'none'.freeze

    class << self
      # All valid presets. Loaded lazily and memoized.
      def all
        @all ||= load_and_validate
      end

      # Force a reload from disk.
      def reset!
        @all = nil
      end

      def find(slug)
        all.find { |p| p[:slug] == slug.to_s }
      end

      # Presets whose three referenced providers are all currently available
      # (API key set). Each preset gets an extra :missing_providers array so
      # the caller can render disabled-state tooltips.
      def applicable
        available = Llm::ProviderRegistry.available_providers.map(&:to_s)
        all.map do |preset|
          missing = SLOTS.filter_map do |slot|
            next if preset[slot].nil?

            slug = preset[slot][:provider]
            slug unless available.include?(slug)
          end
          preset.merge(missing_providers: missing, applicable: missing.empty?)
        end
      end

      # Returns the slug of the preset whose slot assignments exactly match
      # the current InstallationConfig rows, or nil.
      def matching_current_config
        current = SLOTS.each_with_object({}) do |slot, h|
          h[slot] = {
            provider: GlobalConfigService.load("PILOT_LLM_#{slot.upcase}_PROVIDER", nil).to_s,
            model: GlobalConfigService.load("PILOT_LLM_#{slot.upcase}_MODEL", nil).to_s
          }
        end
        matching_current_config_for(current)
      end

      # Returns the slug of the preset whose slot assignments match the given
      # in-memory slot map, or nil. Used by the controller after an Advanced
      # save to compute the PILOT_LLM_PRESET value without re-reading config.
      def matching_current_config_for(slot_map)
        match = all.find do |preset|
          SLOTS.all? do |slot|
            current_provider = slot_map[slot][:provider].to_s
            current_model = slot_map[slot][:model].to_s
            if preset[slot].nil?
              current_provider == DISABLED_SENTINEL && current_model == DISABLED_SENTINEL
            else
              preset[slot][:provider] == current_provider && preset[slot][:model] == current_model
            end
          end
        end
        match&.dig(:slug)
      end

      # Apply a preset: write the six slot rows + PILOT_LLM_PRESET in a
      # single transaction. Raises if the preset slug isn't found or any
      # slot fails capability validation.
      def apply!(slug)
        preset = find(slug)
        raise ArgumentError, "Unknown preset slug: #{slug}" if preset.nil?

        SLOTS.each do |slot|
          next if preset[slot].nil?

          provider = preset[slot][:provider].to_sym
          unless Llm::ProviderRegistry.providers_for(slot).include?(provider)
            raise Llm::ProviderRegistry::CapabilityMismatch,
                  "Preset '#{slug}' assigns #{provider} to #{slot} but it is not capable or not available"
          end
        end

        ActiveRecord::Base.transaction do
          SLOTS.each do |slot|
            if preset[slot].nil?
              write_config("PILOT_LLM_#{slot.upcase}_PROVIDER", DISABLED_SENTINEL)
              write_config("PILOT_LLM_#{slot.upcase}_MODEL", DISABLED_SENTINEL)
            else
              write_config("PILOT_LLM_#{slot.upcase}_PROVIDER", preset[slot][:provider].to_s)
              write_config("PILOT_LLM_#{slot.upcase}_MODEL", preset[slot][:model].to_s)
            end
          end
          write_config(PRESET_CONFIG_KEY, preset[:slug])
        end
        GlobalConfig.clear_cache
        true
      end

      private

      def write_config(name, value)
        row = InstallationConfig.find_or_initialize_by(name: name)
        row.value = value
        row.locked = false if row.new_record?
        row.save!
      end

      def load_and_validate
        raw = parse_yaml
        return [] if raw.blank?

        Array(raw['presets']).filter_map { |entry| validate(entry) }
      end

      def parse_yaml
        YAML.safe_load(File.read(CONFIG_PATH), permitted_classes: [Symbol])
      rescue Errno::ENOENT
        Rails.logger.warn("[Llm::Presets] #{CONFIG_PATH} not found; no presets loaded")
        nil
      rescue Psych::SyntaxError => e
        Rails.logger.warn("[Llm::Presets] YAML parse error in #{CONFIG_PATH}: #{e.message}")
        nil
      end

      OPTIONAL_SLOTS = %i[audio].freeze

      def validate(entry)
        slug = entry['slug'].to_s
        return drop(slug, 'missing slug') if slug.blank?

        label = entry['label'].to_s
        slot_map = {}
        SLOTS.each do |slot|
          row = entry[slot.to_s]
          if row.nil?
            next if OPTIONAL_SLOTS.include?(slot)

            return drop(slug, "missing #{slot} block")
          end
          return drop(slug, "missing #{slot} block") unless row.is_a?(Hash)

          provider = row['provider'].to_s
          model = row['model'].to_s
          return drop(slug, "missing #{slot} provider") if provider.blank?
          return drop(slug, "missing #{slot} model") if model.blank?

          unless Llm::ProviderRegistry.known_slugs.include?(provider.to_sym)
            return drop(slug, "unknown provider '#{provider}' for #{slot}")
          end

          provider_capabilities = (Llm::ProviderRegistry::DEFAULTS[provider.to_sym] || {})[:capabilities] || []
          env_caps = ENV["PILOT_LLM_#{provider.upcase}_CAPABILITIES"].to_s.split(',').map { |s| s.strip.downcase.to_sym }
          capabilities = env_caps.any? ? env_caps : provider_capabilities
          unless capabilities.include?(slot)
            return drop(slug, "provider '#{provider}' does not declare capability '#{slot}'")
          end

          slot_map[slot] = { provider: provider, model: model }
        end

        { slug: slug, label: label.presence || slug }.merge(slot_map)
      end

      def drop(slug, reason)
        Rails.logger.warn("[Llm::Presets] dropping preset '#{slug}': #{reason}")
        nil
      end
    end
  end
end
