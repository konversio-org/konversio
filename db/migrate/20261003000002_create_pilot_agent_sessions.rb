# Persists one row per completed Pilot AI run so operators can audit what the
# assistant did: which knowledge it was offered, what it actually used/cited,
# which scenarios participated, and the turn context the model saw.
#
# `session_kind` discriminates autopilot runs (subject = Conversation, result =
# Message) from copilot runs (subject = CopilotThread, result = CopilotMessage).
class CreatePilotAgentSessions < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  # rubocop:disable Metrics/MethodLength
  def change
    create_table :pilot_agent_sessions do |t|
      t.integer :session_kind, null: false

      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.string :result_type
      t.bigint :result_id

      t.references :account, null: false, foreign_key: true
      t.references :assistant, null: false, foreign_key: { to_table: :pilot_assistants }
      t.references :user, null: true, foreign_key: true

      t.string :llm_model

      t.jsonb :offered_faq_ids, null: false, default: []
      t.jsonb :used_faq_ids, null: false, default: []
      t.jsonb :consulted_document_ids, null: false, default: []
      t.jsonb :cited_document_ids, null: false, default: []
      t.jsonb :scenario_ids, null: false, default: []
      t.jsonb :run_context, null: false, default: {}

      t.timestamps
    end

    add_index :pilot_agent_sessions,
              %i[account_id session_kind created_at],
              name: 'index_pilot_agent_sessions_on_account_kind_created_at'
    add_index :pilot_agent_sessions,
              %i[account_id subject_type subject_id],
              name: 'index_pilot_agent_sessions_on_account_subject'
    add_index :pilot_agent_sessions,
              %i[account_id result_type result_id],
              name: 'index_pilot_agent_sessions_on_account_result'

    add_index :pilot_agent_sessions, :consulted_document_ids, using: :gin, algorithm: :concurrently
    add_index :pilot_agent_sessions, :cited_document_ids, using: :gin, algorithm: :concurrently
    add_index :pilot_agent_sessions, :used_faq_ids, using: :gin, algorithm: :concurrently
  end
  # rubocop:enable Metrics/MethodLength
end
