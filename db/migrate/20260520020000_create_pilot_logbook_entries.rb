# frozen_string_literal: true

class CreatePilotLogbookEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :pilot_logbook_entries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.text :content, null: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end
  end
end
