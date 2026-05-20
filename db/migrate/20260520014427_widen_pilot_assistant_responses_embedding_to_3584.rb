class WidenPilotAssistantResponsesEmbeddingTo3584 < ActiveRecord::Migration[7.1]
  # Switching the embedding stack from OpenAI text-embedding-3-* (1536-dim) to
  # Scaleway bge-multilingual-gemma2 (3584-dim native). Existing vectors live in
  # the previous model's space and would be noise against new BGE queries, so
  # they get cleared and re-embedded by UpdateEmbeddingJob.
  #
  # No replacement vector index: pgvector's ivfflat and hnsw both cap at 2,000
  # dimensions, so vector(3584) is storable but not indexable. Sequential scan
  # is fine for FAQ-size corpora; at scale, revisit with halfvec(3584) or a
  # sub-2000-dim model.
  def up
    execute 'UPDATE pilot_assistant_responses SET embedding = NULL'
    execute 'DROP INDEX IF EXISTS vector_idx_knowledge_entries_embedding'
    execute 'ALTER TABLE pilot_assistant_responses ALTER COLUMN embedding TYPE vector(3584)'
  end

  def down
    execute 'UPDATE pilot_assistant_responses SET embedding = NULL'
    execute 'ALTER TABLE pilot_assistant_responses ALTER COLUMN embedding TYPE vector(1536)'
    execute 'CREATE INDEX vector_idx_knowledge_entries_embedding ' \
            'ON pilot_assistant_responses USING ivfflat (embedding vector_l2_ops)'
  end
end
