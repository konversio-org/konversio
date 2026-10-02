class BackfillPilotDocumentSyncState < ActiveRecord::Migration[7.2]
  BATCH_SIZE = 1000

  # Baseline existing `available` web-backed documents so the new
  # cadence-aware scheduler does not re-fetch the whole fleet on first deploy.
  # Rows already marked synced with a recorded timestamp are left alone.
  def up
    say_with_time('Backfilling pilot_documents sync state') do
      loop do
        updated = execute(<<~SQL.squish).cmd_tuples
          UPDATE pilot_documents
          SET sync_status = 1, last_synced_at = updated_at
          WHERE id IN (
            SELECT id FROM pilot_documents
            WHERE status = 1
              AND (sync_status IS NULL OR (sync_status = 1 AND last_synced_at IS NULL))
              AND external_link NOT LIKE 'PDF:%'
              AND external_link NOT LIKE 'MD:%'
            LIMIT #{BATCH_SIZE}
          )
        SQL
        break if updated.zero?
      end
    end
  end

  def down
    # The baselined sync columns are harmless; nothing to undo.
  end
end
