class CreatePilotFaqSuggestionsAndObservations < ActiveRecord::Migration[7.1]
  def change
    create_suggestions_table
    create_observations_table
  end

  private

  def create_suggestions_table
    create_table :pilot_faq_suggestions do |t|
      t.string :question, null: false
      t.text :answer, null: false
      t.vector :embedding, limit: 1536
      t.bigint :assistant_id, null: false
      t.bigint :account_id, null: false
      t.string :language, null: false
      t.integer :source_count, default: 0, null: false
      t.integer :status, default: 0, null: false
      t.timestamps

      t.index %i[account_id assistant_id status language], name: 'idx_pilot_faq_suggestions_review_queue'
      t.index :assistant_id, name: 'index_pilot_faq_suggestions_on_assistant_id'
      t.index :embedding, name: 'vector_idx_pilot_faq_suggestions_embedding', using: :ivfflat, opclass: :vector_cosine_ops
    end
  end

  def create_observations_table
    create_table :pilot_faq_observations do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :faq_suggestion_id
      t.string :generated_question, null: false
      t.text :generated_answer, null: false
      t.string :language, null: false
      t.integer :status, default: 0, null: false
      t.timestamps

      t.index :account_id, name: 'index_pilot_faq_observations_on_account_id'
      t.index :faq_suggestion_id, name: 'index_pilot_faq_observations_on_faq_suggestion_id'
      t.index %i[conversation_id faq_suggestion_id],
              unique: true,
              where: 'faq_suggestion_id IS NOT NULL',
              name: 'idx_pilot_faq_observations_unique_sighting'
    end
  end
end
