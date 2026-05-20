class RemovePilotLlmEmbeddingDimensionsConfig < ActiveRecord::Migration[7.1]
  # The `PILOT_LLM_EMBEDDING_DIMENSIONS` InstallationConfig row used to be the
  # operator's source of truth for the expected embedding dimension. It's been
  # retired in favor of deriving the dimension from the slot's model (via
  # `Custom::Pilot::EmbeddingService::MODEL_DIMENSIONS`) or an explicit
  # `PILOT_LLM_EMBEDDING_DIMENSIONS_OVERRIDE` set via the Custom-mode form.
  # Drop the row so it stops showing up in Super Admin > Installation Config.
  # Idempotent: no-op when the row is already absent.
  def up
    InstallationConfig.where(name: 'PILOT_LLM_EMBEDDING_DIMENSIONS').delete_all
  end

  def down
    # No-op. Restoring the row would not bring back the code path that used it.
  end
end
