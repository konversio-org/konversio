# frozen_string_literal: true

class CreatePilotReportingEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :pilot_reporting_events do |t|
      t.string :name, null: false
      t.float :value
      t.float :value_in_business_hours
      t.references :account, null: false, foreign_key: true
      t.bigint :inbox_id
      t.bigint :user_id
      t.bigint :conversation_id
      t.datetime :event_start_at
      t.datetime :event_end_at
      t.datetime :created_at, null: false
    end

    add_index :pilot_reporting_events, [:account_id, :name, :event_start_at],
              name: 'index_pilot_reporting_events_on_account_name_start'
    add_index :pilot_reporting_events, :conversation_id
    add_index :pilot_reporting_events, :inbox_id
  end
end
