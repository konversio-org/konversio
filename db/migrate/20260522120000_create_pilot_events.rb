# frozen_string_literal: true

class CreatePilotEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :pilot_events do |t|
      t.references :account, null: false, foreign_key: true
      t.string :event_name, null: false
      t.jsonb :payload, default: {}, null: false
      t.string :related_entity_type
      t.bigint :related_entity_id
      t.datetime :created_at, null: false
    end

    add_index :pilot_events, [:account_id, :created_at], order: { created_at: :desc },
                                                         name: 'index_pilot_events_on_account_id_and_created_at_desc'
    add_index :pilot_events, :event_name
    add_index :pilot_events, [:related_entity_type, :related_entity_id],
              name: 'index_pilot_events_on_related_entity'
  end
end
