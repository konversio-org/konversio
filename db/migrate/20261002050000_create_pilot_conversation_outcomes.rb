# frozen_string_literal: true

# Episode-grained record of one continuous window of potential Pilot AI
# involvement on a conversation. Each row is a terminal snapshot of that
# window: lifecycle timestamps, reply facts, categorized handoff, resolution,
# and CSAT. At most one episode may be open (`ended_at IS NULL`) per
# conversation, and at most one episode may be the initial one.
class CreatePilotConversationOutcomes < ActiveRecord::Migration[7.2]
  def change
    create_table :pilot_conversation_outcomes do |t|
      add_episode_columns(t)
      add_fact_columns(t)
      t.timestamps
    end

    add_open_episode_uniqueness
    add_initial_episode_uniqueness
    add_reporting_indexes
  end

  private

  def add_episode_columns(table)
    table.references :account, null: false, foreign_key: { on_delete: :cascade }
    table.references :assistant, null: false, foreign_key: { to_table: :pilot_assistants, on_delete: :cascade }
    table.references :conversation, null: false
    table.references :inbox, null: false
    table.string :episode_trigger, null: false, default: 'initial'
    table.datetime :started_at, null: false
    table.datetime :ended_at
  end

  def add_fact_columns(table)
    table.datetime :first_ai_reply_at
    table.datetime :last_ai_reply_at
    table.integer :ai_reply_count, null: false, default: 0
    table.datetime :first_human_reply_at
    table.datetime :handoff_at
    table.string :handoff_reason_category
    table.datetime :resolved_at
    table.integer :csat_rating
    table.datetime :csat_received_at
  end

  def add_open_episode_uniqueness
    add_index :pilot_conversation_outcomes, [:account_id, :conversation_id],
              unique: true,
              where: 'ended_at IS NULL',
              name: 'index_pilot_outcomes_on_open_episode'
  end

  def add_initial_episode_uniqueness
    add_index :pilot_conversation_outcomes, [:account_id, :conversation_id],
              unique: true,
              where: "episode_trigger = 'initial'",
              name: 'index_pilot_outcomes_on_initial_episode'

    add_index :pilot_conversation_outcomes, [:account_id, :conversation_id, :started_at],
              unique: true,
              name: 'index_pilot_outcomes_on_conversation_and_started_at'
  end

  def add_reporting_indexes
    add_index :pilot_conversation_outcomes, [:account_id, :assistant_id, :started_at],
              name: 'index_pilot_outcomes_on_account_assistant_started'
    add_index :pilot_conversation_outcomes, [:account_id, :assistant_id, :resolved_at],
              name: 'index_pilot_outcomes_on_account_assistant_resolved'
    add_index :pilot_conversation_outcomes, [:account_id, :assistant_id, :handoff_at],
              name: 'index_pilot_outcomes_on_account_assistant_handoff'
  end
end
