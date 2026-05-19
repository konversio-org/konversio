class RenamePilotSupportKeysToKonversio < ActiveRecord::Migration[7.0]
  RENAMES = {
    'PILOT_SUPPORT_WEBSITE_TOKEN' => 'KONVERSIO_SUPPORT_WEBSITE_TOKEN',
    'PILOT_SUPPORT_SCRIPT_URL' => 'KONVERSIO_SUPPORT_SCRIPT_URL',
    'PILOT_SUPPORT_IDENTIFIER_HASH' => 'KONVERSIO_SUPPORT_IDENTIFIER_HASH'
  }.freeze

  def up
    rename_keys(RENAMES)
  end

  def down
    rename_keys(RENAMES.invert)
  end

  private

  def rename_keys(mapping)
    mapping.each do |from, to|
      from_row = InstallationConfig.find_by(name: from)
      next if from_row.nil?
      next if InstallationConfig.exists?(name: to)

      from_row.update!(name: to)
    end
    GlobalConfig.clear_cache if defined?(GlobalConfig)
  end
end
