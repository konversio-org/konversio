class RenameCaptainFeaturesInInstallationConfig < ActiveRecord::Migration[7.0]
  FEATURE_RENAMES = {
    'captain_integration' => 'pilot_integration',
    'captain_integration_v2' => 'pilot_integration_v2',
    'captain_tasks' => 'pilot_tasks'
  }.freeze

  def up
    apply_renames(FEATURE_RENAMES)
  end

  def down
    apply_renames(FEATURE_RENAMES.invert)
  end

  private

  def apply_renames(mapping)
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config.nil?

    value = config.value
    changed = false
    Array(value).each do |entry|
      next unless entry.is_a?(Hash)

      key = entry.key?('name') ? 'name' : (entry.key?(:name) ? :name : nil)
      next if key.nil?
      next unless mapping.key?(entry[key])

      entry[key] = mapping[entry[key]]
      changed = true
    end

    return unless changed

    config.update!(value: value)
    GlobalConfig.clear_cache if defined?(GlobalConfig)
  end
end
