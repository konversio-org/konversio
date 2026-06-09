class AddFeatureCitationToAssistantConfig < ActiveRecord::Migration[7.1]
  def up
    return unless KonversioApp.enterprise?

    # Using raw SQL instead of Captain::Assistant (class no longer exists;
    # renamed to Pilot::Assistant). Table is still captain_assistants at this
    # point in the migration sequence (renamed by 20260517135325).
    execute(<<~SQL)
      UPDATE captain_assistants
      SET config = jsonb_set(config, '{feature_citation}', 'true'::jsonb)
    SQL
  end

  def down
    return unless KonversioApp.enterprise?

    execute(<<~SQL)
      UPDATE captain_assistants
      SET config = config - 'feature_citation'
    SQL
  end
end
