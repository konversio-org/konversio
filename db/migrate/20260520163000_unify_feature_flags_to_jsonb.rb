class UnifyFeatureFlagsToJsonb < ActiveRecord::Migration[7.0]
  def up
    # 1. Rename old bigint feature_flags column
    rename_column :accounts, :feature_flags, :legacy_feature_flags

    # 2. Add new jsonb feature_flags column
    add_column :accounts, :feature_flags, :jsonb, default: {}, null: false

    # 3. Dynamic bit decoding & migration in batches
    feature_list = YAML.safe_load(File.read(Rails.root.join('config/features.yml')))
    features = feature_list.each_with_object({}).with_index do |(feature, result), index|
      result[index + 1] = feature['name'].to_s
    end

    pilot_columns = [
      :pilot_enabled, :pilot_briefing_enabled, :pilot_copilot_enabled,
      :pilot_autopilot_enabled, :pilot_logbook_enabled, :pilot_tools_enabled,
      :pilot_autoresolve_enabled, :pilot_summary_enabled, :pilot_csat_analysis_enabled,
      :pilot_follow_up_enabled, :pilot_rewrite_enabled, :pilot_label_suggestion_enabled
    ]

    # Temporarily define a bare-metal model subclass to avoid AR autoload collisions/validations
    account_class = Class.new(ActiveRecord::Base) do
      self.table_name = 'accounts'
    end

    account_class.find_in_batches(batch_size: 100) do |batch|
      ActiveRecord::Base.transaction do
        batch.each do |account|
          new_flags = {}

          # Decode legacy bits
          legacy_val = account.read_attribute(:legacy_feature_flags) || 0
          features.each do |bit_pos, feature_name|
            new_flags[feature_name] = true if (legacy_val & (1 << (bit_pos - 1))) != 0
          end

          # Copy Pilot boolean columns
          pilot_columns.each do |col|
            val = account.read_attribute(col)
            # Standardize names from pilot_xxx_enabled to pilot_xxx
            feature_name = col.to_s.sub(/_enabled$/, '')
            new_flags[feature_name] = val
          end

          # Save JSONB directly
          account.update_columns(feature_flags: new_flags)
        end
      end
    end

    # 4. Create high-traffic expression indexes
    # Standard expression index
    execute "CREATE INDEX index_accounts_on_feature_flags_pilot ON accounts USING btree ((feature_flags ->> 'pilot'))"
    execute "CREATE INDEX index_accounts_on_feature_flags_pilot_briefing ON accounts USING btree ((feature_flags ->> 'pilot_briefing'))"

    # Coalesce expression index to cover default-true scopes
    execute "CREATE INDEX index_accounts_on_feature_flags_pilot_coalesce ON accounts USING btree ((COALESCE(feature_flags ->> 'pilot', 'true')))"
    execute "CREATE INDEX index_accounts_on_feature_flags_pilot_briefing_coalesce ON accounts USING btree ((COALESCE(feature_flags ->> 'pilot_briefing', 'true')))"
  end

  def down
    # Drop custom indexes
    execute 'DROP INDEX IF EXISTS index_accounts_on_feature_flags_pilot'
    execute 'DROP INDEX IF EXISTS index_accounts_on_feature_flags_pilot_briefing'
    execute 'DROP INDEX IF EXISTS index_accounts_on_feature_flags_pilot_coalesce'
    execute 'DROP INDEX IF EXISTS index_accounts_on_feature_flags_pilot_briefing_coalesce'

    # Remove JSONB column
    remove_column :accounts, :feature_flags

    # Restore bigint column
    rename_column :accounts, :legacy_feature_flags, :feature_flags
  end
end
