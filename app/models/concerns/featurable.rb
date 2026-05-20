module Featurable
  extend ActiveSupport::Concern

  FEATURE_LIST = YAML.safe_load(Rails.root.join('config/features.yml').read).freeze

  # Fallback Defaults — single source of truth is config/features.yml.
  # Pilot flags (pilot, pilot_briefing, pilot_copilot, etc.) are now defined
  # there alongside every other feature, so no separate constant is needed.
  DEFAULTS = FEATURE_LIST.each_with_object({}) do |feature, hash|
    hash[feature['name'].to_s] = feature['enabled'] == true
  end.freeze

  # Flags that previously lived as dedicated `accounts.pilot_*_enabled` boolean
  # columns. The columns are kept for Phase 1 backward-compat; the legacy
  # accessor names (e.g. `account.pilot_briefing_enabled`) are preserved via
  # the loop further down so existing callers don't have to change. Each entry
  # here must also exist in config/features.yml.
  PILOT_FLAGS = %w[
    pilot pilot_briefing pilot_copilot pilot_autopilot pilot_logbook
    pilot_tools pilot_autoresolve pilot_summary pilot_csat_analysis
    pilot_follow_up pilot_rewrite pilot_label_suggestion
  ].freeze

  included do
    # 2. Dynamic Scopes & Methods Generation
    DEFAULTS.each do |name, default_val|
      # Scopes
      if default_val
        scope "feature_#{name}".to_sym, -> { where("COALESCE(feature_flags ->> ?, 'true') != 'false'", name.to_s) }
        scope "not_feature_#{name}".to_sym, -> { where("feature_flags ->> ? = 'false'", name.to_s) }
      else
        scope "feature_#{name}".to_sym, -> { where("feature_flags ->> ? = 'true'", name.to_s) }
        scope "not_feature_#{name}".to_sym, -> { where("COALESCE(feature_flags ->> ?, 'false') != 'true'", name.to_s) }
      end

      # Dynamic Getter: account.feature_xxx?
      define_method("feature_#{name}?") do
        feature_enabled?(name)
      end

      # Dynamic Getter: account.feature_xxx
      define_method("feature_#{name}") do
        feature_enabled?(name)
      end

      # Dynamic Setter: account.feature_xxx = val
      define_method("feature_#{name}=") do |val|
        self.feature_flags = (feature_flags || {}).merge(name.to_s => ActiveModel::Type::Boolean.new.cast(val))
      end
    end

    PILOT_FLAGS.each do |flag|
      method_name = flag == 'pilot' ? 'pilot_enabled' : "#{flag}_enabled"

      # Dynamic Getter: account.pilot_enabled
      define_method(method_name) do
        feature_enabled?(flag)
      end

      # Dynamic Getter: account.pilot_enabled?
      define_method("#{method_name}?") do
        feature_enabled?(flag)
      end

      # Dynamic Setter: account.pilot_enabled = val
      define_method("#{method_name}=") do |val|
        self.feature_flags = (feature_flags || {}).merge(flag.to_s => ActiveModel::Type::Boolean.new.cast(val))
      end
    end

    before_create :enable_default_features
  end

  def enable_features(*names)
    names.each do |name|
      send("feature_#{name}=", true)
    end
  end

  def enable_features!(*names)
    enable_features(*names)
    save
  end

  def disable_features(*names)
    names.each do |name|
      send("feature_#{name}=", false)
    end
  end

  def disable_features!(*names)
    disable_features(*names)
    save
  end

  def feature_enabled?(name)
    override = feature_flags[name.to_s]
    return override unless override.nil?

    DEFAULTS[name.to_s] || false
  end

  def all_features
    DEFAULTS.keys.index_with do |feature_name|
      feature_enabled?(feature_name)
    end
  end

  def enabled_features
    all_features.select { |_feature, enabled| enabled == true }
  end

  def disabled_features
    all_features.select { |_feature, enabled| enabled == false }
  end

  # Helper method for checkboxes view
  def selected_feature_flags
    self.class.all_feature_names.select { |name| feature_enabled?(name) }.map(&:to_sym)
  end

  # Checkbox setter utilizing sentinel logic
  def selected_feature_flags=(flags)
    flags = Array(flags).map(&:to_s) - ['__sentinel__']
    new_flags = {}
    self.class.all_feature_names.each do |name|
      new_flags[name] = flags.include?(name)
    end
    self.feature_flags = new_flags
  end

  class_methods do
    def all_feature_names
      DEFAULTS.keys
    end
  end

  private

  # Installation-level Defaults
  def enable_default_features
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return true if config.blank?

    # Build the defaults hash first, then assign in one go. In-place hash
    # mutation on a JSONB attribute can fail to trigger ActiveRecord dirty
    # tracking, which would silently drop the new account's defaults on save.
    defaults = {}
    config.value.each do |f|
      next unless f.is_a?(Hash)

      feature_name = f['name'] || f[:name]
      enabled_val = f['enabled'].nil? ? f[:enabled] : f['enabled']
      next if feature_name.blank?

      defaults[feature_name.to_s] = enabled_val == true
    end
    self.feature_flags = (feature_flags || {}).merge(defaults)
  end
end
