class DropChannelVoice < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:channel_voice)

    if select_value('SELECT COUNT(*) FROM channel_voice').to_i.positive?
      raise ActiveRecord::MigrationError, 'channel_voice is not empty; refusing to drop a populated table'
    end

    drop_table :channel_voice
  end

  def down
    create_table :channel_voice do |t|
      t.string :phone_number, null: false
      t.string :provider, null: false, default: 'twilio'
      t.jsonb :provider_config, null: false
      t.integer :account_id, null: false
      t.jsonb :additional_attributes, default: {}

      t.timestamps
    end

    add_index :channel_voice, :phone_number, unique: true
    add_index :channel_voice, :account_id
  end
end
