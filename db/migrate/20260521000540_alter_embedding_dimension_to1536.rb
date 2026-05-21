class AlterEmbeddingDimensionTo1536 < ActiveRecord::Migration[7.1]
  def up
    execute 'UPDATE pilot_assistant_responses SET embedding = NULL'
    execute 'ALTER TABLE pilot_assistant_responses ALTER COLUMN embedding TYPE vector(1536)'
    execute 'CREATE INDEX IF NOT EXISTS vector_idx_knowledge_entries_embedding ' \
            'ON pilot_assistant_responses USING ivfflat (embedding vector_l2_ops)'
  end

  def down
    execute 'UPDATE pilot_assistant_responses SET embedding = NULL'
    execute 'DROP INDEX IF EXISTS vector_idx_knowledge_entries_embedding'
    execute 'ALTER TABLE pilot_assistant_responses ALTER COLUMN embedding TYPE vector(3584)'
  end
end
