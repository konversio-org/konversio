class RenameAccountsSettingsCaptainKeys < ActiveRecord::Migration[7.0]
  KEY_RENAMES = {
    'captain_models' => 'pilot_models',
    'captain_features' => 'pilot_features',
    'captain_auto_resolve_mode' => 'pilot_auto_resolve_mode'
  }.freeze

  def up
    rename_keys(KEY_RENAMES)
  end

  def down
    rename_keys(KEY_RENAMES.invert)
  end

  private

  def rename_keys(mapping)
    mapping.each do |from, to|
      execute(<<~SQL)
        UPDATE accounts
        SET settings = jsonb_set(settings - '#{from}', '{#{to}}', settings -> '#{from}')
        WHERE settings ? '#{from}'
      SQL
    end
  end
end
