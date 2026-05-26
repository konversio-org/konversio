class LockPilotEmbeddingTo1536 < ActiveRecord::Migration[7.1]
  # Locks the pgvector column at 1536 dims installation-wide so OpenAI
  # text-embedding-3-small (native 1536), Scaleway qwen3-embedding-8b, and
  # Nebius Qwen/Qwen3-Embedding-8B (4096 native, truncate to 1536 with
  # MRL-aware renorm) can share one column without schema churn.
  # Provider/model swaps still require a full re-embedding rebuild because
  # same dimension does not mean same embedding space.
  #
  # Previously the column was sized for Scaleway bge-multilingual-gemma2
  # (3584, fixed, no truncation). That model is no longer supported — see
  # Custom::Pilot::EmbeddingService::MODEL_DIMENSIONS for the rationale.
  #
  # Existing vectors are dropped (they live in 3584-dim space and can't be
  # mapped to 1536). UpdateEmbeddingJob (or the auto-rebuild flow tracked
  # in konversio-org/konversio#12) repopulates them from source text.
  #
  # 1536 is also under pgvector's 2,000-dim ivfflat / hnsw indexing cap, so
  # we re-create the index that the 3584 widening had to drop.

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
